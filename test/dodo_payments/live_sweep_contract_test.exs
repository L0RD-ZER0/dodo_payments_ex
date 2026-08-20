defmodule DodoPayments.LiveSweepContractTest do
  use ExUnit.Case, async: true

  alias DodoPayments.{Page, Response, TestSupport}

  test "customer portal creation sends options in the query and redacts the returned capability" do
    parent = self()
    portal_link = "https://portal.invalid/SENTINEL_PORTAL_CAPABILITY"

    transport = fn request ->
      send(parent, {:portal_request, request})
      TestSupport.response(200, Jason.encode!(%{"link" => portal_link}))
    end

    return_url = "https://merchant.invalid/account?token=SENTINEL_RETURN_TOKEN"

    assert {:ok,
            %Response{
              data: %DodoPayments.CustomerPortalSession{link: ^portal_link} = session,
              status: 200
            } = response} =
             DodoPayments.Customers.PortalSessions.create(
               TestSupport.client(transport),
               "cus_1",
               %{return_url: return_url, send_email: true},
               return: :response
             )

    assert_received {:portal_request, request}
    uri = request.url |> to_string() |> URI.parse()

    assert request.method == :post
    assert uri.path == "/customers/cus_1/customer-portal/session"

    assert URI.decode_query(uri.query) == %{
             "return_url" => return_url,
             "send_email" => "true"
           }

    assert request.body == nil
    refute inspect(request) =~ "SENTINEL_RETURN_TOKEN"
    refute inspect(session) =~ "SENTINEL_PORTAL_CAPABILITY"
    refute inspect(response) =~ "SENTINEL_PORTAL_CAPABILITY"
  end

  test "subscription payment-method update initiation unwraps new and existing selections" do
    parent = self()

    transport = fn request ->
      body = Jason.decode!(request.body)
      send(parent, {:payment_method_request, request, body})

      TestSupport.response(
        200,
        Jason.encode!(%{
          "client_secret" => "SENTINEL_CLIENT_SECRET",
          "expires_on" => "2026-08-20T12:00:00Z",
          "payment_id" => "pay_update_1",
          "payment_link" => "https://checkout.invalid/SENTINEL_PAYMENT_LINK"
        })
      )
    end

    client = TestSupport.client(transport)

    assert {:ok,
            %DodoPayments.SubscriptionUpdatePaymentMethodResponse{
              client_secret: "SENTINEL_CLIENT_SECRET",
              expires_on: "2026-08-20T12:00:00Z",
              payment_id: "pay_update_1",
              payment_link: "https://checkout.invalid/SENTINEL_PAYMENT_LINK"
            } = new_response} =
             DodoPayments.Subscriptions.update_payment_method(client, "sub_1", %{
               payment_method: %{
                 type: :new,
                 allowed_payment_method_types: [:credit, :ach],
                 return_url: "https://merchant.invalid/billing"
               }
             })

    assert_received {:payment_method_request, new_request, new_body}
    assert new_request.method == :post

    assert URI.parse(to_string(new_request.url)).path ==
             "/subscriptions/sub_1/update-payment-method"

    assert new_body == %{
             "allowed_payment_method_types" => ["credit", "ach"],
             "return_url" => "https://merchant.invalid/billing",
             "type" => "new"
           }

    refute Map.has_key?(new_body, "payment_method")
    refute inspect(new_response) =~ "SENTINEL"

    # For `type: :new`, these checkout credentials prove only that the hosted
    # customer-action flow was initiated. They do not prove that the customer
    # completed it or that the subscription's saved method changed.

    assert {:ok,
            %Response{
              data: %DodoPayments.SubscriptionUpdatePaymentMethodResponse{} = existing_response
            } = envelope} =
             DodoPayments.Subscriptions.update_payment_method(
               client,
               "sub_2",
               %{payment_method: %{type: :existing, payment_method_id: "pm_1"}},
               return: :response
             )

    assert_received {:payment_method_request, existing_request, existing_body}

    assert URI.parse(to_string(existing_request.url)).path ==
             "/subscriptions/sub_2/update-payment-method"

    assert existing_body == %{"payment_method_id" => "pm_1", "type" => "existing"}

    refute inspect(existing_response) =~ "SENTINEL"
    refute inspect(envelope) =~ "SENTINEL"
  end

  test "dispute list and retrieve preserve string amounts while decoding known enums" do
    parent = self()

    list_item = %{
      "amount" => "1200",
      "business_id" => "bus_1",
      "created_at" => "2026-08-19T10:00:00Z",
      "currency" => "USD",
      "dispute_id" => "dsp_1",
      "dispute_stage" => "pre_dispute",
      "dispute_status" => "dispute_opened",
      "payment_id" => "pay_1",
      "payment_provider" => "dodo",
      "is_resolved_by_rdr" => false
    }

    transport = fn request ->
      uri = request.url |> to_string() |> URI.parse()
      send(parent, {:dispute_request, uri})

      body =
        case uri.path do
          "/disputes" ->
            %{
              "items" => [list_item],
              "page_number" => 0,
              "page_size" => 10,
              "total_count" => 1,
              "total_pages" => 1
            }

          "/disputes/dsp_1" ->
            Map.merge(list_item, %{
              "brand_id" => "brnd_1",
              "customer" => %{"customer_id" => "cus_1"},
              "reason" => "fraudulent",
              "remarks" => "ACH test dispute"
            })
        end

      TestSupport.response(200, Jason.encode!(body))
    end

    client = TestSupport.client(transport)

    assert {:ok, page} =
             DodoPayments.Disputes.list(client, %{
               dispute_stage: :pre_dispute,
               dispute_status: :dispute_opened
             })

    assert_received {:dispute_request, list_uri}

    assert URI.decode_query(list_uri.query) == %{
             "dispute_stage" => "pre_dispute",
             "dispute_status" => "dispute_opened"
           }

    assert [%DodoPayments.DisputeListItem{} = item] = Page.items(page)
    assert item.amount == "1200"
    assert item.currency == "USD"
    assert item.dispute_stage == :pre_dispute
    assert item.dispute_status == :dispute_opened
    assert item.payment_provider == :dodo

    assert {:ok, %DodoPayments.Dispute{} = dispute} =
             DodoPayments.Disputes.retrieve(client, "dsp_1")

    assert_received {:dispute_request, %{path: "/disputes/dsp_1", query: nil}}
    assert dispute.amount == "1200"
    assert dispute.dispute_stage == :pre_dispute
    assert dispute.dispute_status == :dispute_opened
    assert dispute.payment_provider == :dodo
    assert dispute.customer == %{"customer_id" => "cus_1"}
  end

  test "refund and existing-payout invoice downloads preserve exact unauthenticated PDF bytes" do
    parent = self()
    refund_pdf = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0, 0xFF, 1>>
    payout_pdf = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x32, 0x2E, 0x30, 0, 0xFE, 2>>

    transport = fn request ->
      uri = request.url |> to_string() |> URI.parse()
      send(parent, {:invoice_request, uri.path, request.headers})

      case uri.path do
        "/invoices/refunds/ref_1" ->
          TestSupport.response(200, refund_pdf)

        "/invoices/payouts/pyt_1" ->
          TestSupport.response(200, payout_pdf, [{"x-request-id", "req_payout_pdf"}])
      end
    end

    client = TestSupport.client(transport, api_key: "SENTINEL_MERCHANT_KEY")

    assert {:ok, ^refund_pdf} = DodoPayments.Invoices.download_refund(client, "ref_1")

    assert_received {:invoice_request, "/invoices/refunds/ref_1", refund_headers}
    assert List.keyfind(refund_headers, "accept", 0) == {"accept", "application/pdf"}
    refute List.keymember?(refund_headers, "authorization", 0)

    # The payout endpoint can only download an invoice for an already-successful
    # payout; test mode does not provide an API for synthesizing that prerequisite.
    assert {:ok,
            %Response{
              data: ^payout_pdf,
              status: 200,
              request_id: "req_payout_pdf"
            }} =
             DodoPayments.Invoices.download_payout(client, "pyt_1", return: :response)

    assert_received {:invoice_request, "/invoices/payouts/pyt_1", payout_headers}
    assert List.keyfind(payout_headers, "accept", 0) == {"accept", "application/pdf"}
    refute List.keymember?(payout_headers, "authorization", 0)
  end

  test "saved payment-method payloads retain nested string keys and future fields" do
    wire_item = %{
      "payment_method_id" => "pm_1",
      "payment_method_type" => "card",
      "is_default" => true,
      "card" => %{
        "brand" => "visa",
        "last4" => "4242",
        "expiry" => %{"month" => 12, "year" => 2030}
      },
      "future_details" => %{"network_tokenized" => true}
    }

    transport = fn _request ->
      TestSupport.response(200, Jason.encode!(%{"items" => [wire_item]}))
    end

    assert {:ok, %DodoPayments.CustomerPaymentMethodsResponse{items: [decoded]}} =
             DodoPayments.Customers.PaymentMethods.list(
               TestSupport.client(transport),
               "cus_1"
             )

    assert decoded == wire_item
    assert decoded["card"]["expiry"] == %{"month" => 12, "year" => 2030}
    refute Map.has_key?(decoded, :payment_method_id)
    refute Map.has_key?(decoded["card"], :brand)
  end
end
