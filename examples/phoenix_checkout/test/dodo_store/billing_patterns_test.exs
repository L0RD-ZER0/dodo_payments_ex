defmodule DodoStore.BillingPatternsTest do
  use ExUnit.Case, async: false

  alias DodoStore.{Billing, Patterns, Workflows}

  setup {Req.Test, :verify_on_exit!}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DodoStore.Repo)
    DodoStore.DodoTest.configure(__MODULE__.DodoStub)
    :ok
  end

  test "the catalog exposes every documented pattern and every local demo is runnable" do
    assert Enum.map(Patterns.all(), & &1.id) == Enum.to_list(1..10)

    for pattern <- Patterns.all() do
      assert {:ok, message} = Patterns.demo(pattern.id)
      refute message == ""
    end
  end

  test "outbox command and per-meter event IDs are deterministic" do
    measurements = %{"ai.tokens" => 800, "compute.seconds" => 3, "storage.bytes" => 1_024}

    assert {:ok, first, :accepted} =
             Workflows.record_multiple_meter_usage("job_42", "cus_42", measurements)

    assert {:ok, second, :duplicate} =
             Workflows.record_multiple_meter_usage("job_42", "cus_42", measurements)

    assert first.id == second.id
    assert first.command_id == "usage:cus_42:job_42"

    assert Enum.map(first.payload["events"], & &1["event_id"]) == [
             "cus_42:job_42:ai.tokens",
             "cus_42:job_42:compute.seconds",
             "cus_42:job_42:storage.bytes"
           ]
  end

  test "hard limit authorization cannot cross its configured cap" do
    account = "account_#{System.unique_integer([:positive])}"

    for used <- 1..3 do
      assert {:ok, bucket} =
               Workflows.authorize_limited_use(
                 account,
                 "exports",
                 "2026-08",
                 "export_#{used}",
                 1,
                 3
               )

      assert bucket.used == used
    end

    assert {:error, :limit_exceeded, bucket} =
             Workflows.authorize_limited_use(account, "exports", "2026-08", "export_4", 1, 3)

    assert bucket.used == 3
  end

  test "credit grants and expected orders reject conflicting idempotency intent" do
    assert {:ok, _grant} =
             DodoStore.Commerce.grant_credits_once(
               "account_a",
               "payment:pay_1",
               "prepaid",
               100,
               "prepaid"
             )

    assert {:ok, _same_grant} =
             DodoStore.Commerce.grant_credits_once(
               "account_a",
               "payment:pay_1",
               "prepaid",
               100,
               "prepaid"
             )

    assert {:error, :idempotency_conflict} =
             DodoStore.Commerce.grant_credits_once(
               "account_b",
               "payment:pay_1",
               "prepaid",
               1_000,
               "prepaid"
             )

    assert {:ok, _order} =
             DodoStore.Commerce.expect_order(
               "order_intent",
               5,
               [%{product_id: "pdt_credits", quantity: 1}],
               account_id: "account_a",
               credits: 100
             )

    assert {:error, :idempotency_conflict} =
             DodoStore.Commerce.expect_order(
               "order_intent",
               5,
               [%{product_id: "pdt_other", quantity: 1}],
               account_id: "account_a",
               credits: 100
             )

    assert {:error, :account_mismatch} =
             DodoStore.Commerce.fulfill_payment(
               %{
                 "payment_id" => "pay_wrong_account",
                 "metadata" => %{
                   "example_order_id" => "order_intent",
                   "example_pattern" => 5,
                   "example_account_id" => "account_b",
                   "example_cart_hash" =>
                     DodoStore.Commerce.cart_fingerprint([
                       %{product_id: "pdt_credits", quantity: 1}
                     ])
                 }
               },
               "wh_wrong_account"
             )
  end

  test "mixed-cart fulfillment creates and fulfills durable line items" do
    cart = [
      %{product_id: "pdt_subscription", quantity: 1},
      %{product_id: "pdt_setup", quantity: 1}
    ]

    assert {:ok, _order} = DodoStore.Commerce.expect_order("order_lines", 3, cart)

    assert Enum.map(DodoStore.Commerce.order_items("order_lines"), & &1.status) == [
             "awaiting_payment",
             "awaiting_payment"
           ]

    assert {:ok, _order, :accepted} =
             DodoStore.Commerce.fulfill_payment(
               %{
                 "payment_id" => "pay_lines",
                 "product_cart" => cart,
                 "metadata" => %{
                   "example_order_id" => "order_lines",
                   "example_pattern" => 3,
                   "example_cart_hash" => DodoStore.Commerce.cart_fingerprint(cart)
                 }
               },
               "wh_lines"
             )

    assert Enum.map(DodoStore.Commerce.order_items("order_lines"), & &1.status) == [
             "fulfilled",
             "fulfilled"
           ]
  end

  test "hybrid authorization reserves locally and queues remote accounting" do
    assert {:ok, _subscription} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_hybrid",
               "status" => "active",
               "previous_billing_date" => "2026-08-01T00:00:00Z",
               "metadata" => %{
                 "example_pattern" => 9,
                 "example_account_id" => "account_hybrid",
                 "example_credits_per_period" => 100
               }
             })

    assert {:ok, bucket} =
             Workflows.authorize_hybrid_usage(
               "account_hybrid",
               "cus_hybrid",
               "2026-08-01",
               "generation_17",
               "ai.tokens",
               25,
               100
             )

    assert bucket.used == 25
    assert [%{command_id: "usage:cus_hybrid:generation_17"}] = Billing.pending_commands()

    assert {:ok, retried_bucket} =
             Workflows.authorize_hybrid_usage(
               "account_hybrid",
               "cus_hybrid",
               "2026-08-01",
               "generation_17",
               "ai.tokens",
               25,
               100
             )

    assert retried_bucket.used == 25
    assert [_one_command] = Billing.pending_commands()
  end

  test "charge and refund intentions are durable before any network dispatch" do
    assert {:ok, _subscription} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_7",
               "status" => "active",
               "on_demand" => true,
               "metadata" => %{
                 "example_pattern" => 6,
                 "example_account_id" => "account_7"
               }
             })

    assert {:ok, charge, :accepted} =
             Workflows.queue_on_demand_charge("invoice_7", "sub_7", %{
               "product_price" => 2_500
             })

    assert charge.kind == "subscription_charge"

    assert charge.payload["params"]["metadata"]["example_charge_command_id"] ==
             "charge:invoice_7"

    assert {:ok, refund, :accepted} = Workflows.queue_refund("support_8", "pay_8", 500)
    assert refund.payload == %{"amount" => 500, "payment_id" => "pay_8"}
  end

  test "on-demand checkout configures mandate-only and charges require that remote flag" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = Jason.decode!(body)

      assert params["subscription_data"] == %{"on_demand" => %{"mandate_only" => true}}

      Req.Test.json(conn, %{
        "session_id" => "cks_mandate",
        "checkout_url" => "https://example.test"
      })
    end)

    assert {:ok, _checkout} =
             Workflows.checkout(
               DodoStore.Dodo.client(),
               6,
               [%{product_id: "pdt_on_demand", quantity: 1}],
               "https://example.test/return",
               "https://example.test/cancel",
               "order_mandate",
               account_id: "account_mandate"
             )

    assert {:ok, subscription} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_not_on_demand",
               "status" => "active",
               "on_demand" => false,
               "metadata" => %{
                 "example_pattern" => 6,
                 "example_account_id" => "account_mandate"
               }
             })

    refute subscription.mandate_ready

    assert {:error, :mandate_not_ready} =
             Workflows.queue_on_demand_charge("intent_rejected", "sub_not_on_demand", %{
               "product_price" => 100
             })
  end

  test "hybrid snapshots require a real period and roll back conflicting allowance changes" do
    metadata = %{
      "example_pattern" => 9,
      "example_account_id" => "account_atomic",
      "example_credits_per_period" => 100
    }

    assert {:error, :missing_billing_period} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_missing_period",
               "status" => "active",
               "metadata" => metadata
             })

    refute DodoStore.Repo.get_by(DodoStore.Commerce.Subscription,
             subscription_id: "sub_missing_period"
           )

    assert {:ok, original} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_atomic",
               "status" => "active",
               "previous_billing_date" => "2026-08-01T00:00:00Z",
               "metadata" => metadata
             })

    assert original.credits_per_period == 100

    assert {:error, :idempotency_conflict} =
             DodoStore.Commerce.apply_subscription_snapshot(%{
               "subscription_id" => "sub_atomic",
               "status" => "active",
               "previous_billing_date" => "2026-08-01T00:00:00Z",
               "metadata" => %{metadata | "example_credits_per_period" => 200}
             })

    persisted =
      DodoStore.Repo.get_by!(DodoStore.Commerce.Subscription, subscription_id: "sub_atomic")

    assert persisted.credits_per_period == 100
    assert DodoStore.Commerce.granted_credits("account_atomic", "2026-08-01") == 100
  end

  test "mixed checkout crosses the real SDK boundary with pattern metadata" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.request_path == "/checkouts"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "metadata" => %{"example_order_id" => "order_3", "example_pattern" => 3},
               "product_cart" => [
                 %{"product_id" => "pdt_base", "quantity" => 1},
                 %{"product_id" => "pdt_setup", "quantity" => 1}
               ]
             } = Jason.decode!(body)

      Req.Test.json(conn, %{
        "session_id" => "cks_mixed",
        "checkout_url" => "https://test.checkout.dodopayments.com/session/cks_mixed"
      })
    end)

    assert {:ok, checkout} =
             Workflows.checkout(
               DodoStore.Dodo.client(),
               3,
               [
                 %{product_id: "pdt_base", quantity: 1},
                 %{product_id: "pdt_setup", quantity: 1}
               ],
               "https://example.test/return",
               "https://example.test/cancel",
               "order_3"
             )

    assert checkout.session_id == "cks_mixed"
  end

  test "outbox dispatcher sends queued meter events and marks them delivered" do
    Req.Test.expect(__MODULE__.DodoStub, fn conn ->
      assert conn.request_path == "/events/ingest"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert [%{"event_id" => "cus_9:request_9"}] = Jason.decode!(body)["events"]
      Req.Test.json(conn, %{"ingested_count" => 1})
    end)

    assert {:ok, command, :accepted} =
             Workflows.record_usage("request_9", "cus_9", "api.call", 1)

    assert {:ok, %DodoPayments.UsageEventIngestResponse{ingested_count: 1}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, DodoStore.Dodo.client())

    assert Billing.pending_commands() == []
  end
end
