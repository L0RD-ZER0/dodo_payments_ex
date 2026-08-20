defmodule DodoPayments.Request.ResponseInfo do
  @moduledoc false

  alias DodoPayments.HTTP

  @request_id_headers ["x-request-id", "request-id", "x-dodo-request-id"]

  @spec request_id(HTTP.Response.t()) :: String.t() | nil
  def request_id(response) do
    Enum.find_value(@request_id_headers, &HTTP.Response.header(response, &1))
  end

  @spec request_id_from_headers([{String.t(), String.t()}]) :: String.t() | nil
  def request_id_from_headers(headers) do
    Enum.find_value(@request_id_headers, fn wanted ->
      Enum.find_value(headers, fn
        {name, value} when is_binary(value) ->
          if String.downcase(to_string(name)) == wanted, do: value

        _other ->
          nil
      end)
    end)
  end

  @spec partial_status(HTTP.TransportError.t()) :: integer() | nil
  def partial_status(%HTTP.TransportError{partial_response: %{status: status}}), do: status
  def partial_status(_error), do: nil

  @spec partial_request_id(HTTP.TransportError.t()) :: String.t() | nil
  def partial_request_id(%HTTP.TransportError{partial_response: %{headers: headers}}),
    do: request_id_from_headers(headers)

  def partial_request_id(_error), do: nil
end
