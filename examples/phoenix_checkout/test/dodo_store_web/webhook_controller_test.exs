defmodule DodoStoreWeb.WebhookControllerTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias DodoStore.Billing.{InboxEvent, OutboxCommand, Record}
  alias DodoStore.Commerce
  alias DodoStore.Commerce.Subscription
  alias DodoStore.Repo

  @endpoint DodoStoreWeb.Endpoint
  @key "test-webhook-secret"

  setup {Req.Test, :verify_on_exit!}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    DodoStore.DodoTest.configure(__MODULE__.DodoStub)
    Application.put_env(:dodo_store, :webhook_secrets, ["whsec_" <> Base.encode64(@key)])
    :ok
  end

  test "verified delivery is durably accepted once and fulfilled by the processor" do
    assert {:ok, _order} =
             Commerce.expect_order("order_1", 1, [%{product_id: "pdt_1", quantity: 1}])

    body =
      Jason.encode!(%{
        "type" => "payment.succeeded",
        "data" => %{
          "payment_id" => "pay_1",
          "metadata" => %{
            "example_pattern" => 1,
            "example_order_id" => "order_1",
            "example_cart_hash" =>
              Commerce.cart_fingerprint([%{product_id: "pdt_1", quantity: 1}])
          }
        }
      })

    assert signed_post(body, "wh_payment") |> response(200) == "accepted"
    assert signed_post(body, "wh_payment") |> response(200) == "accepted"
    assert Repo.aggregate(InboxEvent, :count) == 1

    assert :ok = DodoStore.Billing.InboxProcessor.run_once()

    assert %Record{status: "fulfilled", data: %{"payment_id" => "pay_1"}} =
             Repo.get_by!(Record, pattern: 1, business_key: "order_1")

    assert Repo.get_by!(InboxEvent, webhook_id: "wh_payment").state == "processed"
  end

  test "out-of-order lifecycle events enqueue reconciliation instead of overwriting state" do
    cancelled =
      Jason.encode!(%{
        "type" => "subscription.cancelled",
        "data" => %{"subscription_id" => "sub_1"}
      })

    active =
      Jason.encode!(%{"type" => "subscription.active", "data" => %{"subscription_id" => "sub_1"}})

    assert signed_post(cancelled, "wh_later") |> response(200) == "accepted"
    assert signed_post(active, "wh_earlier") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()

    assert Repo.aggregate(
             from(command in OutboxCommand, where: command.kind == "reconcile_subscription"),
             :count
           ) == 1

    assert Repo.aggregate(Record, :count) == 0

    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/subscriptions/sub_1"

      Req.Test.json(conn, %{
        "subscription_id" => "sub_1",
        "status" => "active",
        "metadata" => %{"example_pattern" => 2, "example_account_id" => "account_1"}
      })
    end)

    for command <- DodoStore.Billing.pending_commands() do
      assert {:ok, %DodoPayments.Subscription{status: :active}} =
               DodoStore.Billing.OutboxDispatcher.dispatch(command, DodoStore.Dodo.client())
    end

    assert %Record{status: "active", data: %{"source" => "current_state_reconciliation"}} =
             Repo.get_by!(Record, pattern: 2, business_key: "sub_1")
  end

  test "payment-method lifecycle uses the retrieved subscription snapshot, not redirect or event state" do
    return =
      get(
        build_conn(),
        "/checkout/return?status=succeeded&subscription_id=sub_payment_method&payment_id=pay_return"
      )

    assert html_response(return, 200) =~ "pay_return"
    assert Repo.get_by(Subscription, subscription_id: "sub_payment_method") == nil

    event =
      Jason.encode!(%{
        "type" => "subscription.update_payment_method",
        "data" => %{
          "subscription_id" => "sub_payment_method",
          "status" => "on_hold",
          "payment_method_id" => "pm_event"
        }
      })

    assert signed_post(event, "wh_payment_method") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Repo.get_by(Subscription, subscription_id: "sub_payment_method") == nil

    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/subscriptions/sub_payment_method"

      Req.Test.json(conn, %{
        "subscription_id" => "sub_payment_method",
        "status" => "active",
        "payment_method_id" => "pm_current",
        "metadata" => %{"example_pattern" => 2, "example_account_id" => "account_pm"}
      })
    end)

    assert [%OutboxCommand{} = command] = DodoStore.Billing.pending_commands()

    assert {:ok, %DodoPayments.Subscription{status: :active, payment_method_id: "pm_current"}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, DodoStore.Dodo.client())

    assert %Subscription{status: "active", account_id: "account_pm"} =
             Repo.get_by!(Subscription, subscription_id: "sub_payment_method")
  end

  test "a later dispute reconciles the current status without undoing the earlier payment fact" do
    assert {:ok, _order} =
             Commerce.expect_order("order_disputed", 1, [
               %{product_id: "pdt_disputed", quantity: 1}
             ])

    payment = payment_body("pay_disputed", "order_disputed", "pdt_disputed")
    assert signed_post(payment, "wh_paid_before_dispute") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Commerce.get_order("order_disputed").status == "fulfilled"

    opened =
      lifecycle_body("dispute.opened", %{
        "dispute_id" => "dis_current",
        "payment_id" => "pay_disputed",
        "dispute_status" => "dispute_opened"
      })

    lost =
      lifecycle_body("dispute.lost", %{
        "dispute_id" => "dis_current",
        "payment_id" => "pay_disputed",
        "dispute_status" => "dispute_lost"
      })

    assert signed_post(opened, "wh_dispute_opened") |> response(200) == "accepted"
    assert signed_post(opened, "wh_dispute_opened") |> response(200) == "accepted"
    assert signed_post(lost, "wh_dispute_lost") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()

    assert Repo.aggregate(
             from(command in OutboxCommand, where: command.kind == "reconcile_dispute"),
             :count
           ) == 1

    expect_dispute_snapshot(:dispute_lost)
    assert [%OutboxCommand{} = command] = DodoStore.Billing.pending_commands()

    assert {:ok, %DodoPayments.Dispute{dispute_status: :dispute_lost}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, DodoStore.Dodo.client())

    assert %Record{status: "dispute_lost", data: %{"source" => "current_state_reconciliation"}} =
             Repo.get_by!(Record, pattern: 7, business_key: "dis_current")

    # The example records the reversal for the host application's access policy;
    # an arrival-order projection must not erase the already-observed payment.
    assert Commerce.get_order("order_disputed").payment_id == "pay_disputed"

    assert signed_post(opened, "wh_dispute_opened_stale") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    expect_dispute_snapshot(:dispute_lost)
    assert [%OutboxCommand{} = stale_command] = DodoStore.Billing.pending_commands()

    assert {:ok, %DodoPayments.Dispute{dispute_status: :dispute_lost}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(
               stale_command,
               DodoStore.Dodo.client()
             )

    assert Repo.get_by!(Record, pattern: 7, business_key: "dis_current").status ==
             "dispute_lost"
  end

  test "out-of-order refund notifications persist only the retrieved current status" do
    succeeded =
      lifecycle_body("refund.succeeded", %{
        "refund_id" => "ref_current",
        "payment_id" => "pay_refunded",
        "status" => "succeeded"
      })

    stale_failed =
      lifecycle_body("refund.failed", %{
        "refund_id" => "ref_current",
        "payment_id" => "pay_refunded",
        "status" => "failed"
      })

    assert signed_post(succeeded, "wh_refund_succeeded") |> response(200) == "accepted"
    assert signed_post(stale_failed, "wh_refund_failed_stale") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Repo.get_by(Record, pattern: 7, business_key: "ref_current") == nil

    expect_refund_snapshot(:succeeded)
    assert [%OutboxCommand{} = command] = DodoStore.Billing.pending_commands()

    assert {:ok, %DodoPayments.Refund{status: :succeeded}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, DodoStore.Dodo.client())

    assert %Record{status: "succeeded", data: %{"source" => "current_state_reconciliation"}} =
             Repo.get_by!(Record, pattern: 7, business_key: "ref_current")
  end

  test "verified payments cannot invent orders, change carts, or overwrite payments" do
    assert {:ok, _order} =
             Commerce.expect_order("order_safe", 1, [%{product_id: "pdt_expected", quantity: 1}])

    mismatch =
      payment_body("pay_wrong", "order_safe", "pdt_other")

    unknown = payment_body("pay_unknown", "not_local", "pdt_expected")

    assert signed_post(mismatch, "wh_mismatch") |> response(200) == "accepted"
    assert signed_post(unknown, "wh_unknown") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Commerce.get_order("order_safe").payment_id == nil

    succeeded = payment_body("pay_safe", "order_safe", "pdt_expected")
    assert signed_post(succeeded, "wh_safe") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Commerce.get_order("order_safe").payment_id == "pay_safe"

    replacement = payment_body("pay_replacement", "order_safe", "pdt_expected")
    assert signed_post(replacement, "wh_replacement") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()
    assert Commerce.get_order("order_safe").payment_id == "pay_safe"
  end

  test "failed on-demand payments update only their persisted charge intent" do
    assert {:ok, _command, :accepted} =
             DodoStore.Billing.enqueue("charge:invoice_failed", "subscription_charge", %{
               "subscription_id" => "sub_charge",
               "params" => %{
                 "product_price" => 500,
                 "metadata" => %{"example_charge_command_id" => "charge:invoice_failed"}
               }
             })

    body =
      Jason.encode!(%{
        "type" => "payment.failed",
        "data" => %{
          "payment_id" => "pay_failed",
          "subscription_id" => "sub_charge",
          "metadata" => %{"example_charge_command_id" => "charge:invoice_failed"}
        }
      })

    assert signed_post(body, "wh_charge_failed") |> response(200) == "accepted"
    assert :ok = DodoStore.Billing.InboxProcessor.run_once()

    assert %Record{
             status: "failed",
             data: %{
               "payment_id" => "pay_failed",
               "subscription_id" => "sub_charge",
               "webhook_id" => "wh_charge_failed"
             }
           } = Repo.get_by!(Record, pattern: 6, business_key: "charge:invoice_failed")

    assert Repo.get_by!(OutboxCommand,
             kind: "reconcile_subscription",
             payload: %{"subscription_id" => "sub_charge"}
           )
  end

  test "modified or unsigned bodies are rejected without touching the inbox" do
    body = Jason.encode!(%{"type" => "payment.succeeded", "data" => %{}})
    conn = signed_conn(body, "wh_bad")

    assert post(conn, "/webhooks/dodo", body <> " ") |> response(400) == "invalid webhook"
    unsigned_conn = put_req_header(build_conn(), "content-type", "application/json")
    assert post(unsigned_conn, "/webhooks/dodo", body) |> response(400) == "invalid webhook"
    assert Repo.aggregate(InboxEvent, :count) == 0
  end

  defp signed_post(body, webhook_id) do
    body |> signed_conn(webhook_id) |> post("/webhooks/dodo", body)
  end

  defp payment_body(payment_id, order_id, product_id) do
    Jason.encode!(%{
      "type" => "payment.succeeded",
      "data" => %{
        "payment_id" => payment_id,
        "product_id" => product_id,
        "metadata" => %{
          "example_pattern" => 1,
          "example_order_id" => order_id,
          "example_cart_hash" =>
            Commerce.cart_fingerprint([%{product_id: product_id, quantity: 1}])
        }
      }
    })
  end

  defp lifecycle_body(type, data), do: Jason.encode!(%{"type" => type, "data" => data})

  defp expect_dispute_snapshot(status) do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/disputes/dis_current"

      Req.Test.json(conn, %{
        "dispute_id" => "dis_current",
        "payment_id" => "pay_disputed",
        "dispute_status" => to_string(status)
      })
    end)
  end

  defp expect_refund_snapshot(status) do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/refunds/ref_current"

      Req.Test.json(conn, %{
        "refund_id" => "ref_current",
        "payment_id" => "pay_refunded",
        "status" => to_string(status)
      })
    end)
  end

  defp signed_conn(body, webhook_id) do
    timestamp = System.system_time(:second) |> Integer.to_string()
    signature = :crypto.mac(:hmac, :sha256, @key, webhook_id <> "." <> timestamp <> "." <> body)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("webhook-id", webhook_id)
    |> put_req_header("webhook-timestamp", timestamp)
    |> put_req_header("webhook-signature", "v1," <> Base.encode64(signature))
  end
end
