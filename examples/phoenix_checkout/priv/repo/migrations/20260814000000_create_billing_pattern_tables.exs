defmodule DodoStore.Repo.Migrations.CreateBillingPatternTables do
  use Ecto.Migration

  def change do
    create table(:billing_records) do
      add(:pattern, :integer, null: false)
      add(:business_key, :string, null: false)
      add(:status, :string, null: false)
      add(:data, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:billing_records, [:pattern, :business_key]))

    create table(:webhook_inbox) do
      add(:webhook_id, :string, null: false)
      add(:event_type, :string, null: false)
      add(:resource_id, :string)
      add(:payload, :map, null: false)
      add(:state, :string, null: false, default: "pending")
      add(:attempts, :integer, null: false, default: 0)
      add(:last_error, :string)
      add(:processed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:webhook_inbox, [:webhook_id]))
    create(index(:webhook_inbox, [:state, :inserted_at]))

    create table(:billing_outbox) do
      add(:command_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:payload, :map, null: false)
      add(:state, :string, null: false, default: "pending")
      add(:attempts, :integer, null: false, default: 0)
      add(:result, :map)
      add(:delivered_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:billing_outbox, [:command_id]))
    create(index(:billing_outbox, [:state, :inserted_at]))

    create table(:usage_buckets) do
      add(:account_id, :string, null: false)
      add(:metric, :string, null: false)
      add(:period, :string, null: false)
      add(:used, :integer, null: false, default: 0)
      add(:limit, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:usage_buckets, [:account_id, :metric, :period]))
  end
end
