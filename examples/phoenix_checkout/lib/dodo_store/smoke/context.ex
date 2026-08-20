defmodule DodoStore.Smoke do
  @moduledoc """
  Durable execution manifests for the production-shaped smoke harness.

  A scenario intent and its parameter hash are committed before
  `claim_scenario/1` authorizes consequential work. If a non-replay-safe claim
  is abandoned before its remote resource is recorded, recovery marks the
  scenario inconclusive instead of repeating the mutation.
  """

  import Ecto.Query

  alias DodoStore.Repo
  alias DodoStore.Smoke.{Observation, Resource, Run, Scenario}

  @active_states ["running", "resource_recorded", "verifying"]
  @verification_rank %{
    "local_contract" => 0,
    "session_created" => 1,
    "method_offered" => 2,
    "payment_terminal" => 3,
    "webhook_processed" => 4
  }

  @spec parameter_hash(term()) :: String.t()
  def parameter_hash(parameters) do
    parameters
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec create_run(map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) when is_map(attrs) do
    attrs = Map.update(attrs, :features, %{}, &normalize_features/1)

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Atomically persists a run and its complete immutable scenario plan."
  @spec create_run_with_intents(map(), [map()]) ::
          {:ok, Run.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_run_with_intents(run_attrs, intents)
      when is_map(run_attrs) and is_list(intents) do
    Repo.transaction(fn ->
      run =
        case create_run(run_attrs) do
          {:ok, run} -> run
          {:error, error} -> Repo.rollback(error)
        end

      Enum.each(intents, fn attrs ->
        case record_intent(run, attrs) do
          {:ok, _scenario} -> :ok
          {:error, error} -> Repo.rollback(error)
        end
      end)

      run
    end)
    |> case do
      {:ok, run} -> {:ok, run}
      {:error, error} -> {:error, error}
    end
  end

  @spec get_run(String.t()) :: Run.t() | nil
  def get_run(run_id) when is_binary(run_id), do: Repo.get_by(Run, run_id: run_id)

  @spec resume_run(String.t()) :: {:ok, Run.t()} | {:error, :not_found}
  def resume_run(run_id) when is_binary(run_id) do
    case get_run(run_id) do
      nil -> {:error, :not_found}
      run -> {:ok, Repo.preload(run, [:scenarios, :resources, :observations])}
    end
  end

  @spec resumable_runs() :: [Run.t()]
  def resumable_runs do
    Repo.all(from(run in Run, where: run.state == "running", order_by: [asc: run.inserted_at]))
  end

  @doc "Persists immutable scenario intent before a caller may begin a consequence."
  @spec record_intent(Run.t(), map()) ::
          {:ok, Scenario.t()} | {:error, Ecto.Changeset.t() | :run_not_active}
  def record_intent(%Run{id: run_id}, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      case Repo.get(Run, run_id) do
        %Run{state: "running"} ->
          parameters = Map.get(attrs, :parameters, Map.get(attrs, "parameters", %{}))

          attrs =
            attrs
            |> Map.drop([:parameters, "parameters"])
            |> Map.put(:run_id, run_id)
            |> Map.put_new(:intent, %{})
            |> Map.put(:parameter_hash, parameter_hash(parameters))
            |> Map.put(:state, "intent_persisted")

          case %Scenario{} |> Scenario.changeset(attrs) |> Repo.insert() do
            {:ok, scenario} -> scenario
            {:error, changeset} -> Repo.rollback(changeset)
          end

        _not_running ->
          Repo.rollback(:run_not_active)
      end
    end)
    |> case do
      {:ok, scenario} -> {:ok, scenario}
      {:error, error} -> {:error, error}
    end
  end

  @spec get_scenario(Run.t() | pos_integer(), String.t()) :: Scenario.t() | nil
  def get_scenario(%Run{id: run_id}, scenario_id), do: get_scenario(run_id, scenario_id)

  def get_scenario(run_id, scenario_id) when is_integer(run_id) and is_binary(scenario_id) do
    Repo.get_by(Scenario, run_id: run_id, scenario_id: scenario_id)
  end

  @spec scenarios(Run.t()) :: [Scenario.t()]
  def scenarios(%Run{id: run_id}) do
    Repo.all(from(scenario in Scenario, where: scenario.run_id == ^run_id, order_by: scenario.id))
  end

  @doc "Atomically claims persisted intent before any remote mutation is attempted."
  @spec claim_scenario(Scenario.t()) :: {:ok, Scenario.t()} | {:error, :not_claimable}
  def claim_scenario(%Scenario{id: id}) do
    timestamp = now()
    token = claim_token()

    query =
      from(scenario in Scenario,
        where: scenario.id == ^id and scenario.state in ["intent_persisted", "resume_pending"]
      )

    case Repo.update_all(query,
           set: [state: "running", claimed_at: timestamp, claim_token: token],
           inc: [attempts: 1]
         ) do
      {1, _rows} -> {:ok, Repo.get!(Scenario, id)}
      {0, _rows} -> {:error, :not_claimable}
    end
  end

  @doc "Records exact resource ownership immediately after a successful consequence."
  @spec record_resource(Scenario.t(), map()) ::
          {:ok, Resource.t(), :accepted | :duplicate}
          | {:error, Ecto.Changeset.t() | :stale_claim | :resource_ownership_conflict}
  def record_resource(%Scenario{} = scenario, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, current} <- owned_active_scenario(scenario),
           {:ok, resource, disposition} <- insert_owned_resource(current, attrs),
           {:ok, _scenario} <- mark_resource_recorded(current) do
        {resource, disposition}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {resource, disposition}} -> {:ok, resource, disposition}
      {:error, error} -> {:error, error}
    end
  end

  @spec resources(Run.t() | Scenario.t()) :: [Resource.t()]
  def resources(%Run{id: run_id}) do
    Repo.all(from(resource in Resource, where: resource.run_id == ^run_id, order_by: resource.id))
  end

  def resources(%Scenario{id: scenario_id}) do
    Repo.all(
      from(resource in Resource,
        where: resource.scenario_id == ^scenario_id,
        order_by: resource.id
      )
    )
  end

  @spec record_observation(Scenario.t(), map()) ::
          {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def record_observation(%Scenario{} = scenario, attrs) when is_map(attrs) do
    scenario = Repo.get!(Scenario, scenario.id)

    attrs =
      attrs
      |> Map.put(:run_id, scenario.run_id)
      |> Map.put(:scenario_id, scenario.id)
      |> Map.put_new(:observed_at, now())

    %Observation{}
    |> Observation.changeset(attrs)
    |> Repo.insert()
  end

  @spec observations(Run.t() | Scenario.t()) :: [Observation.t()]
  def observations(%Run{id: run_id}) do
    Repo.all(
      from(observation in Observation,
        where: observation.run_id == ^run_id,
        order_by: observation.id
      )
    )
  end

  def observations(%Scenario{id: scenario_id}) do
    Repo.all(
      from(observation in Observation,
        where: observation.scenario_id == ^scenario_id,
        order_by: observation.id
      )
    )
  end

  @spec mark_verifying(Scenario.t(), String.t() | atom()) ::
          {:ok, Scenario.t()}
          | {:error, Ecto.Changeset.t() | :stale_claim | :verification_downgrade}
  def mark_verifying(%Scenario{} = scenario, verification_level) do
    transition_claimed(scenario, %{
      state: "verifying",
      verification_level: to_string(verification_level)
    })
  end

  @spec finish_scenario(Scenario.t(), String.t() | atom(), String.t() | atom(), map() | nil) ::
          {:ok, Scenario.t()}
          | {:error, Ecto.Changeset.t() | :stale_claim | :verification_downgrade}
  def finish_scenario(scenario, outcome, verification_level, error_summary \\ nil) do
    transition_claimed(scenario, %{
      state: "completed",
      outcome: to_string(outcome),
      verification_level: to_string(verification_level),
      error_summary: error_summary,
      completed_at: now(),
      claimed_at: nil,
      claim_token: nil
    })
  end

  @spec skip_scenario(Scenario.t(), String.t() | atom(), map()) ::
          {:ok, Scenario.t()} | {:error, Ecto.Changeset.t() | :not_skippable}
  def skip_scenario(%Scenario{id: id}, verification_level, reason) when is_map(reason) do
    scenario = Repo.get!(Scenario, id)

    changeset =
      Scenario.changeset(scenario, %{
        state: "completed",
        outcome: "skip",
        verification_level: to_string(verification_level),
        error_summary: reason,
        completed_at: now()
      })

    with true <- scenario.state in ["intent_persisted", "resume_pending"],
         true <- changeset.valid? || {:invalid, changeset} do
      updates = Map.to_list(changeset.changes)

      case Repo.update_all(
             from(candidate in Scenario,
               where:
                 candidate.id == ^id and
                   candidate.state in ["intent_persisted", "resume_pending"]
             ),
             set: updates
           ) do
        {1, _rows} -> {:ok, Repo.get!(Scenario, id)}
        {0, _rows} -> {:error, :not_skippable}
      end
    else
      false -> {:error, :not_skippable}
      {:invalid, changeset} -> {:error, changeset}
    end
  end

  @doc "Recovers expired work without blindly replaying uncertain consequences."
  @spec recover_interrupted_scenarios(Run.t(), non_neg_integer()) ::
          %{
            resume_pending: non_neg_integer(),
            replayable: non_neg_integer(),
            inconclusive: non_neg_integer()
          }
  def recover_interrupted_scenarios(%Run{id: run_id}, timeout_seconds \\ 60) do
    expired_at = DateTime.add(now(), -timeout_seconds, :second)

    Repo.transaction(fn ->
      resourceful_ids =
        Repo.all(
          from(scenario in Scenario,
            join: resource in Resource,
            on: resource.scenario_id == scenario.id,
            where:
              scenario.run_id == ^run_id and scenario.state in ^@active_states and
                scenario.claimed_at < ^expired_at,
            select: scenario.id,
            distinct: true
          )
        )

      {resume_count, _rows} =
        Repo.update_all(
          from(scenario in Scenario, where: scenario.id in ^resourceful_ids),
          set: [state: "resume_pending", claimed_at: nil, claim_token: nil]
        )

      base =
        from(scenario in Scenario,
          where:
            scenario.run_id == ^run_id and scenario.state in ^@active_states and
              scenario.claimed_at < ^expired_at and scenario.id not in ^resourceful_ids
        )

      {replayable_count, _rows} =
        Repo.update_all(from(scenario in base, where: scenario.replay_safe == true),
          set: [state: "intent_persisted", claimed_at: nil, claim_token: nil]
        )

      {inconclusive_count, _rows} =
        Repo.update_all(from(scenario in base, where: scenario.replay_safe == false),
          set: [
            state: "completed",
            outcome: "inconclusive",
            error_summary: %{"category" => "interrupted_after_consequence_claim"},
            completed_at: now(),
            claimed_at: nil,
            claim_token: nil
          ]
        )

      %{
        resume_pending: resume_count,
        replayable: replayable_count,
        inconclusive: inconclusive_count
      }
    end)
    |> case do
      {:ok, counts} -> counts
      {:error, error} -> raise "smoke recovery failed: #{inspect(error)}"
    end
  end

  @spec finish_run(Run.t(), String.t() | atom(), String.t() | atom()) ::
          {:ok, Run.t()}
          | {:error,
             Ecto.Changeset.t()
             | :scenarios_incomplete
             | :run_already_completed
             | :outcome_mismatch}
  def finish_run(%Run{id: run_id}, outcome, verification_level) do
    run = Repo.get!(Run, run_id)
    scenarios = Repo.all(from(scenario in Scenario, where: scenario.run_id == ^run_id))
    requested_outcome = to_string(outcome)

    cond do
      Enum.any?(scenarios, &(&1.state != "completed")) ->
        {:error, :scenarios_incomplete}

      run.state == "completed" and
        run.outcome == requested_outcome and
          run.verification_level == to_string(verification_level) ->
        {:ok, run}

      run.state == "completed" ->
        {:error, :run_already_completed}

      aggregate_scenario_outcome(scenarios, run) != requested_outcome ->
        {:error, :outcome_mismatch}

      true ->
        run
        |> Run.changeset(%{
          state: "completed",
          outcome: requested_outcome,
          verification_level: to_string(verification_level),
          completed_at: now()
        })
        |> Repo.update()
    end
  end

  defp insert_owned_resource(scenario, attrs) do
    attrs =
      attrs
      |> Map.put(:run_id, scenario.run_id)
      |> Map.put(:scenario_id, scenario.id)

    case %Resource{} |> Resource.changeset(attrs) |> Repo.insert() do
      {:ok, resource} ->
        {:ok, resource, :accepted}

      {:error, changeset} ->
        resolve_resource_conflict(changeset, scenario, attrs)
    end
  end

  defp resolve_resource_conflict(changeset, scenario, attrs) do
    existing =
      Repo.get_by(Resource,
        environment: Map.get(attrs, :environment),
        resource_type: Map.get(attrs, :resource_type),
        resource_id: Map.get(attrs, :resource_id)
      )

    cond do
      existing && existing.run_id == scenario.run_id && existing.scenario_id == scenario.id ->
        {:ok, existing, :duplicate}

      existing ->
        {:error, :resource_ownership_conflict}

      true ->
        {:error, changeset}
    end
  end

  defp mark_resource_recorded(scenario) do
    target_state = if scenario.state == "verifying", do: "verifying", else: "resource_recorded"
    transition_claimed(scenario, %{state: target_state})
  end

  defp transition_claimed(%Scenario{} = scenario, attrs) do
    with {:ok, current} <- owned_active_scenario(scenario),
         :ok <- monotonic_verification(current, attrs),
         changeset <- Scenario.changeset(current, attrs),
         true <- changeset.valid? || {:invalid, changeset} do
      updates = Map.take(changeset.changes, Map.keys(attrs))

      if map_size(updates) == 0 do
        {:ok, current}
      else
        case Repo.update_all(owned_active_query(current), set: Map.to_list(updates)) do
          {1, _rows} -> {:ok, Repo.get!(Scenario, current.id)}
          {0, _rows} -> {:error, :stale_claim}
        end
      end
    else
      {:invalid, changeset} -> {:error, changeset}
      {:error, _reason} = error -> error
    end
  end

  defp monotonic_verification(current, attrs) do
    requested = Map.get(attrs, :verification_level, current.verification_level)

    case Map.fetch(@verification_rank, to_string(requested)) do
      {:ok, requested_rank} ->
        if requested_rank >= Map.fetch!(@verification_rank, current.verification_level) do
          :ok
        else
          {:error, :verification_downgrade}
        end

      :error ->
        :ok
    end
  end

  defp owned_active_scenario(%Scenario{id: id, claim_token: token}) when is_binary(token) do
    case Repo.one(
           from(scenario in Scenario,
             where:
               scenario.id == ^id and scenario.state in ^@active_states and
                 scenario.claim_token == ^token
           )
         ) do
      nil -> {:error, :stale_claim}
      current -> {:ok, current}
    end
  end

  defp owned_active_scenario(%Scenario{}), do: {:error, :stale_claim}

  defp owned_active_query(scenario) do
    from(candidate in Scenario,
      where:
        candidate.id == ^scenario.id and candidate.state in ^@active_states and
          candidate.claim_token == ^scenario.claim_token
    )
  end

  defp normalize_features(features) when is_list(features),
    do: %{"selected" => Enum.map(features, &to_string/1)}

  defp normalize_features(features) when is_map(features), do: features

  defp aggregate_scenario_outcome(scenarios, run) do
    outcomes = Enum.map(scenarios, & &1.outcome)
    coverage = run.features["coverage"] || run.features[:coverage]

    cond do
      "fail" in outcomes -> "fail"
      "inconclusive" in outcomes -> "inconclusive"
      coverage == "strict" and "skip" in outcomes -> "fail"
      outcomes != [] and Enum.all?(outcomes, &(&1 == "skip")) -> "skip"
      true -> "pass"
    end
  end

  defp claim_token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
