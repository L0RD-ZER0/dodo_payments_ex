defmodule DodoStore.Smoke.Runner do
  @moduledoc """
  Runs production-shaped, network-blocked local checkout smoke scenarios.

  The default path creates the checkout through the public SDK-backed workflow,
  delivers signed raw JSON over the real loopback Phoenix endpoint, verifies
  durable inbox acceptance, and drains inbox/outbox work with an explicitly
  injected in-memory Dodo client. Callers can replace lifecycle hooks to attach
  the durable smoke manifest without coupling this engine to persistence.

  Sandbox profiles are deliberately rejected here. They require separate
  drivers and must never be silently simulated by the local engine.
  """

  import Ecto.Query

  alias DodoStore.Billing.{InboxEvent, Record}
  alias DodoStore.Commerce
  alias DodoStore.Smoke, as: SmokeManifest
  alias DodoStore.Smoke.{Lifecycle, LocalDodo, Outcome, PaymentMethodRegistry, Report}
  alias DodoStore.Smoke.WebhookDriver
  alias DodoStore.{Repo, Workflows}

  @default_timeout 60_000
  @default_poll_interval 20

  @type runtime_option ::
          {:descriptors, [map()]}
          | {:base_url, String.t()}
          | {:webhook_secret, String.t()}
          | {:deliver, function()}
          | {:process, function()}
          | {:observe, function()}
          | {:before_scenario, function()}
          | {:before_mutation, function()}
          | {:after_mutation, function()}
          | {:after_observation, function()}
          | {:after_scenario, function()}
          | {:processor_mode, :explicit | :supervised}
          | {:local_dodo, GenServer.server()}
          | {:clock, (-> integer())}
          | {:sleep, (non_neg_integer() -> term())}

  @spec run(map()) :: {:ok, Report.t()} | {:error, Report.t()}
  def run(options) do
    cond do
      option(options, :resume, nil) != nil ->
        preflight_failure(options, :resume_not_implemented)

      option(options, :profile, :local) != :local ->
        run(options, [])

      option(options, :dry_run, false) ->
        run(options, [])

      true ->
        case DodoStore.Smoke.Runtime.start(options) do
          {:ok, smoke_runtime} ->
            run_with_manifest(options, smoke_runtime)

          {:error, _error} ->
            preflight_failure(options, :runtime_start_failed)
        end
    end
  end

  @spec run(map(), [runtime_option()]) :: {:ok, Report.t()} | {:error, Report.t()}
  def run(options, runtime) when is_map(options) and is_list(runtime) do
    started_at = DateTime.utc_now()
    seed = option(options, :seed, 0)
    profile = option(options, :profile, :local)
    run_id = Keyword.get(runtime, :run_id, option(options, :resume, nil) || fresh_run_id(seed))

    cond do
      option(options, :resume, nil) != nil ->
        preflight_failure(options, :resume_not_implemented)

      profile == :local ->
        run_local(options, runtime, run_id, seed, started_at)

      true ->
        report = %Report{
          run_id: run_id,
          profile: profile,
          seed: seed,
          outcome: :fail,
          results: [],
          started_at: started_at,
          finished_at: DateTime.utc_now(),
          preflight_error: %{reason: :unsupported_profile},
          claims: no_execution_claims()
        }

        {:error, report}
    end
  end

  defp run_with_manifest(options, smoke_runtime) do
    descriptors = PaymentMethodRegistry.expand(options)

    lifecycles =
      build_lifecycles(descriptors, options, smoke_runtime.run_id, option(options, :seed, 0))

    with {:ok, manifest_run} <- prepare_manifest_plan(options, smoke_runtime.run_id, lifecycles),
         {:ok, claims} <- Agent.start_link(fn -> %{} end) do
      try do
        runtime =
          [
            run_id: smoke_runtime.run_id,
            base_url: smoke_runtime.endpoint_url,
            webhook_secret: smoke_runtime.webhook_secret,
            descriptors: descriptors,
            before_scenario: &manifest_before_scenario(manifest_run, claims, &1),
            before_mutation: &manifest_before_mutation/2,
            after_mutation: &manifest_after_mutation(claims, &1, &2, &3),
            after_observation: &manifest_after_observation(claims, &1, &2),
            after_scenario: &manifest_after_scenario(manifest_run, claims, &1, &2)
          ]
          |> attach_supervised_local_dodo()

        result = run(options, runtime)
        report = elem(result, 1)

        case SmokeManifest.finish_run(manifest_run, report.outcome, :local_contract) do
          {:ok, _run} ->
            result

          {:error, _reason} ->
            {:error,
             %{
               report
               | outcome: :inconclusive,
                 preflight_error: %{reason: :manifest_finish_failed}
             }}
        end
      after
        if Process.alive?(claims), do: Agent.stop(claims)
      end
    else
      {:error, _reason} -> preflight_failure(options, :manifest_start_failed)
    end
  end

  defp attach_supervised_local_dodo(runtime) do
    case Process.whereis(LocalDodo) do
      nil ->
        Keyword.put(runtime, :processor_mode, :explicit)

      _pid ->
        runtime
        |> Keyword.put(:local_dodo, LocalDodo)
        |> Keyword.put(:processor_mode, :supervised)
    end
  end

  defp prepare_manifest_plan(options, run_id, lifecycles) do
    run_attrs = %{
      run_id: run_id,
      seed: option(options, :seed, 0),
      profile: "local",
      features: %{
        selected: Enum.map(option(options, :features, [:core]), &to_string/1),
        coverage: option(options, :coverage, :strict) |> to_string()
      },
      support_expectation: "mixed"
    }

    intents = Enum.map(lifecycles, &manifest_intent_attrs/1)
    SmokeManifest.create_run_with_intents(run_attrs, intents)
  end

  defp manifest_intent_attrs(lifecycle) do
    %{
      scenario_id: lifecycle.scenario_id,
      feature: lifecycle.target |> Map.get(:feature, :core) |> to_string(),
      method_type: optional_string(Map.get(lifecycle.target, :method_type)),
      method_family: optional_string(Map.get(lifecycle.target, :method_family)),
      intent: %{
        "lifecycle_outcome" => to_string(lifecycle.outcome),
        "synthetic_signature" => true
      },
      parameters: %{
        "order_id" => lifecycle.order_id,
        "product_ids" => Enum.map(lifecycle.cart, &to_string(&1.product_id))
      },
      verification_level: "local_contract",
      support_expectation: to_string(lifecycle.support_expectation),
      replay_safe: false
    }
  end

  defp manifest_before_scenario(manifest_run, claims, lifecycle) do
    Agent.get_and_update(claims, fn state ->
      with scenario when not is_nil(scenario) <-
             SmokeManifest.get_scenario(manifest_run, lifecycle.scenario_id),
           {:ok, claimed} <- SmokeManifest.claim_scenario(scenario) do
        {:ok, Map.put(state, lifecycle.scenario_id, claimed)}
      else
        nil -> {{:error, :manifest_scenario_missing}, state}
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end

  defp manifest_before_mutation(_lifecycle, :checkout), do: :ok

  defp manifest_after_mutation(claims, lifecycle, :checkout, checkout) do
    Agent.get(claims, fn state ->
      scenario = Map.fetch!(state, lifecycle.scenario_id)

      case SmokeManifest.record_resource(scenario, %{
             environment: "local",
             resource_type: "checkout_session",
             resource_id: checkout.session_id,
             ownership: "created",
             metadata: %{"synthetic" => true},
             cleanup_state: "not_supported"
           }) do
        {:ok, _resource, _disposition} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp manifest_after_observation(claims, lifecycle, observations) do
    Agent.get_and_update(claims, fn state ->
      scenario = Map.fetch!(state, lifecycle.scenario_id)

      with {:ok, verifying} <- SmokeManifest.mark_verifying(scenario, :local_contract),
           {:ok, _observation} <-
             SmokeManifest.record_observation(verifying, %{
               stage: "local_contract",
               outcome: "pass",
               verification_level: "local_contract",
               details: stringify(observations)
             }) do
        {:ok, Map.put(state, lifecycle.scenario_id, verifying)}
      else
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end

  defp manifest_after_scenario(manifest_run, claims, lifecycle, %Outcome{} = outcome) do
    Agent.get(claims, fn state ->
      case outcome.outcome do
        :skip ->
          scenario = SmokeManifest.get_scenario(manifest_run, lifecycle.scenario_id)

          case SmokeManifest.skip_scenario(scenario, :local_contract, %{
                 "reason" => outcome.observations[:reason] |> optional_string()
               }) do
            {:ok, _scenario} -> :ok
            {:error, reason} -> {:error, reason}
          end

        terminal ->
          scenario = Map.fetch!(state, lifecycle.scenario_id)
          error_summary = if outcome.errors == [], do: nil, else: stringify(hd(outcome.errors))

          case SmokeManifest.finish_scenario(
                 scenario,
                 terminal,
                 :local_contract,
                 error_summary
               ) do
            {:ok, _scenario} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end)
  end

  defp run_local(options, runtime, run_id, seed, started_at) do
    descriptors =
      Keyword.get_lazy(runtime, :descriptors, fn -> PaymentMethodRegistry.expand(options) end)

    lifecycles = build_lifecycles(descriptors, options, run_id, seed)

    if option(options, :dry_run, false) do
      results =
        Enum.map(lifecycles, fn lifecycle ->
          lifecycle |> dry_run_outcome() |> finalize_outcome(lifecycle, runtime)
        end)

      finish_report(run_id, seed, started_at, results, options)
    else
      with {:ok, local_dodo, owner} <- local_dodo(runtime, run_id) do
        execution_runtime =
          runtime
          |> Keyword.put(:local_dodo, local_dodo)
          |> Keyword.put_new(:processor_mode, :explicit)

        results = execute(lifecycles, options, execution_runtime)
        stop_local_dodo(owner)
        finish_report(run_id, seed, started_at, results, options)
      else
        {:error, _reason} ->
          report = %Report{
            run_id: run_id,
            profile: :local,
            seed: seed,
            outcome: :fail,
            results: [],
            started_at: started_at,
            finished_at: DateTime.utc_now(),
            preflight_error: %{reason: :local_boundary_start_failed},
            claims: no_execution_claims()
          }

          {:error, report}
      end
    end
  rescue
    _exception ->
      report = %Report{
        run_id: run_id,
        profile: :local,
        seed: seed,
        outcome: :fail,
        results: [],
        started_at: started_at,
        finished_at: DateTime.utc_now(),
        preflight_error: %{reason: :invalid_local_plan},
        claims: no_execution_claims()
      }

      {:error, report}
  end

  defp build_lifecycles(descriptors, options, run_id, seed) when is_list(descriptors) do
    descriptors
    |> Enum.with_index()
    |> Enum.flat_map(fn {descriptor, index} ->
      case descriptor_value(descriptor, :outcome) do
        nil ->
          Lifecycle.build_all(
            descriptor,
            option(options, :outcomes, [:random]),
            seed,
            index,
            run_id
          )

        outcome ->
          [Lifecycle.build(descriptor, outcome, seed, index, run_id)]
      end
    end)
  end

  defp execute(lifecycles, options, runtime) do
    case option(options, :execution, :sequential) do
      :parallel -> execute_parallel(lifecycles, options, runtime)
      _sequential -> Enum.map(lifecycles, &run_scenario(&1, options, runtime))
    end
  end

  defp execute_parallel(lifecycles, options, runtime) do
    max_concurrency = option(options, :max_concurrency, 4) |> max(1) |> min(32)
    timeout = option(options, :timeout, @default_timeout)

    lifecycles
    |> Task.async_stream(&run_scenario(&1, options, runtime),
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(lifecycles)
    |> Enum.map(fn
      {{:ok, result}, _lifecycle} ->
        result

      {{:exit, _reason}, lifecycle} ->
        lifecycle
        |> inconclusive_outcome(:scenario_timeout, runtime, timeout)
        |> finalize_outcome(lifecycle, runtime)
    end)
  end

  defp run_scenario(%Lifecycle{} = lifecycle, options, runtime) do
    started = clock(runtime).()
    timeout = option(options, :timeout, @default_timeout)
    deadline = started + timeout

    result =
      try do
        if descriptor_value(lifecycle.descriptor, :interaction_match?) == false do
          skipped_outcome(
            lifecycle,
            :interaction_lane_mismatch,
            runtime,
            elapsed(started, runtime)
          )
        else
          do_run_scenario(lifecycle, runtime, deadline, started)
        end
      rescue
        _exception ->
          inconclusive_outcome(
            lifecycle,
            :scenario_exception,
            runtime,
            elapsed(started, runtime)
          )
      catch
        _kind, _reason ->
          inconclusive_outcome(lifecycle, :scenario_exit, runtime, elapsed(started, runtime))
      end

    finalize_outcome(result, lifecycle, runtime)
  end

  defp do_run_scenario(lifecycle, runtime, deadline, started) do
    local_dodo = Keyword.fetch!(runtime, :local_dodo)

    with :ok <- callback(runtime, :before_scenario, [lifecycle]),
         :ok <- callback(runtime, :before_mutation, [lifecycle, :checkout]),
         {:ok, checkout} <- create_checkout(lifecycle, local_dodo, runtime),
         :ok <- callback(runtime, :after_mutation, [lifecycle, :checkout, checkout]),
         :ok <- LocalDodo.register_lifecycle(local_dodo, lifecycle),
         {:ok, delivery} <- deliver_all(lifecycle, runtime, deadline),
         {:ok, observations} <-
           observe(lifecycle, checkout.session_id, delivery, runtime, deadline),
         :ok <- callback(runtime, :after_observation, [lifecycle, observations]) do
      %Outcome{
        scenario_id: lifecycle.scenario_id,
        target: lifecycle.target,
        lifecycle_outcome: lifecycle.outcome,
        outcome: :pass,
        verification_level: :local_contract,
        support_expectation: lifecycle.support_expectation,
        duration_ms: elapsed(started, runtime),
        processor_mode: processor_mode(runtime),
        observations: observations
      }
    else
      {:error, reason} ->
        failed_outcome(lifecycle, safe_reason(reason), runtime, elapsed(started, runtime))
    end
  end

  defp create_checkout(lifecycle, local_dodo, runtime) do
    base_url = base_url(runtime)

    workflow_options =
      case constrained_methods(lifecycle) do
        [] -> []
        methods -> [allowed_payment_method_types: methods]
      end

    Workflows.checkout(
      LocalDodo.client(local_dodo),
      lifecycle.pattern,
      lifecycle.cart,
      base_url <> "/checkout/return",
      base_url <> "/",
      lifecycle.order_id,
      workflow_options
    )
  end

  defp deliver_all(lifecycle, runtime, deadline) do
    Enum.reduce_while(lifecycle.delivery, {:ok, []}, fn event, {:ok, acknowledgements} ->
      result =
        with :ok <- before_deadline(deadline, runtime),
             {:ok, request} <- WebhookDriver.request(event, webhook_secret(runtime)),
             {:ok, acknowledgement} <- deliver(request, lifecycle, runtime),
             :ok <- await_durable_acceptance(event.webhook_id, deadline, runtime),
             :ok <- process(lifecycle, event, runtime),
             :ok <- await_processed(event.webhook_id, deadline, runtime) do
          {:ok, [acknowledgement | acknowledgements]}
        end

      case result do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acknowledgements} -> {:ok, Enum.reverse(acknowledgements)}
      error -> error
    end
  end

  defp deliver(request, lifecycle, runtime) do
    case Keyword.get(runtime, :deliver) do
      fun when is_function(fun, 2) ->
        normalize_delivery(fun.(request, lifecycle))

      fun when is_function(fun, 1) ->
        normalize_delivery(fun.(request))

      nil ->
        WebhookDriver.deliver(request, base_url(runtime), timeout: remaining_timeout(runtime))
    end
  end

  defp process(lifecycle, event, runtime) do
    case Keyword.get(runtime, :process) do
      fun when is_function(fun, 3) ->
        normalize_action(fun.(lifecycle, event, runtime))

      fun when is_function(fun, 2) ->
        normalize_action(fun.(lifecycle, event))

      fun when is_function(fun, 1) ->
        normalize_action(fun.(event))

      nil ->
        if processor_mode(runtime) == :supervised,
          do: :ok,
          else: explicit_process(runtime)
    end
  end

  defp explicit_process(runtime) do
    client = LocalDodo.client(Keyword.fetch!(runtime, :local_dodo))
    :ok = DodoStore.Billing.InboxProcessor.run_once()
    :ok = DodoStore.Billing.OutboxProcessor.run_once(client: client, batch_size: 100)
    :ok
  end

  defp observe(lifecycle, session_id, delivery, runtime, deadline) do
    with :ok <- await_scenario_state(lifecycle, deadline, runtime),
         {:ok, default} <- default_observations(lifecycle, session_id, delivery, runtime) do
      case Keyword.get(runtime, :observe) do
        fun when is_function(fun, 2) -> normalize_observation(fun.(lifecycle, default))
        fun when is_function(fun, 1) -> normalize_observation(fun.(lifecycle))
        nil -> {:ok, default}
      end
    end
  end

  defp default_observations(lifecycle, session_id, delivery, runtime) do
    unique_events = Enum.uniq_by(lifecycle.events, & &1.webhook_id)
    inbox = inbox_events(unique_events)
    order = Commerce.get_order(lifecycle.order_id)
    local_dodo = Keyword.fetch!(runtime, :local_dodo)
    remote = LocalDodo.payment(local_dodo, lifecycle.payment_id)
    checkout = LocalDodo.checkout(local_dodo, session_id)

    checks = [
      {:checkout_session_recorded,
       is_binary(session_id) and order.checkout_session_id == session_id},
      {:all_deliveries_acknowledged, length(delivery) == length(lifecycle.delivery)},
      {:duplicate_collapsed, length(inbox) == length(unique_events)},
      {:inbox_processed, Enum.all?(inbox, &(&1.state == "processed"))},
      {:payment_terminal, remote && remote["status"] != "processing"},
      {:payment_method_constraint, payment_method_constraint?(lifecycle, checkout)},
      {:local_order_state, expected_order_state?(lifecycle, order)},
      {:reconciliation_projection, expected_projection?(lifecycle)}
    ]

    case Enum.find(checks, fn {_name, passed?} -> passed? != true end) do
      nil ->
        {:ok,
         %{
           checkout_session_id: session_id,
           deliveries: length(delivery),
           unique_webhooks: length(unique_events),
           duplicate_deliveries: length(delivery) - length(unique_events),
           source_event_order: Enum.map(lifecycle.events, & &1.type),
           delivery_event_order: Enum.map(lifecycle.delivery, & &1.type),
           final_payment_status: remote["status"],
           allowed_payment_method_types: checkout["allowed_payment_method_types"],
           durable_inbox: true,
           synthetic_signature: true
         }}

      {failed, _value} ->
        {:error, %{category: :local_assertion, reason: failed}}
    end
  end

  defp expected_order_state?(lifecycle, order)
       when lifecycle.outcome in [:accepted, :refunded, :disputed, :processing_accepted] do
    order && order.status == "fulfilled" && order.payment_id == lifecycle.payment_id
  end

  defp expected_order_state?(_lifecycle, order) do
    order && order.status == "checkout_created" && is_nil(order.payment_id)
  end

  defp expected_projection?(%Lifecycle{outcome: :refunded, refund_id: refund_id}) do
    case Repo.get_by(Record, pattern: 7, business_key: refund_id) do
      %Record{status: "succeeded"} -> true
      _other -> false
    end
  end

  defp expected_projection?(%Lifecycle{outcome: :disputed, dispute_id: dispute_id}) do
    case Repo.get_by(Record, pattern: 7, business_key: dispute_id) do
      %Record{status: "dispute_opened"} -> true
      _other -> false
    end
  end

  defp expected_projection?(_lifecycle), do: true

  defp payment_method_constraint?(lifecycle, checkout) do
    case constrained_methods(lifecycle) do
      [] ->
        is_map(checkout)

      methods ->
        is_map(checkout) and
          checkout["allowed_payment_method_types"] ==
            Enum.map(methods, &DodoPayments.Enums.dump!(:payment_method_type, &1))
    end
  end

  defp constrained_methods(lifecycle) do
    case Map.get(lifecycle.target, :method_type) do
      nil -> descriptor_value(lifecycle.descriptor, :methods) || []
      method -> [method]
    end
  end

  defp await_scenario_state(lifecycle, deadline, runtime) do
    await(
      fn ->
        order = Commerce.get_order(lifecycle.order_id)
        projection_ready = expected_projection?(lifecycle)

        expected_order_state?(lifecycle, order) and projection_ready
      end,
      deadline,
      runtime,
      :scenario_state_timeout
    )
  end

  defp await_durable_acceptance(webhook_id, deadline, runtime) do
    await(
      fn -> Repo.exists?(from(event in InboxEvent, where: event.webhook_id == ^webhook_id)) end,
      deadline,
      runtime,
      :durable_acceptance_timeout
    )
  end

  defp await_processed(webhook_id, deadline, runtime) do
    await(
      fn ->
        case Repo.get_by(InboxEvent, webhook_id: webhook_id) do
          %InboxEvent{state: "processed"} -> true
          _other -> false
        end
      end,
      deadline,
      runtime,
      :processor_timeout
    )
  end

  defp await(predicate, deadline, runtime, timeout_reason) do
    cond do
      predicate.() ->
        :ok

      clock(runtime).() >= deadline ->
        {:error, %{category: :deadline, reason: timeout_reason}}

      true ->
        sleep(runtime).(Keyword.get(runtime, :poll_interval, @default_poll_interval))
        await(predicate, deadline, runtime, timeout_reason)
    end
  end

  defp inbox_events(events) do
    ids = Enum.map(events, & &1.webhook_id)
    Repo.all(from(event in InboxEvent, where: event.webhook_id in ^ids))
  end

  defp callback(runtime, name, args) do
    case Keyword.get(runtime, name) do
      nil -> :ok
      fun when is_function(fun) -> fun |> apply(args) |> normalize_action()
    end
  rescue
    _exception -> {:error, %{category: :lifecycle_hook, reason: callback_exception(name)}}
  catch
    _kind, _reason -> {:error, %{category: :lifecycle_hook, reason: callback_exit(name)}}
  end

  defp normalize_action(:ok), do: :ok
  defp normalize_action({:ok, _value}), do: :ok
  defp normalize_action({:error, _reason} = error), do: error
  defp normalize_action(_value), do: {:error, %{category: :callback, reason: :invalid_return}}

  defp normalize_delivery(:ok), do: {:ok, %{status: 200}}
  defp normalize_delivery({:ok, acknowledgement}), do: {:ok, acknowledgement}
  defp normalize_delivery({:error, _reason} = error), do: error
  defp normalize_delivery(_value), do: {:error, %{category: :callback, reason: :invalid_return}}

  defp normalize_observation({:ok, %{} = observation}), do: {:ok, observation}
  defp normalize_observation(%{} = observation), do: {:ok, observation}
  defp normalize_observation({:error, _reason} = error), do: error

  defp local_dodo(runtime, run_id) do
    case Keyword.fetch(runtime, :local_dodo) do
      {:ok, server} ->
        {:ok, server, :external}

      :error ->
        case Process.whereis(LocalDodo) do
          nil -> start_local_dodo(run_id)
          _pid -> {:ok, LocalDodo, :external}
        end
    end
  end

  defp start_local_dodo(run_id) do
    child_id = {:smoke_local_dodo, run_id}

    child = %{
      id: child_id,
      start: {LocalDodo, :start_link, [[]]},
      restart: :temporary,
      type: :worker
    }

    case Process.whereis(DodoStore.Supervisor) do
      nil ->
        case LocalDodo.start_link() do
          {:ok, pid} -> {:ok, pid, {:direct, pid}}
          error -> error
        end

      supervisor ->
        case Supervisor.start_child(supervisor, child) do
          {:ok, pid} -> {:ok, pid, {:supervisor, supervisor, child_id}}
          error -> error
        end
    end
  end

  defp stop_local_dodo(:external), do: :ok

  defp stop_local_dodo({:direct, pid}),
    do: if(Process.alive?(pid), do: Agent.stop(pid), else: :ok)

  defp stop_local_dodo({:supervisor, supervisor, child_id}) do
    _result = Supervisor.terminate_child(supervisor, child_id)
    _result = Supervisor.delete_child(supervisor, child_id)
    :ok
  end

  defp finish_report(run_id, seed, started_at, results, options) do
    coverage_mode = option(options, :coverage, :strict)
    outcome = aggregate_outcome(results, coverage_mode)

    report = %Report{
      run_id: run_id,
      profile: :local,
      seed: seed,
      outcome: outcome,
      results: results,
      coverage: coverage_summary(results, coverage_mode),
      started_at: started_at,
      finished_at: DateTime.utc_now()
    }

    if outcome in [:pass, :skip], do: {:ok, report}, else: {:error, report}
  end

  defp aggregate_outcome(results, coverage_mode) do
    outcomes = Enum.map(results, & &1.outcome)

    cond do
      :fail in outcomes -> :fail
      :inconclusive in outcomes -> :inconclusive
      coverage_mode == :strict and :skip in outcomes -> :fail
      outcomes != [] and Enum.all?(outcomes, &(&1 == :skip)) -> :skip
      true -> :pass
    end
  end

  defp coverage_summary(results, mode) do
    counts = Enum.frequencies_by(results, & &1.outcome)

    %{
      mode: mode,
      selected: length(results),
      passed: Map.get(counts, :pass, 0),
      skipped: Map.get(counts, :skip, 0),
      failed: Map.get(counts, :fail, 0),
      inconclusive: Map.get(counts, :inconclusive, 0)
    }
  end

  defp dry_run_outcome(lifecycle) do
    %Outcome{
      scenario_id: lifecycle.scenario_id,
      target: lifecycle.target,
      lifecycle_outcome: lifecycle.outcome,
      outcome: :skip,
      verification_level: :local_contract,
      support_expectation: lifecycle.support_expectation,
      observations: %{reason: :dry_run, planned_events: Enum.map(lifecycle.events, & &1.type)}
    }
  end

  defp skipped_outcome(lifecycle, reason, runtime, duration) do
    %Outcome{
      scenario_id: lifecycle.scenario_id,
      target: lifecycle.target,
      lifecycle_outcome: lifecycle.outcome,
      outcome: :skip,
      verification_level: :local_contract,
      support_expectation: lifecycle.support_expectation,
      processor_mode: processor_mode(runtime),
      duration_ms: duration,
      observations: %{reason: reason}
    }
  end

  defp failed_outcome(lifecycle, reason, runtime, duration) do
    %Outcome{
      scenario_id: lifecycle.scenario_id,
      target: lifecycle.target,
      lifecycle_outcome: lifecycle.outcome,
      outcome: :fail,
      verification_level: :local_contract,
      support_expectation: lifecycle.support_expectation,
      processor_mode: processor_mode(runtime),
      duration_ms: duration,
      errors: [%{category: :local_smoke, reason: safe_reason(reason)}]
    }
  end

  defp inconclusive_outcome(lifecycle, reason, runtime, duration) do
    %Outcome{
      scenario_id: lifecycle.scenario_id,
      target: lifecycle.target,
      lifecycle_outcome: lifecycle.outcome,
      outcome: :inconclusive,
      verification_level: :local_contract,
      support_expectation: lifecycle.support_expectation,
      processor_mode: processor_mode(runtime),
      duration_ms: duration,
      errors: [%{category: :local_smoke, reason: safe_reason(reason)}]
    }
  end

  defp finalize_outcome(%Outcome{} = outcome, lifecycle, runtime) do
    case callback(runtime, :after_scenario, [lifecycle, outcome]) do
      :ok ->
        outcome

      {:error, reason} ->
        %{
          outcome
          | outcome: :inconclusive,
            errors: outcome.errors ++ [%{category: :after_scenario, reason: safe_reason(reason)}]
        }
    end
  end

  defp safe_reason(%{reason: reason}) when is_atom(reason), do: reason
  defp safe_reason(%Ecto.Changeset{}), do: :manifest_validation_failed
  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :operation_failed

  defp callback_exception(:before_scenario), do: :before_scenario_exception
  defp callback_exception(:before_mutation), do: :before_mutation_exception
  defp callback_exception(:after_mutation), do: :after_mutation_exception
  defp callback_exception(:after_observation), do: :after_observation_exception
  defp callback_exception(:after_scenario), do: :after_scenario_exception
  defp callback_exception(_name), do: :callback_exception

  defp callback_exit(:before_scenario), do: :before_scenario_exit
  defp callback_exit(:before_mutation), do: :before_mutation_exit
  defp callback_exit(:after_mutation), do: :after_mutation_exit
  defp callback_exit(:after_observation), do: :after_observation_exit
  defp callback_exit(:after_scenario), do: :after_scenario_exit
  defp callback_exit(_name), do: :callback_exit

  defp before_deadline(deadline, runtime) do
    if clock(runtime).() < deadline,
      do: :ok,
      else: {:error, %{category: :deadline, reason: :scenario_timeout}}
  end

  defp base_url(runtime),
    do: Keyword.get_lazy(runtime, :base_url, &DodoStoreWeb.Endpoint.url/0)

  defp webhook_secret(runtime) do
    Keyword.get_lazy(runtime, :webhook_secret, fn ->
      case DodoStore.Dodo.webhook_secrets() do
        [secret | _] -> secret
        [] -> ""
      end
    end)
  end

  defp processor_mode(runtime), do: Keyword.get(runtime, :processor_mode, :explicit)

  defp clock(runtime),
    do: Keyword.get(runtime, :clock, fn -> System.monotonic_time(:millisecond) end)

  defp sleep(runtime), do: Keyword.get(runtime, :sleep, &Process.sleep/1)
  defp elapsed(started, runtime), do: max(clock(runtime).() - started, 0)
  defp remaining_timeout(_runtime), do: 5_000

  defp option(options, key, default), do: Map.get(options, key, default)

  defp descriptor_value(%_{} = descriptor, key),
    do: descriptor |> Map.from_struct() |> descriptor_value(key)

  defp descriptor_value(descriptor, key) when is_map(descriptor) do
    case Map.fetch(descriptor, key) do
      {:ok, value} -> value
      :error -> Map.get(descriptor, Atom.to_string(key))
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value), do: to_string(value)

  defp stringify(%_{} = struct), do: struct |> Map.from_struct() |> stringify()

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value) when is_boolean(value) or is_nil(value), do: value
  defp stringify(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify(value), do: value

  defp preflight_failure(options, reason) do
    now = DateTime.utc_now()

    {:error,
     %Report{
       run_id: option(options, :resume, nil) || "smoke-preflight",
       profile: option(options, :profile, :local),
       seed: option(options, :seed, 0),
       outcome: :fail,
       results: [],
       started_at: now,
       finished_at: now,
       preflight_error: %{reason: reason},
       claims: no_execution_claims()
     }}
  end

  defp no_execution_claims do
    %{
      external_network: :not_attempted,
      webhook_delivery: :not_attempted,
      proves_dodo_origin: false
    }
  end

  defp fresh_run_id(seed), do: "smoke-#{seed}-#{System.unique_integer([:positive, :monotonic])}"
end
