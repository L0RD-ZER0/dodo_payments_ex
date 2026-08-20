Mix.Task.run("app.start")

defmodule DodoPayments.E2E.CloseRemaining do
  @moduledoc false

  @plan_subscription_id "sub_0Nlg6mndF5f1C6SPqraBv"
  @target_product_id "pdt_0NlOsv81KIbXsGCh86hUb"
  @payment_method_subscription_id "sub_0Nlg7dGd2F3DkGE6FAcPG"
  @payment_method_customer_id "cus_0Nlg7dGMPmR3V4KiTywUO"
  @payment_method_id "pm_vwiwSxEC9FcOtoLJmHUe"
  @refund_id "ref_0Nlg8HYU1Lja9ACIObJsE"
  @documented_payout_id "pyt_zFTrrn4sk3x3y2vjDBW3T"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)

    report = %{
      run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      environment: "test_mode",
      plan_change: plan_change_wave(client),
      manual_license_fulfillment: manual_license_fulfillment_wave(client),
      payment_method: payment_method_wave(client),
      invoices: invoice_wave(client, live_public_client())
    }

    path =
      Path.join([
        File.cwd!(),
        "tmp",
        "e2e",
        "e2e-20260819-close-remaining",
        "elixir-wave-a.json"
      ])

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("e2e_close_remaining_report=#{path}")
  end

  defp plan_change_wave(client) do
    params = %{
      product_id: @target_product_id,
      proration_billing_mode: :full_immediately,
      quantity: 1,
      effective_at: :next_billing_date,
      on_payment_failure: :prevent_change,
      metadata: %{e2e_run: "e2e-20260819-close-remaining"}
    }

    preview =
      DodoPayments.Subscriptions.preview_change_plan(client, @plan_subscription_id, params)

    scheduled = DodoPayments.Subscriptions.change_plan(client, @plan_subscription_id, params)
    after_schedule = DodoPayments.Subscriptions.retrieve(client, @plan_subscription_id)

    cancelled =
      DodoPayments.Subscriptions.cancel_scheduled_change_plan(client, @plan_subscription_id)

    after_cancel = DodoPayments.Subscriptions.retrieve(client, @plan_subscription_id)

    %{
      subscription_id: @plan_subscription_id,
      target_product_id: @target_product_id,
      preview: summarize(preview),
      schedule: summarize(scheduled),
      observed_after_schedule: subscription_state(after_schedule),
      cancel: summarize(cancelled),
      observed_after_cancel: subscription_state(after_cancel)
    }
  end

  defp payment_method_wave(client) do
    before = DodoPayments.Customers.PaymentMethods.list(client, @payment_method_customer_id)

    update =
      DodoPayments.Subscriptions.update_payment_method(client, @payment_method_subscription_id, %{
        payment_method: %{
          type: :new,
          allowed_payment_method_types: [:credit],
          return_url: "http://127.0.0.1:4000/e2e/payment-method-updated"
        }
      })

    after_update = DodoPayments.Subscriptions.retrieve(client, @payment_method_subscription_id)

    cancelled =
      DodoPayments.Subscriptions.update(client, @payment_method_subscription_id, %{
        status: :cancelled
      })

    delete =
      DodoPayments.Customers.PaymentMethods.delete(
        client,
        @payment_method_customer_id,
        @payment_method_id
      )

    after_delete = DodoPayments.Customers.PaymentMethods.list(client, @payment_method_customer_id)

    %{
      customer_id: @payment_method_customer_id,
      subscription_id: @payment_method_subscription_id,
      payment_method_id: @payment_method_id,
      before: payment_method_ids(before),
      update: summarize(update),
      observed_after_update: subscription_state(after_update),
      cancel_subscription: summarize(cancelled),
      delete: summarize(delete),
      after_delete: payment_method_ids(after_delete)
    }
  end

  defp manual_license_fulfillment_wave(client) do
    marker = Integer.to_string(System.system_time(:microsecond))

    entitlement_result =
      DodoPayments.Entitlements.create(client, %{
        name: "Elixir E2E manual license #{marker}",
        description: "Disposable test-mode manual-fulfillment fixture",
        integration_type: :license_key,
        integration_config: %{
          fulfillment_mode: :manual,
          activations_limit: 2,
          duration_count: 1,
          duration_interval: :year
        },
        metadata: %{e2e_run: "e2e-20260819-close-remaining"}
      })

    with {:ok, entitlement} <- entitlement_result,
         entitlement_id when is_binary(entitlement_id) <- field(entitlement, :id),
         {:ok, product} <- create_manual_license_product(client, entitlement_id, marker),
         product_id when is_binary(product_id) <- field(product, :product_id),
         {:ok, checkout} <- buy_with_saved_method(client, product_id, marker),
         payment_id when is_binary(payment_id) <- field(checkout, :payment_id),
         {:ok, payment} <- wait_for_payment(client, payment_id, 20),
         :succeeded <- field(payment, :status),
         {:ok, pending_grant} <- wait_for_pending_grant(client, entitlement_id, 20),
         grant_id when is_binary(grant_id) <- field(pending_grant, :id) do
      key = "ELIXIR-E2E-MANUAL-#{marker}"

      fulfillment =
        DodoPayments.EntitlementGrants.fulfill_license_key(client, grant_id, %{
          key: key,
          activations_limit: 2
        })

      observed = find_grant(client, entitlement_id, grant_id)
      archive = DodoPayments.Products.archive(client, product_id)

      %{
        result: "fulfilled",
        entitlement_id: entitlement_id,
        product_id: product_id,
        payment_id: payment_id,
        payment_status: field(payment, :status),
        pending_grant: grant_state({:ok, pending_grant}),
        fulfillment: grant_state(fulfillment),
        observed_after_fulfillment: grant_state(observed),
        product_archive: summarize(archive)
      }
    else
      other ->
        %{
          result: "rejected",
          entitlement: summarize(entitlement_result),
          stopped_at: compact(other)
        }
    end
  end

  defp create_manual_license_product(client, entitlement_id, marker) do
    DodoPayments.Products.create(client, %{
      name: "Elixir E2E manual-license product #{marker}",
      description: "Disposable product for manual grant fulfillment",
      price: %{
        currency: :usd,
        discount: 0,
        price: 100,
        purchasing_power_parity: false,
        type: :one_time_price
      },
      tax_category: :saas,
      entitlements: [%{entitlement_id: entitlement_id}],
      metadata: %{e2e_run: "e2e-20260819-close-remaining"}
    })
  end

  defp buy_with_saved_method(client, product_id, marker) do
    DodoPayments.CheckoutSessions.create(client, %{
      product_cart: [%{product_id: product_id, quantity: 1}],
      customer: %{customer_id: @payment_method_customer_id},
      payment_method_id: @payment_method_id,
      confirm: true,
      billing_currency: :usd,
      billing_address: %{
        country: :us,
        state: "TX",
        city: "Austin",
        street: "102 Test Lane",
        zipcode: "78701"
      },
      return_url: "http://127.0.0.1:4000/e2e/manual-license",
      metadata: %{e2e_run: "e2e-20260819-close-remaining", marker: marker}
    })
  end

  defp wait_for_payment(client, payment_id, attempts) do
    poll(attempts, fn ->
      case DodoPayments.Payments.retrieve(client, payment_id) do
        {:ok, payment} = result ->
          if field(payment, :status) in [:succeeded, :failed, :cancelled] do
            {:done, result}
          else
            :retry
          end

        {:error, _error} = result ->
          {:done, result}
      end
    end)
  end

  defp wait_for_pending_grant(client, entitlement_id, attempts) do
    poll(attempts, fn ->
      case DodoPayments.EntitlementGrants.list(client, entitlement_id, %{
             page_size: 100,
             status: :pending
           }) do
        {:ok, page} ->
          case Enum.find(field(page, :items) || [], fn grant ->
                 field(grant, :customer_id) == @payment_method_customer_id
               end) do
            nil -> :retry
            grant -> {:done, {:ok, grant}}
          end

        {:error, _error} = result ->
          {:done, result}
      end
    end)
  end

  defp poll(0, _fun), do: {:error, :poll_exhausted}

  defp poll(attempts, fun) do
    case fun.() do
      {:done, result} ->
        result

      :retry ->
        Process.sleep(500)
        poll(attempts - 1, fun)
    end
  end

  defp find_grant(client, entitlement_id, grant_id) do
    with {:ok, page} <-
           DodoPayments.EntitlementGrants.list(client, entitlement_id, %{page_size: 100}),
         grant when not is_nil(grant) <-
           Enum.find(field(page, :items) || [], &(field(&1, :id) == grant_id)) do
      {:ok, grant}
    else
      nil -> {:error, :grant_not_found}
      other -> other
    end
  end

  defp grant_state({:ok, grant}) do
    license = field(grant, :license_key)

    %{
      result: "fulfilled",
      id: field(grant, :id),
      status: field(grant, :status),
      customer_id: field(grant, :customer_id),
      entitlement_id: field(grant, :entitlement_id),
      license_key_present: is_map(license) and present?(field(license, :key))
    }
  end

  defp grant_state(result), do: summarize(result)

  defp invoice_wave(client, live_client) do
    %{
      refund: binary_summary(DodoPayments.Invoices.download_refund(client, @refund_id)),
      payout_documented_test_host:
        binary_summary(DodoPayments.Invoices.download_payout(client, @documented_payout_id)),
      payout_documented_live_host:
        binary_summary(DodoPayments.Invoices.download_payout(live_client, @documented_payout_id))
    }
  end

  defp subscription_state({:ok, subscription}) do
    %{
      result: "fulfilled",
      subscription_id: field(subscription, :subscription_id),
      status: field(subscription, :status),
      product_id: field(subscription, :product_id),
      payment_method_id: field(subscription, :payment_method_id),
      scheduled_change: compact(field(subscription, :scheduled_change))
    }
  end

  defp subscription_state(result), do: summarize(result)

  defp payment_method_ids({:ok, page}) do
    %{
      result: "fulfilled",
      ids: Enum.map(field(page, :items) || [], &field(&1, :payment_method_id))
    }
  end

  defp payment_method_ids(result), do: summarize(result)

  defp binary_summary({:ok, binary}) when is_binary(binary) do
    %{
      result: "fulfilled",
      byte_length: byte_size(binary),
      pdf_magic: String.starts_with?(binary, "%PDF"),
      sha256: Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
    }
  end

  defp binary_summary(result), do: summarize(result)

  defp summarize({:ok, value}) do
    %{
      result: "fulfilled",
      value: compact(value)
    }
  end

  defp summarize({:error, error}) do
    %{
      result: "rejected",
      status: if(is_map(error), do: Map.get(error, :status), else: nil),
      code: if(is_map(error), do: Map.get(error, :code), else: nil),
      message: error_message(error)
    }
  end

  defp compact(nil), do: nil
  defp compact(value) when is_binary(value) or is_boolean(value) or is_number(value), do: value
  defp compact(value) when is_atom(value), do: Atom.to_string(value)
  defp compact(value) when is_list(value), do: Enum.map(value, &compact/1)
  defp compact(value) when is_tuple(value), do: value |> Tuple.to_list() |> compact()

  defp compact(value) when is_map(value) do
    normalized = if Map.has_key?(value, :__struct__), do: Map.from_struct(value), else: value

    normalized
    |> Map.drop([
      :extra,
      "extra",
      :client_secret,
      "client_secret",
      :payment_link,
      "payment_link",
      :checkout_url,
      "checkout_url",
      :publishable_key,
      "publishable_key"
    ])
    |> Map.new(fn {key, nested} -> {to_string(key), compact(nested)} end)
  end

  defp field(nil, _key), do: nil

  defp field(value, key) do
    case Map.fetch(value, key) do
      {:ok, result} -> result
      :error -> Map.get(value, Atom.to_string(key))
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp error_message(error) do
    message =
      if is_exception(error) do
        Exception.message(error)
      else
        inspect(error)
      end

    String.slice(message, 0, 500)
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
      max_attempts: 1,
      timeout: 30_000
    )
  end

  defp live_public_client do
    DodoPayments.client!(
      api_key: "unused-for-public-invoice-route",
      environment: :live,
      max_attempts: 1,
      timeout: 30_000
    )
  end

  defp refuse_live!(vars) do
    unless Map.get(vars, "DODO_PAYMENTS_ENVIRONMENT", "test") in ["test", "test_mode"] do
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.CloseRemaining.run()
