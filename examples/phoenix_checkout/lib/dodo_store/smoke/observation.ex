defmodule DodoStore.Smoke.Observation do
  @moduledoc "A secret-safe fact observed while verifying a smoke scenario."

  use Ecto.Schema
  import Ecto.Changeset

  alias DodoStore.Smoke.{Run, Scenario, SecretSafe}

  @outcomes ~w(pass fail skip inconclusive)
  @verification_levels ~w(local_contract session_created method_offered payment_terminal webhook_processed)

  schema "smoke_observations" do
    field(:stage, :string)
    field(:outcome, :string)
    field(:verification_level, :string)
    field(:details, :map, default: %{})
    field(:observed_at, :utc_datetime_usec)
    belongs_to(:run, Run)
    belongs_to(:scenario, Scenario)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, [
      :run_id,
      :scenario_id,
      :stage,
      :outcome,
      :verification_level,
      :details,
      :observed_at
    ])
    |> validate_required([
      :run_id,
      :scenario_id,
      :stage,
      :outcome,
      :verification_level,
      :details,
      :observed_at
    ])
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_inclusion(:verification_level, @verification_levels)
    |> validate_secret_safe(:details)
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
