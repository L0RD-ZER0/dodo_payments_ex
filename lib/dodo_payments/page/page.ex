defmodule DodoPayments.Page do
  @moduledoc """
  Explicit pagination for Dodo Payments list operations.

  Start with the first page returned by a resource function. Use `next/1` when
  request boundaries matter, or opt into a lazy bounded traversal with
  `pages/2` or `stream/2`.

      {:ok, first} = DodoPayments.Products.list(client, %{page_number: 0})

      with {:ok, second} <- DodoPayments.Page.next(first) do
        second.items
      end

      first
      |> DodoPayments.Page.stream(max_pages: 20)
      |> Enum.take(100)

  Automatic traversal is deliberately guarded. It detects repeated iterators or
  page numbers and defaults to at most 1,000 pages. Page structs retain a private
  fetch closure containing client/request state; consume them during the request
  workflow and persist only application data, never the page struct itself.
  """

  alias DodoPayments.Page.{Cursor, Decoder, Numbered, TraversalError}

  @type t(item) :: Cursor.t(item) | Numbered.t(item)
  @type next_result(item) :: {:ok, t(item)} | :done | {:error, Exception.t()}

  @doc false
  @spec from_response(DodoPayments.Operation.t(), term(), (map() -> next_result(item)), map()) ::
          {:ok, t(item)} | {:error, TraversalError.t()}
        when item: term()
  def from_response(
        %DodoPayments.Operation{} = operation,
        decoded,
        fetch_next,
        request_params \\ %{}
      )
      when is_function(fetch_next, 1) and is_map(request_params) do
    Decoder.decode(operation, decoded, fetch_next, request_params)
  end

  @doc "Returns the items held by a page."
  @spec items(t(item)) :: [item] when item: term()
  def items(%{__struct__: module, items: items}) when module in [Cursor, Numbered], do: items

  @doc "Fetches exactly one next page, or returns `:done`."
  @spec next(t(item)) :: next_result(item) when item: term()
  def next(%Numbered{has_more?: false}), do: :done
  def next(%Numbered{next_number: nil}), do: :done

  def next(%Numbered{fetch_next: nil}),
    do: {:error, TraversalError.exception(reason: :missing_fetcher)}

  def next(%Numbered{number: current, next_number: next} = page) when next <= current do
    {:error, TraversalError.exception(reason: :page_did_not_advance, page: page)}
  end

  def next(%Numbered{next_number: next, fetch_next: fetch}) do
    case normalize_fetch(fetch.(next)) do
      {:ok, %Numbered{number: ^next} = page} ->
        {:ok, %{page | fetch_next: fetch}}

      {:ok, %Numbered{} = page} ->
        {:error,
         TraversalError.exception(
           reason: {:response_page_mismatch, next, page.number},
           page: page
         )}

      other ->
        other
    end
  end

  def next(%Cursor{done?: true}), do: :done
  def next(%Cursor{iterator: nil}), do: :done

  def next(%Cursor{fetch_next: nil}),
    do: {:error, TraversalError.exception(reason: :missing_fetcher)}

  def next(%Cursor{request_iterator: iterator, iterator: iterator} = page)
      when not is_nil(iterator) do
    {:error, TraversalError.exception(reason: :iterator_did_not_advance, page: page)}
  end

  def next(%Cursor{iterator: next, fetch_next: fetch}) do
    case normalize_fetch(fetch.(next)) do
      {:ok, %Cursor{iterator: ^next, done?: false} = page} ->
        {:error, TraversalError.exception(reason: :iterator_did_not_advance, page: page)}

      {:ok, %Cursor{} = page} ->
        {:ok, advance_cursor(page, next, fetch)}

      other ->
        other
    end
  end

  @doc """
  Lazily enumerates pages, including the supplied first page.

  Options:

    * `:max_pages` - positive traversal limit, default `1_000`

  Fetch failures and broken pagination invariants raise `TraversalError` while
  the stream is consumed. No further HTTP request occurs after a consumer
  halts the stream.
  """
  @spec pages(t(item), keyword()) :: Enumerable.t() when item: term()
  def pages(first_page, opts \\ []) do
    validate_options!(opts, [:max_pages])
    max_pages = positive_limit!(opts, :max_pages, 1_000)

    Stream.resource(
      fn -> {:emit, first_page, MapSet.new(), 0} end,
      fn
        :done ->
          {:halt, :done}

        {:emit, page, _seen, count} when count >= max_pages ->
          raise TraversalError, reason: :page_limit_reached, page: page

        {:emit, page, seen, count} ->
          token = token(page)

          if MapSet.member?(seen, token) do
            raise TraversalError, reason: :pagination_cycle, page: page
          end

          {[page], {:advance, page, MapSet.put(seen, token), count + 1}}

        {:advance, page, seen, count} ->
          if count >= max_pages and has_more?(page) do
            raise TraversalError, reason: :page_limit_reached, page: page
          else
            case next(page) do
              {:ok, next_page} -> {[], {:emit, next_page, seen, count}}
              :done -> {:halt, :done}
              {:error, error} -> raise TraversalError, reason: error, page: page
            end
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Lazily enumerates items across pages.

  It accepts the `:max_pages` option from `pages/2` plus `:max_items` (default
  `:infinity`). The item limit is a safety ceiling and raises when more items
  are requested; normal early termination such as `Enum.take/2` remains lazy.
  """
  @spec stream(t(item), keyword()) :: Enumerable.t() when item: term()
  def stream(first_page, opts \\ []) do
    validate_options!(opts, [:max_pages, :max_items])
    max_items = item_limit!(opts)

    first_page
    |> pages(Keyword.take(opts, [:max_pages]))
    |> Stream.flat_map(&items/1)
    |> guard_items(max_items)
  end

  defp guard_items(stream, :infinity), do: stream

  defp guard_items(stream, max_items) do
    stream
    |> Stream.with_index()
    |> Stream.map(fn
      {_item, index} when index >= max_items ->
        raise TraversalError, reason: :item_limit_reached

      {item, _index} ->
        item
    end)
  end

  defp normalize_fetch({:ok, %module{} = page}) when module in [Cursor, Numbered], do: {:ok, page}
  defp normalize_fetch({:error, %_{} = error}), do: {:error, error}

  defp normalize_fetch(other) do
    {:error,
     TraversalError.exception(
       reason: {:invalid_fetch_result, other},
       message: "pagination fetcher returned an invalid value"
     )}
  end

  defp token(%Numbered{number: number}), do: {:numbered, number}

  defp token(%Cursor{request_iterator: current, iterator: next}),
    do: {:iterator, current || {:first, next}}

  defp has_more?(%Numbered{has_more?: value}), do: value

  defp has_more?(%Cursor{done?: done?, iterator: iterator}),
    do: not done? and not is_nil(iterator)

  defp positive_limit!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError, "#{inspect(key)} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp item_limit!(opts) do
    case Keyword.get(opts, :max_items, :infinity) do
      :infinity ->
        :infinity

      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              ":max_items must be :infinity or a positive integer, got: #{inspect(value)}"
    end
  end

  defp validate_options!(opts, allowed) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "pagination options must be a keyword list"
    end

    case Keyword.keys(opts) -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown pagination option(s): #{inspect(unknown)}"
    end
  end

  defp advance_cursor(%Cursor{request_iterator: nil} = page, requested, fetch_next),
    do: %{page | request_iterator: requested, fetch_next: fetch_next}

  defp advance_cursor(%Cursor{} = page, _requested, fetch_next),
    do: %{page | fetch_next: fetch_next}
end
