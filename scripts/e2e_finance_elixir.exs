Mix.Task.run("app.start")

defmodule DodoPayments.E2E.FinanceElixir do
  @moduledoc false

  @payment_id "pay_0NlfXxvrokbB9jSWoqwWM"
  @invoice_payment_id "pay_0NlfAGp5VxHdX3DUS4BbG"
  @customer_ids [
    "cus_0NlfOKxVjKiEIFLUhrFHI",
    "cus_0Nlf4lX558HVJtGgzUJgw",
    "cus_0NlOsoRzDK8gRlyyLlbqk"
  ]

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")

    {:ok, ledgers} = DodoPayments.Balances.list_ledger(client, %{page_size: 100})
    {:ok, refunds} = DodoPayments.Refunds.list(client, %{page_size: 100})
    {:ok, disputes} = DodoPayments.Disputes.list(client, %{page_size: 100})
    {:ok, payouts} = DodoPayments.Payouts.list(client, %{page_size: 100})
    refund_probe = DodoPayments.Refunds.create(client, %{payment_id: @payment_id})
    {:ok, payment} = DodoPayments.Payments.retrieve(client, @payment_id)
    {:ok, invoice} = DodoPayments.Invoices.download_payment(client, @invoice_payment_id)

    payment_method_delete =
      DodoPayments.Customers.PaymentMethods.delete(
        client,
        "cus_0NlfOKxVjKiEIFLUhrFHI",
        "pm_e2e_missing"
      )

    refund_retrieve = DodoPayments.Refunds.retrieve(client, "ref_e2e_missing")
    dispute_retrieve = DodoPayments.Disputes.retrieve(client, "dis_e2e_missing")
    payout_breakup = DodoPayments.Payouts.retrieve_breakup(client, "pyt_e2e_missing")

    payout_details =
      DodoPayments.Payouts.list_breakup_details(client, "pyt_e2e_missing", %{page_size: 10})

    payout_csv = DodoPayments.Payouts.download_breakup_csv(client, "pyt_e2e_missing")
    refund_invoice = DodoPayments.Invoices.download_refund(client, "ref_e2e_missing")
    payout_invoice = DodoPayments.Invoices.download_payout(client, "pyt_e2e_missing")

    payment_methods =
      Map.new(@customer_ids, fn customer_id ->
        {:ok, methods} = DodoPayments.Customers.PaymentMethods.list(client, customer_id)
        {customer_id, Enum.map(field(methods, :items) || [], &field(&1, :payment_method_id))}
      end)

    report = %{
      balance_ledgers: compact_ledgers(ledgers),
      refunds: compact_ids(refunds, :refund_id),
      disputes: compact_ids(disputes, :dispute_id),
      payouts: compact_ids(payouts, :payout_id),
      refund_probe: summarize(refund_probe),
      refund_probe_payment_state: field(payment, :status),
      payment_methods: payment_methods,
      missing_fixture_probes: %{
        payment_method_delete: summarize(payment_method_delete),
        refund_retrieve: summarize(refund_retrieve),
        dispute_retrieve: summarize(dispute_retrieve),
        payout_breakup: summarize_collection(payout_breakup),
        payout_details: summarize_page(payout_details),
        payout_csv: summarize_binary(payout_csv),
        refund_invoice: summarize(refund_invoice),
        payout_invoice: summarize(payout_invoice)
      },
      payment_invoice: %{
        byte_length: byte_size(invoice),
        pdf_magic: String.starts_with?(invoice, "%PDF"),
        sha256: Base.encode16(:crypto.hash(:sha256, invoice), case: :lower)
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "finance_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("finance_elixir_report=#{path}")
  end

  defp compact_ledgers(page) do
    Enum.map(field(page, :items) || [], fn item ->
      %{
        id: field(item, :id),
        amount: field(item, :amount),
        currency: field(item, :currency),
        event_type: field(item, :event_type),
        is_credit: field(item, :is_credit),
        reference_object_id: field(item, :reference_object_id)
      }
    end)
  end

  defp compact_ids(page, key), do: Enum.map(field(page, :items) || [], &field(&1, key))

  defp summarize({:ok, value}) do
    %{result: "fulfilled", refund_id: field(value, :refund_id), status: field(value, :status)}
  end

  defp summarize({:error, error}) do
    %{
      result: "rejected",
      status: Map.get(error, :status),
      code: Map.get(error, :code),
      message: Exception.message(error) |> String.slice(0, 300)
    }
  end

  defp summarize_collection({:ok, items}) when is_list(items) do
    %{result: "fulfilled", count: length(items)}
  end

  defp summarize_collection(result), do: summarize(result)

  defp summarize_page({:ok, page}) do
    %{result: "fulfilled", count: length(field(page, :items) || [])}
  end

  defp summarize_page(result), do: summarize(result)

  defp summarize_binary({:ok, binary}) when is_binary(binary) do
    %{
      result: "fulfilled",
      byte_length: byte_size(binary),
      first_line: binary |> String.split(~r/\r?\n/, parts: 2) |> hd()
    }
  end

  defp summarize_binary(result), do: summarize(result)

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

DodoPayments.E2E.FinanceElixir.run()
