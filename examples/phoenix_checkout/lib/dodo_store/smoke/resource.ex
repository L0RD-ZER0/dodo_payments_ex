defmodule DodoStore.Smoke.Resource do
  @moduledoc "An exact remote resource owned or observed by one smoke scenario."

  use Ecto.Schema
  import Ecto.Changeset

  alias DodoStore.Smoke.{Run, Scenario, SecretSafe}

  @environments ~w(local test_mode)
  @ownership ~w(created observed managed_fixture)
  @cleanup_states ~w(retained cancelled archived deleted not_supported)

  schema "smoke_resources" do
    field(:environment, :string)
    field(:resource_type, :string)
    field(:resource_id, :string)
    field(:ownership, :string, default: "created")
    field(:metadata, :map, default: %{})
    field(:cleanup_state, :string, default: "retained")
    belongs_to(:run, Run)
    belongs_to(:scenario, Scenario)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [
      :run_id,
      :scenario_id,
      :environment,
      :resource_type,
      :resource_id,
      :ownership,
      :metadata,
      :cleanup_state
    ])
    |> validate_required([
      :run_id,
      :scenario_id,
      :environment,
      :resource_type,
      :resource_id,
      :ownership,
      :metadata,
      :cleanup_state
    ])
    |> validate_inclusion(:environment, @environments)
    |> validate_inclusion(:ownership, @ownership)
    |> validate_inclusion(:cleanup_state, @cleanup_states)
    |> validate_resource_id()
    |> validate_secret_safe(:metadata)
    |> unique_constraint([:environment, :resource_type, :resource_id])
  end

  defp validate_resource_id(changeset) do
    validate_change(changeset, :resource_id, fn :resource_id, value ->
      if String.starts_with?(value, ["http://", "https://"]) do
        [resource_id: "must be an opaque resource ID, not a URL"]
      else
        []
      end
    end)
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
