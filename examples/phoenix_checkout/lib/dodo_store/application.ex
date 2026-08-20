defmodule DodoStore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DodoStore.Repo,
        smoke_migrator_child(),
        {Phoenix.PubSub, name: DodoStore.PubSub},
        inbox_processor_child(),
        smoke_local_dodo_child(),
        outbox_processor_child(),
        DodoStoreWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: DodoStore.Supervisor)
  end

  defp smoke_migrator_child do
    config = Application.get_env(:dodo_store, :smoke_migrator, [])

    if Keyword.get(config, :enabled, false) do
      {DodoStore.Smoke.Migrator, []}
    end
  end

  defp inbox_processor_child do
    config = Application.get_env(:dodo_store, :inbox_processor, [])

    if Keyword.get(config, :enabled, true) do
      {DodoStore.Billing.InboxProcessor, interval: Keyword.get(config, :interval, 1_000)}
    end
  end

  defp smoke_local_dodo_child do
    config = Application.get_env(:dodo_store, :smoke_local_dodo, [])

    if Keyword.get(config, :enabled, false) do
      {DodoStore.Smoke.LocalDodo, name: Keyword.get(config, :name, DodoStore.Smoke.LocalDodo)}
    end
  end

  defp outbox_processor_child do
    config = Application.get_env(:dodo_store, :outbox_processor, [])

    if Keyword.get(config, :enabled, true) do
      opts = [
        interval: Keyword.get(config, :interval, 1_000),
        batch_size: Keyword.get(config, :batch_size, 20)
      ]

      opts =
        case Keyword.fetch(config, :client) do
          {:ok, client} -> Keyword.put(opts, :client, client)
          :error -> opts
        end

      {DodoStore.Billing.OutboxProcessor, opts}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    DodoStoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
