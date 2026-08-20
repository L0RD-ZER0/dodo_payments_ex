Mix.Task.run("app.start")

defmodule DodoStore.E2E.Stage1 do
  @moduledoc false

  alias DodoStore.Billing.OutboxDispatcher
  alias DodoStore.{Billing, Catalog, Dodo, Workflows}

  @default_fixtures %{
    customer_id: "cus_0NlOsoRzDK8gRlyyLlbqk",
    one_time_product_id: "pdt_0NlOqa3Ht7Txbw0Fb1Rlf",
    recurring_product_id: "pdt_0NlOsv3feJuKVRfQio4Xq",
    credit_pack_product_id: "pdt_0NlOsv4hrozJHqOf7O7bH",
    mandate_product_id: "pdt_0NlOsv3feJuKVRfQio4Xq",
    multi_meter_product_id: "pdt_0NlOsv6xc1xHAYxypOmHE",
    hybrid_product_id: "pdt_0NlOsv81KIbXsGCh86hUb"
  }

  def run do
    Logger.configure(level: :warning)
    refuse_live!()

    run_id =
      System.get_env("DODO_E2E_RUN_ID") ||
        "e2e-#{Date.utc_today() |> Date.to_iso8601() |> String.replace("-", "")}-#{suffix()}"

    fixtures = fixtures()
    client = Dodo.client()

    results =
      []
      |> record("fixture_retrieval", fn -> retrieve_fixtures(client, fixtures) end)
      |> record("pattern_1_checkout", fn ->
        checkout(client, run_id, 1, [product_id!()], [])
      end)
      |> record("pattern_2_checkout", fn ->
        checkout(client, run_id, 2, [fixtures.recurring_product_id],
          account_id: account(run_id, 2)
        )
      end)
      |> record("pattern_3_checkout", fn ->
        checkout(
          client,
          run_id,
          3,
          [fixtures.recurring_product_id, fixtures.one_time_product_id],
          []
        )
      end)
      |> record("pattern_4_usage", fn -> pattern_4(client, run_id, fixtures.customer_id) end)
      |> record("pattern_5_checkout", fn ->
        checkout(client, run_id, 5, [fixtures.credit_pack_product_id],
          account_id: account(run_id, 5),
          credits: 100
        )
      end)
      |> record("pattern_6_checkout", fn ->
        checkout(client, run_id, 6, [fixtures.mandate_product_id], account_id: account(run_id, 6))
      end)
      |> record("pattern_7_prerequisite", fn ->
        %{status: "awaiting_pattern_1_payment", detail: "refund runs after browser payment"}
      end)
      |> record("pattern_8_multiple_meters", fn ->
        pattern_8(client, run_id, fixtures.customer_id)
      end)
      |> record("pattern_9_checkout", fn ->
        checkout(client, run_id, 9, [fixtures.hybrid_product_id],
          account_id: account(run_id, 9),
          credits: 1_000
        )
      end)
      |> record("pattern_10_hard_limit", fn -> pattern_10(run_id) end)

    report = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      environment: "test",
      fixtures: fixtures,
      results: Enum.reverse(results)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage1.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)

    failures = Enum.count(report.results, &(&1.status == "failed"))
    IO.puts("stage1_run=#{run_id} checks=#{length(report.results)} failures=#{failures}")
    IO.puts("stage1_report=#{path}")

    if failures > 0, do: System.halt(2)
  end

  defp retrieve_fixtures(client, fixtures) do
    product_ids = [
      product_id!(),
      fixtures.one_time_product_id,
      fixtures.recurring_product_id,
      fixtures.credit_pack_product_id,
      fixtures.mandate_product_id,
      fixtures.multi_meter_product_id,
      fixtures.hybrid_product_id
    ]

    products =
      Enum.map(product_ids, fn id ->
        {:ok, product} = DodoPayments.Products.retrieve(client, id)
        %{id: id, name: product.name, recurring: product.is_recurring}
      end)

    {:ok, customer} = DodoPayments.Customers.retrieve(client, fixtures.customer_id)
    %{products: products, customer_id: field(customer, :customer_id)}
  end

  defp checkout(client, run_id, pattern, product_ids, opts) do
    order_id = "#{compact(run_id)}p#{pattern}#{suffix()}"
    cart = Enum.map(product_ids, &%{product_id: &1, quantity: 1})

    {:ok, session} =
      Workflows.checkout(
        client,
        pattern,
        cart,
        "http://127.0.0.1:4000/checkout/return",
        "http://127.0.0.1:4000/patterns",
        order_id,
        opts
      )

    %{
      status: "checkout_created",
      pattern: pattern,
      order_id: order_id,
      session_id: session.session_id,
      checkout_url: session.checkout_url,
      account_id: opts[:account_id],
      product_ids: product_ids
    }
  end

  defp pattern_4(client, run_id, customer_id) do
    action_id = "#{compact(run_id)}-api"
    {:ok, command, disposition} = Workflows.record_usage(action_id, customer_id, "api.call", 1)
    dispatch_if_due(command, disposition, client)

    event_id = "#{customer_id}:#{action_id}"
    {:ok, event} = DodoPayments.UsageEvents.retrieve(client, event_id)

    %{
      status: "delivered",
      command_id: command.command_id,
      event_id: event_id,
      remote_event_name: field(event, :event_name)
    }
  end

  defp pattern_8(client, run_id, customer_id) do
    action_id = "#{compact(run_id)}-multi"

    measurements = %{
      "ai.tokens" => 8_000,
      "compute.gpu_seconds" => 42,
      "storage.bytes" => 1_048_576
    }

    {:ok, command, disposition} =
      Workflows.record_multiple_meter_usage(action_id, customer_id, measurements)

    dispatch_if_due(command, disposition, client)

    event_ids =
      measurements
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn event_name ->
        event_id = "#{customer_id}:#{action_id}:#{event_name}"
        {:ok, event} = DodoPayments.UsageEvents.retrieve(client, event_id)
        %{event_id: event_id, event_name: field(event, :event_name)}
      end)

    %{status: "delivered", command_id: command.command_id, events: event_ids}
  end

  defp pattern_10(run_id) do
    period = Date.utc_today() |> Date.to_iso8601() |> String.slice(0, 7)
    account_id = account(run_id, 10)

    accepted =
      Enum.map(1..3, fn index ->
        {:ok, bucket} =
          Workflows.authorize_limited_use(
            account_id,
            "exports",
            period,
            "export-#{index}",
            1,
            3
          )

        bucket.used
      end)

    {:error, :limit_exceeded, denied_bucket} =
      Workflows.authorize_limited_use(
        account_id,
        "exports",
        period,
        "export-4",
        1,
        3
      )

    {:ok, duplicate_bucket} =
      Workflows.authorize_limited_use(
        account_id,
        "exports",
        period,
        "export-1",
        1,
        3
      )

    %{
      status: "enforced",
      accepted_used_values: accepted,
      denied_at: denied_bucket.used,
      duplicate_used: duplicate_bucket.used,
      limit: duplicate_bucket.limit
    }
  end

  defp dispatch_if_due(command, :accepted, client) do
    {:ok, _result} = OutboxDispatcher.dispatch(command, client)
  end

  defp dispatch_if_due(command, :duplicate, _client) do
    unless Billing.get_command(command.command_id).state == "delivered" do
      raise "duplicate command is not already delivered: #{command.command_id}"
    end
  end

  defp record(results, name, fun) do
    value = fun.()
    [%{name: name, status: "passed", evidence: value} | results]
  rescue
    error ->
      [
        %{
          name: name,
          status: "failed",
          error_class: inspect(error.__struct__),
          message: safe_error_message(error)
        }
        | results
      ]
  end

  defp fixtures do
    Enum.reduce(@default_fixtures, %{}, fn {key, default}, acc ->
      env = key |> Atom.to_string() |> String.upcase() |> then(&"DODO_E2E_#{&1}")
      Map.put(acc, key, System.get_env(env, default))
    end)
  end

  defp refuse_live! do
    unless System.get_env("DODO_PAYMENTS_ENVIRONMENT", "test") in ["test", "test_mode"] do
      raise "refusing to run E2E tests outside Dodo test mode"
    end
  end

  defp product_id! do
    case Catalog.fetch_product_id() do
      {:ok, product_id} -> product_id
      {:error, reason} -> raise "pattern-1 product is unavailable: #{inspect(reason)}"
    end
  end

  defp safe_error_message(%DodoPayments.Error.APIError{} = error),
    do: Exception.message(error)

  defp safe_error_message(%DodoPayments.Error.OutcomeUnknown{} = error),
    do: Exception.message(error)

  defp safe_error_message(%DodoPayments.ValidationError{} = error),
    do: Exception.message(error)

  defp safe_error_message(_error), do: "check failed; inspect the failing check locally"

  defp account(run_id, pattern), do: "#{compact(run_id)}-account-p#{pattern}"
  defp compact(value), do: String.replace(value, ~r/[^A-Za-z0-9]/, "")
  defp suffix, do: System.unique_integer([:positive, :monotonic]) |> Integer.to_string(36)
  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end

DodoStore.E2E.Stage1.run()
