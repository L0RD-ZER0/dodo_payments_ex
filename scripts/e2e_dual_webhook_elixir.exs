Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualWebhookElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.WebhookEndpoints.create(client, %{
        url: "https://example.com/dodo-e2e-elixir/#{marker}",
        description: "Elixir dual webhook #{marker}",
        disabled: true,
        headers: %{"x-dodo-e2e" => "initial"},
        metadata: %{"workflow" => "dual_driver", "marker" => marker}
      })

    id = field(created, :id)
    {:ok, initial} = DodoPayments.WebhookEndpoints.retrieve(client, id)
    {:ok, secret} = DodoPayments.WebhookEndpoints.retrieve_secret(client, id)
    {:ok, headers_initial} = DodoPayments.WebhookEndpoints.Headers.retrieve(client, id)

    {:ok, _} =
      DodoPayments.WebhookEndpoints.Headers.update(client, id, %{
        headers: %{"x-dodo-e2e" => "updated", "x-workflow" => "dual_driver"}
      })

    {:ok, headers_updated} = DodoPayments.WebhookEndpoints.Headers.retrieve(client, id)

    {:ok, updated} =
      DodoPayments.WebhookEndpoints.update(client, id, %{
        description: "Elixir dual webhook #{marker} Updated",
        disabled: true,
        rate_limit: 9
      })

    {:ok, listed} = DodoPayments.WebhookEndpoints.list(client, %{limit: 100})

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: id,
      initial: compact(initial),
      secret_present: secret_present?(secret),
      initial_header_keys: header_keys(headers_initial),
      updated_header_keys: header_keys(headers_updated),
      updated: compact(updated),
      listed: includes?(listed, id),
      cleanup_pending: "official SDK must observe and delete this disabled endpoint"
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_webhook_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_webhook_elixir_report=#{path}")
  end

  defp compact(webhook) do
    %{
      id: field(webhook, :id),
      url: field(webhook, :url),
      description: field(webhook, :description),
      disabled: field(webhook, :disabled),
      rate_limit: field(webhook, :rate_limit)
    }
  end

  defp secret_present?(secret) do
    value = field(secret, :secret)
    is_binary(value) and value != ""
  end

  defp header_keys(headers) do
    headers
    |> field(:headers)
    |> Kernel.||(%{})
    |> Map.keys()
    |> Enum.sort()
  end

  defp includes?(page, id), do: Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))

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

DodoPayments.E2E.DualWebhookElixir.run()
