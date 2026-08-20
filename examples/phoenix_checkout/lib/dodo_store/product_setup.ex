defmodule DodoStore.ProductSetup do
  @moduledoc "Creates the example product once and remembers its Dodo identifier locally."

  alias DodoPayments.Error.APIError
  alias DodoStore.{Catalog, Dodo}

  @spec ensure_product() ::
          {:ok, DodoPayments.Product.t(), :created | :existing} | {:error, term()}
  def ensure_product do
    with :ok <- allow_product_mutation() do
      Catalog.with_product_setup_lock(&do_ensure_product/0)
    end
  end

  defp do_ensure_product do
    case Catalog.product_id() do
      nil -> create_product()
      product_id -> retrieve_product(product_id)
    end
  end

  defp allow_product_mutation do
    if Dodo.mode() == :live and System.get_env("DODO_ALLOW_LIVE_EXAMPLE") != "true" do
      {:error,
       "refusing to manage a live product; set DODO_ALLOW_LIVE_EXAMPLE=true only after reviewing the payload"}
    else
      :ok
    end
  end

  defp retrieve_product(product_id) do
    case DodoPayments.Products.retrieve(Dodo.client(), product_id) do
      {:ok, product} ->
        {:ok, product, :existing}

      {:error, %APIError{status: 404}} ->
        {:error,
         "configured product #{product_id} does not exist; remove DODO_PRODUCT_ID or tmp/dodo_product_id before creating another"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_product do
    case DodoPayments.Products.create(Dodo.client(), Catalog.product()) do
      {:ok, %DodoPayments.Product{product_id: product_id} = product}
      when is_binary(product_id) and product_id != "" ->
        case Catalog.save_product_id(product_id) do
          :ok ->
            {:ok, product, :created}

          {:error, reason} ->
            {:error, {:product_created_but_not_saved, product_id, reason}}
        end

      {:ok, product} ->
        {:error, {:missing_product_id, product}}

      {:error, error} ->
        {:error, error}
    end
  end
end
