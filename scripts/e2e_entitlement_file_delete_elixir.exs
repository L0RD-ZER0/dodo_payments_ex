Mix.Task.run("app.start")

defmodule DodoPayments.E2E.EntitlementFileDeleteElixir do
  @moduledoc false

  @entitlement_id "ent_0Nlf5fZT0yPLbnokRUhD4"
  @file_id "124090fa-bf4f-4d6c-80e7-c8e810842370"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    result = DodoPayments.Entitlements.Files.delete(client, @entitlement_id, @file_id)
    {:ok, detail} = DodoPayments.Entitlements.retrieve(client, @entitlement_id)

    report = %{
      entitlement_id: @entitlement_id,
      file_id: @file_id,
      action: summarize(result),
      file_still_present: file_present?(detail, @file_id)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "entitlement_file_delete_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("entitlement_file_delete_elixir_report=#{path}")
  end

  defp summarize({:ok, _value}), do: %{result: "fulfilled"}

  defp summarize({:error, error}) do
    %{
      result: "rejected",
      status: Map.get(error, :status),
      code: Map.get(error, :code),
      message: Exception.message(error) |> String.slice(0, 300)
    }
  end

  defp file_present?(detail, file_id) do
    config = field(detail, :integration_config) || %{}
    digital = field(config, :digital_files) || %{}
    Enum.any?(field(digital, :files) || [], &(field(&1, :file_id) == file_id))
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

DodoPayments.E2E.EntitlementFileDeleteElixir.run()
