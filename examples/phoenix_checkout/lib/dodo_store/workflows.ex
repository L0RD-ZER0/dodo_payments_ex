defmodule DodoStore.Workflows do
  @moduledoc """
  Application-facing entry points for the ten billing patterns.

  Checkout functions call Dodo immediately because a person is waiting for a
  URL. Mutating back-office work is written to the durable outbox first. Hard
  limits are authorized in SQLite before the protected work starts.
  """

  alias DodoStore.{Billing, Checkout, Commerce}

  @checkout_patterns [1, 2, 3, 5, 6, 9]

  @spec checkout(
          DodoPayments.Client.t(),
          1 | 2 | 3 | 5 | 6 | 9,
          [map()],
          String.t(),
          String.t(),
          String.t(),
          keyword()
        ) :: {:ok, DodoPayments.CheckoutSession.t()} | {:error, term()}
  def checkout(client, pattern, cart, return_url, cancel_url, order_id, opts \\ [])
      when pattern in @checkout_patterns and is_list(cart) and is_binary(order_id) do
    metadata =
      [
        example_pattern: pattern,
        example_order_id: order_id,
        example_cart_hash: Commerce.cart_fingerprint(cart),
        example_account_id: opts[:account_id],
        example_credits_per_period: opts[:credits]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    checkout_params =
      if pattern == 6,
        do: %{subscription_data: %{on_demand: %{mandate_only: true}}},
        else: %{}

    checkout_params =
      case opts[:allowed_payment_method_types] do
        methods when is_list(methods) and methods != [] ->
          Map.put(checkout_params, :allowed_payment_method_types, methods)

        _methods ->
          checkout_params
      end

    with {:ok, _order} <- Commerce.expect_order(order_id, pattern, cart, opts) do
      case Checkout.create_cart(
             client,
             cart,
             return_url,
             cancel_url,
             metadata,
             checkout_params
           ) do
        {:ok, checkout} ->
          case Commerce.mark_checkout_created(order_id, checkout.session_id) do
            {:ok, _order} -> {:ok, checkout}
            {:error, _error} = failure -> failure
          end

        {:error, _error} = failure ->
          _result = Commerce.mark_checkout_failed(order_id)
          failure
      end
    end
  end

  @doc "Queues one usage event whose ID is stable for the business action."
  def record_usage(action_id, customer_id, event_name, value) do
    scoped_action = "#{customer_id}:#{action_id}"

    enqueue_usage("usage:#{scoped_action}", [
      usage_event(scoped_action, customer_id, event_name, value)
    ])
  end

  @doc "Queues independent events for every meter measured by one operation."
  def record_multiple_meter_usage(action_id, customer_id, measurements)
      when is_map(measurements) do
    events =
      measurements
      |> Enum.sort()
      |> Enum.map(fn {event_name, value} ->
        usage_event("#{customer_id}:#{action_id}:#{event_name}", customer_id, event_name, value)
      end)

    enqueue_usage("usage:#{customer_id}:#{action_id}", events)
  end

  @doc "Atomically spends a local allowance, then durably records its remote meter event."
  def authorize_hybrid_usage(account_id, customer_id, period, action_id, meter, amount, limit) do
    with {:ok, subscription} <- Commerce.active_subscription(account_id, 9),
         true <- subscription.period == period or {:error, :billing_period_mismatch},
         true <- subscription.credits_per_period == limit or {:error, :limit_mismatch} do
      event_id = "#{customer_id}:#{action_id}"
      event = usage_event(event_id, customer_id, meter, amount)

      case Billing.reserve_and_enqueue_usage(
             "hybrid:#{account_id}:#{period}:#{action_id}",
             account_id,
             "credits",
             period,
             amount,
             limit,
             "usage:#{event_id}",
             %{"events" => [event]}
           ) do
        {:ok, bucket, _disposition} -> {:ok, bucket}
        {:error, _reason, _bucket} = error -> error
        {:error, _reason} = error -> error
      end
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Atomically spends credits granted by successful prepaid purchases."
  def authorize_prepaid_usage(account_id, period, action_id, amount) do
    granted = Commerce.granted_credits(account_id, period)

    if granted > 0 do
      case Billing.reserve_usage_once(
             "prepaid:#{account_id}:#{period}:#{action_id}",
             account_id,
             "prepaid_credits",
             period,
             amount,
             granted
           ) do
        {:ok, bucket, _disposition} -> {:ok, bucket}
        {:error, _reason, _bucket} = error -> error
        {:error, _reason} = error -> error
      end
    else
      {:error, :no_credits}
    end
  end

  @doc "Atomically reserves a hard-capped action before the caller performs it."
  def authorize_limited_use(account_id, capability, period, action_id, amount, limit) do
    reservation_id = "limit:#{account_id}:#{capability}:#{period}:#{action_id}"

    case Billing.reserve_usage_once(
           reservation_id,
           account_id,
           capability,
           period,
           amount,
           limit
         ) do
      {:ok, bucket, _disposition} -> {:ok, bucket}
      {:error, :limit_exceeded, _bucket} = error -> error
      {:error, _reason} = error -> error
    end
  end

  @doc "Persists an on-demand subscription charge before dispatch."
  def queue_on_demand_charge(intent_id, subscription_id, params) do
    command_id = "charge:#{intent_id}"

    with {:ok, _subscription} <- Commerce.mandate_subscription(subscription_id),
         {:ok, params} <- attach_charge_intent(params, command_id) do
      Billing.enqueue(command_id, "subscription_charge", %{
        "subscription_id" => subscription_id,
        "params" => params
      })
    end
  end

  @doc "Persists a full or partial refund before dispatch."
  def queue_refund(case_id, payment_id, amount \\ nil) do
    payload = %{"payment_id" => payment_id}
    payload = if amount, do: Map.put(payload, "amount", amount), else: payload
    Billing.enqueue("refund:#{case_id}", "refund_create", payload)
  end

  defp enqueue_usage(command_id, events) do
    Billing.enqueue(command_id, "usage_ingest", %{"events" => events})
  end

  defp attach_charge_intent(params, command_id) when is_map(params) do
    string_metadata = Map.get(params, "metadata")
    atom_metadata = Map.get(params, :metadata)

    cond do
      not is_nil(string_metadata) and not is_nil(atom_metadata) ->
        {:error, :ambiguous_charge_metadata}

      not is_nil(string_metadata) and not is_map(string_metadata) ->
        {:error, :invalid_charge_metadata}

      not is_nil(atom_metadata) and not is_map(atom_metadata) ->
        {:error, :invalid_charge_metadata}

      true ->
        metadata = string_metadata || atom_metadata || %{}
        existing = metadata["example_charge_command_id"] || metadata[:example_charge_command_id]

        if is_nil(existing) or existing == command_id do
          metadata =
            metadata
            |> Map.delete(:example_charge_command_id)
            |> Map.put("example_charge_command_id", command_id)

          params = params |> Map.delete(:metadata) |> Map.put("metadata", metadata)
          {:ok, params}
        else
          {:error, :charge_intent_metadata_conflict}
        end
    end
  end

  defp attach_charge_intent(_params, _command_id), do: {:error, :invalid_charge_params}

  defp usage_event(event_id, customer_id, event_name, value) do
    %{
      "event_id" => event_id,
      "customer_id" => customer_id,
      "event_name" => event_name,
      "metadata" => %{"value" => value}
    }
  end
end
