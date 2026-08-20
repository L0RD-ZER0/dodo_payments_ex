defmodule DodoStore.Commerce.CreditGrant do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "commerce_credit_grants" do
    field(:account_id, :string)
    field(:source_id, :string)
    field(:period, :string)
    field(:amount, :integer)
    field(:kind, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:account_id, :source_id, :period, :amount, :kind])
    |> validate_required([:account_id, :source_id, :period, :amount, :kind])
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint(:source_id)
  end
end
