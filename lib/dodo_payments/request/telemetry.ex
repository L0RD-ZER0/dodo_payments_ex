defmodule DodoPayments.Request.Telemetry do
  @moduledoc false

  alias DodoPayments.Deadline
  alias DodoPayments.HTTP
  alias DodoPayments.Request.ResponseInfo

  @attempt_followup_reserve 10
  @retry_followup_reserve 20

  @spec run(DodoPayments.Client.t(), DodoPayments.Operation.t(), integer(), (-> result)) :: result
        when result: term()
  def run(client, operation, deadline, fun) do
    started_at = System.monotonic_time()
    metadata = metadata(client, operation)

    execute(
      deadline,
      [:dodo_payments, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result = fun.()

    execute(
      deadline,
      [:dodo_payments, :request, :stop],
      %{duration: System.monotonic_time() - started_at},
      Map.merge(metadata, result_metadata(result))
    )

    result
  end

  @spec attempt_start(map(), pos_integer()) :: :ok
  def attempt_start(context, attempt_number) do
    execute(
      context.deadline,
      [:dodo_payments, :request, :attempt, :start],
      %{system_time: System.system_time(), attempt: attempt_number},
      metadata(context.client, context.operation),
      reserve: @attempt_followup_reserve
    )
  end

  @spec attempt_stop(map(), pos_integer(), HTTP.Response.t() | HTTP.TransportError.t()) :: :ok
  def attempt_stop(context, attempt_number, %HTTP.Response{} = response) do
    metadata =
      context.client
      |> metadata(context.operation)
      |> Map.merge(%{status: response.status, request_id: ResponseInfo.request_id(response)})

    execute(
      context.deadline,
      [:dodo_payments, :request, :attempt, :stop],
      %{attempt: attempt_number},
      metadata
    )
  end

  def attempt_stop(context, attempt_number, %HTTP.TransportError{} = error) do
    metadata =
      context.client
      |> metadata(context.operation)
      |> Map.put(:error_category, transport_error_category(error.reason))
      |> put_known(:status, ResponseInfo.partial_status(error))
      |> put_known(:request_id, ResponseInfo.partial_request_id(error))

    execute(
      context.deadline,
      [:dodo_payments, :request, :attempt, :stop],
      %{attempt: attempt_number},
      metadata
    )
  end

  @spec retry(map(), pos_integer(), non_neg_integer()) :: :ok
  def retry(context, attempt_number, delay) do
    execute(
      context.deadline,
      [:dodo_payments, :request, :retry],
      %{attempt: attempt_number, delay: delay},
      metadata(context.client, context.operation),
      reserve: @retry_followup_reserve
    )
  end

  defp metadata(client, operation) do
    %{
      operation: operation.id,
      method: operation.method,
      authentication: operation.auth,
      environment: client.environment
    }
  end

  defp put_known(metadata, _key, nil), do: metadata
  defp put_known(metadata, key, value), do: Map.put(metadata, key, value)

  defp execute(deadline, event, measurements, metadata, opts \\ []) do
    case :telemetry.list_handlers(event) do
      [] ->
        :ok

      _handlers ->
        case DodoPayments.Telemetry.validate_config!() do
          %{mode: :async, timeout: timeout} ->
            DodoPayments.Telemetry.Supervisor.dispatch(event, measurements, metadata, timeout)

          %{mode: :request_bounded} ->
            budget = Deadline.remaining(deadline) - Keyword.get(opts, :reserve, 0)

            case Deadline.run(
                   fn -> :telemetry.execute(event, measurements, metadata) end,
                   budget
                 ) do
              {:ok, :ok} -> :ok
              :timeout -> :ok
            end
        end
    end
  end

  defp transport_error_category(:sdk_deadline_exceeded), do: :timeout
  defp transport_error_category({:response_too_large, _limit}), do: :response_too_large
  defp transport_error_category({:invalid_client_module_result, _value}), do: :invalid_client
  defp transport_error_category(_reason), do: :transport

  defp result_metadata({:ok, _value}), do: %{result: :ok}

  defp result_metadata(
         {:error,
          %DodoPayments.Error.OutcomeUnknown{
            replay: replay,
            status: status,
            request_id: request_id,
            attempts: attempts
          } = error}
       ) do
    %{
      result: {:error, error.__struct__},
      error_category: :outcome_unknown,
      outcome_replay: replay
    }
    |> put_known(:status, status)
    |> put_known(:request_id, request_id)
    |> put_known(:attempts, attempts)
  end

  defp result_metadata({:error, error}), do: %{result: {:error, error.__struct__}}
end
