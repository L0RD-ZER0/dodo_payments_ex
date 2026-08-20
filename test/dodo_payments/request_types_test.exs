defmodule DodoPayments.RequestTypesTest do
  use ExUnit.Case, async: true

  alias DodoPayments.Operation
  alias DodoPayments.RequestTypes

  test "the complete public catalogue has an explicit input classification" do
    operations = Operation.all()
    schema_ids = RequestTypes.schema_ids()

    assert length(operations) == 140
    assert length(schema_ids) == 82
    assert Enum.uniq(schema_ids) == schema_ids
    assert MapSet.subset?(MapSet.new(schema_ids), MapSet.new(Enum.map(operations, & &1.id)))

    assert Enum.count(schema_ids, &match?({:upstream, _, _}, RequestTypes.source(&1))) == 80
    assert Enum.count(schema_ids, &(RequestTypes.source(&1) == :schema_first)) == 2
    assert RequestTypes.source(:discount_customers_attach) == :schema_first
    assert RequestTypes.source(:discount_customers_list) == :schema_first

    # These operations expose only path arguments and request-local options.
    assert Enum.count(operations, &(RequestTypes.source(&1.id) == nil)) == 58

    Enum.each(schema_ids, fn id ->
      operation = Operation.fetch!(id)

      declared_required =
        operation.required
        |> Enum.reject(&(&1 in operation.path_params))
        |> MapSet.new()

      typed_required =
        operation
        |> RequestTypes.parameter_fields()
        |> Enum.filter(fn {_field, required?, _descriptor} -> required? end)
        |> Enum.map(fn {field, _required?, _descriptor} -> field end)
        |> MapSet.new()

      assert typed_required == declared_required,
             "request-type requiredness drifted from #{id} runtime validation"
    end)
  end

  test "endpoint types render exact fields and preserve mixed key compatibility" do
    rendered = rendered_type(DodoPayments.CheckoutSessions, :create_params)

    assert rendered =~ ":product_cart => [DodoPayments.RequestTypes.checkout_product_item()]"

    assert rendered =~
             "optional(:billing_address) => DodoPayments.RequestTypes.billing_address()"

    assert rendered =~ "optional(:customer) => DodoPayments.RequestTypes.customer_request()"
    assert rendered =~ "optional(:return_url) => String.t()"
    assert rendered =~ "optional(:billing_currency) => DodoPayments.Enums.currency()"

    assert rendered =~
             "optional(:allowed_payment_method_types) => [DodoPayments.Enums.payment_method_type()]"

    assert rendered =~ "optional(String.t()) => DodoPayments.RequestTypes.input_value()"
    assert rendered =~ "DodoPayments.RequestTypes.compatibility_params()"

    operation = Operation.fetch!(:checkout_sessions_create)

    assert {:ok, %{body: %{"product_cart" => [], "return_url" => "https://example.test"}}} =
             Operation.prepare(operation, %{
               "product_cart" => [],
               return_url: "https://example.test"
             })

    assert {:ok, %{body: %{"product_cart" => [], "return_url" => "https://example.test"}}} =
             Operation.prepare(operation, %{
               "return_url" => "https://example.test",
               product_cart: []
             })
  end

  test "generated types remove path fields and retain authoritative body fields" do
    create =
      rendered_type(DodoPayments.ProductCollections.Groups.Items, :create_params)

    update =
      rendered_type(DodoPayments.ProductCollections.Groups.Items, :update_params)

    assert create =~
             ":products => [DodoPayments.RequestTypes.collection_group_product()]"

    refute create =~ ":id =>"
    refute create =~ ":group_id =>"

    assert update =~ ":status => boolean()"
    refute update =~ ":id =>"
    refute update =~ ":group_id =>"
    refute update =~ ":item_id =>"
  end

  test "high-value nested request objects expose their authoritative members" do
    event = rendered_type(DodoPayments.RequestTypes, :usage_event_input)
    checkout_item = rendered_type(DodoPayments.RequestTypes, :checkout_product_item)
    payment_method = rendered_type(DodoPayments.RequestTypes, :subscription_payment_method)

    assert event =~ ":customer_id => String.t()"
    assert event =~ ":event_id => String.t()"
    assert event =~ ":event_name => String.t()"
    assert event =~ "optional(:metadata) => flat_metadata()"
    assert checkout_item =~ ":product_id => String.t()"
    assert checkout_item =~ "optional(:addons) => [attach_addon()]"
    assert payment_method =~ ":payment_method_id => String.t()"

    assert rendered_type(DodoPayments.UsageEvents, :ingest_params) =~
             ":events => [DodoPayments.RequestTypes.usage_event_input()]"

    assert rendered_type(DodoPayments.Subscriptions, :update_payment_method_params) =~
             ":payment_method => DodoPayments.RequestTypes.subscription_payment_method()"

    assert payment_method =~
             ":type => DodoPayments.Enums.subscription_payment_method_selection()"

    assert RequestTypes.generic_nested_residuals() == []

    assert rendered_type(DodoPayments.WebhookEndpoints, :create_params) =~
             "optional(:headers) => DodoPayments.RequestTypes.string_map()"

    assert rendered_type(DodoPayments.CheckoutSessions, :create_params) =~
             "optional(:feature_flags) => DodoPayments.RequestTypes.checkout_session_flags()"

    checkout_flags = rendered_type(DodoPayments.RequestTypes, :checkout_session_flags)
    assert checkout_flags =~ "optional(:single_page) => boolean()"
    assert checkout_flags =~ "optional(:allow_editing_addons) => boolean()"

    subscription_update = rendered_type(DodoPayments.Subscriptions, :update_params)
    assert subscription_update =~ "optional(:pause) => boolean()"

    assert {:ok, %{body: %{"pause" => true}, query: %{}}} =
             Operation.prepare(Operation.fetch!(:subscriptions_update), %{
               subscription_id: "sub_1",
               pause: true
             })
  end

  test "locked nested request unions expose precise reusable types" do
    product_create = rendered_type(DodoPayments.Products, :create_params)
    checkout_create = rendered_type(DodoPayments.CheckoutSessions, :create_params)
    meter_create = rendered_type(DodoPayments.Meters, :create_params)
    entitlement_create = rendered_type(DodoPayments.Entitlements, :create_params)

    assert product_create =~ ":price => DodoPayments.RequestTypes.product_price()"

    assert product_create =~
             "optional(:credit_entitlements) => [DodoPayments.RequestTypes.product_credit_entitlement()]"

    assert checkout_create =~
             "optional(:custom_fields) => [DodoPayments.RequestTypes.checkout_custom_field()]"

    assert checkout_create =~
             "optional(:customization) => DodoPayments.RequestTypes.checkout_customization()"

    assert meter_create =~
             ":aggregation => DodoPayments.RequestTypes.meter_aggregation()"

    assert meter_create =~ "optional(:filter) => DodoPayments.RequestTypes.meter_filter()"

    assert entitlement_create =~
             ":integration_config => DodoPayments.RequestTypes.entitlement_integration_config()"
  end

  test "nested enum atoms encode on the correct domain and invalid atoms fail before dispatch" do
    assert {:ok,
            %{
              body: %{
                "name" => "Typed product",
                "price" => %{
                  "currency" => "USD",
                  "discount" => 0,
                  "price" => 100,
                  "purchasing_power_parity" => false,
                  "type" => "one_time_price"
                },
                "tax_category" => "saas"
              }
            }} =
             Operation.prepare(Operation.fetch!(:products_create), %{
               name: "Typed product",
               price: %{
                 currency: :usd,
                 discount: 0,
                 price: 100,
                 purchasing_power_parity: false,
                 type: :one_time_price
               },
               tax_category: :saas
             })

    meter_params = %{
      aggregation: %{type: :sum, key: "tokens"},
      event_name: "tokens.used",
      measurement_unit: "token",
      name: "Tokens",
      filter: %{
        conjunction: :and,
        clauses: [%{key: "model", operator: :equals, value: "pro"}]
      }
    }

    assert {:ok,
            %{
              body: %{
                "aggregation" => %{"key" => "tokens", "type" => "sum"},
                "filter" => %{
                  "clauses" => [%{"key" => "model", "operator" => "equals", "value" => "pro"}],
                  "conjunction" => "and"
                }
              }
            }} = Operation.prepare(Operation.fetch!(:meters_create), meter_params)

    assert {:error, %DodoPayments.ValidationError{}} =
             Operation.prepare(
               Operation.fetch!(:meters_create),
               put_in(meter_params, [:aggregation, :type], :average)
             )
  end

  test "2.47 brand list and permanent archive parameters prepare on the correct channels" do
    assert {:ok, %{query: %{"include_archived" => true}, body: nil}} =
             Operation.prepare(Operation.fetch!(:brands_list), %{include_archived: true})

    assert {:ok,
            %{
              path: "/brands/brnd_1/archive",
              query: %{},
              body: %{"move_products_to" => "brnd_2"}
            }} =
             Operation.prepare(Operation.fetch!(:brands_archive), %{
               id: "brnd_1",
               move_products_to: "brnd_2"
             })
  end

  test "public specs refer to endpoint-local parameter types" do
    rendered = rendered_specs(DodoPayments.CheckoutSessions, :create)

    assert rendered =~ "create_params()"
    refute rendered =~ "map()"
  end

  test "transport-compatible date and decimal values keep their existing encoding" do
    operation = Operation.fetch!(:subscriptions_update)
    date = ~D[2027-01-02]
    datetime = ~U[2027-01-02 03:04:05Z]
    naive_datetime = ~N[2027-01-02 03:04:05]

    assert {:ok,
            %{
              body: %{
                "next_billing_date" => "2027-01-02",
                "metadata" => %{
                  "decimal" => "12.50",
                  "datetime" => "2027-01-02T03:04:05Z",
                  "naive_datetime" => "2027-01-02T03:04:05"
                }
              }
            }} =
             Operation.prepare(operation, %{
               subscription_id: "sub_123",
               next_billing_date: date,
               metadata: %{
                 decimal: Decimal.new("12.50"),
                 datetime: datetime,
                 naive_datetime: naive_datetime
               }
             })
  end

  test "schema-first parameter types are public and documented as such" do
    rendered = rendered_type(DodoPayments.Discounts, :attach_customers_params)

    assert rendered =~ ":customer_ids => [String.t()]"

    assert RequestTypes.type_doc(Operation.fetch!(:discount_customers_attach)) =~
             "schema-first"
  end

  defp rendered_type(module, name) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    {:type, type} =
      Enum.find(types, fn
        {:type, {^name, _definition, []}} -> true
        _other -> false
      end)

    type
    |> Code.Typespec.type_to_quoted()
    |> Macro.to_string()
  end

  defp rendered_specs(module, name) do
    {:ok, specs} = Code.Typespec.fetch_specs(module)

    specs
    |> Enum.filter(fn {{spec_name, _arity}, _definitions} -> spec_name == name end)
    |> Enum.flat_map(fn {_name_arity, definitions} -> definitions end)
    |> Enum.map(&Code.Typespec.spec_to_quoted(name, &1))
    |> Enum.map_join("\n", &Macro.to_string/1)
  end
end
