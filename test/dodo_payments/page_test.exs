defmodule DodoPayments.PageTest do
  use ExUnit.Case, async: true

  alias DodoPayments.Page
  alias DodoPayments.Page.{Cursor, Numbered, TraversalError}

  test "numbered pages advance by the exact zero-based page requested" do
    fetch = fn number -> {:ok, Numbered.new([number], number, has_more?: false)} end
    first = Numbered.new([0], 0, has_more?: true, fetch_next: fetch)

    assert {:ok, %Numbered{number: 1, items: [1]}} = Page.next(first)
    assert Page.items(first) == [0]
  end

  test "numbered pagination rejects a mismatched server page" do
    fetch = fn _number -> {:ok, Numbered.new([], 9)} end
    first = Numbered.new([], 0, has_more?: true, fetch_next: fetch)

    assert {:error, %TraversalError{reason: {:response_page_mismatch, 1, 9}}} = Page.next(first)
  end

  test "cursor pages preserve Dodo iterator names and detect non-advancement" do
    repeating =
      Cursor.new([], iterator: "same", request_iterator: "same", fetch_next: fn _ -> :done end)

    assert {:error, %TraversalError{reason: :iterator_did_not_advance}} = Page.next(repeating)

    fetch = fn "next" ->
      {:ok, Cursor.new([:second], iterator: nil, prev_iterator: "previous", done?: true)}
    end

    first = Cursor.new([:first], iterator: "next", fetch_next: fetch)

    assert {:ok,
            %Cursor{
              items: [:second],
              request_iterator: "next",
              prev_iterator: "previous",
              done?: true
            }} = Page.next(first)

    repeated_fetch = fn "same" ->
      {:ok, Cursor.new([:duplicate], iterator: "same", done?: false)}
    end

    first = Cursor.new([:first], iterator: "same", fetch_next: repeated_fetch)

    assert {:error, %TraversalError{reason: :iterator_did_not_advance}} = Page.next(first)

    assert_raise TraversalError, fn ->
      first |> Page.stream() |> Enum.take(2)
    end

    terminal_fetch = fn "last" ->
      {:ok, Cursor.new([], iterator: "last", done?: true)}
    end

    assert {:ok, %Cursor{done?: true}} =
             Page.next(Cursor.new([], iterator: "last", fetch_next: terminal_fetch))
  end

  test "lazy traversal does not fetch beyond consumer demand" do
    parent = self()

    fetch = fn number ->
      send(parent, {:fetch, number})
      {:ok, Numbered.new([number], number, has_more?: true)}
    end

    first = Numbered.new([0], 0, has_more?: true, fetch_next: fetch)

    assert Enum.take(Page.stream(first), 1) == [0]
    refute_received {:fetch, _number}
  end

  test "page and item safety ceilings fail explicitly" do
    fetch = fn number -> {:ok, Numbered.new([number], number, has_more?: true)} end
    first = Numbered.new([0, 1], 0, has_more?: true, fetch_next: fetch)

    assert_raise TraversalError, fn -> Enum.to_list(Page.pages(first, max_pages: 1)) end
    assert_raise TraversalError, fn -> Enum.to_list(Page.stream(first, max_items: 1)) end
    assert_raise ArgumentError, fn -> Page.pages(first, max_pages: 0) end
    assert_raise ArgumentError, fn -> Page.stream(first, max_items: 0) end

    assert_raise ArgumentError, ~r/unknown pagination option/, fn ->
      Page.pages(first, max_pagse: 1)
    end

    assert_raise ArgumentError, ~r/unknown pagination option/, fn ->
      Page.stream(first, max_itmes: 1)
    end
  end

  test "numbered wire envelopes cast items and retain unknown metadata" do
    operation = DodoPayments.Operation.fetch!(:products_list)
    fetch = fn _override -> :done end

    decoded = %{
      "items" => [%{"product_id" => "pdt_1", "name" => "Starter"}],
      "page_number" => 0,
      "page_size" => 1,
      "total_count" => 2,
      "future_field" => "preserved"
    }

    assert {:ok,
            %Numbered{
              items: [%DodoPayments.Product{product_id: "pdt_1"}],
              number: 0,
              next_number: 1,
              extra: %{"future_field" => "preserved"}
            }} = Page.from_response(operation, decoded, fetch)
  end

  test "cursor wire envelopes map prev_iterator without leaking it into extra" do
    operation = DodoPayments.Operation.fetch!(:webhook_endpoints_list)
    fetch = fn _override -> :done end

    decoded = %{
      "data" => [%{"id" => "wh_1"}],
      "iterator" => "next",
      "prev_iterator" => "previous",
      "done" => false
    }

    assert {:ok,
            %Cursor{
              iterator: "next",
              prev_iterator: "previous",
              done?: false,
              extra: %{}
            }} = Page.from_response(operation, decoded, fetch)

    terminal = %{"data" => [], "iterator" => "", "prev_iterator" => "", "done" => true}

    assert {:ok,
            %Cursor{
              iterator: nil,
              prev_iterator: nil,
              done?: true,
              extra: %{}
            }} = Page.from_response(operation, terminal, fetch)

    assert :done =
             operation
             |> Page.from_response(terminal, fetch)
             |> then(fn {:ok, page} -> Page.next(page) end)
  end

  test "invalid wire envelopes return traversal errors as data" do
    operation = DodoPayments.Operation.fetch!(:products_list)

    assert {:error, %TraversalError{reason: {:invalid_page_response, _reason}}} =
             Page.from_response(operation, %{"items" => :not_a_list}, fn _ -> :done end)

    assert {:error, %TraversalError{} = error} =
             Page.from_response(
               operation,
               %{"items" => "SENTINEL_CUSTOMER_DATA"},
               fn _ -> :done end
             )

    refute Exception.message(error) =~ "SENTINEL_CUSTOMER_DATA"
    refute inspect(error) =~ "SENTINEL_CUSTOMER_DATA"
  end

  test "manual traversal reports missing fetchers and non-advancing numbered pages" do
    assert {:error, %TraversalError{reason: :missing_fetcher}} =
             Page.next(Numbered.new([], 0, has_more?: true, next_number: 1))

    assert {:error, %TraversalError{reason: :page_did_not_advance}} =
             Page.next(
               Numbered.new([], 1,
                 has_more?: true,
                 next_number: 1,
                 fetch_next: fn _ -> :done end
               )
             )
  end

  test "page streams terminate normally and wrap traversal failures" do
    fetch = fn 1 -> {:ok, Numbered.new([1], 1, has_more?: false)} end
    first = Numbered.new([0], 0, has_more?: true, next_number: 1, fetch_next: fetch)
    assert Enum.to_list(Page.stream(first)) == [0, 1]

    failing =
      Numbered.new([0], 0,
        has_more?: true,
        next_number: 1,
        fetch_next: fn _ -> {:error, RuntimeError.exception("failed")} end
      )

    assert_raise TraversalError, fn -> Enum.to_list(Page.stream(failing)) end
  end

  test "pagination error messages do not embed arbitrary callback values" do
    first =
      Numbered.new([], 0,
        has_more?: true,
        next_number: 1,
        fetch_next: fn _ -> {:invalid, "SENTINEL_PAGE_SECRET"} end
      )

    assert {:error, %TraversalError{} = error} = Page.next(first)
    refute Exception.message(error) =~ "SENTINEL_PAGE_SECRET"
  end
end
