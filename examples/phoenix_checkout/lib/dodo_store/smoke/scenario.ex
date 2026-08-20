defmodule DodoStore.Smoke.Scenario do
  @moduledoc "A persisted smoke intent that is claimed before consequential work begins."

  use Ecto.Schema
  import Ecto.Changeset

  alias DodoStore.Smoke.{Observation, Resource, Run, SecretSafe}

  @states ~w(intent_persisted running resource_recorded verifying resume_pending completed)
  @outcomes ~w(pass fail skip inconclusive)
  @verification_levels ~w(local_contract session_created method_offered payment_terminal webhook_processed)
  @support_expectations ~w(
    documented_supported expected_unsupported merchant_gated regional
    device_or_manual_required enum_only paused
  )

  schema "smoke_scenarios" do
    field(:scenario_id, :string)
    field(:feature, :string)
    field(:method_type, :string)
    field(:method_family, :string)
    field(:intent, :map, default: %{})
    field(:parameter_hash, :string)
    field(:state, :string, default: "intent_persisted")
    field(:outcome, :string)
    field(:verification_level, :string, default: "local_contract")
    field(:support_expectation, :string)
    field(:replay_safe, :boolean, default: false)
    field(:attempts, :integer, default: 0)
    field(:claimed_at, :utc_datetime_usec)
    field(:claim_token, :string)
    field(:error_summary, :map)
    field(:completed_at, :utc_datetime_usec)
    belongs_to(:run, Run)
    has_many(:resources, Resource)
    has_many(:observations, Observation)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [
      :run_id,
      :scenario_id,
      :feature,
      :method_type,
      :method_family,
      :intent,
      :parameter_hash,
      :state,
      :outcome,
      :verification_level,
      :support_expectation,
      :replay_safe,
      :attempts,
      :claimed_at,
      :claim_token,
      :error_summary,
      :completed_at
    ])
    |> validate_required([
      :run_id,
      :scenario_id,
      :feature,
      :intent,
      :parameter_hash,
      :state,
      :verification_level,
      :support_expectation
    ])
    |> validate_length(:parameter_hash, is: 64)
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_inclusion(:verification_level, @verification_levels)
    |> validate_inclusion(:support_expectation, @support_expectations)
    |> validate_secret_safe(:intent)
    |> validate_secret_safe(:error_summary)
    |> unique_constraint([:run_id, :scenario_id])
  end

  defp validate_secret_safe(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case SecretSafe.check(value) do
        :ok -> []
        {:error, path} -> [{field, "contains a secret or capability field at #{path}"}]
      end
    end)
  end
end
