defmodule DodoPayments.Request.Adapter do
  @moduledoc false

  alias DodoPayments.{Client, Deadline, HTTP}

  @spec call(Client.t(), HTTP.Request.t(), integer()) ::
          {:ok, HTTP.Response.t()} | {:error, HTTP.TransportError.t()}
  def call(client, request, timeout) do
    case Deadline.run(fn -> call_once(client, request) end, timeout) do
      {:ok, result} -> result
      :timeout -> transport_error(:sdk_deadline_exceeded)
    end
  end

  defp call_once(client, request) do
    try do
      case client.client_module.request(client.client_state, request) do
        {:ok, %HTTP.Response{} = response} ->
          validate_response(response, request.max_body_bytes)

        {:error, %HTTP.TransportError{} = error} ->
          validate_error(error)

        other ->
          invalid_result(other)
      end
    rescue
      exception -> transport_error({:client_module_exception, exception})
    catch
      kind, reason -> transport_error({:client_module_throw, kind, reason})
    end
  end

  defp validate_response(
         %HTTP.Response{status: status, headers: headers, body: body} = response,
         max_body_bytes
       )
       when is_integer(status) and status in 100..599 and is_list(headers) and is_binary(body) do
    cond do
      not valid_headers?(headers) ->
        invalid_result(response)

      max_body_bytes != :infinity and byte_size(body) > max_body_bytes ->
        {:error,
         %HTTP.TransportError{
           reason: {:response_too_large, max_body_bytes},
           delivery: :unknown,
           partial_response: %{status: status, headers: headers}
         }}

      true ->
        {:ok, response}
    end
  end

  defp validate_response(response, _max_body_bytes), do: invalid_result(response)

  defp validate_error(%HTTP.TransportError{delivery: delivery} = error)
       when delivery in [:not_sent, :unknown] do
    if valid_partial_response?(error.partial_response),
      do: {:error, error},
      else: invalid_result(error)
  end

  defp validate_error(error), do: invalid_result(error)

  defp invalid_result(value), do: transport_error({:invalid_client_module_result, value})

  defp transport_error(reason) do
    {:error, %HTTP.TransportError{reason: reason, delivery: :unknown}}
  end

  defp valid_partial_response?(nil), do: true

  defp valid_partial_response?(partial) when is_map(partial) do
    valid_partial_status?(Map.get(partial, :status)) and
      valid_headers?(Map.get(partial, :headers, []))
  end

  defp valid_partial_response?(_partial), do: false

  defp valid_partial_status?(nil), do: true
  defp valid_partial_status?(status), do: is_integer(status) and status in 100..599

  defp valid_headers?(headers) when is_list(headers) do
    not List.improper?(headers) and
      Enum.all?(headers, fn
        {name, value} -> is_binary(name) and is_binary(value)
        _other -> false
      end)
  end

  defp valid_headers?(_headers), do: false
end
