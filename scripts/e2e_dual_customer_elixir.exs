Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualCustomerElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    fixture = fixture!(run_id)
    customer_id = fixture["id"]

    {:ok, before_customer} = DodoPayments.Customers.retrieve(client, customer_id)

    {:ok, updated_customer} =
      DodoPayments.Customers.update(client, customer_id, %{
        name: fixture["name"] <> " + Elixir",
        metadata: %{workflow: "dual_driver", updated: true, elixir_observed: true}
      })

    {:ok, portal} =
      DodoPayments.Customers.PortalSessions.create(client, customer_id, %{
        return_url: "http://127.0.0.1:4000/",
        send_email: false
      })

    {:ok, wallet_after} =
      DodoPayments.Customers.Wallets.LedgerEntries.create(client, customer_id, %{
        amount: 223,
        currency: :usd,
        entry_type: :credit,
        idempotency_key: "dual-driver-wallet-elixir-#{run_id}",
        reason: "Elixir half of dual-driver endpoint verification"
      })

    {:ok, observed_customer} = DodoPayments.Customers.retrieve(client, customer_id)
    {:ok, wallets} = DodoPayments.Customers.Wallets.list(client, customer_id)

    {:ok, ledger_page} =
      DodoPayments.Customers.Wallets.LedgerEntries.list(client, customer_id, %{
        currency: :usd,
        page_size: 20
      })

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      customer: %{
        id: customer_id,
        before_name: field(before_customer, :name),
        update_response_name: field(updated_customer, :name),
        observed_name: field(observed_customer, :name),
        metadata: field(observed_customer, :metadata)
      },
      portal: %{link_present: is_binary(portal.link) and portal.link != ""},
      wallet_create: %{
        currency: field(wallet_after, :currency),
        balance: field(wallet_after, :balance)
      },
      wallets: sanitize_wallets(wallets),
      ledger: Enum.map(ledger_page.items, &sanitize_ledger/1)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_customer_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_customer_elixir_report=#{path}")
  end

  defp sanitize_wallets(wallets) do
    items = field(wallets, :items) || []

    %{
      total_balance_usd: field(wallets, :total_balance_usd),
      items: Enum.map(items, &%{currency: field(&1, :currency), balance: field(&1, :balance)})
    }
  end

  defp sanitize_ledger(item) do
    %{
      id: field(item, :id),
      amount: field(item, :amount),
      currency: field(item, :currency),
      is_credit: field(item, :is_credit),
      after_balance: field(item, :after_balance),
      reason: field(item, :reason)
    }
  end

  defp fixture!(run_id) do
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_fixtures.json"])
    path |> File.read!() |> Jason.decode!() |> Map.fetch!("customer")
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

DodoPayments.E2E.DualCustomerElixir.run()
