defmodule DodoStore.DodoTest do
  @moduledoc false

  def configure(stub, opts \\ []) do
    put_product_id(Keyword.get(opts, :product_id, "pdt_example"))

    Application.put_env(:dodo_store, :dodo_payments,
      environment: Keyword.get(opts, :environment, :test),
      api_key: "sk_test",
      max_attempts: 1,
      req: Req.new(plug: {Req.Test, stub})
    )
  end

  defp put_product_id(nil), do: Application.delete_env(:dodo_store, :product_id)
  defp put_product_id(product_id), do: Application.put_env(:dodo_store, :product_id, product_id)
end
