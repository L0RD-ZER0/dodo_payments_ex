defmodule DodoPayments.HTTP.Response do
  @moduledoc """
  Buffered, transport-neutral HTTP response returned by a client module.

  Headers remain a list so repeated fields such as `set-cookie` are not collapsed.
  The body must contain undecoded bytes; the SDK owns JSON and schema decoding.
  """

  @enforce_keys [:status, :headers, :body]
  defstruct [:status, :headers, :body]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          body: binary()
        }

  @doc false
  @spec header(t(), String.t()) :: String.t() | nil
  def header(%__MODULE__{headers: headers}, name) do
    name = String.downcase(name)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  @doc false
  @spec headers(t(), String.t()) :: [String.t()]
  def headers(%__MODULE__{headers: headers}, name) do
    name = String.downcase(name)

    for {key, value} <- headers, String.downcase(key) == name, do: value
  end
end

defimpl Inspect, for: DodoPayments.HTTP.Response do
  import Inspect.Algebra

  def inspect(response, opts) do
    values = [
      status: response.status,
      headers: DodoPayments.Redaction.redact_headers(response.headers),
      body_bytes: byte_size(response.body)
    ]

    concat(["#DodoPayments.HTTP.Response<", to_doc(values, opts), ">"])
  end
end
