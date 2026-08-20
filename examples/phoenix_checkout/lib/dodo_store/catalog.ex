defmodule DodoStore.Catalog do
  @moduledoc "The single hard-coded product sold by this example."

  @product_id_file "tmp/dodo_product_id"
  @setup_lock_suffix ".setup-lock"

  @spec product() :: map()
  def product do
    %{
      name: "Phoenix Field Guide",
      description: "A small one-time digital product used by the Dodo Payments SDK example.",
      price: %{
        currency: "USD",
        discount: 0,
        price: 1_900,
        purchasing_power_parity: false,
        type: "one_time_price"
      },
      tax_category: "e_book",
      metadata: %{"example" => "dodo-payments-elixir-phoenix"}
    }
  end

  @spec product_id() :: String.t() | nil
  def product_id do
    non_empty(Application.get_env(:dodo_store, :product_id)) ||
      non_empty(System.get_env("DODO_PRODUCT_ID")) ||
      read_product_id()
  end

  @spec fetch_product_id() :: {:ok, String.t()} | {:error, :product_not_configured}
  def fetch_product_id do
    case product_id() do
      nil -> {:error, :product_not_configured}
      product_id -> {:ok, product_id}
    end
  end

  @spec save_product_id(String.t()) :: :ok | {:error, File.posix()}
  def save_product_id(product_id) when is_binary(product_id) and product_id != "" do
    path = product_id_path()
    temporary = path <> ".tmp.#{System.unique_integer([:positive, :monotonic])}"

    try do
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(temporary, product_id <> "\n") do
        File.rename(temporary, path)
      end
    after
      File.rm(temporary)
    end
  end

  @spec with_product_setup_lock((-> result)) ::
          result
          | {:error, {:setup_locked, String.t()}}
          | {:error, {:setup_lock_failed, String.t(), File.posix()}}
        when result: term()
  def with_product_setup_lock(fun) when is_function(fun, 0) do
    lock_path = product_id_path() <> @setup_lock_suffix

    case File.mkdir_p(Path.dirname(lock_path)) do
      :ok -> acquire_product_setup_lock(lock_path, fun)
      {:error, reason} -> {:error, {:setup_lock_failed, lock_path, reason}}
    end
  end

  defp acquire_product_setup_lock(lock_path, fun) do
    case File.mkdir(lock_path) do
      :ok ->
        try do
          fun.()
        after
          File.rmdir(lock_path)
        end

      {:error, :eexist} ->
        {:error, {:setup_locked, lock_path}}

      {:error, reason} ->
        {:error, {:setup_lock_failed, lock_path, reason}}
    end
  end

  defp read_product_id do
    case File.read(product_id_path()) do
      {:ok, contents} ->
        contents |> String.trim() |> non_empty()

      {:error, :enoent} ->
        nil

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read", path: product_id_path()
    end
  end

  defp product_id_path do
    Application.get_env(:dodo_store, :product_id_file, @product_id_file)
    |> Path.expand(File.cwd!())
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(value), do: value
end
