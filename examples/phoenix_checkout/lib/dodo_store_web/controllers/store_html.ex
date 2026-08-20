defmodule DodoStoreWeb.StoreHTML do
  use DodoStoreWeb, :html

  embed_templates("store_html/*")

  def price_in_dollars(%{price: %{price: cents}}) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end
end
