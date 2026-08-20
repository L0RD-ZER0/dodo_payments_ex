defmodule DodoPayments.Page.Numbered do
  @moduledoc """
  A single page from a page-numbered Dodo Payments endpoint.

  Dodo's numbered list endpoints are zero-based. `number` is always the number
  returned by (or requested from) Dodo; the SDK does not silently translate it.
  The struct includes a private request closure and is not persistence-safe.
  """

  @enforce_keys [:items, :number]
  defstruct items: [],
            number: nil,
            page_size: nil,
            total_count: nil,
            total_pages: nil,
            has_more?: false,
            next_number: nil,
            extra: %{},
            fetch_next: nil

  @typedoc "A numbered API page. `fetch_next` is private SDK traversal state."
  @type t(item) :: %__MODULE__{
          items: [item],
          number: non_neg_integer(),
          page_size: non_neg_integer() | nil,
          total_count: non_neg_integer() | nil,
          total_pages: non_neg_integer() | nil,
          has_more?: boolean(),
          next_number: non_neg_integer() | nil,
          extra: map(),
          fetch_next: (non_neg_integer() -> {:ok, t(item)} | {:error, Exception.t()}) | nil
        }

  @doc false
  @spec new([item], non_neg_integer(), keyword()) :: t(item) when item: term()
  def new(items, number, opts \\ []) when is_list(items) and is_integer(number) and number >= 0 do
    has_more? = Keyword.get(opts, :has_more?, false)
    next_number = Keyword.get(opts, :next_number, if(has_more?, do: number + 1))

    %__MODULE__{
      items: items,
      number: number,
      page_size: Keyword.get(opts, :page_size),
      total_count: Keyword.get(opts, :total_count),
      total_pages: Keyword.get(opts, :total_pages),
      has_more?: has_more?,
      next_number: next_number,
      extra: Keyword.get(opts, :extra, %{}),
      fetch_next: Keyword.get(opts, :fetch_next)
    }
  end
end

defimpl Inspect, for: DodoPayments.Page.Numbered do
  import Inspect.Algebra

  def inspect(page, opts) do
    fields = [
      items: DodoPayments.Redaction.redact(page.items),
      number: page.number,
      page_size: page.page_size,
      total_count: page.total_count,
      total_pages: page.total_pages,
      has_more?: page.has_more?,
      next_number: page.next_number,
      extra: DodoPayments.Redaction.redact(page.extra)
    ]

    concat(["#DodoPayments.Page.Numbered<", to_doc(fields, opts), ">"])
  end
end
