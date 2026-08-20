defmodule DodoPayments.RequestPolicyTest do
  use ExUnit.Case, async: false

  alias DodoPayments.Error
  alias DodoPayments.TestSupport

  test "safe reads retry an uncertain transient failure" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1,
        do: TestSupport.transport(:closed),
        else: TestSupport.response(200, ~s({"product_id":"pdt_1","name":"Starter"}))
    end

    assert {:ok, %DodoPayments.Product{product_id: "pdt_1"}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    assert Agent.get(attempts, & &1) == 2
  end

  test "safe reads retry HTTP statuses and stop at the configured budget" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1,
        do: TestSupport.response(503, ~s({"code":"busy"})),
        else: TestSupport.response(200, ~s({"product_id":"pdt_1"}))
    end

    assert {:ok, %DodoPayments.Product{product_id: "pdt_1"}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    assert Agent.get(attempts, & &1) == 2

    always_busy = fn _request -> TestSupport.response(503, ~s({"code":"busy"})) end

    assert {:error, %Error.APIError{status: 503, code: "busy"}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(always_busy, max_attempts: 2),
               "pdt_1"
             )
  end

  test "exhausted server errors remain indeterminate for idempotent mutations" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      Agent.update(attempts, &(&1 + 1))

      TestSupport.response(503, ~s({"code":"temporarily_unavailable"}), [
        {"x-request-id", "req_503"}
      ])
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-credit-1"
    }

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :customer_wallet_ledger_entries_create,
              status: 503,
              request_id: "req_503",
              attempts: 2,
              replay: :identical_only
            } = error} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport, max_attempts: 2),
               "cus_1",
               params
             )

    assert Agent.get(attempts, & &1) == 2
    assert Exception.message(error) =~ "retry only as an identical replay"
    assert Exception.message(error) =~ "idempotency_key"
    assert inspect(error) =~ "replay: :identical_only"
  end

  test "logical-stop telemetry exposes bounded outcome replay guidance" do
    parent = self()
    handler_id = "outcome-stop-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:dodo_payments, :request, :stop],
        &__MODULE__.handle_outcome_telemetry/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    transport = fn _request ->
      TestSupport.response(503, "{}", [{"x-request-id", "req_outcome"}])
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-telemetry-1"
    }

    assert {:error, %Error.OutcomeUnknown{replay: :identical_only}} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport, max_attempts: 1),
               "cus_1",
               params
             )

    assert_receive {:telemetry, [:dodo_payments, :request, :stop], %{duration: duration},
                    %{
                      result: {:error, Error.OutcomeUnknown},
                      error_category: :outcome_unknown,
                      outcome_replay: :identical_only,
                      status: 503,
                      request_id: "req_outcome",
                      attempts: 1
                    }}

    assert is_integer(duration)
  end

  test "an ambiguous server error without a stable idempotency value is unsafe to replay" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)
      TestSupport.response(500, ~s({"code":"internal"}))
    end

    params = %{amount: 100, currency: "USD", entry_type: "credit"}

    assert {:error,
            %Error.OutcomeUnknown{
              status: 500,
              attempts: 1,
              replay: :unsafe
            } = error} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport),
               "cus_1",
               params
             )

    assert Exception.message(error) =~ "do not repeat it before reconciliation"
    assert_received :attempt
    refute_received :attempt
  end

  test "a conclusive application error remains an API error for an idempotent mutation" do
    transport = fn _request -> TestSupport.response(409, ~s({"code":"duplicate_entry"})) end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-duplicate-1"
    }

    assert {:error, %Error.APIError{status: 409, code: "duplicate_entry"}} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport),
               "cus_1",
               params
             )
  end

  test "an ambiguous server response that consumes the retry deadline remains indeterminate" do
    transport = fn _request ->
      TestSupport.response(503, "{}", [{"retry-after", "2"}])
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-credit-deadline"
    }

    assert {:error,
            %Error.OutcomeUnknown{
              status: 503,
              attempts: 1,
              replay: :identical_only
            }} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport, timeout: 50),
               "cus_1",
               params
             )
  end

  test "retry-after is honored and preserves a response when no retry can fit" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1,
        do: TestSupport.response(429, "{}", [{"retry-after", "0"}]),
        else: TestSupport.response(200, ~s({"product_id":"pdt_1"}))
    end

    assert {:ok, %DodoPayments.Product{}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    too_late = fn _request -> TestSupport.response(503, "{}", [{"retry-after", "2"}]) end

    assert {:error, %Error.APIError{status: 503}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(too_late, timeout: 50),
               "pdt_1"
             )
  end

  test "retry telemetry is emitted only after the delay fits the deadline" do
    parent = self()
    handler_id = "retry-event-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:dodo_payments, :request, :retry],
        &__MODULE__.handle_retry_telemetry/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    too_late = fn _request -> TestSupport.response(503, "{}", [{"retry-after", "2"}]) end

    assert {:error, %Error.APIError{status: 503}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(too_late, timeout: 50),
               "pdt_1"
             )

    refute_received {:retry, _measurements}

    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
        1 -> TestSupport.response(503, "{}", [{"retry-after", "0"}])
        2 -> TestSupport.response(200, ~s({"product_id":"pdt_1"}))
      end
    end

    assert {:ok, %DodoPayments.Product{product_id: "pdt_1"}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    assert_received {:retry, %{attempt: 1, delay: 0}}
  end

  test "retry telemetry leaves budget for the dispatched retry attempt" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)
    parent = self()
    suffix = System.unique_integer([:positive])
    retry_handler = "slow-retry-boundary-#{suffix}"
    attempt_handler = "attempt-boundary-#{suffix}"

    :ok =
      :telemetry.attach(
        retry_handler,
        [:dodo_payments, :request, :retry],
        &__MODULE__.handle_slow_telemetry/4,
        100
      )

    :ok =
      :telemetry.attach(
        attempt_handler,
        [:dodo_payments, :request, :attempt, :start],
        &__MODULE__.handle_outcome_telemetry/4,
        parent
      )

    on_exit(fn ->
      :telemetry.detach(retry_handler)
      :telemetry.detach(attempt_handler)
    end)

    transport = fn _request ->
      Agent.update(attempts, &(&1 + 1))
      TestSupport.response(503, "{}")
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "retry-boundary-accounting"
    }

    assert {:error, %Error.OutcomeUnknown{attempts: 2}} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport,
                 timeout: 30,
                 max_attempts: 2,
                 retry_base_delay: 0,
                 retry_max_delay: 0
               ),
               "cus_1",
               params
             )

    assert Agent.get(attempts, & &1) == 2

    assert_received {:telemetry, [:dodo_payments, :request, :attempt, :start], %{attempt: 1}, _}

    assert_received {:telemetry, [:dodo_payments, :request, :attempt, :start], %{attempt: 2}, _}
  end

  test "retry-after accepts the standard HTTP date form" do
    retry_at = DateTime.add(DateTime.utc_now(), 5, :second)
    value = Calendar.strftime(retry_at, "%a, %d %b %Y %H:%M:%S GMT")

    response = %DodoPayments.HTTP.Response{
      status: 503,
      headers: [{"retry-after", value}],
      body: ""
    }

    delay =
      DodoPayments.Request.RetryPolicy.delay(
        TestSupport.client(fn _request -> TestSupport.response(200, "{}") end),
        1,
        response
      )

    assert delay in 3_000..5_000
  end

  test "retry backoff saturates before calculating an extreme exponent" do
    client =
      TestSupport.client(fn _request -> TestSupport.response(200, "{}") end,
        retry_base_delay: 100,
        retry_max_delay: 1_000
      )

    delay = DodoPayments.Request.RetryPolicy.delay(client, 1_000_000, nil)
    assert delay in 0..1_000
  end

  test "unsafe mutations do not retry when delivery is unknown" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)
      TestSupport.transport(:timeout)
    end

    assert {:error,
            %Error.OutcomeUnknown{
              attempts: 1,
              operation: :refunds_create,
              replay: :unsafe
            }} =
             DodoPayments.Refunds.create(TestSupport.client(transport), %{payment_id: "pay_1"})

    assert_received :attempt
    refute_received :attempt
  end

  test "idempotent usage ingestion retries only with stable event ids" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1,
        do: TestSupport.transport(:closed),
        else: TestSupport.response(200, ~s({"ingested_count":1}))
    end

    event = %{event_id: "evt_1", customer_id: "cus_1", event_name: "api_call"}

    assert {:ok, %DodoPayments.UsageEventIngestResponse{ingested_count: 1, extra: %{}}} =
             DodoPayments.UsageEvents.ingest(TestSupport.client(transport), %{events: [event]})

    assert Agent.get(attempts, & &1) == 2
  end

  test "exhausted uncertain transport remains indeterminate for idempotent mutations" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      Agent.update(attempts, &(&1 + 1))
      TestSupport.transport(:closed)
    end

    event = %{event_id: "evt_transport", customer_id: "cus_1", event_name: "api_call"}

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :usage_events_ingest,
              attempts: 2,
              replay: :identical_only
            }} =
             DodoPayments.UsageEvents.ingest(
               TestSupport.client(transport, max_attempts: 2),
               %{events: [event]}
             )

    assert Agent.get(attempts, & &1) == 2
  end

  test "safe previews retain an API error after exhausting server-error retries" do
    transport = fn _request -> TestSupport.response(503, ~s({"code":"busy"})) end

    assert {:error, %Error.APIError{status: 503, code: "busy"}} =
             DodoPayments.CheckoutSessions.preview(
               TestSupport.client(transport, max_attempts: 2),
               %{product_cart: [%{product_id: "pdt_1", quantity: 1}]}
             )
  end

  test "operation-idempotent mutations still report ambiguous outcomes" do
    transport = fn _request -> TestSupport.response(503, ~s({"code":"busy"})) end

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :discount_customers_attach,
              status: 503,
              replay: :identical_only
            }} =
             DodoPayments.Discounts.attach_customers(
               TestSupport.client(transport, max_attempts: 1),
               "dis_1",
               %{customer_ids: ["cus_1"]}
             )
  end

  test "typed successful responses require JSON objects" do
    for body <- ["", "null", ~s("oops"), "[]"] do
      transport = fn _request -> TestSupport.response(201, body) end

      assert {:error,
              %Error.OutcomeUnknown{
                operation: :products_create,
                status: 201,
                attempts: 1
              }} =
               DodoPayments.Products.create(TestSupport.client(transport), %{
                 name: "Typed response boundary",
                 price: %{currency: "USD", price: 100, type: "one_time_price"},
                 tax_category: "digital_products"
               })
    end
  end

  test "typed pagination rejects non-object items" do
    transport = fn _request -> TestSupport.response(200, ~s({"items":["not-an-object"]})) end

    assert {:error, %DodoPayments.Page.TraversalError{}} =
             DodoPayments.Products.list(TestSupport.client(transport))
  end

  test "webhook creation replays only with a stable idempotency key" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1,
        do: TestSupport.transport(:closed),
        else: TestSupport.response(200, ~s({"id":"wh_1","url":"https://example.invalid/hook"}))
    end

    assert {:ok, %DodoPayments.WebhookEndpoint{id: "wh_1", extra: %{}}} =
             DodoPayments.WebhookEndpoints.create(TestSupport.client(transport), %{
               url: "https://example.invalid/hook",
               idempotency_key: "webhook-setup-1"
             })

    assert Agent.get(attempts, & &1) == 2

    assert {:error, %Error.OutcomeUnknown{replay: :unsafe, attempts: 1}} =
             DodoPayments.WebhookEndpoints.create(
               TestSupport.client(fn _request -> TestSupport.transport(:closed) end),
               %{url: "https://example.invalid/hook"}
             )
  end

  test "change plan accepts the upstream empty response contract" do
    parent = self()

    transport = fn request ->
      send(parent, {:change_plan_headers, request.headers})
      TestSupport.response(200, "accepted")
    end

    assert {:ok, nil} =
             DodoPayments.Subscriptions.change_plan(
               TestSupport.client(transport),
               "sub_1",
               %{product_id: "pdt_1", proration_billing_mode: "none", quantity: 1}
             )

    assert_received {:change_plan_headers, headers}
    assert List.keyfind(headers, "accept", 0) == {"accept", "*/*"}
  end

  test "an unreadable successful unsafe response requires reconciliation" do
    transport = fn _request ->
      TestSupport.response(201, "not-json", [{"x-request-id", "req_1"}])
    end

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :checkout_sessions_create,
              status: 201,
              request_id: "req_1",
              attempts: 1
            }} =
             DodoPayments.CheckoutSessions.create(TestSupport.client(transport), %{
               product_cart: [%{product_id: "pdt_1", quantity: 1}]
             })
  end

  test "an unreadable successful idempotent mutation permits only identical replay" do
    transport = fn _request ->
      TestSupport.response(200, "not-json", [{"x-request-id", "req_idempotent"}])
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-unreadable-1"
    }

    assert {:error,
            %Error.OutcomeUnknown{
              status: 200,
              request_id: "req_idempotent",
              replay: :identical_only
            }} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport),
               "cus_1",
               params
             )
  end

  test "an unreadable successful safe response is a decode error" do
    transport = fn _request -> TestSupport.response(200, "not-json") end

    assert {:error, %Error.DecodeError{status: 200}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")
  end

  test "API errors extract codes and bound untrusted message fragments" do
    code = "\e[31m" <> String.duplicate("X", 1_000)

    transport = fn _request ->
      TestSupport.response(400, Jason.encode!(%{"error" => %{"code" => code}}), [
        {"x-request-id", "req_1"}
      ])
    end

    assert {:error, %Error.APIError{status: 400, code: ^code, request_id: "req_1"} = error} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    assert byte_size(Exception.message(error)) < 300
    refute Exception.message(error) =~ "\e[31m"
    refute inspect(error) =~ String.duplicate("X", 200)
  end

  test "successful response envelopes retain response metadata" do
    transport = fn _request ->
      TestSupport.response(200, ~s({"product_id":"pdt_1"}), [{"x-request-id", "req_ok"}])
    end

    assert {:ok,
            %DodoPayments.Response{
              data: %DodoPayments.Product{product_id: "pdt_1"},
              status: 200,
              request_id: "req_ok",
              headers: [{"x-request-id", "req_ok"}]
            }} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport),
               "pdt_1",
               return: :response
             )
  end

  test "public auth and non-JSON response modes use the expected wire contract" do
    parent = self()

    transport = fn request ->
      send(parent, {:wire, request.url, request.headers})

      cond do
        String.ends_with?(request.url, "/checkout/supported_countries") ->
          TestSupport.response(200, ~s(["US","IN","FUTURE_COUNTRY"]))

        String.ends_with?(request.url, "/csv") ->
          TestSupport.response(200, "a,b\n1,2")

        true ->
          TestSupport.response(200, "%PDF-1.7")
      end
    end

    client = TestSupport.client(transport, api_key: nil)

    assert {:ok,
            [
              :us,
              :in,
              %DodoPayments.UnknownEnum{enum: :country_code, value: "FUTURE_COUNTRY"}
            ]} = DodoPayments.SupportedCountries.list(client)

    assert_received {:wire, _, public_headers}
    refute List.keymember?(public_headers, "authorization", 0)

    merchant = TestSupport.client(transport)
    assert {:ok, "a,b\n1,2"} = DodoPayments.Payouts.download_breakup_csv(merchant, "po_1")
    assert_received {:wire, _, csv_headers}
    assert List.keyfind(csv_headers, "accept", 0) == {"accept", "text/csv"}

    assert {:ok, "%PDF-1.7"} = DodoPayments.Invoices.download_payment(client, "pay_1")
    assert_received {:wire, _, pdf_headers}
    assert List.keyfind(pdf_headers, "accept", 0) == {"accept", "application/pdf"}
  end

  test "non-paginated object arrays cast every item and reject the wrong envelope shape" do
    valid = fn _request ->
      TestSupport.response(200, ~s([{"event_type":"payment","total":120}]))
    end

    assert {:ok, [%DodoPayments.PayoutBreakupItem{event_type: "payment", total: 120}]} =
             DodoPayments.Payouts.retrieve_breakup(TestSupport.client(valid), "pyt_1")

    invalid = fn _request -> TestSupport.response(200, ~s({"items":[]})) end

    assert {:error, %Error.DecodeError{reason: :expected_json_array}} =
             DodoPayments.SupportedCountries.list(TestSupport.client(invalid, api_key: nil))
  end

  test "request-local headers cannot override transport safety policy" do
    parent = self()

    transport = fn request ->
      send(parent, {:prepared_headers, request.headers})
      TestSupport.response(200, ~s({"product_id":"pdt_1"}))
    end

    client = TestSupport.client(transport)

    assert {:ok, %DodoPayments.Product{}} =
             DodoPayments.Products.retrieve(client, "pdt_1",
               headers: [
                 {"Cookie", "SENTINEL_COOKIE"},
                 {"X-Api-Key", "SENTINEL_KEY"},
                 {"Proxy-Authorization", "SENTINEL_PROXY"},
                 {"Accept-Encoding", "gzip"},
                 {"Content-Length", "0"},
                 {"Transfer-Encoding", "chunked"},
                 {"Host", "other.invalid"},
                 {:x_auth_token, "SENTINEL_ATOM_TOKEN"},
                 {:proxy_authorization, "SENTINEL_ATOM_PROXY"},
                 {:accept_encoding, "br"},
                 {:content_length, "0"},
                 {:transfer_encoding, "chunked"},
                 {"X-Trace", ["one", "two"]}
               ]
             )

    assert_received {:prepared_headers, headers}
    names = MapSet.new(headers, fn {name, _value} -> String.downcase(name) end)

    refute MapSet.member?(names, "cookie")
    refute MapSet.member?(names, "x-api-key")
    refute MapSet.member?(names, "proxy-authorization")
    refute MapSet.member?(names, "accept-encoding")
    refute MapSet.member?(names, "content-length")
    refute MapSet.member?(names, "transfer-encoding")
    refute MapSet.member?(names, "host")
    refute MapSet.member?(names, "x_auth_token")
    refute MapSet.member?(names, "proxy_authorization")
    refute MapSet.member?(names, "accept_encoding")

    assert Enum.filter(headers, &(elem(&1, 0) == "X-Trace")) == [
             {"X-Trace", "one"},
             {"X-Trace", "two"}
           ]

    for invalid <- [
          :bad,
          [{"x-test", %{invalid: true}}],
          [:not_a_pair],
          [{"", "value"}],
          [{"bad name", "value"}],
          [{"x-test", "one\r\ntwo"}],
          [{"x-test", "ok\0bad"}],
          [{"x-test", <<1>>}],
          [{"x-test", <<127>>}],
          [{"x-test", :"one\r\ntwo"}],
          [{"x-test", ["one" | :tail]}],
          [{"x-test", "one"} | :tail]
        ] do
      assert {:error, %Error.ConfigurationError{}} =
               DodoPayments.Products.retrieve(client, "pdt_1", headers: invalid)
    end
  end

  test "custom adapters are defensively checked against the body limit" do
    transport = fn _request -> TestSupport.response(200, String.duplicate("x", 9)) end

    assert {:error, %Error.ResponseTooLarge{limit: 8, status: 200}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport, max_response_bytes: 8),
               "pdt_1"
             )
  end

  test "oversized successful responses remain indeterminate for safe consequential mutations" do
    transport = fn _request ->
      TestSupport.response(200, String.duplicate("x", 9), [{"x-request-id", "req_safe"}])
    end

    calls = [
      fn client ->
        DodoPayments.Discounts.attach_customers(client, "dis_1", %{
          customer_ids: ["cus_1"]
        })
      end,
      fn client -> DodoPayments.EntitlementGrants.revoke(client, "ent_1", "grant_1") end
    ]

    for call <- calls do
      assert {:error,
              %Error.OutcomeUnknown{
                status: 200,
                request_id: "req_safe",
                attempts: 1,
                replay: :identical_only
              }} =
               call.(TestSupport.client(transport, max_response_bytes: 8, max_attempts: 1))
    end
  end

  test "oversized ambiguous mutation responses require reconciliation and retain telemetry" do
    parent = self()
    handler_id = "overflow-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:dodo_payments, :request, :attempt, :stop],
        &__MODULE__.handle_telemetry/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    transport = fn _request ->
      TestSupport.response(500, String.duplicate("x", 9), [{"x-request-id", "req_500"}])
    end

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :refunds_create,
              status: 500,
              request_id: "req_500",
              attempts: 1
            }} =
             DodoPayments.Refunds.create(
               TestSupport.client(transport, max_response_bytes: 8, max_attempts: 1),
               %{payment_id: "pay_1"}
             )

    assert_receive {:telemetry, [:dodo_payments, :request, :attempt, :stop], %{attempt: 1},
                    %{
                      error_category: :response_too_large,
                      status: 500,
                      request_id: "req_500"
                    }}
  end

  test "overflow classification distinguishes ambiguous and conclusive mutation statuses" do
    for status <- [408, 503] do
      transport = fn _request ->
        TestSupport.response(status, String.duplicate("x", 9), [
          {"x-request-id", "req_#{status}"}
        ])
      end

      assert {:error, %Error.OutcomeUnknown{status: ^status}} =
               DodoPayments.Refunds.create(
                 TestSupport.client(transport, max_response_bytes: 8, max_attempts: 1),
                 %{payment_id: "pay_1"}
               )
    end

    transport = fn _request -> TestSupport.response(400, String.duplicate("x", 9)) end

    assert {:error, %Error.ResponseTooLarge{status: 400}} =
             DodoPayments.Refunds.create(
               TestSupport.client(transport, max_response_bytes: 8, max_attempts: 1),
               %{payment_id: "pay_1"}
             )
  end

  test "invalid atom response headers are contained at the adapter boundary" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)

      TestSupport.response(200, "{}", [{:x_request_id, "req_atom"}])
    end

    assert {:error,
            %Error.TransportError{
              reason: {:invalid_client_module_result, %DodoPayments.HTTP.Response{}},
              attempts: 1
            }} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport, max_attempts: 3),
               "pdt_1",
               return: :response
             )

    assert_received :attempt
    refute_received :attempt
  end

  test "improper adapter header lists are invalid results and are not retried" do
    parent = self()
    improper_headers = [{"x-request-id", "req_improper"} | :tail]

    results = [
      TestSupport.response(200, "{}", improper_headers),
      TestSupport.transport(:closed, :unknown, %{status: 200, headers: improper_headers})
    ]

    for result <- results do
      transport = fn _request ->
        send(parent, :attempt)
        result
      end

      assert {:error,
              %Error.TransportError{
                reason: {:invalid_client_module_result, _invalid},
                attempts: 1
              }} =
               DodoPayments.Products.retrieve(
                 TestSupport.client(transport, max_attempts: 3),
                 "pdt_1"
               )

      assert_received :attempt
      refute_received :attempt
    end
  end

  test "request-local timeouts reject values above the BEAM timer ceiling" do
    transport = fn _request -> flunk("transport must not run") end
    maximum = DodoPayments.Deadline.max_timeout()

    assert {:error, %Error.ConfigurationError{message: message}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport),
               "pdt_1",
               timeout: maximum + 1
             )

    assert message =~ "between 1 and #{maximum}"
  end

  test "invalid adapter results are not retried" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)
      :invalid
    end

    assert {:error, %Error.TransportError{attempts: 1}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "pdt_1")

    assert_received :attempt
    refute_received :attempt
  end

  test "invalid adapter results for non-replayable conditional mutations require reconciliation" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)
      :invalid_after_delivery
    end

    params = %{amount: 100, currency: "USD", entry_type: "credit"}

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :customer_wallet_ledger_entries_create,
              attempts: 1
            }} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport),
               "cus_1",
               params
             )

    assert_received :attempt
    refute_received :attempt
  end

  test "the logical deadline bounds a slow safe adapter" do
    transport = fn _request ->
      Process.sleep(100)
      TestSupport.response(200, "{}")
    end

    assert {:error, %Error.TimeoutError{timeout: 10}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport, timeout: 10),
               "pdt_1"
             )
  end

  test "logical telemetry consumes the shared deadline" do
    parent = self()
    handler_id = "slow-logical-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:dodo_payments, :request, :start],
        &__MODULE__.handle_slow_telemetry/4,
        100
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    transport = fn _request ->
      send(parent, :adapter_called)
      TestSupport.response(200, ~s({"product_id":"pdt_1"}))
    end

    assert {:error, %Error.TimeoutError{timeout: 10}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport, timeout: 10),
               "pdt_1"
             )

    refute_received :adapter_called
  end

  test "slow attempt telemetry preserves a successful result and emits the paired stop event" do
    parent = self()
    handler_id = "slow-attempt-pair-#{System.unique_integer([:positive])}"

    events = [
      [:dodo_payments, :request, :attempt, :start],
      [:dodo_payments, :request, :attempt, :stop]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_slow_attempt_start/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    transport = fn _request ->
      send(parent, :adapter_called)
      TestSupport.response(200, ~s({"product_id":"pdt_1"}))
    end

    result =
      DodoPayments.Products.retrieve(
        TestSupport.client(transport, timeout: 500),
        "pdt_1"
      )

    assert {:ok, %DodoPayments.Product{product_id: "pdt_1"}} = result

    assert_received :adapter_called
    assert_received {:attempt_event, [:dodo_payments, :request, :attempt, :start]}
    assert_received {:attempt_event, [:dodo_payments, :request, :attempt, :stop]}
  end

  test "a decode deadline after a successful mutation remains indeterminate" do
    parent = self()
    handler_id = "slow-attempt-stop-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:dodo_payments, :request, :attempt, :stop],
        &__MODULE__.handle_slow_telemetry/4,
        100
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    transport = fn _request ->
      send(parent, :successful_mutation_response)
      TestSupport.response(201, ~s({"product_id":"pdt_1"}), [{"x-request-id", "req_decode"}])
    end

    result =
      DodoPayments.Products.create(
        TestSupport.client(transport, timeout: 10),
        %{
          name: "Deadline product",
          price: %{currency: "USD", price: 100, type: "one_time_price"},
          tax_category: "digital_products"
        }
      )

    receive do
      :successful_mutation_response ->
        assert match?(
                 {:error,
                  %Error.OutcomeUnknown{
                    operation: :products_create,
                    status: 201,
                    request_id: "req_decode",
                    attempts: 1
                  }},
                 result
               )
    after
      0 ->
        assert match?({:error, %Error.TimeoutError{operation: :products_create}}, result)
    end
  end

  test "path parameters reject dot segments before transport" do
    transport = fn _request -> flunk("transport must not run") end
    client = TestSupport.client(transport)

    for segment <- [".", ".."] do
      assert {:error,
              %DodoPayments.ValidationError{
                operation: :products_retrieve,
                field: :id,
                reason: :invalid_path_value
              }} = DodoPayments.Products.retrieve(client, segment)
    end
  end

  test "percent-looking path values are encoded as data rather than dot segments" do
    parent = self()

    transport = fn request ->
      send(parent, {:url, request.url})
      TestSupport.response(200, ~s({"product_id":"%2e"}))
    end

    assert {:ok, %DodoPayments.Product{product_id: "%2e"}} =
             DodoPayments.Products.retrieve(TestSupport.client(transport), "%2e")

    assert_received {:url, "https://dodo.invalid/products/%252e"}
  end

  test "a hard-killed custom client is contained by the deadline supervisor" do
    transport = fn _request -> Process.exit(self(), :kill) end

    assert {:error, %Error.TimeoutError{operation: :products_retrieve}} =
             DodoPayments.Products.retrieve(
               TestSupport.client(transport, max_attempts: 1),
               "pdt_1"
             )
  end

  test "provider crashes retain a redacted diagnostic cause and stacktrace" do
    transport = fn _request -> flunk("transport must not run") end

    client =
      TestSupport.client(transport,
        api_key: fn -> raise "SENTINEL_PROVIDER_SECRET" end
      )

    assert {:error,
            %Error.PreparationError{
              operation: :api_key_provider,
              kind: :error,
              cause: %RuntimeError{},
              stacktrace: [_ | _]
            } = error} = DodoPayments.Products.retrieve(client, "pdt_1")

    refute Exception.message(error) =~ "SENTINEL_PROVIDER_SECRET"
    refute inspect(error) =~ "SENTINEL_PROVIDER_SECRET"
  end

  test "runtime key providers cannot inject bytes the transport cannot encode" do
    transport = fn _request -> flunk("transport must not run") end

    for key <- ["sk_runtime\r\nx-injected: yes", <<255>>] do
      client = TestSupport.client(transport, api_key: fn -> key end)

      assert {:error, %Error.ConfigurationError{message: message}} =
               DodoPayments.Products.retrieve(client, "pdt_1")

      assert message =~ "ASCII"
    end
  end

  test "request options reject misspellings before transport" do
    transport = fn _request -> flunk("transport must not run") end

    assert {:error, %Error.ConfigurationError{message: message}} =
             DodoPayments.Products.list(TestSupport.client(transport), retrun: :response)

    assert message =~ ":retrun"
  end

  test "non-string idempotency values never make a mutation replayable" do
    parent = self()

    transport = fn _request ->
      send(parent, :attempt)
      TestSupport.transport(:closed)
    end

    params = %{amount: 100, currency: "USD", entry_type: "credit", idempotency_key: false}

    assert {:error, %Error.OutcomeUnknown{attempts: 1}} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport),
               "cus_1",
               params
             )

    assert_received :attempt
    refute_received :attempt
  end

  test "OutcomeUnknown wording remains accurate after proven-not-sent retries" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      delivery = if attempt == 1, do: :not_sent, else: :unknown
      TestSupport.transport(:closed, delivery)
    end

    assert {:error, %Error.OutcomeUnknown{attempts: 2} = error} =
             DodoPayments.Refunds.create(
               TestSupport.client(transport, max_attempts: 2),
               %{payment_id: "pay_1"}
             )

    assert Exception.message(error) =~ "after 2 attempt(s)"
    refute Exception.message(error) =~ "did not retry"
  end

  test "an earlier ambiguous delivery remains unknown after a later proven-not-sent failure" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      delivery = if attempt == 1, do: :unknown, else: :not_sent
      TestSupport.transport(:closed, delivery)
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-uncertainty-history"
    }

    assert {:error,
            %Error.OutcomeUnknown{
              operation: :customer_wallet_ledger_entries_create,
              attempts: 2,
              replay: :identical_only
            }} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport, max_attempts: 2),
               "cus_1",
               params
             )

    assert Agent.get(attempts, & &1) == 2
  end

  test "an earlier ambiguous server response is not erased by a later application error" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    transport = fn _request ->
      case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
        1 -> TestSupport.response(503, "{}", [{"x-request-id", "req_ambiguous"}])
        2 -> TestSupport.response(409, ~s({"code":"duplicate"}))
      end
    end

    params = %{
      amount: 100,
      currency: "USD",
      entry_type: "credit",
      idempotency_key: "wallet-http-history"
    }

    assert {:error,
            %Error.OutcomeUnknown{
              status: 503,
              request_id: "req_ambiguous",
              attempts: 2,
              replay: :identical_only
            }} =
             DodoPayments.Customers.Wallets.LedgerEntries.create(
               TestSupport.client(transport, max_attempts: 2),
               "cus_1",
               params
             )

    assert Agent.get(attempts, & &1) == 2
  end

  def handle_telemetry(event, measurements, metadata, pid) do
    if metadata.operation == :refunds_create,
      do: send(pid, {:telemetry, event, measurements, metadata})
  end

  def handle_outcome_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  def handle_slow_telemetry(_event, _measurements, _metadata, milliseconds) do
    Process.sleep(milliseconds)
  end

  def handle_slow_attempt_start(event, _measurements, _metadata, pid) do
    send(pid, {:attempt_event, event})

    if event == [:dodo_payments, :request, :attempt, :start], do: Process.sleep(100)
  end

  def handle_retry_telemetry(_event, measurements, _metadata, pid) do
    send(pid, {:retry, measurements})
  end
end
