Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualCheckoutElixir do
  @moduledoc false

  @product_id "pdt_0Nlf5fSRt2eLjquLq5KIV"
  @customer_id "cus_0NlfOKxVjKiEIFLUhrFHI"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)

    params = %{
      product_cart: [%{product_id: @product_id, quantity: 1}],
      customer: %{customer_id: @customer_id},
      billing_currency: :usd
    }

    {:ok, preview} = DodoPayments.CheckoutSessions.preview(client, params)

    {:ok, created} =
      DodoPayments.CheckoutSessions.create(
        client,
        Map.merge(params, %{confirm: false, return_url: "http://127.0.0.1:4000/"})
      )

    session_id = field(created, :session_id)
    {:ok, retrieved} = DodoPayments.CheckoutSessions.retrieve(client, session_id)
    {:ok, observed_mcp} = DodoPayments.CheckoutSessions.retrieve(client, mcp["session_id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      session_id: session_id,
      product_id: @product_id,
      create: %{
        checkout_url_present: present?(field(created, :checkout_url)),
        client_secret_present: present?(field(created, :client_secret)),
        publishable_key_present: present?(field(created, :publishable_key))
      },
      preview: compact_preview(preview),
      retrieve: compact_status(retrieved),
      observed_mcp: compact_status(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_checkout_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_checkout_elixir_report=#{path}")
  end

  defp compact_preview(preview) do
    breakup = field(preview, :current_breakup) || %{}

    %{
      total_price: field(preview, :total_price),
      total_tax: field(preview, :total_tax),
      currency: field(preview, :currency),
      billing_country: field(preview, :billing_country),
      product_cart_count: length(field(preview, :product_cart) || []),
      current_subtotal: field(breakup, :subtotal),
      current_discount: field(breakup, :discount)
    }
  end

  defp compact_status(status) do
    %{
      id: field(status, :id),
      payment_id: field(status, :payment_id),
      payment_status: field(status, :payment_status),
      customer_name: field(status, :customer_name),
      customer_email: field(status, :customer_email),
      created_at_present: present?(field(status, :created_at))
    }
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_checkout_lifecycle.json"])
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

DodoPayments.E2E.DualCheckoutElixir.run()
