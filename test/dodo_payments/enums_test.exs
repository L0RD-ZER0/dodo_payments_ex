defmodule DodoPayments.EnumsTest do
  # Atom-table assertions are VM-global and must not race module loading in async tests.
  use ExUnit.Case, async: false

  alias DodoPayments.{Enums, Operation, Schema, UnknownEnum}

  test "known values round-trip between idiomatic atoms and exact wire strings" do
    assert {:ok, "USD"} = Enums.dump(:currency, :usd)
    assert :usd = Enums.load(:currency, "USD")

    assert {:ok, "Month"} = Enums.dump(:time_interval, :month)
    assert :month = Enums.load(:time_interval, "Month")

    assert {:ok, "payment.succeeded"} =
             Enums.dump(:webhook_event_type, :payment_succeeded)

    assert :payment_succeeded =
             Enums.load(:webhook_event_type, "payment.succeeded")

    assert {:ok, "Pending"} = Enums.dump(:entitlement_grant_status, :pending)
    assert :pending = Enums.load(:entitlement_grant_status, "Pending")

    assert {:ok, "paused"} = Enums.dump(:subscription_status, :paused)
    assert :paused = Enums.load(:subscription_status, "paused")
    assert {:ok, "live_tutoring"} = Enums.dump(:tax_category, :live_tutoring)

    assert {:ok, "subscription.unpaused"} =
             Enums.dump(:webhook_event_type, :subscription_unpaused)
  end

  test "unknown server values are lossless and never become atoms" do
    # Warm the involved modules and lookup paths before measuring the atom table.
    for index <- 1..10 do
      assert %UnknownEnum{} =
               Enums.load(:subscription_status, "future_warmup_#{index}")
    end

    before = :erlang.system_info(:atom_count)

    unknown =
      for index <- 1..2_000 do
        value = "future_status_#{index}"

        assert %UnknownEnum{enum: :subscription_status, value: ^value} =
                 Enums.load(:subscription_status, value)
      end

    assert :erlang.system_info(:atom_count) == before
    assert {:ok, "future_status_2000"} = Enums.dump(:subscription_status, List.last(unknown))
  end

  test "typed responses decode known enums and preserve unknown enum values" do
    payment =
      Schema.cast(DodoPayments.Payment, %{
        "currency" => "USD",
        "status" => "succeeded",
        "payment_provider" => "stripe",
        "settlement_currency" => "EUR"
      })

    assert payment.currency == :usd
    assert payment.status == :succeeded
    assert payment.payment_provider == :stripe
    assert payment.settlement_currency == :eur

    subscription =
      Schema.cast(DodoPayments.Subscription, %{
        "status" => "paused_v2",
        "payment_frequency_interval" => "Month"
      })

    assert subscription.payment_frequency_interval == :month

    assert subscription.status == %UnknownEnum{
             enum: :subscription_status,
             value: "paused_v2"
           }
  end

  test "request atoms encode at the JSON boundary, including nested and query enums" do
    checkout = Operation.fetch!(:checkout_sessions_create)

    assert {:ok, %{body: checkout_body}} =
             Operation.prepare(checkout, %{
               product_cart: [],
               allowed_payment_method_types: [:apple_pay, :card_redirect],
               billing_currency: :usd,
               billing_address: %{country: :us}
             })

    assert checkout_body["allowed_payment_method_types"] == ["apple_pay", "card_redirect"]
    assert checkout_body["billing_currency"] == "USD"
    assert checkout_body["billing_address"]["country"] == "US"

    assert {:ok, %{query: %{"currency" => "EUR", "status" => "processing"}}} =
             Operation.prepare(Operation.fetch!(:payments_list), %{
               currency: :eur,
               status: :processing
             })

    assert {:ok, %{body: %{"type" => "new", "allowed_payment_method_types" => ["ach"]}}} =
             Operation.prepare(Operation.fetch!(:subscriptions_update_payment_method), %{
               subscription_id: "sub_1",
               payment_method: %{type: :new, allowed_payment_method_types: [:ach]}
             })
  end

  test "source-locked enum atoms inside open nested objects still encode safely" do
    assert {:ok, %{body: %{"price" => price}}} =
             Operation.prepare(Operation.fetch!(:products_create), %{
               name: "Metered",
               tax_category: :saas,
               price: %{
                 type: :recurring_price,
                 currency: :usd,
                 subscription_period_interval: :month
               }
             })

    assert price == %{
             "type" => "recurring_price",
             "currency" => "USD",
             "subscription_period_interval" => "Month"
           }
  end

  test "wrong atoms in exact enum positions return a validation error" do
    assert {:error,
            %DodoPayments.ValidationError{
              operation: :payments_list,
              field: :status,
              reason: {:unknown_enum_atom, :intent_status, :definitely_not_a_status, [:status]}
            }} =
             Operation.prepare(Operation.fetch!(:payments_list), %{
               status: :definitely_not_a_status
             })

    # Existing string-key/string-value callers remain wire compatible during v0.x.
    assert {:ok, %{query: %{"status" => "succeeded"}}} =
             Operation.prepare(Operation.fetch!(:payments_list), %{"status" => "succeeded"})
  end

  test "webhook types use atoms while unknown events remain processable" do
    assert {:ok, %DodoPayments.Webhooks.Event{type: :payment_succeeded}} =
             DodoPayments.Webhooks.Event.from_payload(
               "wh_1",
               ~s({"type":"payment.succeeded"}),
               %{"type" => "payment.succeeded"}
             )

    assert {:ok, %DodoPayments.Webhooks.Event{type: %UnknownEnum{value: "future.event"}}} =
             DodoPayments.Webhooks.Event.from_payload(
               "wh_2",
               ~s({"type":"future.event"}),
               %{"type" => "future.event"}
             )
  end
end
