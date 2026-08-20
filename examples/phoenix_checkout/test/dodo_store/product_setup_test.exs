defmodule DodoStore.ProductSetupTest do
  use ExUnit.Case, async: false

  setup {Req.Test, :verify_on_exit!}

  setup do
    keys = [:dodo_payments, :product_id, :product_id_file]
    original_config = Map.new(keys, &{&1, Application.fetch_env(:dodo_store, &1)})
    original_product_id = System.get_env("DODO_PRODUCT_ID")
    original_live_override = System.get_env("DODO_ALLOW_LIVE_EXAMPLE")

    product_id_file =
      Path.join(System.tmp_dir!(), "dodo-product-#{System.unique_integer([:positive])}")

    Application.put_env(:dodo_store, :product_id_file, product_id_file)
    System.delete_env("DODO_PRODUCT_ID")
    System.delete_env("DODO_ALLOW_LIVE_EXAMPLE")

    on_exit(fn ->
      Enum.each(original_config, fn
        {key, {:ok, value}} -> Application.put_env(:dodo_store, key, value)
        {key, :error} -> Application.delete_env(:dodo_store, key)
      end)

      restore_env("DODO_PRODUCT_ID", original_product_id)
      restore_env("DODO_ALLOW_LIVE_EXAMPLE", original_live_override)
      File.rm(product_id_file)
      File.rmdir(product_id_file <> ".setup-lock")
    end)

    {:ok, product_id_file: product_id_file}
  end

  test "creates the hard-coded product and remembers its identifier", %{product_id_file: path} do
    DodoStore.DodoTest.configure(__MODULE__.DodoStub, product_id: nil)

    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/products"

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "name" => "Phoenix Field Guide",
               "price" => %{
                 "currency" => "USD",
                 "price" => 1_900,
                 "type" => "one_time_price"
               },
               "tax_category" => "e_book"
             } = Jason.decode!(body)

      Req.Test.json(conn, %{
        "product_id" => "pdt_created",
        "name" => "Phoenix Field Guide"
      })
    end)

    assert {:ok, %DodoPayments.Product{product_id: "pdt_created"}, :created} =
             DodoStore.ProductSetup.ensure_product()

    assert File.read!(path) == "pdt_created\n"
  end

  test "reuses a remembered product rather than creating another", %{product_id_file: path} do
    File.write!(path, "pdt_existing\n")
    DodoStore.DodoTest.configure(__MODULE__.DodoStub, product_id: nil)

    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/products/pdt_existing"

      Req.Test.json(conn, %{
        "product_id" => "pdt_existing",
        "name" => "Phoenix Field Guide"
      })
    end)

    assert {:ok, %DodoPayments.Product{product_id: "pdt_existing"}, :existing} =
             DodoStore.ProductSetup.ensure_product()
  end

  test "requires an explicit override before managing a live product" do
    DodoStore.DodoTest.configure(__MODULE__.DodoStub, product_id: nil, environment: :live)

    assert {:error, message} = DodoStore.ProductSetup.ensure_product()
    assert message =~ "refusing to manage a live product"
  end

  test "a local lock prevents concurrent setup from creating another product", %{
    product_id_file: path
  } do
    DodoStore.DodoTest.configure(__MODULE__.DodoStub, product_id: nil)
    :ok = File.mkdir(path <> ".setup-lock")

    assert {:error, {:setup_locked, lock_path}} = DodoStore.ProductSetup.ensure_product()
    assert lock_path == path <> ".setup-lock"
  end

  test "a persistence failure returns the remote product id", %{product_id_file: path} do
    DodoStore.DodoTest.configure(__MODULE__.DodoStub, product_id: nil)

    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      :ok = File.mkdir(path)

      Req.Test.json(conn, %{
        "product_id" => "pdt_recoverable",
        "name" => "Phoenix Field Guide"
      })
    end)

    assert {:error, {:product_created_but_not_saved, "pdt_recoverable", _reason}} =
             DodoStore.ProductSetup.ensure_product()

    File.rmdir(path)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
