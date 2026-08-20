defmodule DodoPayments.Error do
  @moduledoc """
  Safe, bounded diagnostics for errors returned by the SDK.

  SDK exceptions intentionally retain structured response and adapter details
  for programmatic reconciliation. Do not serialize exception structs directly.
  Use `safe_summary/1` for logs, metrics, or user-support correlation data that
  must exclude bodies, headers, URLs, credentials, causes, and stacktraces.
  """

  @doc "Returns a bounded map that is safe to serialize as operational metadata."
  @spec safe_summary(Exception.t()) :: map()
  def safe_summary(%DodoPayments.Error.APIError{} = error) do
    compact(%{
      category: :api_error,
      status: error.status,
      code: safe_fragment(error.code),
      request_id: safe_fragment(error.request_id)
    })
  end

  def safe_summary(%DodoPayments.Error.OutcomeUnknown{} = error) do
    compact(%{
      category: :outcome_unknown,
      operation: error.operation,
      status: error.status,
      request_id: safe_fragment(error.request_id),
      attempts: error.attempts,
      replay: error.replay
    })
  end

  def safe_summary(%DodoPayments.Error.TransportError{} = error) do
    compact(%{
      category: :transport_error,
      operation: error.operation,
      attempts: error.attempts
    })
  end

  def safe_summary(%DodoPayments.Error.TimeoutError{} = error) do
    compact(%{
      category: :timeout_error,
      operation: error.operation,
      timeout: error.timeout
    })
  end

  def safe_summary(%DodoPayments.Error.DecodeError{} = error) do
    compact(%{
      category: :decode_error,
      status: error.status,
      request_id: safe_fragment(error.request_id)
    })
  end

  def safe_summary(%DodoPayments.Error.ResponseTooLarge{} = error) do
    compact(%{
      category: :response_too_large,
      operation: error.operation,
      status: error.status,
      limit: error.limit
    })
  end

  def safe_summary(%DodoPayments.Error.PreparationError{} = error) do
    compact(%{category: :preparation_error, operation: error.operation, kind: error.kind})
  end

  def safe_summary(%DodoPayments.Error.ConfigurationError{}),
    do: %{category: :configuration_error}

  def safe_summary(%DodoPayments.ValidationError{} = error) do
    compact(%{
      category: :validation_error,
      operation: error.operation,
      field: safe_field(error.field)
    })
  end

  def safe_summary(%DodoPayments.Page.TraversalError{}),
    do: %{category: :pagination_error}

  def safe_summary(%DodoPayments.Webhooks.VerificationError{} = error) do
    compact(%{
      category: :webhook_verification_error,
      reason: safe_reason(error.reason),
      header: safe_header(error.header)
    })
  end

  def safe_summary(%module{}) when is_atom(module),
    do: %{category: :unknown_error, exception: module}

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp safe_fragment(nil), do: nil

  defp safe_fragment(value) when is_binary(value) do
    prefix = binary_part(value, 0, min(byte_size(value), 128))

    if String.printable?(prefix), do: prefix, else: :redacted
  end

  defp safe_fragment(_value), do: :redacted

  defp safe_field(value) when is_atom(value), do: value
  defp safe_field(value) when is_binary(value), do: safe_fragment(value)
  defp safe_field(_value), do: :redacted

  defp safe_reason(value) when is_atom(value), do: value
  defp safe_reason({value, _detail}) when is_atom(value), do: value
  defp safe_reason(_value), do: :redacted

  defp safe_header(value) when value in ["webhook-id", "webhook-signature", "webhook-timestamp"],
    do: value

  defp safe_header(nil), do: nil
  defp safe_header(_value), do: :redacted
end
