defmodule DodoPayments.Schema do
  @moduledoc """
  Minimal response schema support.

  Known fields become atom-keyed struct fields. Unknown fields are retained under
  `:extra`, allowing Dodo to add response data without waiting for an SDK release.
  Model declarations may attach field-specific types without changing decoding;
  nested response objects remain string-keyed maps for compatibility.

  `use DodoPayments.Schema` accepts legacy atom fields such as `fields: [:id]`
  and typed fields such as `fields: [id: String.t()]`. Both forms may be mixed;
  each field name must occur exactly once.
  Declared enum values decode to atoms; values introduced after this SDK release
  decode to `DodoPayments.UnknownEnum` without creating atoms dynamically. JSON
  numbers retain Jason's normal integer/float representation; response decoding
  does not synthesize `Decimal` values. Request-side `Decimal` values encode as exact decimal strings, while
  endpoints that specify integer minor units should receive integers.

  The configured response byte limit bounds wire input, not transient heap use:
  JSON parsing and schema construction necessarily allocate beyond the body size.
  """

  defmacro __using__(opts) do
    {fields, field_types, enum_fields} = normalize_fields!(Keyword.fetch!(opts, :fields))

    sensitive_fields =
      opts
      |> Keyword.get(:sensitive_fields, [])
      |> Enum.map(&(&1 |> to_string() |> String.downcase()))

    module = __CALLER__.module
    inspect_prefix = "##{inspect(module)}<"

    typed_fields =
      Enum.map(fields, fn field ->
        field_type = Map.get(field_types, field, quote(do: term()))
        {field, quote(do: unquote(field_type) | nil)}
      end)

    quote do
      defstruct unquote(Macro.escape(Enum.map(fields, &{&1, nil}) ++ [extra: %{}]))
      @dodo_fields unquote(fields)
      @dodo_enum_fields unquote(Macro.escape(enum_fields))
      @type t :: %__MODULE__{unquote_splicing(typed_fields), extra: map()}

      @doc false
      @spec __dodo_fields__() :: [atom()]
      def __dodo_fields__, do: @dodo_fields

      @doc false
      @spec __dodo_enum_fields__() :: %{optional(atom()) => atom()}
      def __dodo_enum_fields__, do: @dodo_enum_fields

      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(value, opts) do
          safe =
            value
            |> Map.from_struct()
            |> DodoPayments.Redaction.redact(unquote(sensitive_fields))

          concat([unquote(inspect_prefix), to_doc(safe, opts), ">"])
        end
      end
    end
  end

  @doc """
  Casts known response fields into a schema while retaining unknown fields.

      iex> product =
      ...>   DodoPayments.Schema.cast(
      ...>     DodoPayments.Product,
      ...>     %{"product_id" => "pdt_1", "future_field" => true}
      ...>   )
      iex> {product.product_id, product.extra}
      {"pdt_1", %{"future_field" => true}}
  """
  @spec cast(module(), term()) :: term()
  def cast(module, value) when is_map(value) do
    fields = module.__dodo_fields__()
    enum_fields = module.__dodo_enum_fields__()

    {known, extra} =
      Enum.reduce(value, {%{}, %{}}, fn {key, item}, {known, extra} ->
        atom_key = known_atom(key, fields)

        if atom_key do
          {Map.put(known, atom_key, cast_value(item, Map.get(enum_fields, atom_key))), extra}
        else
          {known, Map.put(extra, key, cast_value(item, nil))}
        end
      end)

    struct(module, Map.put(known, :extra, extra))
  end

  def cast(_module, value), do: value

  @doc false
  @spec cast_object(module(), term()) :: {:ok, struct()} | {:error, :expected_json_object}
  def cast_object(module, value) when is_map(value), do: {:ok, cast(module, value)}
  def cast_object(_module, _value), do: {:error, :expected_json_object}

  defp known_atom(key, fields) when is_atom(key), do: if(key in fields, do: key)

  defp known_atom(key, fields) when is_binary(key),
    do: Enum.find(fields, &(Atom.to_string(&1) == key))

  defp normalize_fields!(entries) when is_list(entries) do
    {fields, types, enums} =
      Enum.reduce(entries, {[], %{}, %{}}, fn
        field, {fields, types, enums} when is_atom(field) ->
          add_field!(field, quote(do: term()), fields, types, enums)

        {field, type}, {fields, types, enums} when is_atom(field) ->
          add_field!(field, type, fields, types, enums)

        entry, _accumulator ->
          raise ArgumentError,
                "response fields must be atoms or {atom, type} entries, got: #{inspect(entry)}"
      end)

    {Enum.reverse(fields), types, enums}
  end

  defp normalize_fields!(value) do
    raise ArgumentError, "response fields must be a list, got: #{inspect(value)}"
  end

  defp add_field!(field, type, fields, types, enums) do
    if Map.has_key?(types, field) do
      raise ArgumentError, "response field declared more than once: #{inspect(field)}"
    end

    enums =
      case enum_name(type) do
        nil -> enums
        enum -> Map.put(enums, field, enum)
      end

    {[field | fields], Map.put(types, field, type), enums}
  end

  defp enum_name({{:., _, [{:__aliases__, _, [:DodoPayments, :Enums]}, decoded_name]}, _, []}) do
    case Atom.to_string(decoded_name) do
      "decoded_" <> name -> String.to_atom(name)
      _other -> nil
    end
  end

  defp enum_name(_type), do: nil

  defp cast_value(value, enum) when is_atom(enum) and not is_nil(enum),
    do: DodoPayments.Enums.load(enum, value)

  defp cast_value(value, nil) when is_list(value),
    do: Enum.map(value, &cast_value(&1, nil))

  defp cast_value(value, nil) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, cast_value(v, nil)} end)

  defp cast_value(value, nil), do: value
end
