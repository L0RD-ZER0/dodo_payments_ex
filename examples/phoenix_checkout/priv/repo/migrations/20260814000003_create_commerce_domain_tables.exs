defmodule DodoStore.Repo.Migrations.CreateCommerceDomainTables do
  use Ecto.Migration

  def change do
    create table(:commerce_orders) do
      add(:order_id, :string, null: false)
      add(:pattern, :integer, null: false)
      add(:account_id, :string)
      add(:status, :string, null: false)
      add(:expected_cart, :map, null: false)
      add(:payment_id, :string)
      add(:checkout_session_id, :string)
      add(:credits, :integer)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:commerce_orders, [:order_id]))
    create(unique_index(:commerce_orders, [:payment_id], where: "payment_id IS NOT NULL"))

    create table(:commerce_order_items) do
      add(:order_id, references(:commerce_orders, on_delete: :delete_all), null: false)
      add(:line_key, :string, null: false)
      add(:product_id, :string, null: false)
      add(:quantity, :integer, null: false)
      add(:status, :string, null: false)
      add(:fulfilled_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:commerce_order_items, [:order_id, :line_key]))

    create table(:commerce_subscriptions) do
      add(:subscription_id, :string, null: false)
      add(:account_id, :string, null: false)
      add(:pattern, :integer, null: false)
      add(:status, :string, null: false)
      add(:mandate_ready, :boolean, null: false, default: false)
      add(:period, :string)
      add(:period_ends_at, :utc_datetime_usec)
      add(:credits_per_period, :integer)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:commerce_subscriptions, [:subscription_id]))
    create(index(:commerce_subscriptions, [:account_id, :pattern, :status]))

    create table(:commerce_credit_grants) do
      add(:account_id, :string, null: false)
      add(:source_id, :string, null: false)
      add(:period, :string, null: false)
      add(:amount, :integer, null: false)
      add(:kind, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:commerce_credit_grants, [:source_id]))
    create(index(:commerce_credit_grants, [:account_id, :period]))
  end
end
