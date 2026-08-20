Mix.Task.run("app.start")

defmodule DodoPayments.E2E.LiveResponseTyping do
  @moduledoc false

  @product_id "pdt_0Nlf5fSRt2eLjquLq5KIV"
  @checkout_session_id "cks_0NlfX4ISapWJzXPDH3znQ"
  @payment_id "pay_0NlfXxvrokbB9jSWoqwWM"
  @subscription_id "sub_0NlfYhzUvNFi4pi0KS5ZZ"
  @license_id "lic_0NlfanDOsImdC67EPsUSb"
  @license_key "ELIXIR-E2E-1787068669994"
  @license_instance_id "lki_0NlfanHoMBqYVcijbpksz"
  @grant_entitlement_id "ent_0NlfA1g08nCTfbr1iRyG7"
  @grant_id "entg_0NlfA1h8PiWtuQB1eTYNn"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")

    {:ok, product} = DodoPayments.Products.retrieve(client, @product_id)
    {:ok, checkout} = DodoPayments.CheckoutSessions.retrieve(client, @checkout_session_id)
    {:ok, payment} = DodoPayments.Payments.retrieve(client, @payment_id)
    {:ok, subscription} = DodoPayments.Subscriptions.retrieve(client, @subscription_id)
    {:ok, license} = DodoPayments.LicenseKeys.retrieve(client, @license_id)

    {:ok, validation} =
      DodoPayments.Licenses.validate(client, %{
        license_key: @license_key,
        license_key_instance_id: @license_instance_id
      })

    {:ok, grants} =
      DodoPayments.EntitlementGrants.list(client, @grant_entitlement_id, %{page_size: 100})

    grant = Enum.find(field(grants, :items) || [], &(field(&1, :id) == @grant_id))

    {:ok, events} =
      DodoPayments.UsageEvents.list(client, %{
        customer_id: "cus_0NlfOKxVjKiEIFLUhrFHI",
        page_size: 100
      })

    usage_event = List.first(field(events, :items) || [])
    {:ok, line_items} = DodoPayments.Payments.list_line_items(client, @payment_id)

    {:ok, addons} = DodoPayments.Addons.list(client, %{page_size: 1})
    {:ok, brands} = DodoPayments.Brands.list(client, %{include_archived: true})
    {:ok, customers} = DodoPayments.Customers.list(client, %{page_size: 1})
    {:ok, discounts} = DodoPayments.Discounts.list(client, %{page_size: 1})
    {:ok, meters} = DodoPayments.Meters.list(client, %{archived: true, page_size: 1})
    {:ok, entitlements} = DodoPayments.Entitlements.list(client, %{page_size: 1})
    {:ok, webhooks} = DodoPayments.WebhookEndpoints.list(client, %{limit: 1})

    required_typed_structs = [
      struct_report("product", product),
      struct_report("checkout_session_status", checkout),
      struct_report("payment", payment),
      struct_report("subscription", subscription),
      struct_report("license_key", license),
      struct_report("license_validation", validation),
      struct_report("entitlement_grant", grant),
      struct_report("usage_event", usage_event),
      struct_report("payment_line_items", line_items),
      struct_report("brand_list_response", brands)
    ]

    optional_typed_structs = [
      struct_report("addon", first_item(addons)),
      struct_report("customer", first_item(customers)),
      struct_report("discount", first_item(discounts)),
      struct_report("meter", first_item(meters)),
      struct_report("entitlement", first_item(entitlements)),
      struct_report("webhook_endpoint", first_item(webhooks))
    ]

    required_drift =
      Enum.filter(required_typed_structs, fn sample ->
        Map.get(sample, :missing_fixture, false) or Map.get(sample, :extra_keys, []) != []
      end)

    optional_drift =
      Enum.filter(optional_typed_structs, fn sample ->
        not Map.get(sample, :missing_fixture, false) and Map.get(sample, :extra_keys, []) != []
      end)

    if required_drift != [] or optional_drift != [] do
      raise "live response typing drift: #{inspect(required_drift ++ optional_drift)}"
    end

    typed_structs = required_typed_structs ++ optional_typed_structs

    report = %{
      typed_structs: typed_structs,
      nested_live_shapes: %{
        payment_line_item: line_items |> field(:items) |> List.first() |> shape()
      },
      summary: %{
        sample_count: length(typed_structs),
        missing_fixture_count: Enum.count(typed_structs, &Map.get(&1, :missing_fixture, false)),
        unexpected_extra_key_count:
          typed_structs
          |> Enum.map(&length(Map.get(&1, :extra_keys, [])))
          |> Enum.sum()
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "live_response_typing.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("live_response_typing_report=#{path}")
  end

  defp struct_report(name, nil), do: %{name: name, missing_fixture: true}

  defp struct_report(name, value) do
    fields = Map.from_struct(value)
    extra = Map.get(fields, :extra, %{})

    %{
      name: name,
      module: value.__struct__ |> inspect(),
      populated_fields:
        fields
        |> Enum.reject(fn {key, item} -> key == :extra or is_nil(item) end)
        |> Enum.map(fn {key, _item} -> Atom.to_string(key) end)
        |> Enum.sort(),
      extra_keys: extra |> Map.keys() |> Enum.sort()
    }
  end

  defp first_item(value), do: value |> field(:items) |> then(&List.first(&1 || []))

  defp shape(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), shape(item)} end)
    |> Map.new()
  end

  defp shape(value) when is_list(value) do
    %{kind: "list", count: length(value), item: value |> List.first() |> shape()}
  end

  defp shape(nil), do: "nil"
  defp shape(value) when is_binary(value), do: "string"
  defp shape(value) when is_boolean(value), do: "boolean"
  defp shape(value) when is_integer(value), do: "integer"
  defp shape(value) when is_float(value), do: "float"
  defp shape(value) when is_atom(value), do: "atom"
  defp shape(_value), do: "other"

  defp field(nil, _key), do: nil

  defp field(value, key) do
    case Map.fetch(value, key) do
      {:ok, result} -> result
      :error -> Map.get(value, Atom.to_string(key))
    end
  end

  defp load_env! do
    ".env"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      [key, value] = String.split(line, "=", parts: 2)
      {String.trim(key), value |> String.trim() |> String.trim("\"")}
    end)
  end

  defp client!(vars) do
    DodoPayments.client!(
      api_key: Map.fetch!(vars, "DODO_PAYMENTS_API_KEY"),
      environment: :test,
      max_attempts: 1
    )
  end

  defp refuse_live!(vars) do
    unless Map.get(vars, "DODO_PAYMENTS_ENVIRONMENT", "test") in ["test", "test_mode"] do
      raise "refusing to read resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.LiveResponseTyping.run()
