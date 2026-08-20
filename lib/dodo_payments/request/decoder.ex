defmodule DodoPayments.Request.Decoder do
  @moduledoc false

  alias DodoPayments.Error
  alias DodoPayments.{Operation, Response}
  alias DodoPayments.Request.ResponseInfo

  @spec decode_success(map(), DodoPayments.HTTP.Response.t(), pos_integer(), (map() -> term())) ::
          {:ok, term()} | {:error, Exception.t()}
  def decode_success(context, response, attempt_number, fetch_next) do
    case decode_body(response, context.operation, context.params, fetch_next) do
      {:ok, data} ->
        return_success(context.return, response, data)

      {:error, error} when context.operation.consequential ->
        {:error,
         Error.OutcomeUnknown.exception(
           operation: context.operation.id,
           reason: {:successful_response_unreadable, error.__struct__},
           status: response.status,
           request_id: ResponseInfo.request_id(response),
           attempts: attempt_number,
           replay: DodoPayments.Request.RetryPolicy.outcome_replay(context),
           reconciliation: context.operation.reconciliation
         )}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec api_error(DodoPayments.HTTP.Response.t()) :: Error.APIError.t()
  def api_error(response) do
    body =
      case Jason.decode(response.body) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> response.body
      end

    Error.APIError.exception(
      status: response.status,
      body: body,
      headers: response.headers,
      request_id: ResponseInfo.request_id(response)
    )
  end

  defp return_success(:data, _response, data), do: {:ok, data}

  defp return_success(:response, response, data) do
    {:ok,
     %Response{
       data: data,
       status: response.status,
       headers: response.headers,
       request_id: ResponseInfo.request_id(response)
     }}
  end

  defp decode_body(_response, %Operation{response_mode: :empty}, _params, _fetch_next),
    do: {:ok, nil}

  defp decode_body(response, %Operation{response_mode: mode}, _params, _fetch_next)
       when mode in [:binary, :pdf, :csv],
       do: {:ok, response.body}

  defp decode_body(
         response,
         %Operation{response_mode: :json, response_schema: schema} = operation,
         params,
         fetch_next
       ) do
    case DodoPayments.Codec.decode(response.body, schema) do
      {:ok, decoded} ->
        case decode_page(operation, decoded, params, fetch_next) do
          {:ok, _data} = success ->
            success

          {:error, %{__struct__: _module}} = error ->
            error

          {:error, reason} ->
            {:error,
             Error.DecodeError.exception(
               reason: reason,
               status: response.status,
               request_id: ResponseInfo.request_id(response),
               body: response.body
             )}
        end

      {:error, reason} ->
        {:error,
         Error.DecodeError.exception(
           reason: reason,
           status: response.status,
           request_id: ResponseInfo.request_id(response),
           body: response.body
         )}
    end
  end

  defp decode_page(
         %Operation{pagination: nil, item_schema: nil},
         decoded,
         _params,
         _fetch_next
       ),
       do: {:ok, decoded}

  defp decode_page(
         %Operation{pagination: nil, item_schema: item_schema},
         decoded,
         _params,
         _fetch_next
       ) do
    decode_items(decoded, item_schema)
  end

  defp decode_page(%Operation{} = operation, decoded, params, fetch_next) do
    DodoPayments.Page.from_response(operation, decoded, fetch_next, params)
  end

  defp decode_items(items, schema) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, decoded} ->
      case decode_item(item, schema) do
        {:ok, item} -> {:cont, {:ok, [item | decoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_items(_items, _schema), do: {:error, :expected_json_array}

  defp decode_item(item, {:enum, enum}) when is_binary(item),
    do: {:ok, DodoPayments.Enums.load(enum, item)}

  defp decode_item(item, {:enum, _enum}), do: {:error, {:expected_enum_string, item}}

  defp decode_item(item, schema), do: DodoPayments.Schema.cast_object(schema, item)
end
