defmodule DodoStore.Billing.OutboxCommand do
  @moduledoc "An idempotent application command awaiting delivery or reconciliation."

  use Ecto.Schema
  import Ecto.Changeset

  schema "billing_outbox" do
    field(:command_id, :string)
    field(:kind, :string)
    field(:payload, :map)
    field(:state, :string, default: "pending")
    field(:attempts, :integer, default: 0)
    field(:result, :map)
    field(:delivered_at, :utc_datetime_usec)
    field(:available_at, :utc_datetime_usec)
    field(:claimed_at, :utc_datetime_usec)
    field(:claim_token, :string)
    field(:resource_key, :string)
    field(:reconcile_again, :boolean, default: false)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(command, attrs) do
    command
    |> cast(attrs, [:command_id, :kind, :payload, :state, :resource_key])
    |> validate_required([:command_id, :kind, :payload, :state])
    |> unique_constraint(:command_id)
    |> unique_constraint(:resource_key, name: :billing_outbox_one_active_reconciliation)
    |> unique_constraint(:resource_key, name: :billing_outbox_resource_key_index)
  end
end
