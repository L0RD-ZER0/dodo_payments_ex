defmodule DodoStore.Smoke.LifecycleTest do
  use ExUnit.Case, async: true

  alias DodoStore.Smoke.{Lifecycle, WebhookDriver}

  @secret "whsec_" <> Base.encode64("local-smoke-signing-key")

  test "fixed seeds replay the exact random lifecycle without touching global RNG state" do
    descriptor = %{id: "core:random", feature: :core, support_expectation: :documented_supported}

    first = Lifecycle.build(descriptor, :random, 20_260_820, 0, "run-fixed")
    second = Lifecycle.build(descriptor, :random, 20_260_820, 0, "run-fixed")

    assert first == second
    assert first.outcome in Lifecycle.terminal_outcomes()
    assert first.events == second.events
    assert first.delivery == second.delivery
  end

  test "every generated source lifecycle is causal and processing is never terminal" do
    descriptor = %{feature: :core, support_expectation: :documented_supported}

    lifecycles = Lifecycle.build_all(descriptor, :all, 17, 0, "run-all")
    assert Enum.map(lifecycles, & &1.outcome) == Lifecycle.terminal_outcomes()

    Enum.each(lifecycles, fn lifecycle ->
      source_types = Enum.map(lifecycle.events, & &1.type)

      refute List.last(source_types) == "payment.processing"

      if Enum.any?(source_types, &String.starts_with?(&1, "refund.")) or
           Enum.any?(source_types, &String.starts_with?(&1, "dispute.")) do
        assert hd(source_types) == "payment.succeeded"
      end

      if lifecycle.outcome in [:rejected, :cancelled, :processing_rejected] do
        refute Enum.any?(source_types, &String.starts_with?(&1, "refund."))
        refute Enum.any?(source_types, &String.starts_with?(&1, "dispute."))
      end

      [retried | _rest] = Enum.reverse(lifecycle.delivery)
      assert Enum.count(lifecycle.delivery, &(&1 == retried)) >= 2
    end)
  end

  test "synthetic requests verify over exact raw bytes and are labelled honestly" do
    [lifecycle] =
      Lifecycle.build_all(
        %{feature: :core, support_expectation: :documented_supported},
        [:accepted],
        44,
        0,
        "run-signature"
      )

    [event] = lifecycle.events
    timestamp = 1_800_000_000

    assert {:ok, request} = WebhookDriver.request(event, @secret, timestamp: timestamp)
    assert request.provenance == :synthetic_valid_signature

    assert {:ok, verified} =
             DodoPayments.Webhooks.verify(request.body, request.headers, @secret, now: timestamp)

    assert verified.webhook_id == event.webhook_id
    assert verified.type == :payment_succeeded

    assert {:error, %{reason: :non_loopback_endpoint}} =
             WebhookDriver.deliver(request, "https://test.dodopayments.com")
  end
end
