defmodule DodoStore.Repo.Migrations.HardenDurableDelivery do
  use Ecto.Migration

  def up do
    alter table(:webhook_inbox) do
      add(:available_at, :utc_datetime_usec)
      add(:claimed_at, :utc_datetime_usec)
      add(:claim_token, :string)
      add(:dead_lettered_at, :utc_datetime_usec)
    end

    create(index(:webhook_inbox, [:state, :available_at, :inserted_at]))

    alter table(:billing_outbox) do
      add(:available_at, :utc_datetime_usec)
      add(:claimed_at, :utc_datetime_usec)
      add(:claim_token, :string)
      add(:resource_key, :string)
    end

    create(index(:billing_outbox, [:state, :available_at, :inserted_at]))

    execute("""
    CREATE UNIQUE INDEX billing_outbox_one_active_reconciliation
    ON billing_outbox(resource_key)
    WHERE resource_key IS NOT NULL
      AND state IN ('pending', 'retryable', 'dispatching')
    """)

    alter table(:usage_reservations) do
      add(:requested_limit, :integer)
    end

    execute("""
    UPDATE usage_reservations
    SET requested_limit = (
      SELECT usage_buckets.`limit`
      FROM usage_buckets
      WHERE usage_buckets.account_id = usage_reservations.account_id
        AND usage_buckets.metric = usage_reservations.metric
        AND usage_buckets.period = usage_reservations.period
    )
    WHERE requested_limit IS NULL
    """)
  end

  def down do
    alter table(:usage_reservations) do
      remove(:requested_limit)
    end

    execute("DROP INDEX billing_outbox_one_active_reconciliation")
    drop(index(:billing_outbox, [:state, :available_at, :inserted_at]))

    alter table(:billing_outbox) do
      remove(:resource_key)
      remove(:claim_token)
      remove(:claimed_at)
      remove(:available_at)
    end

    drop(index(:webhook_inbox, [:state, :available_at, :inserted_at]))

    alter table(:webhook_inbox) do
      remove(:dead_lettered_at)
      remove(:claim_token)
      remove(:claimed_at)
      remove(:available_at)
    end
  end
end
