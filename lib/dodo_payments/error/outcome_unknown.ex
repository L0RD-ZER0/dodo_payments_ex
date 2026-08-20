defmodule DodoPayments.Error.OutcomeUnknown do
  @moduledoc """
  A mutation may have reached Dodo Payments without producing a conclusive
  response.

  `replay: :unsafe` means the application must reconcile before repeating the
  mutation. `replay: :identical_only` means another attempt is safe only when it
  preserves the operation's documented idempotency identity and identical
  request data.
  """

  defexception [
    :operation,
    :reason,
    :status,
    :request_id,
    :attempts,
    :reconciliation,
    :message,
    replay: :unsafe
  ]

  @type replay :: :unsafe | :identical_only

  @type t :: %__MODULE__{
          operation: atom(),
          reason: term(),
          status: integer() | nil,
          request_id: String.t() | nil,
          attempts: pos_integer() | nil,
          replay: replay(),
          reconciliation: String.t() | nil,
          message: String.t()
        }

  @impl true
  def exception(opts) do
    operation = Keyword.get(opts, :operation)
    reason = Keyword.get(opts, :reason)
    reconciliation = Keyword.get(opts, :reconciliation)
    replay = Keyword.get(opts, :replay, :unsafe)

    message =
      "The outcome of #{inspect(operation)} is unknown after #{Keyword.get(opts, :attempts, 1)} attempt(s); " <>
        replay_guidance(replay) <>
        reconciliation_suffix(reconciliation)

    %__MODULE__{
      operation: operation,
      reason: reason,
      status: Keyword.get(opts, :status),
      request_id: Keyword.get(opts, :request_id),
      attempts: Keyword.get(opts, :attempts),
      replay: replay,
      reconciliation: reconciliation,
      message: message
    }
  end

  defp replay_guidance(:identical_only),
    do: "retry only as an identical replay using the same stable idempotency values"

  defp replay_guidance(:unsafe), do: "do not repeat it before reconciliation"

  defp reconciliation_suffix(nil), do: "."

  defp reconciliation_suffix(text) do
    ". Guidance: #{String.trim_trailing(text, ".")}."
  end
end

defimpl Inspect, for: DodoPayments.Error.OutcomeUnknown do
  import Inspect.Algebra

  def inspect(error, opts) do
    fields = [
      operation: error.operation,
      status: error.status,
      request_id: error.request_id,
      attempts: error.attempts,
      replay: error.replay,
      reason: :redacted
    ]

    concat(["#DodoPayments.Error.OutcomeUnknown<", to_doc(fields, opts), ">"])
  end
end
