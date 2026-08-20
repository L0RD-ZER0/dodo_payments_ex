defmodule DodoPayments.Response do
  @moduledoc """
  The optional response envelope returned with `return: :response`.

  Normal SDK calls return the decoded response body directly. The envelope is
  useful when request IDs, status codes, or headers are needed for diagnostics.
  """

  @enforce_keys [:data, :status, :headers]
  defstruct [:data, :status, :headers, :request_id]

  @type t(data) :: %__MODULE__{
          data: data,
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          request_id: String.t() | nil
        }
  @type t :: t(term())
end

defimpl Inspect, for: DodoPayments.Response do
  import Inspect.Algebra

  def inspect(response, opts) do
    fields = [
      data: DodoPayments.Redaction.redact(response.data),
      status: response.status,
      headers: DodoPayments.Redaction.redact_headers(response.headers),
      request_id: response.request_id
    ]

    concat(["#DodoPayments.Response<", to_doc(fields, opts), ">"])
  end
end
