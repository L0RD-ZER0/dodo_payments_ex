Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualEntitlementElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.Entitlements.create(client, %{
        name: "Elixir Dual Feature #{marker}",
        description: "Automated dual-driver entitlement fixture",
        integration_type: :feature_flag,
        integration_config: %{feature_id: "elixir_dual_#{marker}", feature_type: "boolean"},
        metadata: %{workflow: "dual_driver_entitlement", marker: marker}
      })

    entitlement_id = field(created, :id)

    {:ok, updated} =
      DodoPayments.Entitlements.update(client, entitlement_id, %{
        name: "Elixir Dual Feature #{marker} Updated",
        metadata: %{workflow: "dual_driver_entitlement", marker: marker, updated: true}
      })

    {:ok, retrieved} = DodoPayments.Entitlements.retrieve(client, entitlement_id)

    {:ok, listed} =
      DodoPayments.Entitlements.list(client, %{integration_type: :feature_flag, page_size: 100})

    {:ok, grants} = DodoPayments.EntitlementGrants.list(client, entitlement_id, %{page_size: 100})

    {:ok, digital} =
      DodoPayments.Entitlements.create(client, %{
        name: "Elixir Dual Digital #{marker}",
        description: "Automated file-contract probe",
        integration_type: :digital_files,
        integration_config: %{
          digital_file_ids: [],
          external_url: "https://example.com/elixir-dual",
          instructions: "Automated test fixture"
        },
        metadata: %{workflow: "dual_driver_entitlement_file", marker: marker}
      })

    digital_id = field(digital, :id)
    upload = DodoPayments.Entitlements.Files.upload(client, digital_id)
    {:ok, observed_mcp} = DodoPayments.Entitlements.retrieve(client, mcp["feature_id"])
    {:ok, observed_mcp_digital} = DodoPayments.Entitlements.retrieve(client, mcp["digital_id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      entitlement_id: entitlement_id,
      digital_id: digital_id,
      updated: compact(updated),
      retrieved: compact(retrieved),
      listed: includes?(listed, entitlement_id),
      grant_count: length(field(grants, :items) || []),
      upload: summarize(upload),
      observed_mcp: compact(observed_mcp),
      observed_mcp_digital: compact(observed_mcp_digital)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_entitlement_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_entitlement_elixir_report=#{path}")
  end

  defp compact(value) do
    %{
      id: field(value, :id),
      name: field(value, :name),
      integration_type: field(value, :integration_type),
      is_active: field(value, :is_active),
      metadata: field(value, :metadata)
    }
  end

  defp summarize({:ok, value}), do: %{result: "fulfilled", file_id: field(value, :file_id)}

  defp summarize({:error, error}) do
    %{
      result: "rejected",
      status: Map.get(error, :status),
      code: Map.get(error, :code),
      message: Exception.message(error) |> String.slice(0, 300)
    }
  end

  defp includes?(page, id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_entitlement_lifecycle.json"])
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

DodoPayments.E2E.DualEntitlementElixir.run()
