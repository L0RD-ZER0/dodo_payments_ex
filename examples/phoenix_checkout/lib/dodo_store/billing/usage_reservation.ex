defmodule DodoStore.Billing.UsageReservation do
  @moduledoc "A durable, idempotent authorization for one business action."

  use Ecto.Schema

  schema "usage_reservations" do
    field(:reservation_id, :string)
    field(:account_id, :string)
    field(:metric, :string)
    field(:period, :string)
    field(:amount, :integer)
    field(:requested_limit, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
