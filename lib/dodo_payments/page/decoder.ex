defmodule DodoPayments.Page.Decoder do
  @moduledoc false

  alias DodoPayments.Page.{Cursor, Numbered, TraversalError}

  @spec decode(DodoPayments.Operation.t(), term(), (map() -> term()), map()) ::
          {:ok, DodoPayments.Page.t(term())} | {:error, TraversalError.t()}
  def decode(operation, decoded, fetch_next, request_params) do
    case operation.pagination do
      %{kind: :page_number, initial: initial} ->
        requested_number = request_value(request_params, :page_number, initial)

        numbered_from_response(
          decoded,
          requested_number,
          initial,
          operation.item_schema,
          fetch_next
        )

      %{kind: :cursor} ->
        requested_cursor = request_value(request_params, :iterator)
        cursor_from_response(decoded, requested_cursor, operation.item_schema, fetch_next)

      nil ->
        {:error,
         TraversalError.exception(
           reason: :not_paginated,
           message: "operation #{inspect(operation.id)} is not paginated"
         )}
    end
  end

  defp numbered_from_response(decoded, requested_number, initial, schema, fetch_next) do
    with {:ok, envelope, items} <- envelope(decoded),
         {:ok, items} <- cast_items(items, schema),
         {:ok, number} <- non_negative(envelope, :page_number, requested_number),
         {:ok, page_size} <- optional_non_negative(envelope, :page_size),
         {:ok, total_count} <- optional_non_negative(envelope, :total_count),
         {:ok, total_pages} <- optional_non_negative(envelope, :total_pages),
         {:ok, next_number} <- optional_non_negative(envelope, :next_page) do
      has_more? =
        numbered_has_more?(
          envelope,
          items,
          number,
          initial,
          next_number,
          total_pages,
          total_count,
          page_size
        )

      {:ok,
       Numbered.new(items, number,
         page_size: page_size,
         total_count: total_count,
         total_pages: total_pages,
         has_more?: has_more?,
         next_number: next_number || if(has_more?, do: number + 1),
         extra:
           extra(
             envelope,
             ~w(items data page_number page_size total_count total_pages has_more next_page)
           ),
         fetch_next: fn next -> fetch_next.(%{page_number: next}) end
       )}
    end
  end

  defp cursor_from_response(decoded, requested_cursor, schema, fetch_next) do
    with {:ok, envelope, items} <- envelope(decoded),
         {:ok, items} <- cast_items(items, schema),
         {:ok, iterator} <- optional_binary(envelope, :iterator, nil),
         {:ok, prev_iterator} <- optional_binary(envelope, :prev_iterator, nil) do
      done? = value(envelope, :done, false) == true

      {:ok,
       Cursor.new(items,
         iterator: iterator,
         prev_iterator: prev_iterator,
         done?: done?,
         request_iterator: requested_cursor,
         extra: extra(envelope, ~w(items data iterator prev_iterator done)),
         fetch_next: fn next -> fetch_next.(%{iterator: next}) end
       )}
    end
  end

  defp envelope(items) when is_list(items), do: {:ok, %{}, items}

  defp envelope(%{} = envelope) do
    case value(envelope, :items, value(envelope, :data)) do
      items when is_list(items) -> {:ok, envelope, items}
      other -> invalid_page({:items_must_be_a_list, other})
    end
  end

  defp envelope(other), do: invalid_page({:envelope_must_be_a_map, other})

  defp non_negative(map, key, default) do
    case value(map, key, default) do
      number when is_integer(number) and number >= 0 -> {:ok, number}
      other -> invalid_page({:invalid_non_negative_integer, key, other})
    end
  end

  defp optional_non_negative(map, key) do
    case value(map, key) do
      nil -> {:ok, nil}
      number when is_integer(number) and number >= 0 -> {:ok, number}
      other -> invalid_page({:invalid_non_negative_integer, key, other})
    end
  end

  defp optional_binary(map, key, default) do
    case value(map, key, default) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      other -> invalid_page({:invalid_cursor, key, other})
    end
  end

  defp numbered_has_more?(
         envelope,
         items,
         number,
         initial,
         next_number,
         total_pages,
         total_count,
         page_size
       ) do
    cond do
      is_boolean(value(envelope, :has_more)) ->
        value(envelope, :has_more)

      not is_nil(next_number) ->
        true

      not is_nil(total_pages) or not is_nil(total_count) ->
        more_from_totals?(number, initial, total_pages, total_count, page_size)

      true ->
        items != []
    end
  end

  defp more_from_totals?(number, initial, total_pages, _total_count, _page_size)
       when is_integer(total_pages),
       do: number - initial + 1 < total_pages

  defp more_from_totals?(number, initial, nil, total_count, page_size)
       when is_integer(total_count) and is_integer(page_size) and page_size > 0,
       do: number - initial + 1 < div(total_count + page_size - 1, page_size)

  defp more_from_totals?(_number, _initial, _total_pages, _total_count, _page_size), do: false

  defp cast_items(items, nil), do: {:ok, items}

  defp cast_items(items, schema) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, cast} ->
      case DodoPayments.Schema.cast_object(schema, item) do
        {:ok, item} -> {:cont, {:ok, [item | cast]}}
        {:error, _reason} -> {:halt, invalid_page(:item_must_be_a_map)}
      end
    end)
    |> case do
      {:ok, cast} -> {:ok, Enum.reverse(cast)}
      {:error, _reason} = error -> error
    end
  end

  defp extra(envelope, known) do
    known = MapSet.new(known)

    Map.new(envelope, fn {key, value} -> {key, value} end)
    |> Enum.reject(fn {key, _value} -> MapSet.member?(known, to_string(key)) end)
    |> Map.new()
  end

  defp value(map, key, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key), default)
    end
  end

  defp request_value(params, key, default \\ nil) do
    case DodoPayments.Validation.fetch(params, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp invalid_page(reason) do
    {:error,
     TraversalError.exception(
       reason: {:invalid_page_response, reason},
       message: "Dodo Payments returned an invalid pagination envelope"
     )}
  end
end
