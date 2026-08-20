Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualSubscriptionElixir do
  @moduledoc false

  @customer_id "cus_0NlfOKxVjKiEIFLUhrFHI"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))
    {:ok, product} = create_product(client, "Elixir Dual Subscription #{marker}", 799)
    {:ok, target} = create_product(client, "Elixir Dual Subscription Target #{marker}", 999)
    product_id = field(product, :product_id)
    target_id = field(target, :product_id)

    {:ok, created} =
      DodoPayments.Subscriptions.create(client, %{
        billing: %{
          city: "San Francisco",
          country: :us,
          state: "CA",
          street: "1 Market Street",
          zipcode: "94105"
        },
        customer: %{customer_id: @customer_id},
        product_id: product_id,
        quantity: 1,
        billing_currency: :usd,
        metadata: %{workflow: "dual_driver_subscription", marker: marker},
        payment_link: false,
        return_url: "http://127.0.0.1:4000/"
      })

    subscription_id = field(created, :subscription_id)

    {:ok, updated} =
      DodoPayments.Subscriptions.update(client, subscription_id, %{
        metadata: %{workflow: "dual_driver_subscription", marker: marker, updated: "true"},
        customer_name: "Dual Subscription Customer"
      })

    {:ok, retrieved} = DodoPayments.Subscriptions.retrieve(client, subscription_id)

    {:ok, listed} =
      DodoPayments.Subscriptions.list(client, %{customer_id: @customer_id, page_size: 100})

    {:ok, credit_usage} = DodoPayments.Subscriptions.credit_usage(client, subscription_id)

    {:ok, usage_history} =
      DodoPayments.Subscriptions.usage_history(client, subscription_id, %{page_size: 100})

    gated = %{
      charge:
        DodoPayments.Subscriptions.charge(client, subscription_id, %{
          product_price: 100,
          product_currency: :usd,
          product_description: "Prerequisite probe"
        }),
      preview_change_plan:
        DodoPayments.Subscriptions.preview_change_plan(client, subscription_id, %{
          product_id: target_id,
          proration_billing_mode: :prorated_immediately,
          quantity: 1
        }),
      change_plan:
        DodoPayments.Subscriptions.change_plan(client, subscription_id, %{
          product_id: target_id,
          proration_billing_mode: :prorated_immediately,
          quantity: 1
        }),
      update_payment_method:
        DodoPayments.Subscriptions.update_payment_method(client, subscription_id, %{
          payment_method: %{
            type: :new,
            allowed_payment_method_types: [:credit],
            return_url: "http://127.0.0.1:4000/"
          }
        }),
      cancel_change_plan:
        DodoPayments.Subscriptions.cancel_scheduled_change_plan(client, subscription_id)
    }

    {:ok, observed_mcp} = DodoPayments.Subscriptions.retrieve(client, mcp["subscription_id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      subscription_id: subscription_id,
      product_id: product_id,
      target_product_id: target_id,
      create: %{
        payment_id: field(created, :payment_id),
        client_secret_present: present?(field(created, :client_secret))
      },
      update: compact_subscription(updated),
      retrieve: compact_subscription(retrieved),
      listed: includes?(listed, subscription_id),
      credit_usage: %{
        subscription_id: field(credit_usage, :subscription_id),
        item_count: length(field(credit_usage, :items) || [])
      },
      usage_history_count: length(field(usage_history, :items) || []),
      gated: Map.new(gated, fn {key, value} -> {key, summarize(value)} end),
      observed_mcp: compact_subscription(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_subscription_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_subscription_elixir_report=#{path}")
  end

  defp create_product(client, name, amount) do
    DodoPayments.Products.create(client, %{
      name: name,
      price: %{
        currency: :usd,
        discount: 0,
        price: amount,
        purchasing_power_parity: false,
        type: "recurring_price",
        payment_frequency_count: 1,
        payment_frequency_interval: :month,
        subscription_period_count: 1,
        subscription_period_interval: :month
      },
      tax_category: :saas
    })
  end

  defp compact_subscription(subscription) do
    %{
      subscription_id: field(subscription, :subscription_id),
      status: field(subscription, :status),
      product_id: field(subscription, :product_id),
      quantity: field(subscription, :quantity),
      metadata: field(subscription, :metadata)
    }
  end

  defp summarize({:ok, _value}), do: %{result: "fulfilled"}

  defp summarize({:error, error}) do
    %{result: "rejected", status: Map.get(error, :status), code: Map.get(error, :code)}
  end

  defp includes?(page, subscription_id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :subscription_id) == subscription_id))
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_subscription_lifecycle.json"])
    |> File.read!()
    |> Jason.decode!()
  end

  defp present?(value), do: is_binary(value) and value != ""
  defp field(nil, _key), do: nil
  defp field(value, key), do: Map.get(value, key) || Map.get(value, Atom.to_string(key))

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
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.DualSubscriptionElixir.run()
