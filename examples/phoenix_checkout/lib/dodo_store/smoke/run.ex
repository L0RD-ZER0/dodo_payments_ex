defmodule DodoStore.Smoke.Run do
  @moduledoc "A durable, resumable smoke-test invocation."

  use Ecto.Schema
  import Ecto.Changeset

  alias DodoStore.Smoke.{Observation, Resource, Scenario, SecretSafe}

  @profiles ~w(local sandbox-api sandbox-checkout)
  @states ~w(running completed)
  @outcomes ~w(pass fail skip inconclusive)
  @verification_levels ~w(local_contract session_created method_offered payment_terminal webhook_processed)

  schema "smoke_runs" do
    field(:run_id, :string)
    field(:seed, :integer)
    field(:profile, :string)
    field(:features, :map, default: %{})
    field(:state, :string, default: "running")
    field(:outcome, :string)
    field(:verification_level, :string)
    field(:support_expectation, :string, default: "mixed")
    field(:completed_at, :utc_datetime_usec)
    has_many(:scenarios, Scenario)
    has_many(:resources, Resource)
    has_many(:observations, Observation)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :run_id,
      :seed,
      :profile,
      :features,
      :state,
      :outcome,
      :verification_level,
      :support_expectation,
      :completed_at
    ])
    |> validate_required([:run_id, :seed, :profile, :features, :state, :support_expectation])
    |> validate_inclusion(:profile, @profiles)
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_inclusion(:verification_level, @verification_levels)
    |> validate_secret_safe(:features)
    |> unique_constraint(:run_id)
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
