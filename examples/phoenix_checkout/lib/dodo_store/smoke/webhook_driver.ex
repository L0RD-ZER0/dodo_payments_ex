defmodule DodoStore.Smoke.WebhookDriver do
  @moduledoc """
  Produces synthetic but cryptographically valid Standard Webhooks requests.

  The driver only POSTs to an explicit loopback HTTP endpoint. A valid local
  signature proves raw-body handling and verification logic; it does not prove
  that Dodo originated or delivered the event.
  """

  @type request :: %{
          body: binary(),
          headers: [{binary(), binary()}],
          webhook_id: binary(),
          event_type: binary(),
          provenance: :synthetic_valid_signature
        }

  @spec request(map(), String.t(), keyword()) :: {:ok, request()} | {:error, map()}
  def request(%{webhook_id: webhook_id, payload: payload, type: type}, webhook_secret, opts \\ []) do
    timestamp = Keyword.get_lazy(opts, :timestamp, fn -> System.system_time(:second) end)

    with true <- is_integer(timestamp) or {:error, safe_error(:invalid_timestamp)},
         {:ok, signing_key} <- decode_secret(webhook_secret) do
      body = Jason.encode!(payload)
      timestamp = Integer.to_string(timestamp)
      signed = webhook_id <> "." <> timestamp <> "." <> body
      signature = :crypto.mac(:hmac, :sha256, signing_key, signed)

      {:ok,
       %{
         body: body,
         headers: [
           {"content-type", "application/json"},
           {"webhook-id", webhook_id},
           {"webhook-timestamp", timestamp},
           {"webhook-signature", "v1," <> Base.encode64(signature)}
         ],
         webhook_id: webhook_id,
         event_type: type,
         provenance: :synthetic_valid_signature
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  @spec deliver(request(), String.t(), keyword()) ::
          {:ok, %{status: pos_integer(), webhook_id: String.t()}} | {:error, map()}
  def deliver(request, base_url, opts \\ []) do
    with :ok <- loopback_only(base_url),
         url = String.trim_trailing(base_url, "/") <> "/webhooks/dodo",
         {:ok, response} <-
           Req.post(url,
             body: request.body,
             headers: request.headers,
             retry: false,
             redirect: false,
             receive_timeout: Keyword.get(opts, :timeout, 5_000)
           ),
         true <- response.status in 200..299 or {:error, safe_error(:webhook_not_acknowledged)} do
      {:ok, %{status: response.status, webhook_id: request.webhook_id}}
    else
      {:error, %{} = error} -> {:error, error}
      {:error, _transport} -> {:error, safe_error(:loopback_transport_failed)}
    end
  rescue
    _exception -> {:error, safe_error(:loopback_transport_failed)}
  end

  defp decode_secret("whsec_" <> encoded) do
    case Base.decode64(encoded) do
      {:ok, key} when byte_size(key) > 0 -> {:ok, key}
      _error -> {:error, safe_error(:invalid_webhook_secret)}
    end
  end

  defp decode_secret(_secret), do: {:error, safe_error(:invalid_webhook_secret)}

  defp loopback_only(base_url) when is_binary(base_url) do
    uri = URI.parse(base_url)

    if uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"] and
         is_integer(uri.port) do
      :ok
    else
      {:error, safe_error(:non_loopback_endpoint)}
    end
  end

  defp loopback_only(_base_url), do: {:error, safe_error(:non_loopback_endpoint)}

  defp safe_error(reason), do: %{category: :local_smoke, reason: reason}
end
