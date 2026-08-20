defmodule DodoPayments.Operation do
  @moduledoc """
  Wire-level description of a Dodo Payments operation.

  Operations are data rather than transport code.  Keeping the catalogue explicit
  gives the request engine one authoritative place to make authentication, replay,
  remote-consequence, pagination and decoding decisions. Replayability answers
  whether an identical request may be repeated; consequence classification answers
  whether an ambiguous result needs reconciliation.
  """

  @type auth :: :merchant | :public
  @type replay :: :safe | :never | {:idempotent_by, [atom() | [atom()]]}
  @type response_mode :: :json | :empty | :binary | :pdf | :csv
  @type pagination :: nil | %{kind: :page_number, initial: non_neg_integer()} | %{kind: :cursor}
  @type item_schema :: module() | {:enum, atom()} | nil

  @enforce_keys [
    :id,
    :method,
    :path,
    :auth,
    :replay,
    :consequential,
    :response_mode,
    :success_statuses
  ]
  defstruct [
    :id,
    :method,
    :path,
    :response_schema,
    :item_schema,
    :body_field,
    :validator,
    :auth,
    :replay,
    :consequential,
    :response_mode,
    :success_statuses,
    input: :body,
    path_params: [],
    required: [],
    pagination: nil,
    reconciliation: nil
  ]

  @type t :: %__MODULE__{
          id: atom(),
          method: :get | :post | :put | :patch | :delete,
          path: String.t(),
          auth: auth(),
          replay: replay(),
          consequential: boolean(),
          input: :none | :body | :query,
          path_params: [atom()],
          required: [atom()],
          pagination: pagination(),
          response_mode: response_mode(),
          success_statuses: [pos_integer()],
          response_schema: module() | nil,
          item_schema: item_schema(),
          body_field: atom() | nil,
          validator: atom() | nil,
          reconciliation: String.t() | nil
        }

  @doc "Returns an operation, raising for an SDK-internal unknown identifier."
  @spec fetch!(atom()) :: t()
  # Dynamic dispatch keeps the operation data type independent of its catalogue at compile time.
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def fetch!(id), do: apply(catalog_module(), :fetch!, [id])

  @doc "Returns every operation in stable catalogue order."
  @spec all() :: [t()]
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def all, do: apply(catalog_module(), :all, [])

  defp catalog_module, do: Module.concat(__MODULE__, "Catalog")

  @doc false
  @spec new(
          atom(),
          :get | :post | :put | :patch | :delete,
          String.t(),
          keyword()
        ) :: t()
  def new(id, method, path, opts \\ []) do
    replay = Keyword.get(opts, :replay, if(method == :get, do: :safe, else: :never))
    response_mode = Keyword.get(opts, :response_mode, :json)

    success_statuses =
      opts
      |> Keyword.get(:success_statuses, success_statuses(method, response_mode))
      |> validate_success_statuses!(id, response_mode)

    %__MODULE__{
      id: id,
      method: method,
      path: path,
      path_params: Keyword.get(opts, :path_params, []),
      input: Keyword.get(opts, :input, if(method == :get, do: :query, else: :body)),
      auth: Keyword.get(opts, :auth, :merchant),
      replay: replay,
      consequential: Keyword.get(opts, :consequential, method != :get),
      pagination: Keyword.get(opts, :pagination),
      response_mode: response_mode,
      success_statuses: success_statuses,
      required: Keyword.get(opts, :required, []),
      response_schema: Keyword.get(opts, :response_schema),
      item_schema: Keyword.get(opts, :item_schema),
      body_field: Keyword.get(opts, :body_field),
      validator: Keyword.get(opts, :validator),
      reconciliation: Keyword.get(opts, :reconciliation, default_reconciliation(replay))
    }
  end

  @doc "Validates input, expands path variables and separates query/body data."
  @spec prepare(t(), map() | nil) ::
          {:ok, %{path: String.t(), body: map() | nil, query: map()}} | {:error, Exception.t()}
  def prepare(%__MODULE__{} = operation, params \\ %{}) do
    with {:ok, params} <- DodoPayments.Validation.map(params, operation.id),
         :ok <- DodoPayments.Validation.required(params, operation.required, operation.id),
         :ok <- validate_pagination_params(operation, params),
         :ok <-
           DodoPayments.Operation.Validator.validate(operation.validator, operation.id, params),
         {:ok, path} <- render_path(operation, params),
         {:ok, payload} <-
           DodoPayments.RequestTypes.encode(
             operation,
             drop_keys(params, operation.path_params)
           ) do
      build_request(operation, path, payload)
    end
  end

  defp build_request(%__MODULE__{input: :none}, path, _payload),
    do: {:ok, %{path: path, query: %{}, body: nil}}

  defp build_request(%__MODULE__{input: :query}, path, payload),
    do: {:ok, %{path: path, query: DodoPayments.Codec.encode(payload), body: nil}}

  defp build_request(%__MODULE__{input: :body} = operation, path, payload) do
    with {:ok, body} <- body_payload(operation, payload) do
      {:ok, %{path: path, query: %{}, body: DodoPayments.Codec.encode(body)}}
    end
  end

  defp body_payload(%__MODULE__{body_field: nil}, payload), do: {:ok, payload}

  defp body_payload(%__MODULE__{body_field: field, id: operation}, payload) do
    case DodoPayments.Validation.fetch(payload, field) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: field,
           reason: :required
         )}
    end
  end

  @doc "Expands `{name}` variables using URL-encoded values from the input map."
  @spec render_path(t(), map()) :: {:ok, String.t()} | {:error, Exception.t()}
  def render_path(%__MODULE__{} = operation, params) do
    Enum.reduce_while(operation.path_params, {:ok, operation.path}, fn name, {:ok, path} ->
      case DodoPayments.Validation.fetch(params, name) do
        {:ok, value} when is_binary(value) or is_integer(value) ->
          rendered = to_string(value)

          if rendered in ["", ".", ".."] do
            {:halt, invalid_path_value(operation, name)}
          else
            encoded = URI.encode(rendered, &URI.char_unreserved?/1)
            {:cont, {:ok, String.replace(path, "{#{name}}", encoded)}}
          end

        {:ok, _value} ->
          {:halt, invalid_path_value(operation, name)}

        :error ->
          {:halt,
           {:error,
            DodoPayments.ValidationError.exception(
              operation: operation.id,
              field: name,
              reason: :required
            )}}
      end
    end)
  end

  defp invalid_path_value(operation, field) do
    {:error,
     DodoPayments.ValidationError.exception(
       operation: operation.id,
       field: field,
       reason: :invalid_path_value
     )}
  end

  defp validate_pagination_params(
         %__MODULE__{pagination: %{kind: :page_number}, id: operation},
         params
       ) do
    case DodoPayments.Validation.fetch(params, :page_number) do
      :error ->
        :ok

      {:ok, value} when is_integer(value) and value >= 0 ->
        :ok

      {:ok, _value} ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: :page_number,
           reason: :invalid_page_number
         )}
    end
  end

  defp validate_pagination_params(%__MODULE__{}, _params), do: :ok

  defp drop_keys(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      acc |> Map.delete(key) |> Map.delete(Atom.to_string(key))
    end)
  end

  defp success_statuses(:get, _mode), do: [200]
  defp success_statuses(:post, :empty), do: [200, 201, 204]
  defp success_statuses(:put, :empty), do: [200, 201, 204]
  defp success_statuses(:patch, :empty), do: [200, 204]
  defp success_statuses(:delete, :empty), do: [200, 204]
  defp success_statuses(:post, _mode), do: [200, 201]
  defp success_statuses(:put, _mode), do: [200, 201]
  defp success_statuses(:patch, _mode), do: [200]
  defp success_statuses(:delete, _mode), do: [200]

  defp validate_success_statuses!(statuses, id, response_mode)
       when is_list(statuses) and statuses != [] do
    cond do
      not Enum.all?(statuses, &(is_integer(&1) and &1 in 200..299)) ->
        raise ArgumentError, "operation #{inspect(id)} has invalid success statuses"

      response_mode == :json and Enum.any?(statuses, &(&1 in [204, 205])) ->
        raise ArgumentError,
              "operation #{inspect(id)} cannot decode a bodyless success status as JSON"

      true ->
        statuses
    end
  end

  defp validate_success_statuses!(_statuses, id, _response_mode) do
    raise ArgumentError, "operation #{inspect(id)} must define non-empty success statuses"
  end

  defp default_reconciliation(:safe),
    do: "The identical logical operation is safe to retry within the request deadline."

  defp default_reconciliation({:idempotent_by, fields}) do
    rendered =
      Enum.map_join(fields, ", ", fn
        path when is_list(path) -> Enum.map_join(path, ".", &Atom.to_string/1)
        field -> Atom.to_string(field)
      end)

    "Retry only with the identical body and stable #{rendered} value."
  end

  defp default_reconciliation(:never),
    do:
      "If delivery is unknown, inspect the affected Dodo resource or webhook stream before repeating this mutation."
end
