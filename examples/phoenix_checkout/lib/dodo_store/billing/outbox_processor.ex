defmodule DodoStore.Billing.OutboxProcessor do
  @moduledoc "Supervised poller for the durable billing outbox."

  use GenServer

  alias DodoStore.Billing
  alias DodoStore.Billing.OutboxDispatcher

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Claims and dispatches one bounded batch. Concurrent pollers remain safe."
  @spec run_once(keyword()) :: :ok
  def run_once(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 20)
    client = opts |> Keyword.get(:client, &DodoStore.Dodo.client/0) |> resolve_client()
    dispatcher = Keyword.get(opts, :dispatcher, &OutboxDispatcher.dispatch/2)

    Billing.pending_commands()
    |> Enum.take(batch_size)
    |> Enum.each(&safe_dispatch(&1, client, dispatcher))

    :ok
  end

  @impl true
  def init(opts) do
    state = %{
      interval: Keyword.fetch!(opts, :interval),
      batch_size: Keyword.get(opts, :batch_size, 20),
      client: Keyword.get(opts, :client),
      dispatcher: Keyword.get(opts, :dispatcher)
    }

    schedule(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:process, state) do
    opts = [batch_size: state.batch_size]
    opts = if state.client, do: Keyword.put(opts, :client, state.client), else: opts
    opts = if state.dispatcher, do: Keyword.put(opts, :dispatcher, state.dispatcher), else: opts
    run_once(opts)
    schedule(state.interval)
    {:noreply, state}
  end

  defp safe_dispatch(command, client, dispatcher) do
    dispatcher.(command, client)
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp resolve_client(provider) when is_function(provider, 0), do: provider.()
  defp resolve_client(client), do: client

  defp schedule(interval), do: Process.send_after(self(), :process, interval)
end
