defmodule DodoPayments.WebhooksTest do
  use ExUnit.Case, async: true

  alias DodoPayments.Webhooks
  alias DodoPayments.Webhooks.{Event, VerificationError}

  test "verifies the exact body and preserves unknown event types" do
    {body, headers, secret, now} = signed_event("future.event.created")

    assert {:ok,
            %Event{
              webhook_id: "wh_1",
              type: %DodoPayments.UnknownEnum{
                enum: :webhook_event_type,
                value: "future.event.created"
              },
              raw_body: ^body,
              payload: %{"type" => "future.event.created"}
            }} = Webhooks.verify(body, headers, secret, now: now)

    assert {:error, %VerificationError{reason: :invalid_signature}} =
             Webhooks.verify(body <> " ", headers, secret, now: now)
  end

  test "repeated verification is valid because the verifier is stateless" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    assert {:ok, %Event{webhook_id: "wh_1"} = first} =
             Webhooks.verify(body, headers, secret, now: now)

    assert {:ok, %Event{webhook_id: "wh_1"} = second} =
             Webhooks.verify(body, headers, secret, now: now)

    assert first == second
  end

  test "struct-shaped headers stay inside the tagged verification channel" do
    {_body, _headers, secret, _now} = signed_event("payment.succeeded")

    assert {:error, %VerificationError{reason: :missing_header}} =
             Webhooks.verify("{}", Date.utc_today(), secret)
  end

  test "all verifier option mistakes use the tagged error channel" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    invalid_options = [
      [unknown: true],
      [tolerance: -1],
      [now: :invalid],
      [now: fn -> :invalid end],
      [now: fn -> raise "boom" end],
      [max_body_bytes: 0],
      [max_header_bytes: 0],
      [max_signatures: 0],
      [max_secrets: 0],
      [max_secret_bytes: 0]
    ]

    for options <- invalid_options do
      assert {:error, %VerificationError{reason: :invalid_options}} =
               Webhooks.verify(body, headers, secret, Keyword.put_new(options, :now, now))
    end
  end

  test "bang verification raises only the documented verification exception" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    assert_raise VerificationError, fn ->
      Webhooks.verify!(body, headers, secret, now: now, max_body_bytes: 1)
    end
  end

  test "verification limits reject oversized untrusted input" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    assert {:error, %VerificationError{reason: :resource_limit}} =
             Webhooks.verify(body, headers, secret, now: now, max_body_bytes: byte_size(body) - 1)
  end

  test "malformed structured header values cannot bypass the byte-work limit" do
    for values <- [List.duplicate(123, 1_000_000), List.duplicate("", 1_000_000)] do
      headers = [{"x-untrusted", values}]

      assert {:error, %VerificationError{reason: :resource_limit}} =
               Webhooks.verify("{}", headers, "whsec_" <> Base.encode64("secret"),
                 max_header_bytes: 100
               )
    end

    assert {:error, %VerificationError{reason: :resource_limit}} =
             Webhooks.verify(
               "{}",
               [{"x", []}, {"x", []}],
               "whsec_" <> Base.encode64("secret"),
               max_header_bytes: 3
             )
  end

  test "secret count limits stop before traversing an oversized rotation list" do
    {body, headers, secret, now} = signed_event("payment.succeeded")
    secrets = List.duplicate(secret, 1_000_000)

    assert {:error, %VerificationError{reason: :resource_limit}} =
             Webhooks.verify(body, headers, secrets, now: now, max_secrets: 1)
  end

  test "improper webhook lists stay inside the verification error channel" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    assert {:error, %VerificationError{reason: :resource_limit}} =
             Webhooks.verify(body, [hd(headers) | :tail], secret, now: now)

    assert {:error, %VerificationError{reason: :resource_limit}} =
             Webhooks.verify(body, [{"webhook-id", ["wh_1" | :tail]} | tl(headers)], secret,
               now: now
             )

    assert {:error, %VerificationError{reason: :invalid_secret}} =
             Webhooks.verify(body, headers, [secret | :tail], now: now)
  end

  test "event inspection never renders webhook payload or raw body" do
    {body, headers, secret, now} = signed_event("payment.succeeded", "SENTINEL_CUSTOMER")
    assert {:ok, event} = Webhooks.verify(body, headers, secret, now: now)
    refute inspect(event) =~ "SENTINEL_CUSTOMER"
  end

  test "an empty signature header is reported as missing" do
    {body, headers, secret, now} = signed_event("payment.succeeded")
    headers = List.keyreplace(headers, "webhook-signature", 0, {"webhook-signature", ""})

    assert {:error, %VerificationError{reason: :missing_header, header: "webhook-signature"}} =
             Webhooks.verify(body, headers, secret, now: now)
  end

  test "timestamp validation rejects malformed and expired requests" do
    {body, headers, secret, now} = signed_event("payment.succeeded")

    assert {:error, %VerificationError{reason: :timestamp_outside_tolerance}} =
             Webhooks.verify(body, headers, secret, now: now + 301)

    malformed =
      List.keyreplace(headers, "webhook-timestamp", 0, {"webhook-timestamp", "not-an-integer"})

    assert {:error, %VerificationError{reason: :invalid_timestamp}} =
             Webhooks.verify(body, malformed, secret, now: now)
  end

  test "secret rotation accepts any valid configured secret and rejects malformed secrets" do
    {body, headers, secret, now} = signed_event("payment.succeeded")
    previous = "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))

    assert {:ok, %Event{}} = Webhooks.verify(body, headers, [previous, secret], now: now)
    assert :ok = Webhooks.verify_signature(body, headers, [previous, secret], now: now)

    for invalid <- ["not-prefixed", "whsec_not-base64"] do
      assert {:error, %VerificationError{reason: :invalid_secret}} =
               Webhooks.verify(body, headers, invalid, now: now)
    end
  end

  test "ambiguous headers and invalid bodies use precise error reasons" do
    {body, headers, secret, now} = signed_event("payment.succeeded")
    duplicate = [{"webhook-id", "wh_2"} | headers]

    assert {:error, %VerificationError{reason: :ambiguous_header, header: "webhook-id"}} =
             Webhooks.verify(body, duplicate, secret, now: now)

    assert {:error, %VerificationError{reason: :invalid_body}} =
             Webhooks.verify(:not_binary, headers, secret, now: now)

    {invalid_json, json_headers, json_secret, json_now} = signed_body("not-json")

    assert {:error, %VerificationError{reason: :invalid_json}} =
             Webhooks.verify(invalid_json, json_headers, json_secret, now: json_now)

    {invalid_event, event_headers, event_secret, event_now} = signed_body("{}")

    assert {:error, %VerificationError{reason: :invalid_event}} =
             Webhooks.verify(invalid_event, event_headers, event_secret, now: event_now)
  end

  test "map and atom header forms support multiple space-separated signatures" do
    {body, headers, secret, now} = signed_event("payment.succeeded")
    signature = headers |> List.keyfind("webhook-signature", 0) |> elem(1)

    map_headers = %{
      webhook_id: "wh_1",
      webhook_timestamp: Integer.to_string(now),
      webhook_signature: "v1,d3Jvbmc= " <> signature
    }

    assert {:ok, %Event{webhook_id: "wh_1"}} =
             Webhooks.verify(body, map_headers, secret, now: now)
  end

  defp signed_event(type, customer \\ "cus_1") do
    now = 1_800_000_000

    body =
      Jason.encode!(%{
        "id" => "evt_1",
        "type" => type,
        "timestamp" => now,
        "data" => %{"customer_id" => customer}
      })

    signed_body(body, now)
  end

  defp signed_body(body, now \\ 1_800_000_000) do
    key = :crypto.strong_rand_bytes(32)
    secret = "whsec_" <> Base.encode64(key)

    webhook_id = "wh_1"
    timestamp = Integer.to_string(now)
    signature = :crypto.mac(:hmac, :sha256, key, webhook_id <> "." <> timestamp <> "." <> body)

    headers = [
      {"webhook-id", webhook_id},
      {"webhook-timestamp", timestamp},
      {"webhook-signature", "v1," <> Base.encode64(signature)}
    ]

    {body, headers, secret, now}
  end
end
