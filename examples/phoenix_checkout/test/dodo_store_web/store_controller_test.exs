defmodule DodoStoreWeb.StoreControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint DodoStoreWeb.Endpoint

  setup {Req.Test, :verify_on_exit!}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DodoStore.Repo)
    DodoStore.DodoTest.configure(__MODULE__.DodoStub)
    :ok
  end

  test "renders the configured product" do
    conn = get(build_conn(), "/")

    assert html_response(conn, 200) =~ "Phoenix Field Guide"
    assert html_response(conn, 200) =~ "Open secure checkout"
  end

  test "creates a server-side checkout session and renders the overlay launcher" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/checkouts"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = Jason.decode!(body)

      assert %{"product_cart" => [%{"product_id" => "pdt_example", "quantity" => 1}]} =
               params

      assert params["return_url"] == "http://localhost:4002/checkout/return"
      assert params["cancel_url"] == "http://localhost:4002/"

      Req.Test.json(conn, %{
        "session_id" => "cks_example",
        "checkout_url" => "https://test.checkout.dodopayments.com/session/cks_example"
      })
    end)

    conn = post(build_conn(), "/checkout")
    body = html_response(conn, 200)

    assert body =~ "Your checkout is ready"
    assert body =~ "https://test.checkout.dodopayments.com/session/cks_example"
    refute body =~ "sk_test"
  end

  test "checkout errors do not expose exception details in the browser" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      conn
      |> Plug.Conn.put_status(502)
      |> Req.Test.json(%{"error" => "SENTINEL_PRIVATE_DODO_DETAIL"})
    end)

    body =
      build_conn()
      |> post("/checkout")
      |> html_response(502)

    assert body =~ "We could not start checkout right now"
    refute body =~ "SENTINEL_PRIVATE_DODO_DETAIL"
  end

  test "return page warns that redirect parameters are not fulfillment evidence" do
    assert {:ok, _order} =
             DodoStore.Commerce.expect_order("order_return", 1, [
               %{product_id: "pdt_example", quantity: 1}
             ])

    conn = get(build_conn(), "/checkout/return?status=succeeded&payment_id=pay_123")
    body = html_response(conn, 200)

    assert body =~ "pay_123"
    assert body =~ "verifying a Dodo webhook"

    order = DodoStore.Commerce.get_order("order_return")
    assert order.status == "checkout_pending"
    assert order.payment_id == nil
    assert DodoStore.Billing.pending_webhooks() == []
  end
end
