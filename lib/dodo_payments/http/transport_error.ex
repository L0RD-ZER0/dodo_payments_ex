defmodule DodoPayments.HTTP.TransportError do
  @moduledoc """
  A transport-neutral failure returned by a `DodoPayments.ClientModule`.

  `:not_sent` must only be used when the adapter can positively establish that no
  part of the request reached the remote service. All uncertain failures use
  `:unknown`.
  """

  @enforce_keys [:reason, :delivery]
  defstruct [:reason, :partial_response, delivery: :unknown]

  @type delivery :: :not_sent | :unknown
  @type t :: %__MODULE__{
          reason: term(),
          delivery: delivery(),
          partial_response: nil | %{optional(:status) => integer(), optional(:headers) => list()}
        }
end

defimpl Inspect, for: DodoPayments.HTTP.TransportError do
  import Inspect.Algebra

  def inspect(error, opts) do
    fields = [
      delivery: error.delivery,
      status: partial_status(error.partial_response),
      reason: :redacted,
      headers: :redacted
    ]

    concat(["#DodoPayments.HTTP.TransportError<", to_doc(fields, opts), ">"])
  end

  defp partial_status(%{status: status}) when is_integer(status), do: status
  defp partial_status(_), do: nil
end
