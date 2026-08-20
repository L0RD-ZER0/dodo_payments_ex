Mix.Task.run("app.start")

defmodule DodoPayments.E2E.CleanupLicenseElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    elixir = read!(run_id, "dual_license_elixir.json")
    mcp = read!(run_id, "mcp_license_lifecycle.json")

    {:ok, mcp_validation} =
      DodoPayments.Licenses.validate(client, %{
        license_key: mcp["license_key"],
        license_key_instance_id: mcp["instance_id"]
      })

    mcp_retrieve = DodoPayments.LicenseKeyInstances.retrieve(client, mcp["instance_id"])

    {:ok, mcp_instances} =
      DodoPayments.LicenseKeyInstances.list(client, %{
        license_key_id: mcp["license_id"],
        page_size: 100
      })

    case DodoPayments.LicenseKeyInstances.retrieve(client, elixir["instance_id"]) do
      {:ok, _instance} ->
        {:ok, _} =
          DodoPayments.Licenses.deactivate(client, %{
            license_key: elixir["license_key"],
            license_key_instance_id: elixir["instance_id"]
          })

      {:error, %{status: 404}} ->
        :already_deactivated
    end

    {:ok, validation} =
      DodoPayments.Licenses.validate(client, %{
        license_key: elixir["license_key"],
        license_key_instance_id: elixir["instance_id"]
      })

    retrieve_after = DodoPayments.LicenseKeyInstances.retrieve(client, elixir["instance_id"])

    {:ok, instances_after} =
      DodoPayments.LicenseKeyInstances.list(client, %{
        license_key_id: elixir["license_id"],
        page_size: 100
      })

    case DodoPayments.Products.archive(client, elixir["product_id"]) do
      {:ok, _result} -> :archived
      {:error, %{status: 410}} -> :already_archived
    end

    report = %{
      observed_mcp_deactivated: %{
        valid: field(mcp_validation, :valid),
        retrieve_gone: gone?(mcp_retrieve),
        listed: includes?(mcp_instances, mcp["instance_id"])
      },
      deactivated_elixir: %{
        valid: field(validation, :valid),
        retrieve_gone: gone?(retrieve_after),
        listed: includes?(instances_after, elixir["instance_id"])
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "cleanup_license_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("cleanup_license_elixir_report=#{path}")
  end

  defp gone?({:error, %{status: 404}}), do: true
  defp gone?(_result), do: false

  defp includes?(page, id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))
  end

  defp read!(run_id, name) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, name])
    |> File.read!()
    |> Jason.decode!()
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

DodoPayments.E2E.CleanupLicenseElixir.run()
