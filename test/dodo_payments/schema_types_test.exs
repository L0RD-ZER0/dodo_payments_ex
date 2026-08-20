defmodule DodoPayments.SchemaTypesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "top-level response specs describe authoritative wire domains and remain nullable" do
    payment_type = rendered_type(DodoPayments.Payment)
    product_type = rendered_type(DodoPayments.Product)
    subscription_type = rendered_type(DodoPayments.Subscription)
    line_items_type = rendered_type(DodoPayments.PaymentLineItemsResponse)

    assert payment_type =~ "total_amount: number() | nil"
    assert payment_type =~ "customer: DodoPayments.ResponseTypes.customer_limited_details() | nil"
    assert payment_type =~ "refunds: [DodoPayments.ResponseTypes.refund_list_item()] | nil"
    assert payment_type =~ "status: DodoPayments.Enums.decoded_intent_status() | nil"
    assert payment_type =~ "currency: DodoPayments.Enums.decoded_currency() | nil"

    assert product_type =~
             "price: (number() | DodoPayments.ResponseTypes.object()) | nil"

    assert product_type =~ "metadata: DodoPayments.ResponseTypes.metadata() | nil"
    assert subscription_type =~ "paused_at: String.t() | nil"

    assert line_items_type =~
             "items: [DodoPayments.ResponseTypes.payment_line_item()] | nil"

    assert %DodoPayments.Payment{}.total_amount == nil
  end

  test "2.47 response additions decode into typed fields instead of extra" do
    subscription =
      DodoPayments.Schema.cast(DodoPayments.Subscription, %{
        "subscription_id" => "sub_1",
        "status" => "paused",
        "paused_at" => "2026-08-18T12:00:00Z"
      })

    assert subscription.status == :paused
    assert subscription.paused_at == "2026-08-18T12:00:00Z"
    assert subscription.extra == %{}

    line_items =
      DodoPayments.Schema.cast(DodoPayments.PaymentLineItemsResponse, %{
        "currency" => "USD",
        "items" => [%{"items_id" => "pdt_1", "amount" => 100}]
      })

    assert line_items.currency == :usd
    assert line_items.items == [%{"items_id" => "pdt_1", "amount" => 100}]

    archived =
      DodoPayments.Schema.cast(DodoPayments.BrandArchiveResponse, %{
        "archived_at" => "2026-08-18T12:00:00Z",
        "brand_id" => "brnd_1",
        "products_moved" => 0,
        "subscriptions_moved" => 0,
        "collections_moved" => 0
      })

    assert archived.brand_id == "brnd_1"
    assert archived.products_moved == 0
    assert archived.extra == %{}
  end

  test "catalog, customer, metering, fulfillment, refund, and webhook responses are typed" do
    samples = [
      {DodoPayments.Addon,
       %{
         "id" => "add_1",
         "currency" => "USD",
         "tax_category" => "saas",
         "future" => true
       }, %{currency: :usd, tax_category: :saas}},
      {DodoPayments.Brand, %{"brand_id" => "brnd_1", "verification_status" => "Success"},
       %{verification_status: :success}},
      {DodoPayments.Customer, %{"customer_id" => "cus_1", "email" => "a@example.com"}, %{}},
      {DodoPayments.Discount,
       %{"discount_id" => "dsc_1", "type" => "flat", "customer_eligibility" => "any"},
       %{type: :flat, customer_eligibility: :any}},
      {DodoPayments.Meter, %{"id" => "mtr_1", "event_name" => "tokens.used"}, %{}},
      {DodoPayments.Refund, %{"refund_id" => "ref_1", "status" => "pending", "currency" => "USD"},
       %{status: :pending, currency: :usd}},
      {DodoPayments.Entitlement, %{"id" => "ent_1", "integration_type" => "feature_flag"},
       %{integration_type: :feature_flag}},
      {DodoPayments.WebhookEndpoint, %{"id" => "wh_1", "disabled" => false}, %{}}
    ]

    Enum.each(samples, fn {module, wire, expected} ->
      value = DodoPayments.Schema.cast(module, wire)

      Enum.each(expected, fn {field, expected_value} ->
        assert Map.fetch!(value, field) == expected_value
      end)

      expected_extra = if Map.has_key?(wire, "future"), do: %{"future" => true}, else: %{}
      assert value.extra == expected_extra
    end)
  end

  test "reusable response schemas cover their complete operation families" do
    response_schemas = %{
      addons_create: DodoPayments.Addon,
      addons_retrieve: DodoPayments.Addon,
      addons_update: DodoPayments.Addon,
      brands_create: DodoPayments.Brand,
      brands_retrieve: DodoPayments.Brand,
      brands_update: DodoPayments.Brand,
      customers_create: DodoPayments.Customer,
      customers_retrieve: DodoPayments.Customer,
      customers_update: DodoPayments.Customer,
      discounts_create: DodoPayments.Discount,
      discounts_retrieve: DodoPayments.Discount,
      discounts_update: DodoPayments.Discount,
      discounts_retrieve_by_code: DodoPayments.Discount,
      meters_create: DodoPayments.Meter,
      meters_retrieve: DodoPayments.Meter,
      refunds_create: DodoPayments.Refund,
      refunds_retrieve: DodoPayments.Refund,
      entitlements_create: DodoPayments.Entitlement,
      entitlements_retrieve: DodoPayments.Entitlement,
      entitlements_update: DodoPayments.Entitlement,
      webhook_endpoints_create: DodoPayments.WebhookEndpoint,
      webhook_endpoints_retrieve: DodoPayments.WebhookEndpoint,
      webhook_endpoints_update: DodoPayments.WebhookEndpoint
    }

    Enum.each(response_schemas, fn {operation, schema} ->
      assert DodoPayments.Operation.fetch!(operation).response_schema == schema
    end)

    item_schemas = %{
      addons_list: DodoPayments.Addon,
      customers_list: DodoPayments.Customer,
      discounts_list: DodoPayments.Discount,
      meters_list: DodoPayments.Meter,
      refunds_list: DodoPayments.Refund,
      entitlements_list: DodoPayments.Entitlement,
      webhook_endpoints_list: DodoPayments.WebhookEndpoint
    }

    Enum.each(item_schemas, fn {operation, schema} ->
      assert DodoPayments.Operation.fetch!(operation).item_schema == schema
    end)

    assert DodoPayments.Operation.fetch!(:brands_list).response_schema ==
             DodoPayments.BrandListResponse
  end

  test "every JSON operation exposes a typed response contract" do
    generic =
      DodoPayments.Operation.all()
      |> Enum.filter(fn operation ->
        operation.response_mode == :json and is_nil(operation.response_schema) and
          is_nil(operation.item_schema)
      end)
      |> Enum.map(& &1.id)

    assert generic == []
  end

  test "new response families cast authoritative scalar and enum fields" do
    samples = [
      {DodoPayments.LocalizedPrice,
       %{"id" => "lp_1", "currency" => "USD", "mode" => "by_country"},
       %{currency: :usd, mode: :by_country}},
      {DodoPayments.ProductCollection,
       %{
         "id" => "pc_1",
         "effective_at_on_upgrade" => "next_billing_date",
         "on_payment_failure" => "prevent_change"
       }, %{effective_at_on_upgrade: :next_billing_date, on_payment_failure: :prevent_change}},
      {DodoPayments.CustomerWalletTransaction,
       %{"id" => "txn_1", "currency" => "EUR", "event_type" => "payment_reversal"},
       %{currency: :eur, event_type: :payment_reversal}},
      {DodoPayments.DisputeListItem,
       %{
         "dispute_id" => "dsp_1",
         "dispute_stage" => "pre_dispute",
         "dispute_status" => "dispute_opened",
         "payment_provider" => "dodo"
       },
       %{dispute_stage: :pre_dispute, dispute_status: :dispute_opened, payment_provider: :dodo}},
      {DodoPayments.CreditEntitlement,
       %{
         "id" => "ce_1",
         "overage_behavior" => "invoice_at_billing",
         "rollover_timeframe_interval" => "Month"
       }, %{overage_behavior: :invoice_at_billing, rollover_timeframe_interval: :month}},
      {DodoPayments.CreditGrant, %{"id" => "cg_1", "source_type" => "rollover"},
       %{source_type: :rollover}},
      {DodoPayments.Payout,
       %{"payout_id" => "pyt_1", "currency" => "USD", "status" => "in_progress"},
       %{currency: :usd, status: :in_progress}}
    ]

    Enum.each(samples, fn {module, wire, expected} ->
      value = DodoPayments.Schema.cast(module, wire)
      assert value.extra == %{}

      Enum.each(expected, fn {field, expected_value} ->
        assert Map.fetch!(value, field) == expected_value
      end)
    end)
  end

  test "credit balance types preserve both declared strings and observed sandbox numbers" do
    balance_type = rendered_type(DodoPayments.CustomerCreditBalance)
    grant_type = rendered_type(DodoPayments.CreditGrant)

    assert balance_type =~ "balance: (String.t() | number()) | nil"
    assert balance_type =~ "overage: (String.t() | number()) | nil"
    assert grant_type =~ "initial_amount: (String.t() | number()) | nil"
    assert grant_type =~ "remaining_amount: (String.t() | number()) | nil"

    balance =
      DodoPayments.Schema.cast(DodoPayments.CustomerCreditBalance, %{
        "balance" => 7.25,
        "overage" => 0.0
      })

    assert balance.balance == 7.25
    assert balance.overage == 0.0
  end

  test "typed nested wire shapes preserve string-key maps, Jason numbers, and extra fields" do
    payment =
      DodoPayments.Schema.cast(DodoPayments.Payment, %{
        "payment_id" => "pay_1",
        "total_amount" => 12.5,
        "billing" => %{"country" => "US", "city" => "New York"},
        "customer" => %{
          "customer_id" => "cus_1",
          "metadata" => %{"cohort" => "early"}
        },
        "refunds" => [
          %{"refund_id" => "ref_1", "amount" => 2.5, "is_partial" => true}
        ],
        "future_payment_field" => %{"nested" => [1, 2.5, true]}
      })

    assert payment.total_amount == 12.5
    assert payment.billing["country"] == "US"
    assert payment.customer["metadata"]["cohort"] == "early"
    assert [%{"amount" => 2.5, "is_partial" => true}] = payment.refunds
    assert payment.extra == %{"future_payment_field" => %{"nested" => [1, 2.5, true]}}
    refute is_struct(payment.billing)
    refute is_struct(payment.customer)
  end

  test "schema declarations reject duplicate field sources at compile time" do
    module = "DodoPayments.InvalidTypedSchema#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, ~r/response field declared more than once: :id/, fn ->
      Code.compile_string("""
      defmodule #{module} do
        use DodoPayments.Schema,
          fields: [:id, id: String.t()]
      end
      """)
    end
  end

  test "schema declarations reject malformed field names" do
    module = "DodoPayments.MalformedTypedSchema#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, ~r/response fields must be atoms/, fn ->
      Code.compile_string("""
      defmodule #{module} do
        use DodoPayments.Schema,
          fields: [{"id", String.t()}]
      end
      """)
    end
  end

  test "legacy atom-only schema declarations still compile and cast with extra" do
    module_name = "DodoPayments.LegacySchema#{System.unique_integer([:positive])}"

    capture_io(:stderr, fn ->
      module =
        Code.compile_string("""
        defmodule #{module_name} do
          use DodoPayments.Schema, fields: [:id, :payload]
        end
        """)
        |> Enum.find_value(fn {module, _bytecode} ->
          if function_exported?(module, :__dodo_fields__, 0), do: module
        end)

      send(self(), {:legacy_schema, module})
    end)

    assert_received {:legacy_schema, module}
    assert module.__dodo_fields__() == [:id, :payload]

    value = DodoPayments.Schema.cast(module, %{"id" => "legacy_1", "future" => true})
    assert Map.fetch!(value, :id) == "legacy_1"
    assert Map.fetch!(value, :payload) == nil
    assert Map.fetch!(value, :extra) == %{"future" => true}
  end

  defp rendered_type(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    Enum.find_value(types, fn
      {:type, type} ->
        rendered = type |> Code.Typespec.type_to_quoted() |> Macro.to_string()
        if String.starts_with?(rendered, "t() ::"), do: rendered

      _other ->
        nil
    end)
  end
end
