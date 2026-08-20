Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualCreditElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    customer_id = fixture!(run_id, "mcp_fixtures.json")["customer"]["id"]
    mcp_credit = fixture!(run_id, "mcp_credit_lifecycle.json")
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.CreditEntitlements.create(client, %{
        name: "Elixir Dual Credit #{marker}",
        description: "139 endpoint workflow verification",
        precision: 2,
        unit: "credits",
        rollover_enabled: false,
        overage_enabled: false
      })

    id = field(created, :id)

    {:ok, _} =
      DodoPayments.CreditEntitlements.update(client, id, %{
        name: "Elixir Dual Credit #{marker} Updated",
        unit: "tokens"
      })

    {:ok, updated} = DodoPayments.CreditEntitlements.retrieve(client, id)

    {:ok, entry} =
      DodoPayments.CreditEntitlements.Balances.create_ledger_entry(client, id, customer_id, %{
        amount: "7.25",
        entry_type: :credit,
        idempotency_key: "elixir-credit-#{marker}",
        metadata: %{source: "elixir", marker: marker},
        reason: "Dual-driver credit verification"
      })

    {:ok, balance} = DodoPayments.CreditEntitlements.Balances.retrieve(client, id, customer_id)

    {:ok, balances} =
      DodoPayments.CreditEntitlements.Balances.list(client, id, %{
        customer_id: customer_id,
        page_size: 100
      })

    {:ok, grants} =
      DodoPayments.CreditEntitlements.Balances.list_grants(client, id, customer_id, %{
        page_size: 100
      })

    {:ok, ledger} =
      DodoPayments.CreditEntitlements.Balances.list_ledger(client, id, customer_id, %{
        page_size: 100
      })

    {:ok, _} = DodoPayments.CreditEntitlements.delete(client, id)

    {:ok, deleted} =
      DodoPayments.CreditEntitlements.list(client, %{deleted: true, page_size: 100})

    {:ok, _} = DodoPayments.CreditEntitlements.undelete(client, id)
    {:ok, restored} = DodoPayments.CreditEntitlements.retrieve(client, id)

    {:ok, active} =
      DodoPayments.CreditEntitlements.list(client, %{deleted: false, page_size: 100})

    {:ok, observed_mcp} = DodoPayments.CreditEntitlements.retrieve(client, mcp_credit["id"])

    {:ok, observed_mcp_balance} =
      DodoPayments.CreditEntitlements.Balances.retrieve(client, mcp_credit["id"], customer_id)

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: id,
      updated: compact_entitlement(updated),
      entry: compact_entry(entry),
      balance: compact_balance(balance),
      balance_listed: includes?(balances, :customer_id, customer_id),
      grants: compact_grants(grants),
      ledger: compact_ledger(ledger),
      deleted_listed: includes?(deleted, :id, id),
      restored: compact_entitlement(restored),
      active_listed: includes?(active, :id, id),
      observed_mcp: compact_entitlement(observed_mcp),
      observed_mcp_balance: compact_balance(observed_mcp_balance)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_credit_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_credit_elixir_report=#{path}")
  end

  defp compact_entitlement(item) do
    %{
      id: field(item, :id),
      name: field(item, :name),
      unit: field(item, :unit),
      precision: field(item, :precision)
    }
  end

  defp compact_entry(item) do
    %{
      id: field(item, :id),
      amount: field(item, :amount),
      balance_after: field(item, :balance_after),
      grant_id: field(item, :grant_id)
    }
  end

  defp compact_balance(item) do
    %{
      customer_id: field(item, :customer_id),
      balance: field(item, :balance),
      overage: field(item, :overage)
    }
  end

  defp compact_grants(page) do
    Enum.map(field(page, :items) || [], fn item ->
      %{
        id: field(item, :id),
        initial_amount: field(item, :initial_amount),
        remaining_amount: field(item, :remaining_amount),
        source_type: field(item, :source_type)
      }
    end)
  end

  defp compact_ledger(page) do
    Enum.map(field(page, :items) || [], fn item ->
      %{
        id: field(item, :id),
        amount: field(item, :amount),
        balance_after: field(item, :balance_after),
        is_credit: field(item, :is_credit),
        transaction_type: field(item, :transaction_type)
      }
    end)
  end

  defp includes?(page, key, value) do
    Enum.any?(field(page, :items) || [], &(field(&1, key) == value))
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

DodoPayments.E2E.DualCreditElixir.run()
