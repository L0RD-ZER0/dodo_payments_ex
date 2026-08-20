defmodule DodoStore.Dodo do
  @moduledoc "Application-owned access to the explicitly configured Dodo client."

  @spec client() :: DodoPayments.Client.t()
  def client do
    :dodo_store
    |> Application.fetch_env!(:dodo_payments)
    |> DodoPayments.client!()
  end

  @spec mode() :: :test | :live
  def mode do
    case Application.fetch_env!(:dodo_store, :dodo_payments)[:environment] do
      value when value in [:live, :live_mode, "live", "live_mode"] -> :live
      _value -> :test
    end
  end

  @spec webhook_secrets() :: [String.t()]
  def webhook_secrets do
    Application.get_env(:dodo_store, :webhook_secrets, [])
  end
end
