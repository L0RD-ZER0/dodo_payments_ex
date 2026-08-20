defmodule DodoStore.Billing.UsageBucket do
  @moduledoc "An application-enforced allowance for one account, metric, and period."

  use Ecto.Schema
  import Ecto.Changeset

  schema "usage_buckets" do
    field(:account_id, :string)
    field(:metric, :string)
    field(:period, :string)
    field(:used, :integer, default: 0)
    field(:limit, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:account_id, :metric, :period, :used, :limit])
    |> validate_required([:account_id, :metric, :period, :used, :limit])
    |> validate_number(:used, greater_than_or_equal_to: 0)
    |> validate_number(:limit, greater_than: 0)
    |> unique_constraint([:account_id, :metric, :period])
  end
end
