defmodule DodoPayments.Service do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import DodoPayments.Service, only: [operation: 2, operation: 3]
    end
  end

  # This compile-time DSL deliberately emits three distinct public API shapes.
  # Keeping the complete generated contract together is easier to audit than
  # distributing quoted clauses across helper functions.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro operation(name, id, opts \\ []) do
    operation = DodoPayments.Operation.Catalog.fetch!(id)
    path_params = Keyword.get(opts, :path, [])
    accepts_params = Keyword.get(opts, :params, true)

    requires_params =
      accepts_params and (operation.required != [] or not is_nil(operation.body_field))

    deprecated = Keyword.get(opts, :deprecated)
    data_type = result_type(operation)
    data_result = result_type(data_type, false)
    option_result = result_type(data_type, true)
    operation_doc = operation_doc(operation)

    {params_type, params_type_declaration, params_type_doc} =
      if accepts_params do
        type_name = String.to_atom("#{name}_params")
        type_ref = {type_name, [], []}
        type_ast = DodoPayments.RequestTypes.params_ast(operation)

        {type_ref, {:"::", [], [type_ref, type_ast]},
         DodoPayments.RequestTypes.type_doc(operation)}
      else
        {nil, nil, nil}
      end

    deprecation =
      if deprecated do
        quote do: @deprecated(unquote(deprecated))
      else
        quote do: nil
      end

    args = Enum.map(path_params, &Macro.var(&1, nil))
    path_types = Enum.map(path_params, fn _ -> quote(do: String.t() | integer()) end)

    pairs =
      Enum.zip(path_params, args)
      |> Enum.map(fn {key, var} -> quote(do: {unquote(key), unquote(var)}) end)

    cond do
      requires_params ->
        quote do
          @typedoc unquote(params_type_doc)
          @type unquote(params_type_declaration)

          @doc unquote(operation_doc <> "\n\nAPI parameters must be supplied as a map.")
          unquote(deprecation)

          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types),
                  unquote(params_type)
                ) :: unquote(data_result)
          def unquote(name)(client, unquote_splicing(args), params) when is_map(params) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), params, [])
          end

          unquote(deprecation)

          def unquote(name)(_client, unquote_splicing(args), params) when is_list(params) do
            _ = {unquote_splicing(args)}
            DodoPayments.Service.parameter_map_error(unquote(id))
          end

          unquote(deprecation)

          def unquote(name)(client, unquote_splicing(args), params) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), params, [])
          end

          @doc unquote(operation_doc <> "\n\nThe final argument contains request-local options.")
          unquote(deprecation)

          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types),
                  unquote(params_type),
                  keyword()
                ) :: unquote(option_result)
          def unquote(name)(client, unquote_splicing(args), params, opts) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), params, opts)
          end
        end

      accepts_params ->
        quote do
          @typedoc unquote(params_type_doc)
          @type unquote(params_type_declaration)

          @doc unquote(operation_doc <> "\n\nCalls the operation with an empty parameter map.")
          unquote(deprecation)

          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types)
                ) :: unquote(data_result)
          def unquote(name)(client, unquote_splicing(args)) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), %{}, [])
          end

          @doc unquote(
                 operation_doc <>
                   "\n\nPass a map for Dodo parameters or a keyword list for request-local options."
               )
          unquote(deprecation)

          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types),
                  unquote(params_type) | nil | keyword()
                ) :: unquote(option_result)
          def unquote(name)(client, unquote_splicing(args), opts) when is_list(opts) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), %{}, opts)
          end

          unquote(deprecation)

          def unquote(name)(client, unquote_splicing(args), params) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), params, [])
          end

          @doc unquote(
                 operation_doc <>
                   "\n\nAccepts both a Dodo parameter map and request-local options."
               )
          unquote(deprecation)

          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types),
                  unquote(params_type) | nil,
                  keyword()
                ) :: unquote(option_result)
          def unquote(name)(client, unquote_splicing(args), params, opts) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), params, opts)
          end
        end

      true ->
        quote do
          @doc unquote(operation_doc <> "\n\nOptions are request-local.")
          @spec unquote(name)(
                  DodoPayments.Client.t(),
                  unquote_splicing(path_types),
                  keyword()
                ) :: unquote(option_result)
          def unquote(name)(client, unquote_splicing(args), opts \\ []) do
            DodoPayments.Service.call(client, unquote(id), unquote(pairs), %{}, opts)
          end
        end
    end
  end

  @doc false
  def parameter_map_error(operation) do
    {:error,
     DodoPayments.Error.ConfigurationError.exception(
       message:
         "API parameters for #{operation} must be passed as a map; keyword lists are reserved for request options"
     )}
  end

  @doc false
  @spec call(DodoPayments.Client.t(), atom(), [{atom(), term()}], map() | nil, keyword()) ::
          {:ok, term()} | {:error, Exception.t()}
  def call(client, id, path_pairs, params, opts) do
    with {:ok, params} <- DodoPayments.Validation.map(params, id),
         :ok <- validate_options(opts) do
      path_values = Map.new(path_pairs)

      DodoPayments.Request.request(
        client,
        DodoPayments.Operation.fetch!(id),
        Map.merge(params, path_values),
        opts
      )
    end
  end

  defp validate_options(opts) do
    if is_list(opts) do
      :ok
    else
      {:error,
       DodoPayments.Error.ConfigurationError.exception(
         message: "request options must be a keyword list"
       )}
    end
  end

  defp result_type(%DodoPayments.Operation{pagination: %{kind: :page_number}} = operation) do
    item = schema_type(operation.item_schema)
    quote(do: DodoPayments.Page.Numbered.t(unquote(item)))
  end

  defp result_type(%DodoPayments.Operation{pagination: %{kind: :cursor}} = operation) do
    item = schema_type(operation.item_schema)
    quote(do: DodoPayments.Page.Cursor.t(unquote(item)))
  end

  defp result_type(%DodoPayments.Operation{response_mode: :empty}), do: quote(do: nil)

  defp result_type(%DodoPayments.Operation{response_mode: mode})
       when mode in [:binary, :pdf, :csv],
       do: quote(do: binary())

  defp result_type(%DodoPayments.Operation{pagination: nil, item_schema: schema})
       when not is_nil(schema) do
    item = schema_type(schema)
    quote(do: [unquote(item)])
  end

  defp result_type(%DodoPayments.Operation{id: id, response_schema: schema}) do
    if is_atom(schema) and not is_nil(schema) do
      quote(do: unquote(schema).t())
    else
      raise ArgumentError, "JSON operation #{inspect(id)} has no response type"
    end
  end

  defp schema_type(nil), do: quote(do: DodoPayments.json())
  defp schema_type({:enum, enum}), do: enum_type(enum)
  defp schema_type(schema), do: quote(do: unquote(schema).t())

  defp enum_type(enum) do
    function = String.to_atom("decoded_#{enum}")

    {{:., [], [{:__aliases__, [alias: false], [:DodoPayments, :Enums]}, function]}, [], []}
  end

  defp result_type(data_type, false) do
    quote(do: {:ok, unquote(data_type)} | {:error, Exception.t()})
  end

  defp result_type(data_type, true) do
    quote(
      do:
        {:ok, unquote(data_type) | DodoPayments.Response.t(unquote(data_type))}
        | {:error, Exception.t()}
    )
  end

  defp operation_doc(operation) do
    required =
      case operation.required do
        [] -> "none"
        fields -> Enum.map_join(fields, ", ", &"`:#{&1}`")
      end

    pagination =
      case operation.pagination do
        %{kind: :page_number} -> " Numbered pagination is zero-based."
        %{kind: :cursor} -> " Pagination uses Dodo iterators."
        nil -> ""
      end

    "Calls Dodo operation `#{operation.id}` (`#{String.upcase(to_string(operation.method))} #{operation.path}`). Required parameters: #{required}.#{pagination}"
  end
end
