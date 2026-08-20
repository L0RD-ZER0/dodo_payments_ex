Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualEntitlementGrantElixir do
  @moduledoc false

  @elixir_entitlement_id "ent_0NlfA1g08nCTfbr1iRyG7"
  @elixir_grant_id "entg_0NlfA1h8PiWtuQB1eTYNn"
  @mcp_entitlement_id "ent_0Nlf8xzStrBe6NyFfMCk0"
  @mcp_grant_id "entg_0Nlf8y0nyQi1INiCdqaFN"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")

    {:ok, revoked} =
      DodoPayments.EntitlementGrants.revoke(client, @elixir_entitlement_id, @elixir_grant_id)

    {:ok, elixir_grants} =
      DodoPayments.EntitlementGrants.list(client, @elixir_entitlement_id, %{page_size: 100})

    {:ok, mcp_grants} =
      DodoPayments.EntitlementGrants.list(client, @mcp_entitlement_id, %{page_size: 100})

    report = %{
      elixir_action: %{
        grant_id: field(revoked, :id),
        status: field(revoked, :status),
        listed_status: status(elixir_grants, @elixir_grant_id)
      },
      observed_mcp: %{
        grant_id: @mcp_grant_id,
        listed_status: status(mcp_grants, @mcp_grant_id)
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_entitlement_grant_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_entitlement_grant_elixir_report=#{path}")
  end

  defp status(page, grant_id) do
    page
    |> field(:items)
    |> Enum.find(&(field(&1, :id) == grant_id))
    |> field(:status)
  end

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
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.DualEntitlementGrantElixir.run()
