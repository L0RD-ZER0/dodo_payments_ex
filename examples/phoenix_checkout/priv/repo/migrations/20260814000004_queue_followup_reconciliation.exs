defmodule DodoStore.Repo.Migrations.QueueFollowupReconciliation do
  use Ecto.Migration

  def change do
    alter table(:billing_outbox) do
      add(:reconcile_again, :boolean, null: false, default: false)
    end
  end
end
