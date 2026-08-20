defmodule DodoPayments.Webhooks.VerificationError do
  @moduledoc "An error produced while authenticating or decoding a Dodo webhook."

  defexception [:message, :reason, :header]

  @type reason ::
          :invalid_body
          | :missing_header
          | :ambiguous_header
          | :invalid_timestamp
          | :timestamp_outside_tolerance
          | :invalid_secret
          | :invalid_signature
          | :invalid_json
          | :invalid_event
          | :invalid_options
          | :resource_limit

  @type t :: %__MODULE__{message: String.t(), reason: reason(), header: String.t() | nil}

  @impl Exception
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    header = Keyword.get(opts, :header)
    message = Keyword.get(opts, :message, default_message(reason, header))
    %__MODULE__{message: message, reason: reason, header: header}
  end

  defp default_message(:invalid_body, _), do: "webhook body must be the exact raw request bytes"

  defp default_message(:missing_header, header),
    do: "missing required webhook header #{inspect(header)}"

  defp default_message(:ambiguous_header, header),
    do: "webhook header #{inspect(header)} was supplied more than once"

  defp default_message(:invalid_timestamp, _), do: "webhook timestamp is invalid"

  defp default_message(:timestamp_outside_tolerance, _),
    do: "webhook timestamp is outside the allowed tolerance"

  defp default_message(:invalid_secret, _), do: "webhook signing secret is invalid"
  defp default_message(:invalid_signature, _), do: "webhook signature is invalid"
  defp default_message(:invalid_json, _), do: "verified webhook body is not valid JSON"
  defp default_message(:invalid_event, _), do: "verified webhook body is not a valid event"
  defp default_message(:invalid_options, _), do: "webhook verification options are invalid"
  defp default_message(:resource_limit, _), do: "webhook input exceeds a configured safety limit"
end
