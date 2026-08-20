defmodule DodoPayments.Redaction do
  @moduledoc false

  @credential_headers ~w(
    api-key
    authorization
    cookie
    proxy-authorization
    x-api-key
    x-auth-token
    x-amz-security-token
    x-amz-date
    x-amz-content-sha256
    x-amz-credential
    x-amz-signature
    x-amz-signedheaders
  )
  @sensitive_headers MapSet.new(["set-cookie" | @credential_headers])

  @sensitive_fields MapSet.new([
                      "api_key",
                      "access_token",
                      "authorization",
                      "card_number",
                      "checkout_url",
                      "client_secret",
                      "cookie",
                      "cvv",
                      "download_url",
                      "headers",
                      "invoice_url",
                      "key",
                      "license_key",
                      "oauth_url",
                      "password",
                      "payment_link",
                      "payout_document_url",
                      "refresh_token",
                      "secret",
                      "session_token",
                      "token",
                      "webhook_secret"
                    ])

  @spec sensitive_header?(term()) :: boolean()
  def sensitive_header?(name) do
    normalized = header_name(name)
    normalized in @sensitive_headers or String.starts_with?(normalized, "x-amz-")
  end

  @doc "Returns whether a header must never be retained on an SDK request."
  @spec credential_header?(term()) :: boolean()
  def credential_header?(name) do
    normalized = header_name(name)
    normalized in @credential_headers or String.starts_with?(normalized, "x-amz-")
  end

  @spec header_name(term()) :: String.t()
  def header_name(name) when is_binary(name),
    do: name |> String.downcase() |> String.replace("_", "-")

  def header_name(name) when is_atom(name),
    do: name |> Atom.to_string() |> header_name()

  def header_name(_name), do: ""

  @spec credential_headers() :: [String.t()]
  def credential_headers, do: @credential_headers

  @spec sensitive_field?(term()) :: boolean()
  def sensitive_field?(name) do
    normalized = normalized(name)
    normalized in @sensitive_fields or sensitive_header?(name)
  end

  @spec redact_headers(list()) :: list()
  def redact_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, _value} = header ->
        if sensitive_header?(name), do: {name, "[REDACTED]"}, else: header

      value ->
        value
    end)
  end

  @spec redact(term(), [String.t() | atom()]) :: term()
  def redact(value, additional_fields \\ []) do
    fields = MapSet.new(additional_fields, &normalized/1)
    do_redact(value, fields)
  end

  # SDK schema structs provide their own field-aware Inspect implementations.
  # Preserve structs so a surrounding page/response inspector delegates to
  # those implementations instead of flattening away their redaction policy.
  defp do_redact(%_{} = struct, _fields), do: struct

  defp do_redact(map, fields) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if sensitive_field?(key) or normalized(key) in fields,
        do: {key, :redacted},
        else: {key, do_redact(value, fields)}
    end)
  end

  defp do_redact(list, fields) when is_list(list),
    do: Enum.map(list, &do_redact(&1, fields))

  defp do_redact(value, _fields), do: value

  defp normalized(value) when is_binary(value), do: String.downcase(value)
  defp normalized(value) when is_atom(value), do: value |> Atom.to_string() |> String.downcase()
  defp normalized(_value), do: ""
end
