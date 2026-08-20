Mix.Task.run("app.start")

defmodule DodoPayments.E2E.ObserveElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    resources = observed_resources!(run_id)

    observations =
      resources
      |> Enum.map(&observe(client, &1))
      |> Map.new(&{&1.kind, &1})

    report = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      engine: "elixir_sdk",
      observations: observations
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "elixir_observation_catalog.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("elixir_observation_report=#{path}")
  end

  defp observe(client, %{"kind" => kind, "id" => id} = resource) do
    result =
      case kind do
        "customer" ->
          DodoPayments.Customers.retrieve(client, id)

        "meter" ->
          DodoPayments.Meters.retrieve(client, id)

        "credit_entitlement" ->
          DodoPayments.CreditEntitlements.retrieve(client, id)

        "webhook" ->
          DodoPayments.WebhookEndpoints.retrieve(client, id)

        "discount" ->
          DodoPayments.Discounts.retrieve(client, id)

        "addon" ->
          DodoPayments.Addons.retrieve(client, id)

        "brand" ->
          DodoPayments.Brands.retrieve(client, id)

        "product" ->
          DodoPayments.Products.retrieve(client, id)

        "localized_price" ->
          DodoPayments.Products.LocalizedPrices.retrieve(
            client,
            Map.fetch!(resource, "product_id"),
            id
          )

        "product_collection" ->
          DodoPayments.ProductCollections.retrieve(client, id)
      end

    case result do
      {:ok, value} ->
        %{
          kind: kind,
          id: id,
          observed: "retrieved",
          remote_id: remote_id(value),
          name: field(value, :name),
          archived: field(value, :archived) || field(value, :is_archived),
          status: field(value, :status)
        }

      {:error, error} ->
        %{
          kind: kind,
          id: id,
          observed: "not_retrievable",
          http_status: Map.get(error, :status),
          error_code: Map.get(error, :code),
          error_class: inspect(error.__struct__)
        }
    end
  end

  defp observed_resources!(run_id) do
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage2_observed.json"])
    report = path |> File.read!() |> Jason.decode!()
    products = Map.new(report["resources"], &{&1["kind"], &1["id"]})

    Enum.map(report["resources"], fn
      %{"kind" => "localized_price"} = resource ->
        Map.put(resource, "product_id", Map.fetch!(products, "product"))

      resource ->
        resource
    end)
  end

  defp remote_id(value) do
    Enum.find_value(
      [:customer_id, :meter_id, :id, :addon_id, :brand_id, :product_id, :product_collection_id],
      &field(value, &1)
    )
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
      raise "refusing to observe resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.ObserveElixir.run()
