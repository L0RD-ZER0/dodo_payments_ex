defmodule DodoStore.SmokeManifestTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias DodoStore.Repo
  alias DodoStore.Smoke
  alias DodoStore.Smoke.{Resource, Scenario}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "intent is durable before claim and terminal evidence remains resumable" do
    assert {:ok, run} =
             Smoke.create_run(%{
               run_id: "smoke_manifest",
               seed: 42,
               profile: "local",
               features: [:core, :resilience]
             })

    parameters = %{amount: 500, currency: :usd, payment_method: :credit}

    assert {:ok, intent} =
             Smoke.record_intent(run, %{
               scenario_id: "credit:accepted",
               feature: "payment-method-types",
               method_type: "credit",
               method_family: "card",
               intent: %{"expected_terminal" => "succeeded"},
               parameters: parameters,
               support_expectation: "documented_supported"
             })

    assert intent.state == "intent_persisted"
    assert intent.intent == %{"expected_terminal" => "succeeded"}
    assert intent.parameter_hash == Smoke.parameter_hash(parameters)
    refute Map.has_key?(intent.intent, "amount")

    assert {:ok, claimed} = Smoke.claim_scenario(intent)
    assert claimed.state == "running"
    assert claimed.attempts == 1
    assert is_binary(claimed.claim_token)
    assert {:error, :not_claimable} = Smoke.claim_scenario(intent)

    assert {:ok, resource, :accepted} =
             Smoke.record_resource(claimed, %{
               environment: "local",
               resource_type: "payment",
               resource_id: "pay_smoke_1",
               metadata: %{"request_id" => "req_1"}
             })

    assert resource.run_id == run.id
    assert resource.scenario_id == intent.id

    assert {:ok, duplicate, :duplicate} =
             Smoke.record_resource(claimed, %{
               environment: "local",
               resource_type: "payment",
               resource_id: "pay_smoke_1",
               metadata: %{"request_id" => "ignored_on_duplicate"}
             })

    assert duplicate.id == resource.id

    assert {:ok, observation} =
             Smoke.record_observation(claimed, %{
               stage: "payment_terminal",
               outcome: "pass",
               verification_level: "payment_terminal",
               details: %{"payment_id" => "pay_smoke_1", "status" => "succeeded"}
             })

    assert observation.scenario_id == intent.id

    assert {:ok, verifying} = Smoke.mark_verifying(claimed, :payment_terminal)

    assert {:ok, completed} =
             Smoke.finish_scenario(verifying, :pass, :webhook_processed)

    assert completed.state == "completed"
    assert completed.outcome == "pass"
    assert completed.completed_at
    refute completed.claim_token

    assert {:ok, completed_run} = Smoke.finish_run(run, :pass, :webhook_processed)
    assert completed_run.state == "completed"

    assert {:error, :run_not_active} =
             Smoke.record_intent(completed_run, %{
               scenario_id: "too-late",
               feature: "core",
               parameters: %{},
               support_expectation: "documented_supported"
             })

    assert {:ok, resumed} = Smoke.resume_run(run.run_id)
    assert [%Scenario{scenario_id: "credit:accepted"}] = resumed.scenarios
    assert [%Resource{resource_id: "pay_smoke_1"}] = resumed.resources
    assert length(resumed.observations) == 1
  end

  test "exact resource ownership prevents a second scenario from claiming the same remote ID" do
    {:ok, run} = run("ownership")
    {:ok, first} = intent(run, "first", false)
    {:ok, second} = intent(run, "second", false)
    {:ok, first} = Smoke.claim_scenario(first)
    {:ok, second} = Smoke.claim_scenario(second)

    attrs = %{
      environment: "test_mode",
      resource_type: "checkout_session",
      resource_id: "cks_shared"
    }

    assert {:ok, _resource, :accepted} = Smoke.record_resource(first, attrs)
    assert {:error, :resource_ownership_conflict} = Smoke.record_resource(second, attrs)
    assert [%Resource{scenario_id: owner_id}] = Smoke.resources(run)
    assert owner_id == first.id
  end

  test "recovery resumes recorded resources, requeues replay-safe work, and stops ambiguity" do
    {:ok, run} = run("recovery")
    {:ok, unsafe} = intent(run, "unsafe", false)
    {:ok, safe} = intent(run, "safe", true)
    {:ok, resourceful} = intent(run, "resourceful", false)

    {:ok, unsafe} = Smoke.claim_scenario(unsafe)
    {:ok, safe} = Smoke.claim_scenario(safe)
    {:ok, resourceful} = Smoke.claim_scenario(resourceful)

    assert {:ok, _resource, :accepted} =
             Smoke.record_resource(resourceful, %{
               environment: "test_mode",
               resource_type: "checkout_session",
               resource_id: "cks_recorded"
             })

    expire_claims([unsafe, safe, resourceful])

    assert %{resume_pending: 1, replayable: 1, inconclusive: 1} =
             Smoke.recover_interrupted_scenarios(run)

    assert Smoke.get_scenario(run, "unsafe").outcome == "inconclusive"
    assert Smoke.get_scenario(run, "unsafe").state == "completed"
    assert Smoke.get_scenario(run, "safe").state == "intent_persisted"
    assert Smoke.get_scenario(run, "resourceful").state == "resume_pending"

    assert {:ok, reclaimed_safe} = Smoke.claim_scenario(Smoke.get_scenario(run, "safe"))
    assert reclaimed_safe.attempts == 2

    assert {:ok, reclaimed_resource} =
             Smoke.claim_scenario(Smoke.get_scenario(run, "resourceful"))

    assert reclaimed_resource.attempts == 2
    assert [%Resource{resource_id: "cks_recorded"}] = Smoke.resources(reclaimed_resource)
  end

  test "manifest fields reject API keys, webhook secrets, and capability URLs" do
    {:ok, run} = run("secret_safety")

    assert {:error, changeset} =
             Smoke.record_intent(run, %{
               scenario_id: "leaky",
               feature: "core",
               intent: %{"checkout_url" => "https://checkout.example/secret"},
               parameters: %{},
               support_expectation: "documented_supported"
             })

    assert Enum.any?(errors_on(changeset).intent, &String.starts_with?(&1, "contains a secret"))

    {:ok, scenario} = intent(run, "safe", false)
    {:ok, scenario} = Smoke.claim_scenario(scenario)

    assert {:error, changeset} =
             Smoke.record_resource(scenario, %{
               environment: "test_mode",
               resource_type: "payment",
               resource_id: "pay_safe",
               metadata: %{"api_key" => "dodo_test_should_never_be_stored"}
             })

    assert Enum.any?(errors_on(changeset).metadata, &String.starts_with?(&1, "contains a secret"))

    assert {:error, changeset} =
             Smoke.record_resource(scenario, %{
               environment: "test_mode",
               resource_type: "checkout_session",
               resource_id: "https://checkout.example/capability"
             })

    assert "must be an opaque resource ID, not a URL" in errors_on(changeset).resource_id
  end

  test "a claimed scenario cannot downgrade its verification evidence" do
    {:ok, run} = run("verification")
    {:ok, scenario} = intent(run, "monotonic", false)
    {:ok, scenario} = Smoke.claim_scenario(scenario)

    assert {:ok, scenario} = Smoke.mark_verifying(scenario, :payment_terminal)
    assert {:error, :verification_downgrade} = Smoke.mark_verifying(scenario, :method_offered)
  end

  test "run creation rolls back when any planned intent is invalid" do
    assert {:error, %Ecto.Changeset{}} =
             Smoke.create_run_with_intents(
               %{
                 run_id: "smoke_atomic_plan",
                 seed: 7,
                 profile: "local",
                 features: ["core"]
               },
               [
                 %{
                   scenario_id: "valid",
                   feature: "core",
                   parameters: %{},
                   support_expectation: "documented_supported"
                 },
                 %{
                   scenario_id: "invalid",
                   feature: "core",
                   parameters: %{}
                 }
               ]
             )

    assert Smoke.get_run("smoke_atomic_plan") == nil
  end

  test "run outcome is derived from terminal scenarios and completed runs are immutable" do
    {:ok, run} = run("derived_outcome")
    {:ok, scenario} = intent(run, "failed", false)
    {:ok, scenario} = Smoke.claim_scenario(scenario)
    assert {:ok, _scenario} = Smoke.finish_scenario(scenario, :fail, :local_contract)

    assert {:error, :outcome_mismatch} = Smoke.finish_run(run, :pass, :local_contract)
    assert {:ok, completed} = Smoke.finish_run(run, :fail, :local_contract)
    assert completed.outcome == "fail"
    assert {:ok, same} = Smoke.finish_run(run, :fail, :local_contract)
    assert same.id == completed.id
    assert {:error, :run_already_completed} = Smoke.finish_run(run, :pass, :local_contract)
  end

  defp run(id) do
    Smoke.create_run(%{
      run_id: "smoke_#{id}",
      seed: 7,
      profile: "sandbox-checkout",
      features: ["core"]
    })
  end

  defp intent(run, id, replay_safe) do
    Smoke.record_intent(run, %{
      scenario_id: id,
      feature: "core",
      intent: %{"operation" => id},
      parameters: %{operation: id},
      replay_safe: replay_safe,
      support_expectation: "documented_supported"
    })
  end

  defp expire_claims(scenarios) do
    ids = Enum.map(scenarios, & &1.id)

    expired_at =
      DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(from(scenario in Scenario, where: scenario.id in ^ids),
      set: [claimed_at: expired_at]
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
