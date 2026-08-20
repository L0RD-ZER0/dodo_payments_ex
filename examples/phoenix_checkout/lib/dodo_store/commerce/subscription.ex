defmodule DodoStore.Commerce.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "commerce_subscriptions" do
    field(:subscription_id, :string)
    field(:account_id, :string)
    field(:pattern, :integer)
    field(:status, :string)
    field(:mandate_ready, :boolean, default: false)
    field(:period, :string)
    field(:period_ends_at, :utc_datetime_usec)
    field(:credits_per_period, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :subscription_id,
      :account_id,
      :pattern,
      :status,
      :mandate_ready,
      :period,
      :period_ends_at,
      :credits_per_period
    ])
    |> validate_required([:subscription_id, :account_id, :pattern, :status])
    |> validate_inclusion(:pattern, [2, 6, 9])
    |> validate_number(:credits_per_period, greater_than: 0)
    |> unique_constraint(:subscription_id)
  end
end
