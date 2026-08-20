defmodule DodoStoreWeb.StoreController do
  use DodoStoreWeb, :controller

  alias DodoStore.{Catalog, Checkout, Dodo, Workflows}

  def index(conn, _params) do
    render(conn, :index,
      product: Catalog.product(),
      product_id: Catalog.product_id(),
      dodo_mode: Dodo.mode()
    )
  end

  def create_checkout(conn, _params) do
    order_id = Checkout.order_id()

    with {:ok, product_id} <- Catalog.fetch_product_id(),
         {:ok, checkout} <-
           Workflows.checkout(
             Dodo.client(),
             1,
             [%{product_id: product_id, quantity: 1}],
             absolute_url("/checkout/return"),
             absolute_url("/"),
             order_id
           ) do
      render(conn, :checkout, checkout: checkout, dodo_mode: Dodo.mode())
    else
      {:error, :product_not_configured} ->
        conn
        |> put_flash(:error, "Run mix run scripts/create_product.exs before starting checkout.")
        |> redirect(to: ~p"/")

      {:error, error} ->
        conn
        |> put_status(:bad_gateway)
        |> render(:checkout_error, error: error)
    end
  end

  def checkout_return(conn, params) do
    # Redirect parameters improve UX, but are not trusted fulfillment evidence.
    result = Map.take(params, ["payment_id", "subscription_id", "status"])
    render(conn, :checkout_return, result: result)
  end

  defp absolute_url(path), do: DodoStoreWeb.Endpoint.url() <> path
end
