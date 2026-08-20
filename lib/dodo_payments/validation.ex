defmodule DodoPayments.Validation do
  @moduledoc false

  @spec map(map() | nil, atom()) :: {:ok, map()} | {:error, DodoPayments.ValidationError.t()}
  def map(nil, _operation), do: {:ok, %{}}

  def map(value, operation) when is_map(value) do
    case key_issue(value) do
      nil ->
        {:ok, value}

      {reason, field} ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: field,
           reason: reason
         )}
    end
  end

  def map(_value, operation) do
    {:error, DodoPayments.ValidationError.exception(operation: operation, reason: :not_a_map)}
  end

  @spec required(map(), [atom()], atom()) :: :ok | {:error, DodoPayments.ValidationError.t()}
  def required(params, fields, operation) do
    case Enum.find(fields, &(fetch(params, &1) == :error)) do
      nil ->
        :ok

      field ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: field,
           reason: :required
         )}
    end
  end

  @spec fetch(map(), atom()) :: {:ok, term()} | :error
  def fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  # These structs are request-codec scalars, not JSON objects. Descending into
  # their implementation fields both misclassifies them and attempts to
  # enumerate structs that do not implement Enumerable.
  defp key_issue(%Decimal{}), do: nil
  defp key_issue(%Date{}), do: nil
  defp key_issue(%DateTime{}), do: nil
  defp key_issue(%NaiveDateTime{}), do: nil

  defp key_issue(%_{} = struct), do: struct |> Map.from_struct() |> key_issue()

  defp key_issue(map) when is_map(map) do
    direct_key_issue(map) || Enum.find_value(map, fn {_key, value} -> key_issue(value) end)
  end

  defp key_issue(list) when is_list(list), do: Enum.find_value(list, &key_issue/1)
  defp key_issue(_value), do: nil

  defp direct_key_issue(map) do
    map
    |> Enum.reduce_while(%{}, fn {key, _value}, seen ->
      case DodoPayments.Codec.key_name(key) do
        {:ok, name} -> detect_collision(seen, name, key)
        :error -> {:halt, {:issue, {:unsupported_json_key, nil}}}
      end
    end)
    |> case do
      {:issue, issue} -> issue
      _seen -> nil
    end
  end

  defp detect_collision(seen, name, key) do
    case Map.fetch(seen, name) do
      {:ok, previous} -> {:halt, {:issue, collision(previous, key, name)}}
      :error -> {:cont, Map.put(seen, name, key)}
    end
  end

  defp collision(first, second, name) do
    if atom_and_string?(first, second) do
      {:duplicate_atom_and_string_key, if(is_atom(first), do: first, else: second)}
    else
      {:duplicate_json_key, name}
    end
  end

  defp atom_and_string?(first, second),
    do: (is_atom(first) and is_binary(second)) or (is_binary(first) and is_atom(second))
end
