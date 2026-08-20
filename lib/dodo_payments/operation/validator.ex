defmodule DodoPayments.Operation.Validator do
  @moduledoc false

  @spec validate(atom() | nil, atom(), map()) :: :ok | {:error, DodoPayments.ValidationError.t()}
  def validate(nil, _operation, _params), do: :ok

  def validate(:usage_event_batch, operation, params) do
    with {:ok, events} when is_list(events) and events != [] and length(events) <= 1_000 <-
           DodoPayments.Validation.fetch(params, :events),
         true <- Enum.all?(events, &valid_usage_event?/1) do
      :ok
    else
      _ -> invalid(operation, :events, :invalid_usage_events)
    end
  end

  def validate(:customer_id_list, operation, params) do
    case DodoPayments.Validation.fetch(params, :customer_ids) do
      {:ok, ids} when is_list(ids) and ids != [] ->
        if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
          do: :ok,
          else: invalid(operation, :customer_ids, :invalid_customer_ids)

      _ ->
        invalid(operation, :customer_ids, :invalid_customer_ids)
    end
  end

  defp valid_usage_event?(event) when is_map(event) do
    Enum.all?([:event_id, :customer_id, :event_name], fn field ->
      case DodoPayments.Validation.fetch(event, field) do
        {:ok, value} when is_binary(value) and value != "" -> true
        _ -> false
      end
    end)
  end

  defp valid_usage_event?(_event), do: false

  defp invalid(operation, field, reason) do
    {:error,
     DodoPayments.ValidationError.exception(
       operation: operation,
       field: field,
       reason: reason
     )}
  end
end
