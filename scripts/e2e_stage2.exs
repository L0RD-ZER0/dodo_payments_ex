Mix.Task.run("app.start")

defmodule DodoPayments.E2E.Stage2 do
  @moduledoc false

  @customer_id "cus_0NlOsoRzDK8gRlyyLlbqk"
  @credit_entitlement_id "cde_0NlOsoaXXmhr1EJgKEal5"
  @product_id "pdt_0Nlf2O1IofbJ0gPgPNW3K"
  @meter_id "mtr_0NlOsoVqgzaUAEod7UD9B"
  @brand_id "bus_0NlOlFYaiDGMSLkXkfLPj"
  @webhook_id "ep_3HvG6mYjXnxdddhReLX2s9Ex1HF"

  def run do
    Logger.configure(level: :warning)
    vars = load_env!()
    refuse_live!(vars)

    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    client = client!(vars)
    operations = DodoPayments.Operation.all()

    if length(operations) != DodoPayments.operation_count() do
      raise "catalog drift: source lock and operation catalogue disagree"
    end

    stage1 = stage1_report!(run_id)
    checkout_id = checkout_id!(stage1, "pattern_1_checkout")
    event_id = "#{@customer_id}:#{compact(run_id)}-api"

    pathless =
      operations
      |> Enum.filter(&(&1.method == :get and &1.path_params == [] and &1.required == []))
      |> Enum.map(&{&1.id, []})

    pathful = fixture_reads(checkout_id, event_id)
    live_results = [execute_checkout_preview(client) | execute_reads(client, pathless ++ pathful)]

    live_by_id =
      live_results
      |> Kernel.++(observed_results(run_id))
      |> Map.new(&{&1.operation, &1})

    rows =
      Enum.map(operations, fn operation ->
        base = %{
          operation: operation.id,
          method: operation.method,
          path: operation.path,
          path_params: operation.path_params,
          required: operation.required,
          response_mode: operation.response_mode,
          consequential: operation.consequential,
          replay: inspect(operation.replay)
        }

        case Map.fetch(live_by_id, operation.id) do
          {:ok, result} -> Map.merge(base, result)
          :error -> Map.merge(base, %{status: "pending_fixture_or_mutation"})
        end
      end)

    report = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      environment: "test",
      operation_count: length(rows),
      counts: Enum.frequencies_by(rows, & &1.status),
      operations: rows
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage2.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)

    failures = Enum.count(rows, &(&1.status == "live_failed"))
    passes = Enum.count(rows, &(&1.status == "live_passed"))

    IO.puts(
      "stage2_run=#{run_id} operations=#{length(rows)} live_passed=#{passes} failures=#{failures}"
    )

    IO.puts("stage2_report=#{path}")

    if failures > 0, do: System.halt(2)
  end

  defp execute_reads(client, fixtures) do
    fixtures
    |> Task.async_stream(
      fn {operation, path_pairs} -> execute_read(client, operation, path_pairs) end,
      max_concurrency: 8,
      timeout: 60_000,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> %{operation: :task_exit, status: "live_failed", error: "task_exit"}
    end)
  end

  defp execute_read(client, operation, path_pairs) do
    case DodoPayments.Service.call(client, operation, path_pairs, %{}, []) do
      {:ok, value} ->
        %{operation: operation, status: "live_passed", response_shape: response_shape(value)}

      {:error, error} ->
        %{
          operation: operation,
          status: "live_failed",
          error_class: inspect(error.__struct__),
          http_status: Map.get(error, :status)
        }
    end
  end

  defp execute_checkout_preview(client) do
    case DodoPayments.CheckoutSessions.preview(client, %{
           product_cart: [%{product_id: @product_id, quantity: 1}]
         }) do
      {:ok, value} ->
        %{
          operation: :checkout_sessions_preview,
          status: "live_passed",
          response_shape: response_shape(value),
          wave: "safe_mutations"
        }

      {:error, error} ->
        %{
          operation: :checkout_sessions_preview,
          status: "live_failed",
          response_shape: "error",
          wave: "safe_mutations",
          error_class: inspect(error.__struct__),
          http_status: Map.get(error, :status)
        }
    end
  end

  defp fixture_reads(checkout_id, event_id) do
    [
      brands_retrieve: [id: @brand_id],
      checkout_sessions_retrieve: [id: checkout_id],
      products_retrieve: [id: @product_id],
      localized_prices_list: [product_id: @product_id],
      customers_retrieve: [customer_id: @customer_id],
      customer_payment_methods_list: [customer_id: @customer_id],
      customer_credit_entitlements_list: [customer_id: @customer_id],
      customer_entitlements_list: [customer_id: @customer_id],
      customer_entitlement_grants_list: [customer_id: @customer_id],
      customer_wallets_list: [customer_id: @customer_id],
      customer_wallet_ledger_entries_list: [customer_id: @customer_id],
      meters_retrieve: [id: @meter_id],
      usage_events_retrieve: [event_id: event_id],
      credit_entitlements_retrieve: [id: @credit_entitlement_id],
      credit_balances_list: [credit_entitlement_id: @credit_entitlement_id],
      credit_balances_retrieve: [
        credit_entitlement_id: @credit_entitlement_id,
        customer_id: @customer_id
      ],
      credit_balance_grants_list: [
        credit_entitlement_id: @credit_entitlement_id,
        customer_id: @customer_id
      ],
      credit_balance_ledger_list: [
        credit_entitlement_id: @credit_entitlement_id,
        customer_id: @customer_id
      ],
      webhook_endpoints_retrieve: [webhook_id: @webhook_id],
      webhook_endpoints_retrieve_secret: [webhook_id: @webhook_id],
      webhook_headers_retrieve: [webhook_id: @webhook_id]
    ]
  end

  defp stage1_report!(run_id) do
    path =
      Path.join([
        File.cwd!(),
        "examples",
        "phoenix_checkout",
        "tmp",
        "e2e",
        run_id,
        "stage1.json"
      ])

    path |> File.read!() |> Jason.decode!()
  end

  defp observed_results(run_id) do
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage2_observed.json"])

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("operations")
      |> Enum.map(fn row ->
        base = %{
          operation: String.to_existing_atom(row["operation"]),
          status: row["status"],
          response_shape: row["response_shape"],
          wave: row["wave"]
        }

        Enum.reduce(["error_class", "http_status", "message"], base, fn key, acc ->
          case Map.fetch(row, key) do
            {:ok, value} -> Map.put(acc, String.to_atom(key), value)
            :error -> acc
          end
        end)
      end)
    else
      []
    end
  end

  defp checkout_id!(stage1, name) do
    stage1
    |> Map.fetch!("results")
    |> Enum.find(&(&1["name"] == name))
    |> get_in(["evidence", "session_id"])
  end

  defp response_shape(%DodoPayments.Page.Numbered{}), do: "numbered_page"
  defp response_shape(%DodoPayments.Page.Cursor{}), do: "cursor_page"
  defp response_shape(value) when is_list(value), do: "list"
  defp response_shape(value) when is_map(value), do: "map"
  defp response_shape(value) when is_binary(value), do: "binary"
  defp response_shape(nil), do: "empty"
  defp response_shape(_value), do: "other"

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

  defp compact(value), do: String.replace(value, ~r/[^A-Za-z0-9]/, "")
end

DodoPayments.E2E.Stage2.run()
