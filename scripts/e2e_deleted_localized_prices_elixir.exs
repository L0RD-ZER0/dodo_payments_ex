Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DeletedLocalizedPricesElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")

    fixtures = [
      {"pdt_0NlfUjHPHsGJMxyuz2qlg", "lcp_0NlfUjuCiO4qFr6G7BWrc"},
      {"pdt_0Nlf5fSRt2eLjquLq5KIV", "lcp_0NlfUyDvl2l1nIn6wJebg"}
    ]

    observations =
      Enum.map(fixtures, fn {product_id, localized_id} ->
        case DodoPayments.Products.LocalizedPrices.retrieve(client, product_id, localized_id) do
          {:error, error} ->
            %{product_id: product_id, id: localized_id, status: Map.get(error, :status)}

          {:ok, _price} ->
            %{product_id: product_id, id: localized_id, status: 200}
        end
      end)

    report = %{run_id: run_id, engine: "elixir_sdk", observations: observations}
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "deleted_localized_prices_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("deleted_localized_prices_elixir_report=#{path}")
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

DodoPayments.E2E.DeletedLocalizedPricesElixir.run()
