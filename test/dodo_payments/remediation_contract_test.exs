defmodule DodoPayments.RemediationContractTest do
  use ExUnit.Case, async: true

  alias DodoPayments.Error
  alias DodoPayments.Page
  alias DodoPayments.Page.{Numbered, TraversalError}
  alias DodoPayments.TestSupport

  test "explicit nil page numbers fail before transport" do
    client = TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error,
            %DodoPayments.ValidationError{
              operation: :products_list,
              field: :page_number,
              reason: :invalid_page_number
            }} = DodoPayments.Products.list(client, %{page_number: nil})
  end

  test "empty path identifiers fail before transport" do
    client = TestSupport.client(fn _request -> flunk("transport must not run") end)

    assert {:error,
            %DodoPayments.ValidationError{
              operation: :products_retrieve,
              field: :id,
              reason: :invalid_path_value
            }} = DodoPayments.Products.retrieve(client, "")
  end

  test "JSON operations cannot declare bodyless success statuses" do
    assert_raise ArgumentError, ~r/cannot decode a bodyless success status as JSON/, fn ->
      DodoPayments.Operation.new(:invalid_json_status, :post, "/invalid",
        success_statuses: [201, 204]
      )
    end

    operation =
      DodoPayments.Operation.new(:valid_empty_status, :post, "/valid", response_mode: :empty)

    assert 204 in operation.success_statuses
  end

  test "unexpected bodyless mutation success remains outcome-unknown" do
    transport = fn _request -> TestSupport.response(204, "") end

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :products_create,
              reason: {:unexpected_success_status, 204},
              status: 204,
              attempts: 1
            }} =
             DodoPayments.Products.create(TestSupport.client(transport), %{
               name: "Bodyless product",
               price: %{currency: "USD", price: 100, type: "one_time_price"},
               tax_category: "digital_products"
             })
  end

  test "lazy pagination exposes a safe underlying API failure category" do
    error = Error.APIError.exception(status: 503, body: %{"secret" => "redacted"})
    first = Numbered.new([:first], 0, has_more?: true, fetch_next: fn _ -> {:error, error} end)

    raised =
      assert_raise TraversalError, ~r/next-page request returned HTTP 503/, fn ->
        first |> Page.pages() |> Enum.to_list()
      end

    assert raised.reason == error
    assert inspect(raised) =~ "DodoPayments.Error.APIError"
    refute Exception.message(raised) =~ "secret"
    refute inspect(raised) =~ "secret"
  end

  test "safe error summaries exclude retained raw diagnostics" do
    error =
      Error.APIError.exception(
        status: 400,
        body: %{"secret" => "SENTINEL_BODY"},
        headers: [{"authorization", "SENTINEL_HEADER"}],
        request_id: "req_123"
      )

    assert Error.safe_summary(error) == %{
             category: :api_error,
             status: 400,
             request_id: "req_123"
           }

    encoded = Jason.encode!(Error.safe_summary(error))
    refute encoded =~ "SENTINEL_BODY"
    refute encoded =~ "SENTINEL_HEADER"
  end
end
