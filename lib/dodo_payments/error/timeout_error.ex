defmodule DodoPayments.Error.TimeoutError do
  @moduledoc "The logical deadline for an SDK call was exhausted."

  defexception [:operation, :timeout, message: "Dodo Payments request deadline exceeded"]
end
