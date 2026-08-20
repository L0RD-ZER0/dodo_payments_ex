defmodule DodoPayments.Page.TraversalError do
  @moduledoc """
  Raised when automatic pagination cannot continue safely.

  Manual pagination through `DodoPayments.Page.next/1` returns the underlying
  error. Lazy streams raise this exception because an `Enumerable` has no
  natural error return channel.
  """

  defexception [:message, :reason, :page]

  @type t :: %__MODULE__{message: String.t(), reason: term(), page: term()}

  @impl Exception
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    page = Keyword.get(opts, :page)

    message =
      Keyword.get_lazy(opts, :message, fn ->
        "pagination stopped: #{format_reason(reason)}"
      end)

    %__MODULE__{message: message, reason: reason, page: page}
  end

  defp format_reason(:page_limit_reached), do: "the configured page limit was reached"
  defp format_reason(:item_limit_reached), do: "the configured item limit was reached"
  defp format_reason(:missing_fetcher), do: "this page has no next-page fetcher"
  defp format_reason(:iterator_did_not_advance), do: "the API returned the same iterator twice"
  defp format_reason(:page_did_not_advance), do: "the API returned a non-advancing page number"
  defp format_reason(:pagination_cycle), do: "the API returned a previously visited page token"

  defp format_reason({:response_page_mismatch, expected, actual}),
    do: "expected page #{expected}, received page #{actual}"

  defp format_reason(%DodoPayments.Error.APIError{status: status}),
    do: "the next-page request returned HTTP #{status}"

  defp format_reason(%DodoPayments.Error.TimeoutError{}),
    do: "the next-page request timed out"

  defp format_reason(%DodoPayments.Error.TransportError{}),
    do: "the next-page request failed in transport"

  defp format_reason(%DodoPayments.Error.DecodeError{}),
    do: "the next-page response could not be decoded"

  defp format_reason(%DodoPayments.Error.ResponseTooLarge{}),
    do: "the next-page response exceeded the configured size limit"

  defp format_reason(%__MODULE__{} = error), do: Exception.message(error)

  defp format_reason(_reason), do: "pagination failed"
end

defimpl Inspect, for: DodoPayments.Page.TraversalError do
  import Inspect.Algebra

  def inspect(error, opts) do
    values = [reason: reason_category(error.reason), page: :redacted]
    concat(["#DodoPayments.Page.TraversalError<", to_doc(values, opts), ">"])
  end

  defp reason_category({category, _rest}) when is_atom(category), do: category
  defp reason_category({category, _left, _right}) when is_atom(category), do: category
  defp reason_category(%module{}) when is_atom(module), do: module
  defp reason_category(reason) when is_atom(reason), do: reason
  defp reason_category(_reason), do: :redacted
end
