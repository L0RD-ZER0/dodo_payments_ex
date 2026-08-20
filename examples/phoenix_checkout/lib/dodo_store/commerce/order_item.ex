defmodule DodoStore.Commerce.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "commerce_order_items" do
    field(:line_key, :string)
    field(:product_id, :string)
    field(:quantity, :integer)
    field(:status, :string)
    field(:fulfilled_at, :utc_datetime_usec)
    belongs_to(:order, DodoStore.Commerce.Order)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:order_id, :line_key, :product_id, :quantity, :status, :fulfilled_at])
    |> validate_required([:order_id, :line_key, :product_id, :quantity, :status])
    |> validate_number(:quantity, greater_than: 0)
    |> unique_constraint([:order_id, :line_key])
  end
end
