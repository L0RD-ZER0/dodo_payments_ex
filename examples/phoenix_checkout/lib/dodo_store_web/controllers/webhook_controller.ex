defmodule DodoStoreWeb.WebhookController do
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias DodoStore.{Billing, Dodo}

  def create(conn, _params) do
    raw_body = conn.private[:raw_body] || ""

    case Dodo.webhook_secrets() do
      [] ->
        send_resp(conn, :service_unavailable, "webhook secret is not configured")

      secrets ->
        verify_and_store(conn, raw_body, secrets)
    end
  end

  defp verify_and_store(conn, raw_body, secrets) do
    case DodoPayments.Webhooks.verify(raw_body, conn.req_headers, secrets) do
      {:ok, event} ->
        case Billing.accept_webhook(event) do
          {:ok, _disposition} -> send_resp(conn, :ok, "accepted")
          {:error, _changeset} -> send_resp(conn, :service_unavailable, "not persisted")
        end

      {:error, %DodoPayments.Webhooks.VerificationError{}} ->
        send_resp(conn, :bad_request, "invalid webhook")
    end
  end
end
