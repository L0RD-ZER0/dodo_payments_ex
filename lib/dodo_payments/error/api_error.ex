defmodule DodoPayments.Error.APIError do
  @moduledoc "An error response returned by Dodo Payments."

  defexception [:message, :status, :code, :request_id, :body, headers: []]

  @type t :: %__MODULE__{
          message: String.t(),
          status: pos_integer(),
          code: String.t() | nil,
          request_id: String.t() | nil,
          body: term(),
          headers: [{String.t(), String.t()}]
        }

  @impl true
  def exception(opts) do
    status = Keyword.fetch!(opts, :status)
    body = Keyword.get(opts, :body)
    code = error_code(body)
    request_id = Keyword.get(opts, :request_id)

    message =
      "Dodo Payments returned HTTP #{status}" <>
        code_suffix(code) <> request_suffix(request_id)

    %__MODULE__{
      message: message,
      status: status,
      code: code,
      request_id: request_id,
      body: body,
      headers: Keyword.get(opts, :headers, [])
    }
  end

  defp error_code(%{"code" => code}) when is_binary(code), do: code
  defp error_code(%{"error" => %{"code" => code}}) when is_binary(code), do: code
  defp error_code(_), do: nil

  defp request_suffix(nil), do: ""
  defp request_suffix(request_id), do: " (request #{safe_fragment(request_id)})"
  defp code_suffix(nil), do: ""
  defp code_suffix(code), do: " (#{safe_fragment(code)})"

  defp safe_fragment(value) when is_binary(value) do
    suffix = if byte_size(value) > 128, do: "…", else: ""
    prefix = binary_part(value, 0, min(byte_size(value), 128))

    prefix
    |> :binary.bin_to_list()
    |> Enum.map(fn
      byte when byte in 32..126 -> byte
      _byte -> ??
    end)
    |> then(&IO.iodata_to_binary([&1, suffix]))
  end

  defp safe_fragment(_value), do: "unknown"
end

defimpl Inspect, for: DodoPayments.Error.APIError do
  import Inspect.Algebra

  def inspect(error, opts),
    do:
      concat([
        "#DodoPayments.Error.APIError<",
        to_doc(
          [
            status: error.status,
            code: safe_label(error.code),
            request_id: safe_label(error.request_id),
            body: :redacted,
            headers: :redacted
          ],
          opts
        ),
        ">"
      ])

  defp safe_label(nil), do: nil

  defp safe_label(value) when is_binary(value) and byte_size(value) <= 128 do
    if String.printable?(value), do: value, else: :redacted
  end

  defp safe_label(_value), do: :redacted
end
