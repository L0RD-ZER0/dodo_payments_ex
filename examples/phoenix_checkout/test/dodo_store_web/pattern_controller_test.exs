defmodule DodoStoreWeb.PatternControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint DodoStoreWeb.Endpoint

  setup {Req.Test, :verify_on_exit!}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DodoStore.Repo)
    DodoStore.DodoTest.configure(__MODULE__.DodoStub)
    :ok
  end

  test "index makes all ten patterns discoverable" do
    body = build_conn() |> get("/patterns") |> html_response(200)

    assert body =~ "Ten billing patterns"
    assert body =~ "One-time hosted checkout"
    assert body =~ "Multiple-meter billing"
    assert body =~ "Hard usage limits"
  end

  test "a safe demo persists local state and redirects to the pattern" do
    conn = post(build_conn(), "/patterns/hard-usage-limit/demo", %{})

    assert redirected_to(conn) == "/patterns/hard-usage-limit"
    assert [%{metric: "exports", used: 1}] = DodoStore.Billing.usage_buckets()
  end

  test "unknown patterns return 404" do
    assert build_conn() |> get("/patterns/not-real") |> response(404) ==
             "Unknown billing pattern"
  end

  test "checkout patterns are executable from the browser with an expected local order" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = Jason.decode!(body)

      assert params["product_cart"] == [%{"product_id" => "pdt_credits", "quantity" => 1}]
      assert params["metadata"]["example_pattern"] == 5
      assert params["metadata"]["example_account_id"] == "account_browser"
      assert params["metadata"]["example_credits_per_period"] == 250
      assert is_binary(params["metadata"]["example_cart_hash"])

      Req.Test.json(conn, %{
        "session_id" => "cks_credits",
        "checkout_url" => "https://test.checkout.dodopayments.com/session/cks_credits"
      })
    end)

    conn =
      post(build_conn(), "/patterns/prepaid-credits/checkout", %{
        "product_ids" => "pdt_credits",
        "account_id" => "account_browser",
        "credits" => "250"
      })

    assert html_response(conn, 200) =~ "Your checkout is ready"

    assert [%{account_id: "account_browser", status: "checkout_created"}] =
             DodoStore.Repo.all(DodoStore.Commerce.Order)
  end
end
