Mix.Task.run("app.start")

defmodule DodoPayments.E2E.CustomerReadsElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    fixture = fixture!(run_id)
    customer_id = fixture["id"]

    {:ok, customers} =
      DodoPayments.Customers.list(client, %{
        email: "elixir-mcp-e2e-1787064741883@example.com",
        page_size: 100
      })

    {:ok, payment_methods} = DodoPayments.Customers.PaymentMethods.list(client, customer_id)

    {:ok, credit_entitlements} =
      DodoPayments.Customers.CreditEntitlements.list(client, customer_id)

    {:ok, entitlements} = DodoPayments.Customers.Entitlements.list(client, customer_id)

    {:ok, grants} =
      DodoPayments.Customers.Entitlements.list_grants(client, customer_id, %{page_size: 100})

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      customer_id: customer_id,
      customers:
        customers.items
        |> Enum.filter(&(field(&1, :customer_id) == customer_id))
        |> Enum.map(fn customer ->
          %{
            customer_id: field(customer, :customer_id),
            email: field(customer, :email),
            name: field(customer, :name)
          }
        end),
      payment_methods: compact_items(payment_methods),
      credit_entitlements: compact_items(credit_entitlements),
      entitlements: compact_items(entitlements),
      grants: compact_items(grants)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "customer_reads_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("customer_reads_elixir_report=#{path}")
  end

  defp compact_items(value) do
    value
    |> field(:items)
    |> List.wrap()
    |> Enum.map(fn item ->
      Map.take(item, [
        :id,
        :payment_method_id,
        :credit_entitlement_id,
        :entitlement_id,
        :grant_id,
        :status,
        :integration_type
      ])
    end)
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_fixtures.json"])
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("customer")
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
      raise "refusing to inspect resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.CustomerReadsElixir.run()
