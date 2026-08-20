Mix.Task.run("app.start")

defmodule DodoPayments.E2E.Stage2Billing do
  @moduledoc false

  @customer_id "cus_0NlOsoRzDK8gRlyyLlbqk"
  @one_time_product_id "pdt_0Nlf2O1IofbJ0gPgPNW3K"
  @recurring_product_id "pdt_0NlOsv3feJuKVRfQio4Xq"
  @hybrid_product_id "pdt_0NlOsv81KIbXsGCh86hUb"

  def run do
    Logger.configure(level: :warning)
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    state = %{run_id: run_id, operations: [], resources: [], findings: []}

    state
    |> payment_wave(client)
    |> subscription_wave(client)
    |> persist!()
    |> summarize!()
  end

  defp payment_wave(state, client) do
    {state, created} =
      call(state, :payments_create, fn ->
        DodoPayments.Payments.create(client, %{
          billing: billing(),
          customer: %{customer_id: @customer_id},
          product_cart: [%{product_id: @one_time_product_id, quantity: 1}],
          payment_link: true,
          return_url: "http://127.0.0.1:4000/",
          metadata: %{e2e_run: state.run_id, wave: "payment"}
        })
      end)

    case created do
      {:ok, payment} ->
        payment_id = field!(payment, :payment_id)
        state = resource(state, "pending_payment", payment_id, "expires_without_capture")

        {state, _} =
          call(state, :payments_retrieve, fn ->
            DodoPayments.Payments.retrieve(client, payment_id)
          end)

        {state, _} =
          call(state, :payment_line_items_list, fn ->
            DodoPayments.Payments.list_line_items(client, payment_id)
          end)

        {state, _} =
          call(state, :invoices_payment_download, fn ->
            DodoPayments.Invoices.download_payment(client, payment_id)
          end)

        state

      {:error, _error} ->
        state
    end
  end

  defp subscription_wave(state, client) do
    {state, created} =
      call(state, :subscriptions_create, fn ->
        DodoPayments.Subscriptions.create(client, %{
          billing: billing(),
          customer: %{customer_id: @customer_id},
          product_id: @hybrid_product_id,
          quantity: 1,
          payment_link: true,
          return_url: "http://127.0.0.1:4000/",
          metadata: %{e2e_run: state.run_id, wave: "subscription"}
        })
      end)

    case created do
      {:ok, subscription} ->
        subscription_id = field!(subscription, :subscription_id)
        payment_id = field!(subscription, :payment_id)

        state =
          state
          |> resource("pending_subscription", subscription_id, "expires_without_capture")
          |> resource("pending_subscription_payment", payment_id, "expires_without_capture")

        {state, _} =
          call(state, :subscriptions_retrieve, fn ->
            DodoPayments.Subscriptions.retrieve(client, subscription_id)
          end)

        {state, _} =
          call(state, :subscriptions_update, fn ->
            DodoPayments.Subscriptions.update(client, subscription_id, %{
              metadata: %{e2e_run: state.run_id, updated: true}
            })
          end)

        {state, _} =
          call(state, :subscriptions_usage_history, fn ->
            DodoPayments.Subscriptions.usage_history(client, subscription_id, %{page_size: 10})
          end)

        {state, _} =
          call(state, :subscriptions_credit_usage, fn ->
            DodoPayments.Subscriptions.credit_usage(client, subscription_id)
          end)

        {state, _} =
          call(state, :subscriptions_update_payment_method, fn ->
            DodoPayments.Subscriptions.update_payment_method(client, subscription_id, %{
              payment_method: %{
                type: "new",
                return_url: "http://127.0.0.1:4000/"
              }
            })
          end)

        {state, _} =
          call(state, :subscriptions_preview_change_plan, fn ->
            DodoPayments.Subscriptions.preview_change_plan(client, subscription_id, %{
              product_id: @recurring_product_id,
              quantity: 1,
              proration_billing_mode: :do_not_bill
            })
          end)

        {state, _} =
          call(state, :subscriptions_charge, fn ->
            DodoPayments.Subscriptions.charge(client, subscription_id, %{
              product_price: 100,
              product_currency: :usd,
              product_description: "Inactive-subscription boundary probe"
            })
          end)

        {state, _} =
          call(state, :subscriptions_change_plan, fn ->
            DodoPayments.Subscriptions.change_plan(client, subscription_id, %{
              product_id: @recurring_product_id,
              quantity: 1,
              proration_billing_mode: :do_not_bill
            })
          end)

        {state, _} =
          call(state, :subscriptions_cancel_change_plan, fn ->
            DodoPayments.Subscriptions.cancel_scheduled_change_plan(client, subscription_id)
          end)

        state

      {:error, _error} ->
        state
    end
  end

  defp call(state, operation, fun) do
    result = fun.()

    row =
      case result do
        {:ok, value} ->
          %{
            operation: Atom.to_string(operation),
            status: "live_passed",
            response_shape: response_shape(value),
            wave: "pending_billing_lifecycle"
          }

        {:error, error} ->
          %{
            operation: Atom.to_string(operation),
            status: error_status(operation, error),
            response_shape: "error",
            wave: "pending_billing_lifecycle",
            error_class: inspect(error.__struct__),
            http_status: Map.get(error, :status),
            message: safe_message(error)
          }
      end

    next = %{state | operations: upsert(state.operations, row)}
    persist!(next)
    {next, result}
  end

  defp resource(state, kind, id, cleanup) do
    %{state | resources: [%{kind: kind, id: id, cleanup: cleanup} | state.resources]}
  end

  defp persist!(state) do
    directory = Path.join([File.cwd!(), "tmp", "e2e", state.run_id])
    File.mkdir_p!(directory)

    wave = %{
      run_id: state.run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      environment: "test",
      operations: Enum.reverse(state.operations),
      resources: Enum.reverse(state.resources),
      findings: Enum.reverse(state.findings)
    }

    write_private!(Path.join(directory, "stage2_billing.json"), wave)
    merge_observed!(directory, state.operations)
    state
  end

  defp merge_observed!(directory, rows) do
    path = Path.join(directory, "stage2_observed.json")
    existing = path |> File.read!() |> Jason.decode!()

    merged =
      (Map.fetch!(existing, "operations") ++ Enum.map(rows, &stringify_keys/1))
      |> Enum.reverse()
      |> Enum.uniq_by(& &1["operation"])
      |> Enum.reverse()

    write_private!(path, Map.put(existing, "operations", merged))
  end

  defp write_private!(path, value) do
    File.write!(path, Jason.encode!(value, pretty: true), [:binary])
    File.chmod!(path, 0o600)
  end

  defp summarize!(state) do
    counts = Enum.frequencies_by(state.operations, & &1.status)

    IO.puts(
      "billing_wave=#{state.run_id} passed=#{Map.get(counts, "live_passed", 0)} failed=#{Map.get(counts, "live_failed", 0)}"
    )

    if Map.get(counts, "live_failed", 0) > 0, do: System.halt(2)
  end

  defp billing, do: %{country: :us, city: "San Francisco", state: "CA", zipcode: "94105"}

  defp upsert(rows, row), do: [row | Enum.reject(rows, &(&1.operation == row.operation))]

  defp field!(value, key) do
    Map.get(value, key) || Map.get(value, Atom.to_string(key)) ||
      raise "missing #{key} in #{inspect(value, limit: 20)}"
  end

  defp response_shape(%DodoPayments.Page.Numbered{}), do: "numbered_page"
  defp response_shape(%DodoPayments.Page.Cursor{}), do: "cursor_page"
  defp response_shape(value) when is_list(value), do: "list"
  defp response_shape(value) when is_map(value), do: "map"
  defp response_shape(value) when is_binary(value), do: "binary"
  defp response_shape(nil), do: "empty"
  defp response_shape(_value), do: "other"

  defp error_status(_operation, %DodoPayments.Error.APIError{
         code: code
       })
       when code in ["SUBSCRIPTION_INACTIVE", "INACTIVE_SUBSCRIPTION_PLAN_CHANGE_NOT_SUPPORTED"],
       do: "prerequisite_blocked"

  defp error_status(:subscriptions_charge, %DodoPayments.Error.APIError{
         code: "UNSUPPORTED_ACTION"
       }),
       do: "prerequisite_blocked"

  defp error_status(:subscriptions_cancel_change_plan, %DodoPayments.Error.APIError{
         code: "SCHEDULED_PLAN_CHANGE_NOT_FOUND"
       }),
       do: "prerequisite_blocked"

  defp error_status(_operation, _error), do: "live_failed"

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp safe_message(error) do
    error
    |> Exception.message()
    |> String.replace(~r/(Bearer|api[_-]?key)\s+[^\s]+/i, "[REDACTED]")
    |> String.slice(0, 500)
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
      raise "refusing to run E2E tests outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.Stage2Billing.run()
