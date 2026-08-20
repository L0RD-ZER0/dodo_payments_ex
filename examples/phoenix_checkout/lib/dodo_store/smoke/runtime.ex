defmodule DodoStore.Smoke.Runtime do
  @moduledoc """
  Starts the example with production-shaped local resources for a smoke run.

  Mix tasks load application configuration before they run, but they must not
  start `:dodo_store` until this module has replaced the development database,
  endpoint, and worker settings. This keeps `mix dodo.smoke` isolated from the
  ordinary example database and avoids Ecto SQL Sandbox entirely.
  """

  alias DodoStore.Smoke.PreflightError

  @type t :: %__MODULE__{
          run_id: String.t(),
          database: String.t(),
          endpoint_url: String.t(),
          webhook_secret: String.t(),
          application_started?: boolean()
        }

  @enforce_keys [:run_id, :database, :endpoint_url, :webhook_secret, :application_started?]
  defstruct @enforce_keys

  @spec start(map()) :: {:ok, t()} | {:error, Exception.t()}
  def start(options) when is_map(options) do
    if started?(:dodo_store) do
      existing_runtime(options)
    else
      configure_and_start(options)
    end
  end

  defp configure_and_start(options) do
    with :ok <- refuse_live_profile(options),
         {:ok, port} <- available_port() do
      run_id = options.resume || fresh_run_id(options)
      database = smoke_database(run_id)
      webhook_secret = smoke_webhook_secret(run_id)

      File.mkdir_p!(Path.dirname(database))
      configure_repo(database)
      configure_endpoint(port)
      configure_workers(options)
      Application.put_env(:dodo_store, :smoke_migrator, enabled: true)
      Application.put_env(:dodo_store, :webhook_secrets, [webhook_secret])

      case Application.ensure_all_started(:dodo_store) do
        {:ok, _applications} ->
          {:ok,
           %__MODULE__{
             run_id: run_id,
             database: database,
             endpoint_url: "http://127.0.0.1:#{port}",
             webhook_secret: webhook_secret,
             application_started?: true
           }}

        {:error, {_application, reason}} ->
          {:error,
           RuntimeError.exception("could not start smoke application: #{inspect(reason)}")}
      end
    end
  end

  defp existing_runtime(options) do
    endpoint = Application.fetch_env!(:dodo_store, DodoStoreWeb.Endpoint)
    repo = Application.fetch_env!(:dodo_store, DodoStore.Repo)
    secrets = Application.get_env(:dodo_store, :webhook_secrets, [])

    with [secret | _] <- secrets,
         {:ok, port} <- endpoint_port(endpoint) do
      {:ok,
       %__MODULE__{
         run_id: options.resume || fresh_run_id(options),
         database: Keyword.get(repo, :database, "already-started"),
         endpoint_url: "http://127.0.0.1:#{port}",
         webhook_secret: secret,
         application_started?: false
       }}
    else
      [] ->
        {:error,
         PreflightError.exception(
           reason: :missing_webhook_secret,
           message: "the running application has no webhook signing secret"
         )}

      {:error, error} ->
        {:error, error}
    end
  end

  defp refuse_live_profile(%{profile: profile})
       when profile in [:sandbox_api, :sandbox_checkout] do
    case System.get_env("DODO_PAYMENTS_ENVIRONMENT", "test") do
      environment when environment in ["test", "test_mode"] ->
        :ok

      _environment ->
        {:error,
         PreflightError.exception(
           reason: :live_environment,
           message: "credentialed smoke profiles require Dodo test mode"
         )}
    end
  end

  defp refuse_live_profile(_options), do: :ok

  defp configure_repo(database) do
    current = Application.get_env(:dodo_store, DodoStore.Repo, [])

    config =
      current
      |> Keyword.delete(:pool)
      |> Keyword.put(:database, database)
      # A single SQLite connection avoids WAL/bootstrap lock races while the
      # smoke runner still exercises bounded process and HTTP concurrency.
      |> Keyword.put(:pool_size, 1)
      |> Keyword.put(:busy_timeout, 10_000)

    Application.put_env(:dodo_store, DodoStore.Repo, config)
  end

  defp configure_endpoint(port) do
    current = Application.get_env(:dodo_store, DodoStoreWeb.Endpoint, [])

    config =
      current
      |> Keyword.put(:server, true)
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: port)
      |> Keyword.put(:url, scheme: "http", host: "127.0.0.1", port: port)

    Application.put_env(:dodo_store, DodoStoreWeb.Endpoint, config)
  end

  defp configure_workers(%{profile: :local}) do
    local_dodo = DodoStore.Smoke.LocalDodo

    Application.put_env(:dodo_store, :inbox_processor, enabled: true, interval: 25)
    Application.put_env(:dodo_store, :smoke_local_dodo, enabled: true, name: local_dodo)

    Application.put_env(:dodo_store, :outbox_processor,
      enabled: true,
      interval: 25,
      batch_size: 20,
      client: DodoStore.Smoke.LocalDodo.client_from_name(local_dodo)
    )
  end

  defp configure_workers(_options) do
    Application.put_env(:dodo_store, :smoke_local_dodo, enabled: false)
    Application.put_env(:dodo_store, :inbox_processor, enabled: true, interval: 100)

    Application.put_env(:dodo_store, :outbox_processor,
      enabled: true,
      interval: 100,
      batch_size: 20
    )
  end

  defp available_port do
    case :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        {:ok, {_address, port}} = :inet.sockname(socket)
        :ok = :gen_tcp.close(socket)
        {:ok, port}

      {:error, reason} ->
        {:error,
         RuntimeError.exception("could not reserve a local smoke port: #{inspect(reason)}")}
    end
  end

  defp endpoint_port(config) do
    case config |> Keyword.get(:http, []) |> Keyword.get(:port) do
      port when is_integer(port) and port > 0 -> {:ok, port}
      _value -> {:error, RuntimeError.exception("the running endpoint has no usable HTTP port")}
    end
  end

  defp fresh_run_id(options) do
    seed = Map.get(options, :seed) || System.unique_integer([:positive, :monotonic])
    "smoke-#{seed}-#{System.system_time(:millisecond)}"
  end

  defp smoke_database(run_id) do
    safe = String.replace(run_id, ~r/[^A-Za-z0-9_.-]/, "-")
    Path.expand("../../../tmp/smoke/#{safe}.db", __DIR__)
  end

  defp smoke_webhook_secret(run_id) do
    encoded = run_id |> then(&:crypto.hash(:sha256, &1)) |> Base.encode64()
    "whsec_" <> encoded
  end

  defp started?(application) do
    Enum.any?(Application.started_applications(), fn {name, _description, _version} ->
      name == application
    end)
  end
end
