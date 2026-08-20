defmodule DodoPayments.ClientAndSchemaTest do
  use ExUnit.Case, async: true

  doctest DodoPayments
  doctest DodoPayments.Schema

  alias DodoPayments.Error.ConfigurationError

  test "custom endpoints require an explicit custom environment when environment is supplied" do
    assert {:error, %ConfigurationError{message: message}} =
             DodoPayments.client(environment: :test, base_url: "https://proxy.invalid")

    assert message =~ "environment: :custom"

    assert {:ok, %DodoPayments.Client{environment: :custom, base_url: "https://proxy.invalid"}} =
             DodoPayments.client(base_url: "https://proxy.invalid")

    assert {:ok, %DodoPayments.Client{environment: :custom}} =
             DodoPayments.client(environment: :custom, base_url: "https://proxy.invalid")
  end

  test "client inspection distinguishes a missing key from a redacted key" do
    without_key = DodoPayments.client!()
    with_key = DodoPayments.client!(api_key: "sk_test")

    assert inspect(without_key) =~ "api_key: nil"
    assert inspect(with_key) =~ "api_key: :redacted"
    refute inspect(with_key) =~ "sk_test"
  end

  test "with_api_key raises a configuration error instead of a function clause error" do
    client = DodoPayments.client!()

    assert_raise ConfigurationError, ~r/api_key must be/, fn ->
      DodoPayments.Client.with_api_key(client, 123)
    end

    assert_raise ConfigurationError, ~r/api_key must be/, fn ->
      DodoPayments.Client.with_api_key(client, "")
    end

    assert_raise ConfigurationError, ~r/control bytes/, fn ->
      DodoPayments.Client.with_api_key(client, "sk_test\r\nx-injected: yes")
    end
  end

  test "direct empty API keys and ambiguous transport configuration fail eagerly" do
    assert {:error, %ConfigurationError{message: key_message}} =
             DodoPayments.client(api_key: "")

    assert key_message =~ "api_key"

    for unsafe_key <- ["sk_test\r\nx-injected: yes", "sk_test\0", <<1>>, <<255>>] do
      assert {:error, %ConfigurationError{message: unsafe_key_message}} =
               DodoPayments.client(api_key: unsafe_key)

      assert unsafe_key_message =~ "control bytes"
    end

    assert {:error, %ConfigurationError{message: exclusive_message}} =
             DodoPayments.client(
               client: {DodoPayments.TestClient, fn _ -> :ok end},
               req: :invalid
             )

    assert exclusive_message =~ "mutually exclusive"

    assert {:error, %ConfigurationError{message: url_message}} =
             DodoPayments.client(environment: :custom, base_url: 123)

    assert url_message =~ "absolute HTTPS URL"

    for malformed <- [
          "https://example.com:bad",
          "http://[::1",
          "https://bad host",
          "https://example.com\0",
          "https://example.com:0",
          "https://example.com:65536",
          "https://example.com/%ZZ",
          "https://exa%ZZmple.com"
        ] do
      assert {:error, %ConfigurationError{message: malformed_message}} =
               DodoPayments.client(base_url: malformed)

      assert malformed_message =~ "absolute HTTPS URL"
    end

    assert {:ok, %DodoPayments.Client{base_url: "https://example.com/%2F"}} =
             DodoPayments.client(base_url: "https://example.com/%2F")
  end

  test "plaintext custom origins require an explicit opt-in" do
    assert {:error, %ConfigurationError{message: message}} =
             DodoPayments.client(base_url: "http://127.0.0.1:4000")

    assert message =~ "allow_insecure_http"

    assert {:ok, %DodoPayments.Client{base_url: "http://127.0.0.1:4000"}} =
             DodoPayments.client(
               base_url: "http://127.0.0.1:4000",
               allow_insecure_http: true
             )

    assert {:error, %ConfigurationError{message: boolean_message}} =
             DodoPayments.client(
               base_url: "http://127.0.0.1:4000",
               allow_insecure_http: :yes
             )

    assert boolean_message == "allow_insecure_http must be a boolean"
  end

  test "invalid environment errors do not echo arbitrary configuration values" do
    secret = "SENTINEL_CONFIGURATION_VALUE"

    assert {:error, %ConfigurationError{} = error} =
             DodoPayments.client(environment: secret)

    refute Exception.message(error) =~ secret
    refute inspect(error) =~ secret
  end

  test "timeouts are bounded by the BEAM timer ceiling" do
    maximum = DodoPayments.Deadline.max_timeout()

    assert {:ok, %DodoPayments.Client{timeout: ^maximum}} =
             DodoPayments.client(timeout: maximum)

    for timeout <- [0, maximum + 1] do
      assert {:error, %ConfigurationError{message: message}} =
               DodoPayments.client(timeout: timeout)

      assert message =~ "between 1 and #{maximum}"
    end
  end

  test "version and user agent have one source of truth" do
    expected = File.read!(Path.expand("../../VERSION", __DIR__)) |> String.trim()

    assert DodoPayments.version() == expected
    assert DodoPayments.user_agent() == "dodo-payments-elixir/" <> expected
    assert Mix.Project.config()[:version] == expected
  end

  test "schema inspection recursively redacts canonical and schema-specific fields" do
    value = %DodoPayments.CheckoutSession{
      checkout_url: "https://checkout.invalid/SENTINEL_LINK",
      client_secret: "SENTINEL_CLIENT_SECRET",
      extra: %{
        "authorization" => "SENTINEL_AUTH",
        "nested" => %{"license_key" => "SENTINEL_LICENSE"}
      }
    }

    rendered = inspect(value)

    refute rendered =~ "SENTINEL"
    assert rendered =~ ":redacted"

    credential_shaped = %DodoPayments.Product{
      extra: %{
        "x-api-key" => "SENTINEL_X_API_KEY",
        "x-auth-token" => "SENTINEL_AUTH_TOKEN",
        "proxy-authorization" => "SENTINEL_PROXY"
      }
    }

    refute inspect(credential_shaped) =~ "SENTINEL"

    document_urls = [
      %DodoPayments.Payment{invoice_url: "https://files.invalid/SENTINEL_INVOICE"},
      %DodoPayments.Product{
        digital_product_delivery: %{
          "files" => [%{"download_url" => "https://files.invalid/SENTINEL_DOWNLOAD"}]
        }
      },
      %DodoPayments.Response{
        data: %{"payout_document_url" => "https://files.invalid/SENTINEL_PAYOUT"},
        status: 200,
        headers: [],
        request_id: nil
      }
    ]

    Enum.each(document_urls, fn value -> refute inspect(value) =~ "SENTINEL" end)
  end

  test "response envelopes and pages redact untyped secrets" do
    response = %DodoPayments.Response{
      data: %{
        "client_secret" => "SENTINEL_CLIENT",
        "refresh_token" => "SENTINEL_REFRESH"
      },
      status: 200,
      headers: [{"set-cookie", "SENTINEL_COOKIE"}],
      request_id: "req_1"
    }

    numbered =
      DodoPayments.Page.Numbered.new(
        [
          %{"license_key" => "SENTINEL_LICENSE"},
          %DodoPayments.LicenseKey{key: "SENTINEL_TYPED_KEY"}
        ],
        0,
        extra: %{"api_key" => "SENTINEL_API_KEY"}
      )

    cursor =
      DodoPayments.Page.Cursor.new(
        [%{"payment_link" => "SENTINEL_LINK"}],
        iterator: "next",
        extra: %{"webhook_secret" => "SENTINEL_WEBHOOK"}
      )

    for value <- [response, numbered, cursor] do
      rendered = inspect(value)
      refute rendered =~ "SENTINEL"
      assert rendered =~ ":redacted" or rendered =~ "[REDACTED]"
    end

    refute inspect(numbered) =~ "fetch_next"
    refute inspect(cursor) =~ "fetch_next"
  end

  test "the operation catalogue is complete, unique, and declares business validators locally" do
    operations = DodoPayments.Operation.all()

    assert length(operations) == DodoPayments.operation_count()
    assert Enum.uniq_by(operations, & &1.id) == operations
    assert DodoPayments.Operation.fetch!(:usage_events_ingest).validator == :usage_event_batch

    assert DodoPayments.Operation.fetch!(:discount_customers_attach).validator ==
             :customer_id_list

    assert DodoPayments.Operation.fetch!(:discount_customers_attach).consequential
    assert DodoPayments.Operation.fetch!(:entitlement_grants_revoke).consequential
    refute DodoPayments.Operation.fetch!(:checkout_sessions_preview).consequential
    refute DodoPayments.Operation.fetch!(:subscriptions_preview_change_plan).consequential
    refute DodoPayments.Operation.fetch!(:licenses_validate).consequential

    assert DodoPayments.Operation.fetch!(:webhook_endpoints_create).replay ==
             {:idempotent_by, [:idempotency_key]}

    assert DodoPayments.Operation.fetch!(:subscriptions_change_plan).response_mode == :empty
  end

  test "source metadata is derived from the audited source lock" do
    source_lock =
      "../../priv/upstream/source-lock.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    assert DodoPayments.source_sdk_version() == source_lock["version"]
    assert DodoPayments.operation_count() == source_lock["sdk_core_operation_total"]
  end

  test "generated resource functions expose only usable arities and operation-aware docs" do
    functions = DodoPayments.Products.__info__(:functions)

    refute {:create, 1} in functions
    assert {:create, 2} in functions
    assert {:create, 3} in functions
    assert {:list, 1} in functions

    subscription_functions = DodoPayments.Subscriptions.__info__(:functions)
    refute {:charge, 2} in subscription_functions
    assert {:charge, 3} in subscription_functions
    assert {:charge, 4} in subscription_functions

    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(DodoPayments.Products)

    {{:function, :create, 2}, _, _, %{"en" => create_doc}, _} =
      Enum.find(docs, fn
        {{:function, :create, 2}, _, _, _, _} -> true
        _ -> false
      end)

    assert create_doc =~ "POST /products"
    assert create_doc =~ "`:name`, `:price`, `:tax_category`"

    for module <- [DodoPayments.Products, DodoPayments.Brands, DodoPayments.WebhookEndpoints] do
      {:ok, specs} = Code.Typespec.fetch_specs(module)
      refute inspect(specs, limit: :infinity) =~ "{:atom, 0, nil}, {:atom, 0, :t}"
    end
  end

  test "upstream-required request bodies cannot be omitted" do
    cases = [
      {:product_short_links_create, [:slug], DodoPayments.Products.ShortLinks, :create,
       ["pdt_1"]},
      {:localized_prices_create, [:amount, :currency], DodoPayments.Products.LocalizedPrices,
       :create, ["pdt_1"]},
      {:collection_groups_create, [:products], DodoPayments.ProductCollections.Groups, :create,
       ["pc_1"]},
      {:collection_group_items_create, [:products], DodoPayments.ProductCollections.Groups.Items,
       :create, ["pc_1", "grp_1"]},
      {:collection_group_items_update, [:status], DodoPayments.ProductCollections.Groups.Items,
       :update, ["pc_1", "grp_1", "item_1"]},
      {:subscriptions_preview_change_plan, [:product_id, :proration_billing_mode, :quantity],
       DodoPayments.Subscriptions, :preview_change_plan, ["sub_1"]},
      {:entitlement_grants_fulfill_license_key, [:key], DodoPayments.EntitlementGrants,
       :fulfill_license_key, ["grant_1"]},
      {:license_key_instances_update, [:name], DodoPayments.LicenseKeyInstances, :update,
       ["instance_1"]},
      {:webhook_headers_update, [:headers], DodoPayments.WebhookEndpoints.Headers, :update,
       ["webhook_1"]}
    ]

    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    Enum.each(cases, fn {operation_id, required, module, function, path_args} ->
      assert DodoPayments.Operation.fetch!(operation_id).required == required
      refute function_exported?(module, function, 1 + length(path_args))

      assert {:error, %DodoPayments.ValidationError{field: field, reason: :required}} =
               apply(module, function, [client | path_args] ++ [%{}])

      assert field == hd(required)
    end)
  end

  test "capability-bearing response schemas redact links in data and response envelopes" do
    transport = fn request ->
      path = request.url |> to_string() |> URI.parse() |> Map.fetch!(:path)

      body =
        cond do
          path == "/products/pdt_1/files" ->
            %{"file_id" => "file_1", "url" => "https://upload.invalid/SENTINEL_FILE"}

          path == "/customers/cus_1/customer-portal/session" ->
            %{"link" => "https://portal.invalid/SENTINEL_PORTAL"}

          true ->
            %{"image_id" => "image_1", "url" => "https://upload.invalid/SENTINEL_IMAGE"}
        end

      DodoPayments.TestSupport.response(200, Jason.encode!(body))
    end

    client = DodoPayments.TestSupport.client(transport)

    calls = [
      {fn opts -> DodoPayments.Addons.update_images(client, "addon_1", opts) end,
       DodoPayments.PresignedImageUpload, :image_id},
      {fn opts -> DodoPayments.Brands.update_images(client, "brand_1", opts) end,
       DodoPayments.PresignedImageUpload, :image_id},
      {fn opts -> DodoPayments.Products.Images.update(client, "pdt_1", opts) end,
       DodoPayments.PresignedImageUpload, :image_id},
      {fn opts ->
         DodoPayments.Products.update_files(client, "pdt_1", %{file_name: "guide.pdf"}, opts)
       end, DodoPayments.PresignedFileUpload, :file_id},
      {fn opts -> DodoPayments.ProductCollections.update_images(client, "pc_1", opts) end,
       DodoPayments.PresignedImageUpload, :image_id},
      {fn opts -> DodoPayments.Customers.PortalSessions.create(client, "cus_1", opts) end,
       DodoPayments.CustomerPortalSession, :link}
    ]

    Enum.each(calls, fn {call, schema, visible_field} ->
      assert {:ok, %{__struct__: ^schema} = data} = call.([])
      assert Map.get(data, visible_field)
      refute inspect(data) =~ "SENTINEL"

      assert {:ok, %DodoPayments.Response{data: %{__struct__: ^schema} = enveloped} = response} =
               call.(return: :response)

      assert Map.get(enveloped, visible_field)
      refute inspect(response) =~ "SENTINEL"
    end)
  end

  test "resource declarations exactly match catalogue ids and path parameters" do
    declarations =
      "../../lib/dodo_payments/resources/*.ex"
      |> Path.expand(__DIR__)
      |> Path.wildcard()
      |> Enum.flat_map(&resource_declarations/1)

    operations = DodoPayments.Operation.all()
    expected = Map.new(operations, &{&1.id, &1.path_params})

    assert length(declarations) == length(operations)
    assert Map.new(declarations) == expected
  end

  test "operation-specific validation fails before transport" do
    client =
      DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error, %DodoPayments.ValidationError{field: :events}} =
             DodoPayments.UsageEvents.ingest(client, %{events: [%{event_id: "missing-fields"}]})

    assert {:error, %DodoPayments.ValidationError{field: :customer_ids}} =
             DodoPayments.Discounts.attach_customers(client, "discount_1", %{customer_ids: []})

    assert {:error, %DodoPayments.ValidationError{reason: :invalid_usage_events}} =
             DodoPayments.UsageEvents.ingest(client, %{events: []})

    too_many =
      List.duplicate(%{event_id: "evt", customer_id: "cus", event_name: "api"}, 1_001)

    assert {:error, %DodoPayments.ValidationError{reason: :invalid_usage_events}} =
             DodoPayments.UsageEvents.ingest(client, %{events: too_many})

    assert {:error, %DodoPayments.ValidationError{reason: :invalid_customer_ids}} =
             DodoPayments.Discounts.attach_customers(client, "discount_1", %{
               customer_ids: ["cus_1", 2]
             })
  end

  test "atom and string forms of the same request key are rejected as ambiguous" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error,
            %DodoPayments.ValidationError{
              field: :page_number,
              reason: :duplicate_atom_and_string_key
            }} =
             DodoPayments.Products.list(client, %{"page_number" => 1, page_number: 0})
  end

  test "nested atom and string key collisions are rejected before replay analysis" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    event = %{
      "event_id" => "",
      event_id: "evt_stable",
      customer_id: "cus_1",
      event_name: "api_call"
    }

    assert {:error,
            %DodoPayments.ValidationError{
              field: :event_id,
              reason: :duplicate_atom_and_string_key
            }} = DodoPayments.UsageEvents.ingest(client, %{events: [event]})
  end

  test "keys that collide after JSON encoding are rejected recursively" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    for params <- [
          %{1 => "integer", "1" => "string"},
          %{metadata: %{2 => "integer", "2" => "string"}},
          %{items: [%{3 => "integer", "3" => "string"}]}
        ] do
      assert {:error,
              %DodoPayments.ValidationError{
                field: field,
                reason: :duplicate_json_key
              }} = DodoPayments.Products.create(client, params)

      assert field in ["1", "2", "3"]
    end
  end

  test "unsupported JSON object keys return validation errors before transport" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error,
            %DodoPayments.ValidationError{
              field: nil,
              reason: :unsupported_json_key
            }} = DodoPayments.Products.create(client, %{{:not, :stringable} => "value"})
  end

  test "resource functions return validation errors for invalid parameter shapes" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error, %DodoPayments.ValidationError{reason: :not_a_map}} =
             DodoPayments.Products.create(client, "not-a-map")

    assert {:error, %ConfigurationError{message: parameter_message}} =
             DodoPayments.Products.create(client, name: "Starter")

    assert parameter_message =~ "must be passed as a map"
    assert parameter_message =~ "keyword lists are reserved for request options"

    assert {:error, %ConfigurationError{message: message}} =
             DodoPayments.Products.retrieve(client, "pdt_1", :not_options)

    assert message =~ "keyword list"

    assert {:error, %DodoPayments.ValidationError{field: :id, reason: :invalid_path_value}} =
             DodoPayments.Products.retrieve(client, :invalid)
  end

  test "codec normalizes supported Elixir values deterministically" do
    datetime = ~U[2026-08-13 10:20:30Z]
    naive = ~N[2026-08-13 10:20:30]

    assert DodoPayments.Codec.encode(%{
             amount: Decimal.new("12.50"),
             date: ~D[2026-08-13],
             datetime: datetime,
             naive: naive
           }) == %{
             "amount" => "12.50",
             "date" => "2026-08-13",
             "datetime" => "2026-08-13T10:20:30Z",
             "naive" => "2026-08-13T10:20:30"
           }

    product = %DodoPayments.Product{product_id: "pdt_1", extra: %{"future" => "ignored"}}
    encoded = DodoPayments.Codec.encode(product)
    assert encoded["product_id"] == "pdt_1"
    refute Map.has_key?(encoded, "extra")
    assert DodoPayments.Codec.decode("") == {:ok, nil}
  end

  test "secret resolution returns bounded, redacted failures" do
    assert {:error, %ConfigurationError{}} = DodoPayments.Secret.resolve(nil)

    assert {:error, %ConfigurationError{}} =
             DodoPayments.Secret.resolve(DodoPayments.Secret.new(""))

    throwing = DodoPayments.Secret.new(fn -> throw(:provider_failed) end)

    assert {:error, %DodoPayments.Error.PreparationError{kind: :throw}} =
             DodoPayments.Secret.resolve(throwing)

    secret = DodoPayments.Secret.new("SENTINEL_SECRET")
    refute inspect(secret) =~ "SENTINEL_SECRET"
  end

  test "validation errors retain diagnostics without exposing request values in inspection" do
    client = DodoPayments.TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error, %DodoPayments.ValidationError{} = error} =
             DodoPayments.Products.create(client, %{
               name: "Starter",
               price: 100,
               tax_category: "digital",
               metadata: {:SENTINEL_REQUEST_VALUE, self()}
             })

    refute inspect(error) =~ "SENTINEL_REQUEST_VALUE"
    refute Exception.message(error) =~ "SENTINEL_REQUEST_VALUE"
  end

  defp resource_declarations(file) do
    ast = file |> File.read!() |> Code.string_to_quoted!()

    {_ast, declarations} =
      Macro.prewalk(ast, [], fn
        {:operation, _, [_name, id]} = node, acc when is_atom(id) ->
          {node, [{id, []} | acc]}

        {:operation, _, [_name, id, opts]} = node, acc when is_atom(id) and is_list(opts) ->
          {node, [{id, Keyword.get(opts, :path, [])} | acc]}

        node, acc ->
          {node, acc}
      end)

    declarations
  end
end
