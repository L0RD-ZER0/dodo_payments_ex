defmodule DodoPayments.Error.PreparationError do
  @moduledoc "Returned when request preparation crashes before an HTTP attempt is made."

  defexception [:operation, :kind, :cause, stacktrace: []]

  @type t :: %__MODULE__{
          operation: atom(),
          kind: :error | :exit | :throw,
          cause: term(),
          stacktrace: Exception.stacktrace()
        }

  @impl Exception
  def message(%__MODULE__{operation: operation, kind: kind, cause: cause}) do
    "request preparation failed for #{operation} (#{kind}: #{cause_name(cause)})"
  end

  defp cause_name(%module{}), do: inspect(module)
  defp cause_name(_cause), do: "redacted cause"
end

defimpl Inspect, for: DodoPayments.Error.PreparationError do
  import Inspect.Algebra

  def inspect(error, opts) do
    cause = if is_struct(error.cause), do: error.cause.__struct__, else: :redacted

    values = [operation: error.operation, kind: error.kind, cause: cause]
    concat(["#DodoPayments.Error.PreparationError<", to_doc(values, opts), ">"])
  end
end
