defmodule DodoStore.CatalogTest do
  use ExUnit.Case, async: false

  alias DodoStore.Catalog

  test "an empty application product ID is treated as unconfigured" do
    product_id = Application.get_env(:dodo_store, :product_id)
    product_id_file = Application.get_env(:dodo_store, :product_id_file)
    system_product_id = System.get_env("DODO_PRODUCT_ID")
    missing_file = Path.join(System.tmp_dir!(), "missing-dodo-product-id")

    on_exit(fn ->
      restore_env(:product_id, product_id)
      restore_env(:product_id_file, product_id_file)
      restore_system_env("DODO_PRODUCT_ID", system_product_id)
    end)

    Application.put_env(:dodo_store, :product_id, "")
    Application.put_env(:dodo_store, :product_id_file, missing_file)
    System.delete_env("DODO_PRODUCT_ID")

    assert Catalog.product_id() == nil
    assert Catalog.fetch_product_id() == {:error, :product_not_configured}
  end

  defp restore_env(key, nil), do: Application.delete_env(:dodo_store, key)
  defp restore_env(key, value), do: Application.put_env(:dodo_store, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
