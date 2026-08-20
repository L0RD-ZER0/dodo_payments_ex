defmodule DodoStore.Smoke.Lifecycle do
  @moduledoc """
  Seeded local checkout lifecycle generation.

  Source events are always causally valid: refunds and disputes can only be
  generated after a successful payment, and `payment.processing` is never a
  terminal state. `delivery` may intentionally differ from source order because
  real webhook delivery is not ordered. Duplicate deliveries retain the exact
  webhook ID and body.
  """

  @terminal_outcomes [
    :accepted,
    :rejected,
    :cancelled,
    :refunded,
    :disputed,
    :processing_accepted,
    :processing_rejected
  ]

  @enforce_keys [
    :scenario_id,
    :order_id,
    :payment_id,
    :descriptor,
    :target,
    :support_expectation,
    :outcome,
    :events,
    :delivery
  ]
  defstruct @enforce_keys ++ [:refund_id, :dispute_id, :cart, :pattern]

  @type outcome ::
          :accepted
          | :rejected
          | :cancelled
          | :refunded
          | :disputed
          | :processing_accepted
          | :processing_rejected

  @type event :: %{
          required(:webhook_id) => String.t(),
          required(:type) => String.t(),
          required(:payload) => map()
        }

  @type t :: %__MODULE__{
          scenario_id: String.t(),
          order_id: String.t(),
          payment_id: String.t(),
          refund_id: String.t() | nil,
          dispute_id: String.t() | nil,
          descriptor: map(),
          target: map(),
          support_expectation: atom(),
          outcome: outcome(),
          events: [event()],
          delivery: [event()],
          cart: [map()],
          pattern: 1..10
        }

  @spec terminal_outcomes() :: [outcome()]
  def terminal_outcomes, do: @terminal_outcomes

  @doc "Expands `:all` and chooses `:random` without using process-global RNG state."
  @spec build_all(map(), atom() | [atom()], integer(), non_neg_integer(), String.t()) :: [t()]
  def build_all(descriptor, requested, seed, index, run_id) do
    requested
    |> normalize_requested()
    |> Enum.with_index()
    |> Enum.map(fn {outcome, outcome_index} ->
      build(descriptor, outcome, seed, index * length(@terminal_outcomes) + outcome_index, run_id)
    end)
  end

  @spec build(map(), atom(), integer(), non_neg_integer(), String.t()) :: t()
  def build(descriptor, requested, seed, index, run_id) when is_map(descriptor) do
    outcome = select_outcome(requested, seed, descriptor, index)
    target = target(descriptor)
    token = stable_token({run_id, seed, index, target, outcome})
    scenario_id = value(descriptor, :id) || "scenario-#{token}"
    order_id = "order-#{token}"
    payment_id = "pay-#{token}"
    refund_id = if outcome == :refunded, do: "ref-#{token}"
    dispute_id = if outcome == :disputed, do: "dis-#{token}"
    product_id = value(descriptor, :product_id) || "pdt-smoke-local"
    cart = [%{product_id: product_id, quantity: 1}]
    pattern = valid_pattern(value(descriptor, :pattern))

    base = %__MODULE__{
      scenario_id: scenario_id,
      order_id: order_id,
      payment_id: payment_id,
      refund_id: refund_id,
      dispute_id: dispute_id,
      descriptor: descriptor,
      target: target,
      support_expectation: support_expectation(descriptor),
      outcome: outcome,
      events: [],
      delivery: [],
      cart: cart,
      pattern: pattern
    }

    events = source_events(base)
    %{base | events: events, delivery: adversarial_delivery(events, outcome)}
  end

  defp normalize_requested(:all), do: @terminal_outcomes
  defp normalize_requested("all"), do: @terminal_outcomes
  defp normalize_requested(nil), do: [:random]
  defp normalize_requested(requested) when is_atom(requested), do: [requested]

  defp normalize_requested(requested) when is_list(requested) do
    requested
    |> Enum.flat_map(fn
      :all -> @terminal_outcomes
      "all" -> @terminal_outcomes
      value -> [normalize_outcome(value)]
    end)
    |> Enum.uniq()
  end

  defp normalize_outcome(value) when value in @terminal_outcomes or value == :random, do: value

  defp normalize_outcome(value) when is_binary(value) do
    case String.replace(value, "-", "_") do
      "accepted" -> :accepted
      "rejected" -> :rejected
      "cancelled" -> :cancelled
      "refunded" -> :refunded
      "disputed" -> :disputed
      "processing_accepted" -> :processing_accepted
      "processing_rejected" -> :processing_rejected
      "random" -> :random
      _other -> raise ArgumentError, "unknown local smoke lifecycle outcome: #{inspect(value)}"
    end
  end

  defp normalize_outcome(value),
    do: raise(ArgumentError, "unknown local smoke lifecycle outcome: #{inspect(value)}")

  defp select_outcome(requested, seed, descriptor, index) do
    case normalize_outcome(requested) do
      :random ->
        state = seeded_state({seed, target(descriptor), index})
        {position, _state} = :rand.uniform_s(length(@terminal_outcomes), state)
        Enum.at(@terminal_outcomes, position - 1)

      outcome ->
        outcome
    end
  end

  defp source_events(%__MODULE__{} = scenario) do
    succeeded = payment_event(scenario, "payment.succeeded", "succeeded", "succeeded")
    failed = payment_event(scenario, "payment.failed", "failed", "failed")
    cancelled = payment_event(scenario, "payment.cancelled", "cancelled", "cancelled")
    processing = payment_event(scenario, "payment.processing", "processing", "processing")

    case scenario.outcome do
      :accepted -> [succeeded]
      :rejected -> [failed]
      :cancelled -> [cancelled]
      :processing_accepted -> [processing, succeeded]
      :processing_rejected -> [processing, failed]
      :refunded -> [succeeded, refund_event(scenario)]
      :disputed -> [succeeded, dispute_event(scenario)]
    end
  end

  defp payment_event(scenario, type, suffix, status) do
    payload = %{
      "type" => type,
      "data" => %{
        "payment_id" => scenario.payment_id,
        "status" => status,
        "product_id" => hd(scenario.cart).product_id,
        "metadata" => %{
          "example_pattern" => scenario.pattern,
          "example_order_id" => scenario.order_id,
          "example_cart_hash" => DodoStore.Commerce.cart_fingerprint(scenario.cart)
        }
      }
    }

    event(scenario, suffix, payload)
  end

  defp refund_event(scenario) do
    event(scenario, "refund-succeeded", %{
      "type" => "refund.succeeded",
      "data" => %{
        "refund_id" => scenario.refund_id,
        "payment_id" => scenario.payment_id,
        "status" => "succeeded"
      }
    })
  end

  defp dispute_event(scenario) do
    event(scenario, "dispute-opened", %{
      "type" => "dispute.opened",
      "data" => %{
        "dispute_id" => scenario.dispute_id,
        "payment_id" => scenario.payment_id,
        "dispute_status" => "dispute_opened"
      }
    })
  end

  defp event(scenario, suffix, payload) do
    %{
      webhook_id: "wh-#{stable_token({scenario.scenario_id, suffix})}",
      type: payload["type"],
      payload: payload
    }
  end

  # The source lifecycle above remains causal. Reversing multi-event delivery
  # models Dodo's explicitly unordered webhook transport, then the exact final
  # event is retried with the same ID and bytes.
  defp adversarial_delivery([event], _outcome), do: [event, event]

  defp adversarial_delivery(events, _outcome) do
    reversed = Enum.reverse(events)
    reversed ++ [hd(reversed)]
  end

  defp target(descriptor) do
    %{
      feature: value(descriptor, :feature) || :core,
      method_type:
        value(descriptor, :method_type) || value(descriptor, :method) || value(descriptor, :type),
      method_family: value(descriptor, :method_family) || value(descriptor, :family)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp support_expectation(descriptor) do
    value(descriptor, :support_expectation) || :documented_supported
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp valid_pattern(value) when is_integer(value) and value in 1..10, do: value
  defp valid_pattern(_value), do: 1

  defp stable_token(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, 9)
    |> Base.url_encode64(padding: false)
  end

  defp seeded_state(term) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(term))
    <<a::unsigned-32, b::unsigned-32, c::unsigned-32, _rest::binary>> = digest
    :rand.seed_s(:exsss, {a + 1, b + 1, c + 1})
  end
end
