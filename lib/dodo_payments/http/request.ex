defmodule DodoPayments.HTTP.Request do
  @moduledoc """
  Transport-neutral request passed to `c:DodoPayments.ClientModule.request/2`.

  It is fully prepared by the SDK. A client module must treat its method, URL,
  headers, body, timeout, response mode, and body limit as authoritative and must
  perform at most one network attempt.
  """

  @enforce_keys [:method, :url]
  defstruct method: nil,
            url: nil,
            headers: [],
            body: nil,
            timeout: 30_000,
            max_body_bytes: 10 * 1024 * 1024,
            response_mode: :raw

  @type t :: %__MODULE__{
          method: atom(),
          url: URI.t() | String.t(),
          headers: [{String.t(), String.t()}],
          body: iodata() | nil,
          timeout: pos_integer(),
          max_body_bytes: pos_integer() | :infinity,
          response_mode: :raw
        }
end

defimpl Inspect, for: DodoPayments.HTTP.Request do
  import Inspect.Algebra

  def inspect(request, opts) do
    headers = DodoPayments.Redaction.redact_headers(request.headers)

    url = URI.parse(to_string(request.url))
    safe_url = %{url | query: if(url.query, do: "[REDACTED]")}
    body_bytes = body_size(request.body)

    values = [
      method: request.method,
      url: URI.to_string(safe_url),
      headers: headers,
      body_bytes: body_bytes,
      timeout: request.timeout
    ]

    concat(["#DodoPayments.HTTP.Request<", to_doc(values, opts), ">"])
  end

  defp body_size(nil), do: 0

  defp body_size(body) do
    IO.iodata_length(body)
  rescue
    _ -> :unknown
  end
end
