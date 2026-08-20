Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualMeterElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp_fixture = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.Meters.create(client, %{
        aggregation: %{type: :count},
        event_name: "dual_driver_meter_elixir_#{marker}",
        measurement_unit: "requests",
        name: "Elixir Dual Driver Meter #{marker}",
        description: "139 endpoint workflow verification"
      })

    id = field(created, :id)
    {:ok, initial} = DodoPayments.Meters.retrieve(client, id)
    {:ok, _} = DodoPayments.Meters.archive(client, id)
    {:ok, archived} = DodoPayments.Meters.list(client, %{archived: true, page_size: 100})
    {:ok, _} = DodoPayments.Meters.unarchive(client, id)
    {:ok, final} = DodoPayments.Meters.retrieve(client, id)
    {:ok, active} = DodoPayments.Meters.list(client, %{archived: false, page_size: 100})
    {:ok, observed_mcp} = DodoPayments.Meters.retrieve(client, mcp_fixture["id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: id,
      created: compact(created),
      initial: compact(initial),
      archived_listed: includes?(archived, id),
      final: compact(final),
      active_listed: includes?(active, id),
      observed_mcp: compact(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_meter_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_meter_elixir_report=#{path}")
  end

  defp includes?(page, id), do: Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))

  defp compact(meter) do
    %{
      id: field(meter, :id),
      name: field(meter, :name),
      event_name: field(meter, :event_name),
      aggregation: field(meter, :aggregation)
    }
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_meter.json"])
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

DodoPayments.E2E.DualMeterElixir.run()
