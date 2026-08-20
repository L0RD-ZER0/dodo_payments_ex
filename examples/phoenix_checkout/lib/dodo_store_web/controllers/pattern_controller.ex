defmodule DodoStoreWeb.PatternController do
  use DodoStoreWeb, :controller

  alias DodoStore.{Billing, Checkout, Dodo, Patterns, Workflows}

  def index(conn, _params) do
    render(conn, :index,
      patterns: Patterns.all(),
      records: Billing.records(),
      commands: Billing.pending_commands(),
      buckets: Billing.usage_buckets()
    )
  end

  def show(conn, %{"id" => id}) do
    case Patterns.fetch(id) do
      {:ok, pattern} ->
        render(conn, :show,
          pattern: pattern,
          records: Billing.records(pattern.id),
          commands: Billing.pending_commands(),
          buckets: Billing.usage_buckets()
        )

      :error ->
        conn
        |> put_status(:not_found)
        |> text("Unknown billing pattern")
    end
  end

  def demo(conn, %{"id" => id}) do
    with {:ok, pattern} <- Patterns.fetch(id),
         {:ok, message} <- Patterns.demo(pattern.id) do
      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/patterns/#{pattern.slug}")
    else
      :error ->
        conn
        |> put_status(:not_found)
        |> text("Unknown billing pattern")

      {:error, _error} ->
        conn
        |> put_flash(:error, "The demo action could not be persisted.")
        |> redirect(to: ~p"/patterns")
    end
  end

  def checkout(conn, %{"id" => id} = params) do
    with {:ok, pattern} <- Patterns.fetch(id),
         true <- pattern.id in [2, 3, 5, 6, 9],
         {:ok, cart} <- cart(params["product_ids"]),
         {:ok, options} <- checkout_options(pattern.id, params),
         order_id = Checkout.order_id(),
         {:ok, checkout} <-
           Workflows.checkout(
             Dodo.client(),
             pattern.id,
             cart,
             absolute_url("/checkout/return"),
             absolute_url("/patterns/#{pattern.slug}"),
             order_id,
             options
           ) do
      conn
      |> put_view(DodoStoreWeb.StoreHTML)
      |> render(:checkout, checkout: checkout, dodo_mode: Dodo.mode())
    else
      false ->
        conn |> put_status(:not_found) |> text("This pattern does not use hosted checkout")

      :error ->
        conn |> put_status(:not_found) |> text("Unknown billing pattern")

      {:error, error} ->
        conn
        |> put_flash(:error, "Checkout was not started: #{friendly_error(error)}")
        |> redirect(to: ~p"/patterns/#{id}")
    end
  end

  defp cart(value) when is_binary(value) do
    items =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&%{product_id: &1, quantity: 1})

    if items == [], do: {:error, :product_ids_required}, else: {:ok, items}
  end

  defp cart(_value), do: {:error, :product_ids_required}

  defp checkout_options(pattern, params) when pattern in [2, 5, 6, 9] do
    account_id = String.trim(params["account_id"] || "")
    credits = parse_positive_integer(params["credits"])

    cond do
      account_id == "" -> {:error, :account_id_required}
      pattern in [5, 9] and is_nil(credits) -> {:error, :credits_required}
      true -> {:ok, [account_id: account_id, credits: credits]}
    end
  end

  defp checkout_options(3, _params), do: {:ok, []}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _error -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp friendly_error(error) when is_atom(error),
    do: error |> Atom.to_string() |> String.replace("_", " ")

  defp friendly_error(_error), do: "Dodo or local persistence returned an error"
  defp absolute_url(path), do: DodoStoreWeb.Endpoint.url() <> path
end
