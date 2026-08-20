defmodule DodoStore.Repo.Migrations.CreateUsageReservations do
  use Ecto.Migration

  def change do
    create table(:usage_reservations) do
      add(:reservation_id, :string, null: false)
      add(:account_id, :string, null: false)
      add(:metric, :string, null: false)
      add(:period, :string, null: false)
      add(:amount, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:usage_reservations, [:reservation_id]))
    create(index(:usage_reservations, [:account_id, :metric, :period]))
  end
end
