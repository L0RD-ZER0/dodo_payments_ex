defmodule DodoStore.Checkout do
  @moduledoc "Low-level hosted checkout call used after `Commerce.expect_order/4`."

  @doc "Creates any one-time, subscription, mixed, credit, or usage-product cart."
  @spec create_cart(DodoPayments.Client.t(), [map()], String.t(), String.t(), keyword(), map()) ::
          {:ok, DodoPayments.CheckoutSession.t()} | {:error, Exception.t()}
  def create_cart(
        client,
        product_cart,
        return_url,
        cancel_url,
        metadata \\ [],
        checkout_params \\ %{}
      ) do
    params = %{
      product_cart: product_cart,
      return_url: return_url,
      cancel_url: cancel_url,
      metadata: Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
    }

    # The application-owned fields above cannot be replaced by optional
    # pattern configuration.
    DodoPayments.CheckoutSessions.create(client, Map.merge(checkout_params, params))
  end

  @doc "Generates the unguessable application order ID embedded in Dodo metadata."
  def order_id do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
