defmodule DodoPayments.ValidationError do
  @moduledoc "Raised when a request is locally invalid and no HTTP call was made."
  defexception [:operation, :field, :reason]

  @type t :: %__MODULE__{operation: atom(), field: atom() | String.t() | nil, reason: term()}

  @impl true
  def message(%__MODULE__{operation: operation, field: field, reason: reason}) do
    field = if field, do: " field #{inspect(field)}", else: " input"
    "invalid#{field} for #{operation}: #{format_reason(reason)}"
  end

  defp format_reason(:required), do: "is required"
  defp format_reason(:invalid_path_value), do: "must be a string or integer"
  defp format_reason(:not_a_map), do: "must be a map"
  defp format_reason(:duplicate_atom_and_string_key), do: "contains ambiguous atom/string keys"
  defp format_reason(:duplicate_json_key), do: "collides with another key after JSON encoding"
  defp format_reason(:unsupported_json_key), do: "contains a key that cannot be encoded as JSON"
  defp format_reason({:json_encoding_failed, _reason}), do: "could not be encoded as JSON"
  defp format_reason({:invalid_query, _reason}), do: "contains an invalid query value"

  defp format_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_reason(_reason), do: "is invalid"
end

defimpl Inspect, for: DodoPayments.ValidationError do
  import Inspect.Algebra

  def inspect(error, opts) do
    values = [
      operation: error.operation,
      field: error.field,
      reason: reason_category(error.reason)
    ]

    concat(["#DodoPayments.ValidationError<", to_doc(values, opts), ">"])
  end

  defp reason_category({category, _reason}) when is_atom(category), do: category
  defp reason_category(reason) when is_atom(reason), do: reason
  defp reason_category(_reason), do: :redacted
end
