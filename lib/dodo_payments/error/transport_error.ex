defmodule DodoPayments.Error.TransportError do
  @moduledoc "A network or HTTP-adapter failure with no successful response."

  defexception [:reason, :operation, :attempts, message: "Dodo Payments transport failed"]

  @impl true
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    operation = Keyword.get(opts, :operation)
    attempts = Keyword.get(opts, :attempts, 1)

    %__MODULE__{
      reason: reason,
      operation: operation,
      attempts: attempts,
      message: "Dodo Payments request failed after #{attempts} attempt(s)"
    }
  end
end

defimpl Inspect, for: DodoPayments.Error.TransportError do
  import Inspect.Algebra

  def inspect(error, opts),
    do:
      concat([
        "#DodoPayments.Error.TransportError<",
        to_doc([operation: error.operation, attempts: error.attempts, reason: :redacted], opts),
        ">"
      ])
end
