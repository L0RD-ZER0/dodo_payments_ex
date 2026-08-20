defmodule DodoStore.Commerce.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "commerce_orders" do
    field(:order_id, :string)
    field(:pattern, :integer)
    field(:account_id, :string)
    field(:status, :string)
    field(:expected_cart, {:array, :map})
    field(:payment_id, :string)
    field(:checkout_session_id, :string)
    field(:credits, :integer)
    has_many(:items, DodoStore.Commerce.OrderItem)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :order_id,
      :pattern,
      :account_id,
      :status,
      :expected_cart,
      :payment_id,
      :checkout_session_id,
      :credits
    ])
    |> validate_required([:order_id, :pattern, :status, :expected_cart])
    |> validate_inclusion(:pattern, 1..10)
    |> validate_number(:credits, greater_than: 0)
    |> unique_constraint(:order_id)
    |> unique_constraint(:payment_id)
  end
end
