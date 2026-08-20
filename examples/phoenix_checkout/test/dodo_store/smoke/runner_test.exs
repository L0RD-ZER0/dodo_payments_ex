defmodule DodoStore.Smoke.RunnerTest do
  use ExUnit.Case, async: false

  alias DodoStore.Repo
  alias DodoStore.Smoke.{Options, Report, Reporter, Runner}

  @secret "whsec_" <> Base.encode64("test-webhook-secret")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Application.put_env(:dodo_store, :webhook_secrets, [@secret])
    :ok
  end

  test "all local outcomes cross the endpoint, inbox, processors, and reconciliation boundary" do
    parent = self()
    options = Options.parse!(["--outcome", "all", "--seed", "73"])

    descriptor = %{
      feature: :core,
      support_expectation: :documented_supported,
      interaction_match?: true
    }

    deliver = fn request, _lifecycle -> endpoint_delivery(request) end

    assert {:ok, %Report{outcome: :pass, results: results} = report} =
             Runner.run(options,
               run_id: "runner-all-73",
               descriptors: [descriptor],
               webhook_secret: @secret,
               base_url: "http://127.0.0.1:4002",
               deliver: deliver,
               processor_mode: :explicit,
               after_mutation: fn lifecycle, :checkout, checkout ->
                 send(parent, {:checkout_recordable, lifecycle.scenario_id, checkout.session_id})
                 :ok
               end,
               after_scenario: fn lifecycle, outcome ->
                 send(parent, {:terminal, lifecycle.scenario_id, outcome.outcome})
                 :ok
               end
             )

    assert Enum.map(results, & &1.lifecycle_outcome) == Options.lifecycle_outcomes()
    assert Enum.all?(results, &(&1.outcome == :pass))
    assert Enum.all?(results, &(&1.verification_level == :local_contract))
    assert Enum.all?(results, &(&1.signature_provenance == :synthetic_valid_signature))
    assert Enum.all?(results, &(&1.processor_mode == :explicit))

    assert report.coverage == %{
             mode: :strict,
             selected: 7,
             passed: 7,
             skipped: 0,
             failed: 0,
             inconclusive: 0
           }

    assert Enum.all?(results, fn result ->
             result.observations.durable_inbox and result.observations.synthetic_signature and
               result.observations.duplicate_deliveries >= 1
           end)

    for result <- results do
      scenario_id = result.scenario_id
      assert_received {:checkout_recordable, ^scenario_id, "cks-" <> _token}
      assert_received {:terminal, ^scenario_id, :pass}
    end

    rendered = Reporter.to_json(report)
    refute rendered =~ "whsec_"
    refute rendered =~ "checkout_url"
    refute rendered =~ "client_secret"
  end

  test "sandbox profiles are rejected rather than silently simulated" do
    options = %{profile: :sandbox_checkout, seed: 1, resume: nil}

    assert {:error, %Report{outcome: :fail, preflight_error: %{reason: :unsupported_profile}}} =
             Runner.run(options, descriptors: [])
  end

  test "resume fails closed before reading or mutating manifests" do
    before_count = Repo.aggregate(DodoStore.Smoke.Resource, :count)

    options = %{profile: :local, seed: 10, resume: "previous-run", dry_run: false}

    assert {:error, %Report{preflight_error: %{reason: :resume_not_implemented}}} =
             Runner.run(options)

    assert Repo.aggregate(DodoStore.Smoke.Resource, :count) == before_count
    assert DodoStore.Smoke.get_run("previous-run") == nil
  end

  test "parallel scenarios stay isolated behind the configured concurrency bound" do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {:ok, tracker} = Agent.start_link(fn -> %{active: 0, maximum: 0} end)

    options =
      Options.parse!([
        "--outcome",
        "accepted",
        "--execution",
        "parallel",
        "--max-concurrency",
        "2",
        "--seed",
        "81"
      ])

    descriptors =
      for index <- 1..5 do
        %{
          id: "parallel:#{index}:accepted",
          outcome: :accepted,
          feature: :core,
          support_expectation: :documented_supported,
          interaction_match?: true
        }
      end

    before_scenario = fn _lifecycle ->
      Agent.update(tracker, fn state ->
        active = state.active + 1
        %{active: active, maximum: max(state.maximum, active)}
      end)

      Process.sleep(25)
      :ok
    end

    after_scenario = fn _lifecycle, _outcome ->
      Agent.update(tracker, &%{&1 | active: &1.active - 1})
      :ok
    end

    assert {:ok, %Report{outcome: :pass, results: results}} =
             Runner.run(options,
               run_id: "runner-parallel-81",
               descriptors: descriptors,
               webhook_secret: @secret,
               base_url: "http://127.0.0.1:4002",
               deliver: &endpoint_delivery/1,
               processor_mode: :explicit,
               before_scenario: before_scenario,
               after_scenario: after_scenario
             )

    assert length(results) == 5
    assert results |> Enum.map(& &1.scenario_id) |> Enum.uniq() |> length() == 5
    assert Agent.get(tracker, & &1) == %{active: 0, maximum: 2}
  end

  test "method type and family lanes cross the SDK as exact wire constraints" do
    options = Options.parse!(["--outcome", "accepted", "--seed", "91"])

    descriptors = [
      %{
        id: "method:credit:accepted",
        outcome: :accepted,
        feature: :payment_method_types,
        method: :credit,
        support_expectation: :documented_supported,
        interaction_match?: true
      },
      %{
        id: "family:bank-debit:accepted",
        outcome: :accepted,
        feature: :payment_method_families,
        family: :bank_debit,
        methods: [:ach, :bacs, :becs, :sepa],
        support_expectation: :enum_only,
        interaction_match?: true
      }
    ]

    assert {:ok, %Report{results: [type_result, family_result]}} =
             Runner.run(options,
               run_id: "runner-methods-91",
               descriptors: descriptors,
               webhook_secret: @secret,
               base_url: "http://127.0.0.1:4002",
               deliver: &endpoint_delivery/1,
               processor_mode: :explicit
             )

    assert type_result.observations.allowed_payment_method_types == ["credit"]

    assert family_result.observations.allowed_payment_method_types == [
             "ach",
             "bacs",
             "becs",
             "sepa"
           ]
  end

  test "strict coverage fails skipped selections while informational coverage reports them" do
    descriptor = %{
      id: "manual:accepted",
      outcome: :accepted,
      feature: :payment_method_types,
      support_expectation: :device_or_manual_required,
      interaction_match?: false
    }

    strict = Options.parse!(["--outcome", "accepted", "--coverage", "strict", "--seed", "92"])

    informational =
      Options.parse!(["--outcome", "accepted", "--coverage", "informational", "--seed", "92"])

    assert {:error, %Report{outcome: :fail, coverage: %{skipped: 1}}} =
             Runner.run(strict, descriptors: [descriptor], run_id: "coverage-strict")

    assert {:ok, %Report{outcome: :skip, coverage: %{skipped: 1}}} =
             Runner.run(informational,
               descriptors: [descriptor],
               run_id: "coverage-informational"
             )
  end

  defp endpoint_delivery(request) do
    conn = Plug.Test.conn(:post, "/webhooks/dodo", request.body)

    conn =
      Enum.reduce(request.headers, conn, fn {name, value}, conn ->
        Plug.Conn.put_req_header(conn, name, value)
      end)

    conn = DodoStoreWeb.Endpoint.call(conn, DodoStoreWeb.Endpoint.init([]))

    if conn.status in 200..299,
      do: {:ok, %{status: conn.status, webhook_id: request.webhook_id}},
      else: {:error, %{reason: :endpoint_rejected}}
  end
end
