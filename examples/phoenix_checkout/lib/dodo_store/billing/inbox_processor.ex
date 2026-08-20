defmodule DodoStore.Billing.InboxProcessor do
  @moduledoc "Supervised poller for the durable webhook inbox."

  use GenServer

  alias DodoStore.{Billing, Patterns}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec run_once() :: :ok
  def run_once do
    process_due(20)
    :ok
  end

  defp process_due(0), do: :ok

  defp process_due(remaining) do
    case Billing.claim_next_webhook() do
      {:ok, event} ->
        result =
          try do
            Patterns.handle_verified_event(event)
          rescue
            error -> {:error, error}
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        case result do
          :ok -> Billing.mark_webhook_processed(event)
          {:error, error} -> Billing.mark_webhook_failed(event, error)
        end

        process_due(remaining - 1)

      :none ->
        :ok
    end
  end

  @impl true
  def init(opts) do
    state = %{interval: Keyword.fetch!(opts, :interval)}
    schedule(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:process, state) do
    run_once()
    schedule(state.interval)
    {:noreply, state}
  end

  defp schedule(interval), do: Process.send_after(self(), :process, interval)
end
