defmodule DodoPayments.Error.DecodeError do
  @moduledoc "A successful response could not be decoded according to its operation schema."

  defexception [
    :reason,
    :status,
    :request_id,
    :body,
    message: "Unable to decode Dodo Payments response"
  ]
end

defimpl Inspect, for: DodoPayments.Error.DecodeError do
  import Inspect.Algebra

  def inspect(error, opts),
    do:
      concat([
        "#DodoPayments.Error.DecodeError<",
        to_doc(
          [
            status: error.status,
            request_id: error.request_id,
            body: :redacted,
            reason: :redacted
          ],
          opts
        ),
        ">"
      ])
end
