Mix.Task.run("app.start")

defmodule DodoPayments.E2E.CleanupEntitlementElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    elixir = read!(run_id, "dual_entitlement_elixir.json")
    mcp = read!(run_id, "mcp_entitlement_lifecycle.json")

    {:ok, _} = DodoPayments.Entitlements.delete(client, elixir["entitlement_id"])
    {:ok, _} = DodoPayments.Entitlements.delete(client, elixir["digital_id"])

    report = %{
      deleted_elixir: %{
        feature: gone?(DodoPayments.Entitlements.retrieve(client, elixir["entitlement_id"])),
        digital: gone?(DodoPayments.Entitlements.retrieve(client, elixir["digital_id"]))
      },
      observed_mcp_deleted: %{
        feature: gone?(DodoPayments.Entitlements.retrieve(client, mcp["feature_id"])),
        digital: gone?(DodoPayments.Entitlements.retrieve(client, mcp["digital_id"]))
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "cleanup_entitlement_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("cleanup_entitlement_elixir_report=#{path}")
  end

  defp gone?({:error, %{status: 404}}), do: true
  defp gone?(_result), do: false

  defp read!(run_id, name) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, name])
    |> File.read!()
    |> Jason.decode!()
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
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.CleanupEntitlementElixir.run()
