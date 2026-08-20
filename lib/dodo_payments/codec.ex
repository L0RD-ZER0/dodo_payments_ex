defmodule DodoPayments.Codec do
  @moduledoc false

  @doc "Converts Elixir request values into JSON-ready values without inventing atoms."
  def encode(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  def encode(%Date{} = date), do: Date.to_iso8601(date)
  def encode(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def encode(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)

  def encode(value) when is_atom(value) and value not in [nil, true, false] do
    case DodoPayments.Enums.dump_unambiguous_atom(value) do
      {:ok, wire} -> wire
      :error -> value
    end
  end

  def encode(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:extra)
    |> encode()
  end

  def encode(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key_name!(key), encode(value)} end)
  end

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  def encode(value), do: value

  @doc "Decodes JSON and optionally casts the top-level object into a schema struct."
  def decode(body, schema \\ nil)
  def decode("", nil), do: {:ok, nil}
  def decode("", schema) when is_atom(schema), do: {:error, :empty_typed_response}
  def decode(body, nil) when is_binary(body), do: Jason.decode(body)

  def decode(body, schema) when is_binary(body) and is_atom(schema) do
    case Jason.decode(body) do
      {:ok, decoded} -> DodoPayments.Schema.cast_object(schema, decoded)
      {:error, _reason} = error -> error
    end
  end

  @doc false
  @spec key_name(term()) :: {:ok, String.t()} | :error
  def key_name(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  def key_name(key) when is_binary(key), do: {:ok, key}
  def key_name(key) when is_integer(key), do: {:ok, Integer.to_string(key)}
  def key_name(key) when is_float(key), do: {:ok, Float.to_string(key)}
  def key_name(_key), do: :error

  defp key_name!(key) do
    case key_name(key) do
      {:ok, name} -> name
      :error -> raise ArgumentError, "JSON object keys must be strings, atoms, or numbers"
    end
  end
end
