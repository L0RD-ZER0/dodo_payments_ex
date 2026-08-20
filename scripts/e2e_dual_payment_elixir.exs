Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualPaymentElixir do
  @moduledoc false

  @product_id "pdt_0Nlf5fSRt2eLjquLq5KIV"
  @customer_id "cus_0NlfOKxVjKiEIFLUhrFHI"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.Payments.create(client, %{
        billing: %{
          city: "San Francisco",
          country: :us,
          state: "CA",
          street: "1 Market Street",
          zipcode: "94105"
        },
        customer: %{customer_id: @customer_id},
        product_cart: [%{product_id: @product_id, quantity: 1}],
        billing_currency: :usd,
        metadata: %{workflow: "dual_driver", marker: marker},
        payment_link: false,
        return_url: "http://127.0.0.1:4000/"
      })

    payment_id = field(created, :payment_id)
    {:ok, retrieved} = DodoPayments.Payments.retrieve(client, payment_id)

    {:ok, payments} =
      DodoPayments.Payments.list(client, %{customer_id: @customer_id, page_size: 100})

    {:ok, line_items} = DodoPayments.Payments.list_line_items(client, payment_id)
    {:ok, observed_mcp} = DodoPayments.Payments.retrieve(client, mcp["payment_id"])
    {:ok, observed_mcp_items} = DodoPayments.Payments.list_line_items(client, mcp["payment_id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      payment_id: payment_id,
      create: %{
        client_secret_present: present?(field(created, :client_secret)),
        total_amount: field(created, :total_amount),
        payment_link_present: present?(field(created, :payment_link))
      },
      retrieve: compact_payment(retrieved),
      listed: includes?(payments, payment_id),
      line_items: compact_items(line_items),
      observed_mcp: compact_payment(observed_mcp),
      observed_mcp_line_items: compact_items(observed_mcp_items),
      completion_blocker:
        "raw confirm requires a publishable API key not present in project credentials or payment create response"
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_payment_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_payment_elixir_report=#{path}")
  end

  defp compact_payment(payment) do
    %{
      payment_id: field(payment, :payment_id),
      status: field(payment, :status),
      total_amount: field(payment, :total_amount),
      currency: field(payment, :currency),
      product_count: length(field(payment, :product_cart) || [])
    }
  end

  defp compact_items(value) do
    items = field(value, :items) || []

    %{
      count: length(items),
      item_ids: Enum.map(items, &field(&1, :items_id))
    }
  end

  defp includes?(page, payment_id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :payment_id) == payment_id))
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_payment_lifecycle.json"])
    |> File.read!()
    |> Jason.decode!()
  end

  defp present?(value), do: is_binary(value) and value != ""
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

DodoPayments.E2E.DualPaymentElixir.run()
