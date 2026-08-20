defmodule DodoPayments.Error.ResponseTooLarge do
  @moduledoc "The response exceeded the configured buffered-response limit."

  defexception [:operation, :limit, :status, :message]

  @impl true
  def exception(opts) do
    limit = Keyword.fetch!(opts, :limit)
    operation = Keyword.get(opts, :operation)
    status = Keyword.get(opts, :status)

    %__MODULE__{
      operation: operation,
      limit: limit,
      status: status,
      message: "Dodo Payments response exceeded the configured #{limit}-byte limit"
    }
  end
end
