Mix.Task.run("app.start")

defmodule DodoPayments.E2E.SupportedCountriesElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    {:ok, countries} = DodoPayments.SupportedCountries.list(client)
    sorted = Enum.sort(countries)

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      count: length(sorted),
      first: List.first(sorted),
      last: List.last(sorted),
      sha256: :crypto.hash(:sha256, Enum.join(sorted, ",")) |> Base.encode16(case: :lower)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "supported_countries_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("supported_countries_elixir_report=#{path}")
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
      raise "refusing to inspect resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.SupportedCountriesElixir.run()
