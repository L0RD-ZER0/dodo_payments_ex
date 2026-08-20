defmodule DodoPayments.SetupDXTest do
  use ExUnit.Case, async: false

  alias DodoPayments.Error

  setup_all do
    start_supervised!({Finch, name: __MODULE__.Finch})
    :ok
  end

  test "runtime application configuration builds an explicit client" do
    Application.put_env(:dodo_setup_test, :dodo_payments,
      environment: "test_mode",
      api_key: fn -> "sk_runtime_test" end,
      timeout: 5_000
    )

    on_exit(fn -> Application.delete_env(:dodo_setup_test, :dodo_payments) end)

    client =
      :dodo_setup_test
      |> Application.fetch_env!(:dodo_payments)
      |> DodoPayments.client!()

    assert client.environment == :test
    assert client.timeout == 5_000
  end

  test "client construction returns configuration errors for malformed options" do
    assert {:error, %Error.ConfigurationError{message: message}} =
             DodoPayments.client(%{environment: :test})

    assert message =~ "keyword list"
  end

  test "ReqClient constructors follow tagged and raising conventions" do
    assert {:ok, %DodoPayments.ReqClient{}} = DodoPayments.ReqClient.new()
    assert %DodoPayments.ReqClient{} = DodoPayments.ReqClient.new!()

    credentialed = Req.new(headers: [{"authorization", "Bearer retained"}])

    assert {:error, %Error.ConfigurationError{}} =
             DodoPayments.ReqClient.from_req(credentialed)

    assert_raise Error.ConfigurationError, fn ->
      DodoPayments.ReqClient.from_req!(credentialed)
    end
  end

  test "Req.Test provides a no-network setup path" do
    Req.Test.stub(__MODULE__.Stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_test"]
      Req.Test.json(conn, %{"product_id" => "pdt_123", "name" => "Starter"})
    end)

    client =
      DodoPayments.client!(
        environment: :test,
        api_key: "sk_test",
        req: Req.new(plug: {Req.Test, __MODULE__.Stub})
      )

    assert {:ok, %DodoPayments.Product{product_id: "pdt_123", name: "Starter"}} =
             DodoPayments.Products.retrieve(client, "pdt_123")
  end

  test "a supervised named Finch does not conflict with request timeouts" do
    client =
      DodoPayments.client!(
        environment: :custom,
        base_url: "http://127.0.0.1:1",
        allow_insecure_http: true,
        api_key: "sk_test",
        req: Req.new(finch: [name: __MODULE__.Finch]),
        timeout: 200,
        max_attempts: 1
      )

    assert {:error, error} =
             DodoPayments.Products.retrieve(client, "pdt_123")

    assert match?(%Error.TransportError{}, error) or match?(%Error.TimeoutError{}, error)

    if match?(%Error.TransportError{}, error) do
      refute match?(%ArgumentError{}, error.reason)
    end
  end
end
