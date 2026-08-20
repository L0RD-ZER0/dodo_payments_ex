defmodule DodoStore.Billing.InboxEvent do
  @moduledoc "A verified webhook durably accepted for supervised processing."

  use Ecto.Schema
  import Ecto.Changeset

  schema "webhook_inbox" do
    field(:webhook_id, :string)
    field(:event_type, :string)
    field(:resource_id, :string)
    field(:payload, :map)
    field(:state, :string, default: "pending")
    field(:attempts, :integer, default: 0)
    field(:last_error, :string)
    field(:processed_at, :utc_datetime_usec)
    field(:available_at, :utc_datetime_usec)
    field(:claimed_at, :utc_datetime_usec)
    field(:claim_token, :string)
    field(:dead_lettered_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:webhook_id, :event_type, :resource_id, :payload, :state])
    |> validate_required([:webhook_id, :event_type, :payload, :state])
    |> unique_constraint(:webhook_id)
  end
end
