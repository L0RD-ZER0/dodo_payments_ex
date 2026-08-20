defmodule DodoStore.Billing.OutboxDispatcher do
  @moduledoc """
  Delivers one durable command through the SDK.

  A database claim is committed before network I/O. Consequential mutations
  with uncertain outcomes stop in `reconciliation_required`; only operations
  with stable replay identity (meter events and current-state reads) retry.
  """

  alias DodoStore.Billing
  alias DodoStore.Billing.OutboxCommand

  @spec dispatch(OutboxCommand.t(), DodoPayments.Client.t()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(%OutboxCommand{} = command, client) do
    with {:ok, claimed} <- Billing.claim_command(command) do
      dispatch_claimed(claimed, client)
    end
  end

  defp dispatch_claimed(command, client) do
    result = safe_call(command.kind, command.payload, client)

    case result do
      {:ok, value} ->
        complete(command, value)

      {:error, %DodoPayments.Error.OutcomeUnknown{} = error} ->
        handle_unknown(command, error)
        {:error, error}

      {:error, error} ->
        handle_failure(command, error)
        {:error, error}
    end
  end

  defp safe_call(kind, payload, client) do
    call(kind, payload, client)
  rescue
    error -> {:error, error}
  end

  defp call("usage_ingest", %{"events" => events}, client),
    do: DodoPayments.UsageEvents.ingest(client, %{events: events})

  defp call("subscription_charge", payload, client) do
    subscription_id = Map.fetch!(payload, "subscription_id")
    params = Map.fetch!(payload, "params")
    DodoPayments.Subscriptions.charge(client, subscription_id, params)
  end

  defp call("refund_create", payload, client),
    do: DodoPayments.Refunds.create(client, payload)

  defp call("reconcile_subscription", %{"subscription_id" => id}, client),
    do: DodoPayments.Subscriptions.retrieve(client, id)

  defp call("reconcile_refund", %{"refund_id" => id}, client),
    do: DodoPayments.Refunds.retrieve(client, id)

  defp call("reconcile_dispute", %{"dispute_id" => id}, client),
    do: DodoPayments.Disputes.retrieve(client, id)

  defp call(_kind, _payload, _client),
    do: {:error, ArgumentError.exception("unsupported example outbox command")}

  defp complete(command, value) do
    with :ok <- project_reconciliation(command, value),
         {:ok, _command} <- Billing.mark_command_delivered(command, %{"category" => "ok"}) do
      {:ok, value}
    else
      {:error, error} ->
        handle_post_delivery_failure(command, error)
        {:error, error}
    end
  end

  defp handle_unknown(
         %OutboxCommand{kind: "usage_ingest"} = command,
         %{
           replay: :identical_only
         } = error
       ),
       do: Billing.retry_or_fail_command(command, error)

  defp handle_unknown(%OutboxCommand{kind: kind} = command, error)
       when kind in ["reconcile_subscription", "reconcile_refund", "reconcile_dispute"],
       do: Billing.retry_or_fail_command(command, error)

  defp handle_unknown(command, error),
    do: Billing.require_command_reconciliation(command, error)

  defp handle_failure(%OutboxCommand{} = command, %ArgumentError{} = error),
    do: Billing.fail_command(command, error)

  defp handle_failure(%OutboxCommand{} = command, %DodoPayments.Error.APIError{} = error),
    do: Billing.fail_command(command, error)

  defp handle_failure(%OutboxCommand{} = command, %DodoPayments.Error.PreparationError{} = error),
    do: Billing.fail_command(command, error)

  defp handle_failure(
         %OutboxCommand{} = command,
         %DodoPayments.Error.ConfigurationError{} = error
       ),
       do: Billing.fail_command(command, error)

  defp handle_failure(%OutboxCommand{} = command, %DodoPayments.ValidationError{} = error),
    do: Billing.fail_command(command, error)

  defp handle_failure(%OutboxCommand{kind: kind} = command, error)
       when kind in ["subscription_charge", "refund_create"],
       do: Billing.require_command_reconciliation(command, error)

  defp handle_failure(command, error), do: Billing.retry_or_fail_command(command, error)

  # The remote side has already returned success. If projection or delivery
  # persistence fails, an unsafe mutation must never become ordinarily due.
  defp handle_post_delivery_failure(%OutboxCommand{kind: kind} = command, error)
       when kind in ["subscription_charge", "refund_create"],
       do: Billing.require_command_reconciliation(command, error)

  defp handle_post_delivery_failure(command, error),
    do: Billing.retry_or_fail_command(command, error)

  defp project_reconciliation(
         %OutboxCommand{kind: "reconcile_subscription", payload: %{"subscription_id" => id}},
         subscription
       ) do
    status = field(subscription, :status) || "unknown"
    metadata = field(subscription, :metadata) || %{}
    pattern = pattern_from_metadata(metadata, 2)

    with :ok <- apply_subscription_snapshot(subscription),
         {:ok, _record} <-
           Billing.put_record(pattern, id, to_string(status), %{
             "source" => "current_state_reconciliation"
           }) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  defp project_reconciliation(
         %OutboxCommand{kind: kind, payload: payload},
         resource
       )
       when kind in ["reconcile_refund", "reconcile_dispute"] do
    id_field = if kind == "reconcile_refund", do: "refund_id", else: "dispute_id"
    status_field = if kind == "reconcile_refund", do: :status, else: :dispute_status
    id = Map.fetch!(payload, id_field)
    status = field(resource, status_field) || "unknown"

    case Billing.put_record(7, id, to_string(status), %{
           "source" => "current_state_reconciliation"
         }) do
      {:ok, _record} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp project_reconciliation(_command, _value), do: :ok

  defp apply_subscription_snapshot(subscription) do
    if Code.ensure_loaded?(DodoStore.Commerce) and
         function_exported?(DodoStore.Commerce, :apply_subscription_snapshot, 1) do
      case DodoStore.Commerce.apply_subscription_snapshot(subscription) do
        {:ok, _snapshot} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      :ok
    end
  end

  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_value, _key), do: nil

  defp pattern_from_metadata(metadata, default) when is_map(metadata) do
    value = Map.get(metadata, "example_pattern") || Map.get(metadata, :example_pattern)

    case value do
      pattern when is_integer(pattern) and pattern in [2, 6, 9, 10] -> pattern
      pattern when is_binary(pattern) -> parse_pattern(pattern, default)
      _value -> default
    end
  end

  defp pattern_from_metadata(_metadata, default), do: default

  defp parse_pattern(value, default) do
    case Integer.parse(value) do
      {pattern, ""} when pattern in [2, 6, 9, 10] -> pattern
      _result -> default
    end
  end
end
