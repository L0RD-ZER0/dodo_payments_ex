defmodule DodoPayments.Error.ConfigurationError do
  @moduledoc "Raised or returned when a client cannot be configured safely."
  defexception [:message, :cause, stacktrace: []]

  @type t :: %__MODULE__{
          message: String.t(),
          cause: term() | nil,
          stacktrace: Exception.stacktrace()
        }
end

defimpl Inspect, for: DodoPayments.Error.ConfigurationError do
  import Inspect.Algebra

  def inspect(error, opts) do
    cause = if is_struct(error.cause), do: error.cause.__struct__, else: nil
    values = [message: error.message, cause: cause]
    concat(["#DodoPayments.Error.ConfigurationError<", to_doc(values, opts), ">"])
  end
end
