Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualDiscountElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    customer_id = fixture!(run_id, "mcp_fixtures.json")["customer"]["id"]
    marker = Integer.to_string(System.system_time(:millisecond))
    code = "ELX" <> String.slice(marker, -10, 10)

    {:ok, created} =
      DodoPayments.Discounts.create(client, %{
        amount: 1_100,
        type: :percentage,
        code: code,
        name: "Elixir Dual Discount #{marker}",
        customer_eligibility: :specific,
        metadata: %{workflow: "dual_driver", marker: marker}
      })

    id = field(created, :discount_id)

    {:ok, updated} =
      DodoPayments.Discounts.update(client, id, %{
        amount: 1_400,
        name: "Elixir Dual Discount #{marker} Updated"
      })

    {:ok, retrieved} = DodoPayments.Discounts.retrieve(client, id)
    {:ok, by_code} = DodoPayments.Discounts.retrieve_by_code(client, code)
    {:ok, listed} = DodoPayments.Discounts.list(client, %{code: code, page_size: 100})
    {:ok, _} = DodoPayments.Discounts.attach_customers(client, id, %{customer_ids: [customer_id]})
    {:ok, attached} = DodoPayments.Discounts.list_customers(client, id, %{page_size: 100})
    {:ok, _} = DodoPayments.Discounts.detach_customer(client, id, customer_id)
    {:ok, detached} = DodoPayments.Discounts.list_customers(client, id, %{page_size: 100})
    {:ok, _} = DodoPayments.Discounts.attach_customers(client, id, %{customer_ids: [customer_id]})
    {:ok, reattached} = DodoPayments.Discounts.list_customers(client, id, %{page_size: 100})

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: id,
      code: code,
      updated: compact(updated),
      retrieved: compact(retrieved),
      by_code: compact(by_code),
      listed: includes?(listed, :discount_id, id),
      attached: includes_customer?(attached, customer_id),
      detached: not includes_customer?(detached, customer_id),
      reattached: includes_customer?(reattached, customer_id),
      cleanup_pending:
        "MCP raw transport must observe, detach, and delete because these routes are absent from its public SDK surface"
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_discount_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_discount_elixir_report=#{path}")
  end

  defp compact(item) do
    %{
      discount_id: field(item, :discount_id),
      code: field(item, :code),
      amount: field(item, :amount),
      name: field(item, :name),
      type: field(item, :type),
      customer_eligibility: field(item, :customer_eligibility)
    }
  end

  defp includes?(page, key, value) do
    Enum.any?(field(page, :items) || [], &(field(&1, key) == value))
  end

  defp includes_customer?(page, customer_id) do
    Enum.any?(field(page, :items) || [], fn item ->
      field(item, :customer_id) == customer_id or field(item, :id) == customer_id
    end)
  end

  defp fixture!(run_id, name) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, name])
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

DodoPayments.E2E.DualDiscountElixir.run()
