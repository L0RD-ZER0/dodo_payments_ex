defmodule DodoStore.Repo.Migrations.CreateSmokeManifests do
  use Ecto.Migration

  def change do
    create table(:smoke_runs) do
      add(:run_id, :string, null: false)
      add(:seed, :integer, null: false)
      add(:profile, :string, null: false)
      add(:features, :map, null: false, default: %{})
      add(:state, :string, null: false, default: "running")
      add(:outcome, :string)
      add(:verification_level, :string)
      add(:support_expectation, :string, null: false, default: "mixed")
      add(:completed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:smoke_runs, [:run_id]))
    create(index(:smoke_runs, [:state, :inserted_at]))

    create table(:smoke_scenarios) do
      add(:run_id, references(:smoke_runs, on_delete: :delete_all), null: false)
      add(:scenario_id, :string, null: false)
      add(:feature, :string, null: false)
      add(:method_type, :string)
      add(:method_family, :string)
      add(:intent, :map, null: false, default: %{})
      add(:parameter_hash, :string, null: false)
      add(:state, :string, null: false, default: "intent_persisted")
      add(:outcome, :string)
      add(:verification_level, :string, null: false, default: "local_contract")
      add(:support_expectation, :string, null: false)
      add(:replay_safe, :boolean, null: false, default: false)
      add(:attempts, :integer, null: false, default: 0)
      add(:claimed_at, :utc_datetime_usec)
      add(:claim_token, :string)
      add(:error_summary, :map)
      add(:completed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:smoke_scenarios, [:run_id, :scenario_id]))
    create(index(:smoke_scenarios, [:run_id, :state, :inserted_at]))

    create table(:smoke_resources) do
      add(:run_id, references(:smoke_runs, on_delete: :delete_all), null: false)
      add(:scenario_id, references(:smoke_scenarios, on_delete: :delete_all), null: false)
      add(:environment, :string, null: false)
      add(:resource_type, :string, null: false)
      add(:resource_id, :string, null: false)
      add(:ownership, :string, null: false, default: "created")
      add(:metadata, :map, null: false, default: %{})
      add(:cleanup_state, :string, null: false, default: "retained")
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:smoke_resources, [:environment, :resource_type, :resource_id]))
    create(index(:smoke_resources, [:run_id, :scenario_id]))

    create table(:smoke_observations) do
      add(:run_id, references(:smoke_runs, on_delete: :delete_all), null: false)
      add(:scenario_id, references(:smoke_scenarios, on_delete: :delete_all), null: false)
      add(:stage, :string, null: false)
      add(:outcome, :string, null: false)
      add(:verification_level, :string, null: false)
      add(:details, :map, null: false, default: %{})
      add(:observed_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:smoke_observations, [:run_id, :scenario_id, :inserted_at]))
  end
end
