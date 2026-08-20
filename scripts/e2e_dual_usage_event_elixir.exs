Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualUsageEventElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp_event = fixture!(run_id, "mcp_usage_event.json")
    meter = fixture!(run_id, "dual_meter_elixir.json")
    customer = fixture!(run_id, "mcp_fixtures.json")["customer"]
    marker = Integer.to_string(System.system_time(:millisecond))
    event_id = "elixir_dual_event_#{marker}"
    event_name = meter["final"]["event_name"]

    {:ok, ingested} =
      DodoPayments.UsageEvents.ingest(client, %{
        events: [
          %{
            customer_id: customer["id"],
            event_id: event_id,
            event_name: event_name,
            metadata: %{source: "elixir", units: 5, billable: true}
          }
        ]
      })

    {:ok, retrieved} = DodoPayments.UsageEvents.retrieve(client, event_id)

    {:ok, listed} =
      DodoPayments.UsageEvents.list(client, %{
        customer_id: customer["id"],
        event_name: event_name,
        page_size: 100
      })

    {:ok, observed_mcp} = DodoPayments.UsageEvents.retrieve(client, mcp_event["event_id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      event_id: event_id,
      event_name: event_name,
      customer_id: customer["id"],
      ingest: %{ingested_count: field(ingested, :ingested_count)},
      retrieved: compact(retrieved),
      listed: includes?(listed, event_id),
      observed_mcp: compact(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_usage_event_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_usage_event_elixir_report=#{path}")
  end

  defp compact(event) do
    %{
      event_id: field(event, :event_id),
      event_name: field(event, :event_name),
      customer_id: field(event, :customer_id),
      metadata: field(event, :metadata)
    }
  end

  defp includes?(page, event_id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :event_id) == event_id))
  end

  defp fixture!(run_id, name) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, name])
    |> File.read!()
    |> Jason.decode!()
  end

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

DodoPayments.E2E.DualUsageEventElixir.run()
