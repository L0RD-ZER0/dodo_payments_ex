defmodule DodoStore.Billing.Record do
  @moduledoc "Application-owned billing and entitlement projection."

  use Ecto.Schema
  import Ecto.Changeset

  schema "billing_records" do
    field(:pattern, :integer)
    field(:business_key, :string)
    field(:status, :string)
    field(:data, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:pattern, :business_key, :status, :data])
    |> validate_required([:pattern, :business_key, :status, :data])
    |> validate_number(:pattern, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> unique_constraint([:pattern, :business_key])
  end
end
