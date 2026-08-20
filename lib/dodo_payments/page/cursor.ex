defmodule DodoPayments.Page.Cursor do
  @moduledoc """
  A single page from a cursor-paginated Dodo Payments endpoint.

  Iterators are opaque. Applications must pass them back unchanged and must not
  infer ordering or offsets from their contents. The struct includes a private
  request closure and is not persistence-safe.
  """

  @enforce_keys [:items]
  defstruct items: [],
            iterator: nil,
            prev_iterator: nil,
            done?: false,
            extra: %{},
            request_iterator: nil,
            fetch_next: nil

  @typedoc "A Dodo iterator page. `request_iterator` and `fetch_next` are private traversal state."
  @type t(item) :: %__MODULE__{
          items: [item],
          iterator: String.t() | nil,
          prev_iterator: String.t() | nil,
          done?: boolean(),
          extra: map(),
          request_iterator: String.t() | nil,
          fetch_next: (String.t() -> {:ok, t(item)} | {:error, Exception.t()}) | nil
        }

  @doc false
  @spec new([item], keyword()) :: t(item) when item: term()
  def new(items, opts \\ []) when is_list(items) do
    iterator = Keyword.get(opts, :iterator)
    done? = Keyword.get(opts, :done?, is_nil(iterator))

    %__MODULE__{
      items: items,
      iterator: iterator,
      prev_iterator: Keyword.get(opts, :prev_iterator),
      done?: done?,
      extra: Keyword.get(opts, :extra, %{}),
      request_iterator: Keyword.get(opts, :request_iterator),
      fetch_next: Keyword.get(opts, :fetch_next)
    }
  end
end

defimpl Inspect, for: DodoPayments.Page.Cursor do
  import Inspect.Algebra

  def inspect(page, opts) do
    fields = [
      items: DodoPayments.Redaction.redact(page.items),
      iterator: page.iterator,
      prev_iterator: page.prev_iterator,
      done?: page.done?,
      extra: DodoPayments.Redaction.redact(page.extra)
    ]

    concat(["#DodoPayments.Page.Cursor<", to_doc(fields, opts), ">"])
  end
end
