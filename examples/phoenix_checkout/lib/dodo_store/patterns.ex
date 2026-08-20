defmodule DodoStore.Patterns do
  @moduledoc "Executable catalog of the ten billing patterns shown by the example."

  alias DodoStore.{Billing, Commerce}
  alias DodoStore.Billing.InboxEvent

  @patterns [
    %{
      id: 1,
      slug: "one-time-checkout",
      title: "One-time hosted checkout",
      use_case: "Downloads, courses, lifetime plans, and single purchases.",
      sdk: "CheckoutSessions.create/2",
      invariant:
        "The return URL is UX only; payment.succeeded fulfills once by order and payment ID.",
      storage: "orders + webhook_inbox"
    },
    %{
      id: 2,
      slug: "saas-subscription",
      title: "SaaS subscription lifecycle",
      use_case: "Monthly or annual plans with upgrades, holds, renewals, and cancellation.",
      sdk: "CheckoutSessions.create/2 + Subscriptions.retrieve/2",
      invariant:
        "Lifecycle webhooks schedule current-state reconciliation instead of trusting arrival order.",
      storage: "subscriptions + reconciliation outbox"
    },
    %{
      id: 3,
      slug: "mixed-cart",
      title: "Mixed cart and add-ons",
      use_case: "A subscription plus setup fee, add-ons, or a product bundle.",
      sdk: "CheckoutSessions.create/2 with multiple product_cart items",
      invariant: "Fulfill every line item independently under one durable order.",
      storage: "orders + order_items + entitlements"
    },
    %{
      id: 4,
      slug: "usage-billing",
      title: "Usage-based billing",
      use_case: "API calls, tokens, storage, generated media, or compute time.",
      sdk: "UsageEvents.ingest/2",
      invariant: "Commit a deterministic event_id to an outbox with the business action.",
      storage: "usage_outbox"
    },
    %{
      id: 5,
      slug: "prepaid-credits",
      title: "Prepaid credits",
      use_case: "Credit packs or subscription allowances consumed by metered actions.",
      sdk: "CheckoutSessions.create/2 + CreditEntitlements balances",
      invariant:
        "Dodo billing balances are asynchronous; local request authorization must be atomic.",
      storage: "credit grants + local authorization ledger"
    },
    %{
      id: 6,
      slug: "on-demand-charge",
      title: "On-demand variable charge",
      use_case: "A mandate established once, followed by variable server-initiated charges.",
      sdk: "Subscriptions.charge/3",
      invariant: "Persist the charge intent first and reconcile OutcomeUnknown before repeating.",
      storage: "charge_intents + billing_outbox"
    },
    %{
      id: 7,
      slug: "refund-dispute",
      title: "Refund and dispute lifecycle",
      use_case: "Full/partial refunds and account review after disputes.",
      sdk: "Refunds.create/2 + Refunds/Disputes.retrieve",
      invariant: "Refund commands are idempotent; webhook updates schedule reconciliation.",
      storage: "refund_intents + dispute_reviews"
    },
    %{
      id: 8,
      slug: "multiple-meters",
      title: "Multiple-meter billing",
      use_case:
        "One workload emits independently priced token, storage, and compute measurements.",
      sdk: "UsageEvents.ingest/2 with one deterministic event per meter",
      invariant:
        "Each meter event has its own stable ID while sharing the business-operation ID.",
      storage: "usage_outbox"
    },
    %{
      id: 9,
      slug: "subscription-usage-credits",
      title: "Subscription + usage-based credits",
      use_case: "A recurring plan grants credits that multiple usage meters consume.",
      sdk: "CheckoutSessions.create/2 + UsageEvents.ingest/2",
      invariant:
        "Subscription state grants access; an atomic local allowance gates immediate usage.",
      storage: "subscriptions + credit grants + usage_outbox"
    },
    %{
      id: 10,
      slug: "hard-usage-limit",
      title: "Hard usage limits",
      use_case: "Exactly N exports, seats, jobs, or API operations per billing period.",
      sdk: "Local atomic authorization + optional UsageEvents.ingest/2",
      invariant:
        "Reserve locally before work; remote metering is accounting, not the authorization lock.",
      storage: "usage_buckets + usage_outbox"
    }
  ]

  @spec all() :: [map()]
  def all, do: @patterns

  @spec fetch(String.t() | pos_integer()) :: {:ok, map()} | :error
  def fetch(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} -> fetch(number)
      _other -> find_by_slug(id)
    end
  end

  def fetch(id) when is_integer(id) do
    case Enum.find(@patterns, &(&1.id == id)) do
      nil -> :error
      pattern -> {:ok, pattern}
    end
  end

  @spec demo(pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def demo(1),
    do: {:ok, "Use the checkout button on the home page; no fulfillment occurs on return."}

  def demo(2) do
    with {:ok, _order} <-
           Commerce.expect_order("subscription_demo", 2, [%{product_id: "pdt_plan", quantity: 1}],
             account_id: "account_demo"
           ) do
      {:ok, "Created an expected subscription checkout tied to account_demo."}
    end
  end

  def demo(3) do
    cart =
      Enum.map(
        ["subscription_base", "onboarding_fee", "extra_seat"],
        &%{product_id: &1, quantity: 1}
      )

    with {:ok, _order} <- Commerce.expect_order("order_demo", 3, cart) do
      {:ok, "Stored one expected order and three independently addressable line items."}
    end
  end

  def demo(4) do
    enqueue_usage("usage:request_demo", [usage_event("request_demo", "api.call", 1)])
  end

  def demo(5) do
    order_id = "credit_demo_#{demo_action_id()}"

    with {:ok, _order} <-
           Commerce.expect_order(order_id, 5, [%{product_id: "pdt_credit_pack", quantity: 1}],
             account_id: "account_demo",
             credits: 100
           ),
         {:ok, _order, _disposition} <-
           Commerce.fulfill_payment(
             %{
               "payment_id" => "pay_#{order_id}",
               "metadata" => %{
                 "example_order_id" => order_id,
                 "example_pattern" => 5,
                 "example_cart_hash" =>
                   Commerce.cart_fingerprint([%{product_id: "pdt_credit_pack", quantity: 1}]),
                 "example_account_id" => "account_demo"
               },
               "product_id" => "pdt_credit_pack"
             },
             "demo_#{order_id}"
           ) do
      {:ok, "Granted 100 prepaid credits from a matched, successful local order."}
    end
  end

  def demo(6) do
    with {:ok, _subscription} <-
           Commerce.apply_subscription_snapshot(%{
             "subscription_id" => "sub_demo",
             "status" => "active",
             "on_demand" => true,
             "metadata" => %{"example_pattern" => 6, "example_account_id" => "account_demo"}
           }) do
      DodoStore.Workflows.queue_on_demand_charge("invoice_demo", "sub_demo", %{
        "product_price" => 2_500
      })
    end
    |> case do
      {:ok, _command, disposition} ->
        {:ok, "#{disposition}: durable charge intent; dispatch once, reconcile uncertainty."}

      {:error, error} ->
        {:error, error}
    end
  end

  def demo(7) do
    case Billing.enqueue("refund:case_demo", "refund_create", %{
           "payment_id" => "pay_demo",
           "amount" => 500
         }) do
      {:ok, _command, disposition} -> {:ok, "#{disposition}: idempotent partial-refund command."}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def demo(8) do
    events = [
      usage_event("job_demo:tokens", "ai.tokens", 8_000),
      usage_event("job_demo:gpu", "compute.gpu_seconds", 42),
      usage_event("job_demo:storage", "storage.bytes", 1_048_576)
    ]

    enqueue_usage("usage:job_demo", events)
  end

  def demo(9) do
    period = current_period()

    with {:ok, _subscription} <-
           Commerce.apply_subscription_snapshot(%{
             "subscription_id" => "sub_hybrid_demo",
             "status" => "active",
             "previous_billing_date" => period <> "T00:00:00Z",
             "metadata" => %{
               "example_pattern" => 9,
               "example_account_id" => "account_demo",
               "example_credits_per_period" => 1_000
             }
           }) do
      action_id = demo_action_id()

      case DodoStore.Workflows.authorize_hybrid_usage(
             "account_demo",
             "cus_demo",
             period,
             action_id,
             "ai.tokens",
             25,
             1_000
           ) do
        {:ok, bucket} ->
          {:ok,
           "Active subscription; #{bucket.used}/#{bucket.limit} credits reserved and metering queued."}

        {:error, :limit_exceeded, bucket} ->
          {:ok, "Denied: the hybrid allowance is exhausted (#{bucket.used}/#{bucket.limit})."}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def demo(10) do
    action_id = demo_action_id()

    case Billing.reserve_usage_once(
           "exports:#{action_id}",
           "account_demo",
           "exports",
           current_period(),
           1,
           3
         ) do
      {:ok, bucket, _disposition} ->
        {:ok, "Authorized export #{bucket.used} of #{bucket.limit}."}

      {:error, :limit_exceeded, bucket} ->
        {:ok, "Denied: #{bucket.used} of #{bucket.limit} already used."}
    end
  end

  @spec handle_verified_event(InboxEvent.t()) :: :ok | {:error, term()}
  def handle_verified_event(%InboxEvent{event_type: "payment.succeeded"} = event) do
    data = Map.get(event.payload, "data", %{})

    if charge_command_id(data) do
      handle_charge_payment(event, "succeeded")
    else
      fulfill_checkout_payment(event, data)
    end
  end

  def handle_verified_event(%InboxEvent{event_type: "payment.failed"} = event) do
    data = Map.get(event.payload, "data", %{})

    with :ok <- maybe_handle_failed_charge(event, data),
         :ok <- maybe_reconcile_failed_subscription(event, data) do
      :ok
    end
  end

  def handle_verified_event(%InboxEvent{event_type: "subscription." <> _} = event) do
    enqueue_reconciliation(event, "subscription_id", "reconcile_subscription")
  end

  def handle_verified_event(%InboxEvent{event_type: "refund." <> _} = event) do
    enqueue_reconciliation(event, "refund_id", "reconcile_refund")
  end

  def handle_verified_event(%InboxEvent{event_type: "dispute." <> _} = event) do
    enqueue_reconciliation(event, "dispute_id", "reconcile_dispute")
  end

  def handle_verified_event(_event), do: :ok

  defp fulfill_checkout_payment(event, data) do
    metadata = Map.get(data, "metadata", %{})

    case Commerce.fulfill_payment(data, event.webhook_id) do
      {:ok, order, _disposition} ->
        case Billing.put_record(order.pattern, order.order_id, "fulfilled", %{
               "payment_id" => order.payment_id,
               "webhook_id" => event.webhook_id
             }) do
          {:ok, _record} -> :ok
          {:error, error} -> {:error, error}
        end

      {:error, reason} ->
        # A verified payment is not sufficient authorization. Keep the rejected
        # observation for operators, then acknowledge it without fulfilling.
        pattern = parse_pattern(Map.get(metadata, "example_pattern"), 1)
        key = "rejected:#{event.webhook_id}"
        _result = Billing.put_record(pattern, key, "rejected", %{"reason" => to_string(reason)})
        :ok
    end
  end

  defp handle_charge_payment(event, status) do
    data = Map.get(event.payload, "data", %{})
    command_id = charge_command_id(data)
    payment_id = data["payment_id"]
    subscription_id = data["subscription_id"]

    case Billing.get_command(command_id) do
      %{kind: "subscription_charge", payload: %{"subscription_id" => expected_subscription}}
      when is_binary(payment_id) and
             (is_nil(subscription_id) or subscription_id == expected_subscription) ->
        case Billing.put_record(6, command_id, status, %{
               "payment_id" => payment_id,
               "subscription_id" => expected_subscription,
               "webhook_id" => event.webhook_id
             }) do
          {:ok, _record} -> :ok
          {:error, error} -> {:error, error}
        end

      _unknown_or_mismatched ->
        _result =
          Billing.put_record(6, "rejected:#{event.webhook_id}", "rejected", %{
            "reason" => "unknown_or_mismatched_charge_intent"
          })

        :ok
    end
  end

  defp maybe_handle_failed_charge(event, data) do
    if charge_command_id(data), do: handle_charge_payment(event, "failed"), else: :ok
  end

  defp maybe_reconcile_failed_subscription(event, %{"subscription_id" => subscription_id})
       when is_binary(subscription_id) do
    enqueue_reconciliation(event, "subscription_id", "reconcile_subscription")
  end

  defp maybe_reconcile_failed_subscription(_event, _data), do: :ok

  defp charge_command_id(data) do
    case Map.get(data, "metadata", %{}) do
      %{} = metadata ->
        case Map.get(metadata, "example_charge_command_id") do
          command_id when is_binary(command_id) -> command_id
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp enqueue_reconciliation(event, id_field, kind) do
    id = get_in(event.payload, ["data", id_field]) || event.resource_id

    if is_binary(id) do
      command_id = "#{kind}:#{id}:#{event.webhook_id}"

      case Billing.enqueue(command_id, kind, %{id_field => id}) do
        {:ok, _command, _disposition} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      :ok
    end
  end

  defp enqueue_usage(command_id, events) do
    case Billing.enqueue(command_id, "usage_ingest", %{"events" => events}) do
      {:ok, _command, disposition} ->
        {:ok, "#{disposition}: #{length(events)} deterministic usage event(s) in the outbox."}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp usage_event(event_id, event_name, value) do
    %{
      "event_id" => event_id,
      "customer_id" => "cus_demo",
      "event_name" => event_name,
      "metadata" => %{"value" => value}
    }
  end

  defp current_period do
    today = Date.utc_today()
    Date.to_iso8601(%{today | day: 1})
  end

  defp demo_action_id do
    9
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp parse_pattern(value, _default) when is_integer(value) and value in 1..10, do: value

  defp parse_pattern(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number in 1..10 -> number
      _other -> default
    end
  end

  defp parse_pattern(_value, default), do: default

  defp find_by_slug(slug) do
    case Enum.find(@patterns, &(&1.slug == slug)) do
      nil -> :error
      pattern -> {:ok, pattern}
    end
  end
end
