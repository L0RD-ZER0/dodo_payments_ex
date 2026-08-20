defmodule DodoPayments.Request do
  @moduledoc false

  alias DodoPayments.{Client, Deadline, Operation, Response}
  alias DodoPayments.Error
  alias DodoPayments.HTTP
  alias DodoPayments.Request.{Adapter, Decoder, Preparation, ResponseInfo, RetryPolicy, Telemetry}

  @doc "Executes one Dodo operation through the client's shared policy engine."
  @spec request(Client.t(), Operation.t(), map() | nil, keyword()) ::
          {:ok, term() | Response.t()} | {:error, Exception.t()}
  def request(%Client{} = client, %Operation{} = operation, params \\ %{}, opts \\ [])
      when is_list(opts) do
    started_at = Deadline.now()

    with {:ok, timeout} <- Preparation.timeout_option(opts, client.timeout) do
      deadline = started_at + timeout

      Telemetry.run(client, operation, deadline, fn ->
        do_request(client, operation, params, opts, timeout, deadline)
      end)
    end
  end

  defp do_request(client, operation, params, opts, timeout, deadline) do
    case Deadline.run(
           fn ->
             safely_prepare(
               fn ->
                 with :ok <- Preparation.validate_options(opts) do
                   Preparation.prepare(client, operation, params, opts, timeout, deadline)
                 end
               end,
               operation.id
             )
           end,
           Deadline.remaining(deadline)
         ) do
      {:ok, {:ok, context}} -> attempt(context, 1)
      {:ok, {:error, _} = error} -> error
      :timeout -> deadline_error(operation, timeout)
    end
  end

  defp safely_prepare(fun, operation) do
    try do
      fun.()
    rescue
      error ->
        {:error,
         Error.PreparationError.exception(
           operation: operation,
           kind: :error,
           cause: error,
           stacktrace: __STACKTRACE__
         )}
    catch
      kind, reason ->
        {:error,
         Error.PreparationError.exception(
           operation: operation,
           kind: kind,
           cause: reason,
           stacktrace: __STACKTRACE__
         )}
    end
  end

  defp deadline_error(operation, timeout) do
    {:error, Error.TimeoutError.exception(operation: operation.id, timeout: timeout)}
  end

  defp attempt(context, attempt_number) do
    remaining = Deadline.remaining(context.deadline)

    if remaining <= 0 do
      timeout_or_prior_uncertainty(context, attempt_number - 1)
    else
      Telemetry.attempt_start(context, attempt_number)
      remaining = Deadline.remaining(context.deadline)

      if remaining <= 0 do
        timeout_or_prior_uncertainty(context, attempt_number - 1)
      else
        request = %HTTP.Request{
          method: context.operation.method,
          url: context.url,
          headers: context.headers,
          body: context.body,
          timeout: remaining,
          max_body_bytes: context.max_response_bytes,
          response_mode: :raw
        }

        case Adapter.call(context.client, request, remaining) do
          {:ok, %HTTP.Response{} = response} ->
            Telemetry.attempt_stop(context, attempt_number, response)
            handle_response(context, response, attempt_number)

          {:error, %HTTP.TransportError{} = error} ->
            Telemetry.attempt_stop(context, attempt_number, error)
            handle_transport_error(context, error, attempt_number)
        end
      end
    end
  end

  defp handle_response(context, response, attempt_number) do
    cond do
      response.status in context.operation.success_statuses ->
        decode_success(context, response, attempt_number)

      response.status in 200..299 ->
        unexpected_success_status(context, response, attempt_number)

      true ->
        handle_error_response(context, response, attempt_number)
    end
  end

  defp handle_error_response(context, response, attempt_number) do
    cond do
      RetryPolicy.retryable_status?(response.status) and context.replayable? and
          RetryPolicy.available?(context, attempt_number) ->
        retry(context, attempt_number, {:response, response})

      RetryPolicy.ambiguous_status?(response.status) and
          RetryPolicy.consequential_mutation?(context) ->
        outcome_unknown(context, {:http_status, response.status}, attempt_number,
          status: response.status,
          request_id: ResponseInfo.request_id(response)
        )

      prior_uncertainty?(context) ->
        prior_outcome_unknown(context, {:http_status, response.status}, attempt_number)

      true ->
        terminal_api_error(context, response, attempt_number)
    end
  end

  defp handle_transport_error(context, error, attempt_number) do
    case error.reason do
      {:invalid_client_module_result, _value} ->
        invalid_client_error(context, error, attempt_number)

      {:response_too_large, limit} ->
        overflow_error(context, error, limit, attempt_number)

      _reason ->
        handle_delivery_error(context, error, attempt_number)
    end
  end

  defp handle_delivery_error(context, error, attempt_number) do
    may_replay? = context.replayable? or error.delivery == :not_sent

    cond do
      may_replay? and RetryPolicy.available?(context, attempt_number) ->
        retry(context, attempt_number, {:transport, error})

      RetryPolicy.consequential_mutation?(context) and error.delivery == :unknown ->
        outcome_unknown(context, error.reason, attempt_number,
          status: ResponseInfo.partial_status(error),
          request_id: ResponseInfo.partial_request_id(error)
        )

      error.reason == :sdk_deadline_exceeded ->
        timeout_or_prior_uncertainty(context, attempt_number)

      prior_uncertainty?(context) ->
        prior_outcome_unknown(context, error.reason, attempt_number)

      true ->
        {:error,
         Error.TransportError.exception(
           operation: context.operation.id,
           reason: error.reason,
           attempts: attempt_number
         )}
    end
  end

  defp invalid_client_error(context, error, attempt_number) do
    if RetryPolicy.consequential_mutation?(context) do
      outcome_unknown(context, error.reason, attempt_number,
        status: ResponseInfo.partial_status(error),
        request_id: ResponseInfo.partial_request_id(error)
      )
    else
      {:error,
       Error.TransportError.exception(
         operation: context.operation.id,
         reason: error.reason,
         attempts: attempt_number
       )}
    end
  end

  defp retry(context, attempt_number, cause) do
    context = remember_uncertainty(context, cause)
    delay = RetryPolicy.delay(context.client, attempt_number, retry_response(cause))
    remaining_before_delay = Deadline.remaining(context.deadline)

    if remaining_before_delay <= 0 or delay >= remaining_before_delay do
      retry_unschedulable(context, cause, attempt_number)
    else
      if delay > 0, do: Process.sleep(delay)
      remaining_after_delay = Deadline.remaining(context.deadline)

      if remaining_after_delay <= 0 do
        retry_unschedulable(context, cause, attempt_number)
      else
        Telemetry.retry(context, attempt_number, delay)

        if Deadline.remaining(context.deadline) > 0 do
          attempt(context, attempt_number + 1)
        else
          retry_unschedulable(context, cause, attempt_number)
        end
      end
    end
  end

  defp retry_response({:response, response}), do: response
  defp retry_response({:transport, _error}), do: nil

  defp retry_unschedulable(context, {:response, response}, attempt_number) do
    cond do
      RetryPolicy.ambiguous_status?(response.status) and
          RetryPolicy.consequential_mutation?(context) ->
        outcome_unknown(context, {:http_status, response.status}, attempt_number,
          status: response.status,
          request_id: ResponseInfo.request_id(response)
        )

      prior_uncertainty?(context) ->
        prior_outcome_unknown(context, {:http_status, response.status}, attempt_number)

      true ->
        terminal_api_error(context, response, attempt_number)
    end
  end

  defp retry_unschedulable(context, {:transport, error}, attempt_number) do
    cond do
      error.delivery == :unknown and RetryPolicy.consequential_mutation?(context) ->
        outcome_unknown(context, error.reason, attempt_number,
          status: ResponseInfo.partial_status(error),
          request_id: ResponseInfo.partial_request_id(error)
        )

      prior_uncertainty?(context) ->
        prior_outcome_unknown(context, error.reason, attempt_number)

      error.reason == :sdk_deadline_exceeded ->
        timeout_error(context)

      true ->
        {:error,
         Error.TransportError.exception(
           operation: context.operation.id,
           reason: error.reason,
           attempts: attempt_number
         )}
    end
  end

  defp timeout_or_prior_uncertainty(context, attempt_number) do
    if prior_uncertainty?(context) do
      prior_outcome_unknown(context, :sdk_deadline_exceeded, attempt_number)
    else
      timeout_error(context)
    end
  end

  defp timeout_error(context) do
    {:error,
     Error.TimeoutError.exception(
       operation: context.operation.id,
       timeout: context.timeout
     )}
  end

  defp decode_success(context, response, attempt_number) do
    fetch_next = fn override ->
      params = merge_page_params(context.params, override)
      opts = Keyword.put(context.opts, :return, :data)
      request(context.client, context.operation, params, opts)
    end

    case Deadline.run(
           fn -> Decoder.decode_success(context, response, attempt_number, fetch_next) end,
           Deadline.remaining(context.deadline)
         ) do
      {:ok, result} -> result
      :timeout -> decode_deadline_error(context, response, attempt_number)
    end
  end

  defp decode_api_error(context, response, attempt_number) do
    case Deadline.run(
           fn -> Decoder.api_error(response) end,
           Deadline.remaining(context.deadline)
         ) do
      {:ok, error} -> {:error, error}
      :timeout -> timeout_or_prior_uncertainty(context, attempt_number)
    end
  end

  # Once Dodo has returned a conclusive error, expiry while deciding whether a
  # retry fits must not erase that response and replace it with a local timeout.
  # Decode while budget remains; otherwise preserve the status and bounded raw
  # response without performing additional JSON work.
  defp terminal_api_error(context, response, attempt_number) do
    if Deadline.remaining(context.deadline) > 0 do
      decode_api_error(context, response, attempt_number)
    else
      {:error,
       Error.APIError.exception(
         status: response.status,
         body: response.body,
         headers: response.headers,
         request_id: ResponseInfo.request_id(response)
       )}
    end
  end

  defp decode_deadline_error(context, response, attempt_number) do
    if RetryPolicy.consequential_mutation?(context) do
      outcome_unknown(context, :successful_response_decode_deadline_exceeded, attempt_number,
        status: response.status,
        request_id: ResponseInfo.request_id(response)
      )
    else
      timeout_error(context)
    end
  end

  defp unexpected_success_status(context, response, attempt_number) do
    if RetryPolicy.consequential_mutation?(context) do
      outcome_unknown(context, {:unexpected_success_status, response.status}, attempt_number,
        status: response.status,
        request_id: ResponseInfo.request_id(response)
      )
    else
      {:error,
       Error.DecodeError.exception(
         reason: {:unexpected_success_status, response.status},
         status: response.status,
         request_id: ResponseInfo.request_id(response),
         body: response.body
       )}
    end
  end

  defp overflow_error(context, error, limit, attempt_number) do
    partial = error.partial_response || %{}
    status = Map.get(partial, :status)
    headers = Map.get(partial, :headers, [])

    uncertain_mutation? =
      RetryPolicy.consequential_mutation?(context) and
        (is_nil(status) or status in context.operation.success_statuses or
           RetryPolicy.ambiguous_status?(status))

    cond do
      uncertain_mutation? ->
        outcome_unknown(context, {:successful_response_too_large, limit}, attempt_number,
          status: status,
          request_id: ResponseInfo.request_id_from_headers(headers)
        )

      prior_uncertainty?(context) ->
        prior_outcome_unknown(context, {:response_too_large, limit}, attempt_number)

      true ->
        {:error,
         Error.ResponseTooLarge.exception(
           operation: context.operation.id,
           limit: limit,
           status: status
         )}
    end
  end

  defp merge_page_params(params, override) do
    Enum.reduce(override, params, fn {key, value}, acc ->
      acc
      |> Map.delete(key)
      |> Map.delete(Atom.to_string(key))
      |> Map.put(key, value)
    end)
  end

  defp outcome_unknown(context, reason, attempt_number, metadata) do
    {:error,
     Error.OutcomeUnknown.exception(
       operation: context.operation.id,
       reason: reason,
       status: Keyword.get(metadata, :status),
       request_id: Keyword.get(metadata, :request_id),
       attempts: attempt_number,
       replay: RetryPolicy.outcome_replay(context),
       reconciliation: context.operation.reconciliation
     )}
  end

  defp remember_uncertainty(context, {:response, response}) do
    if is_nil(context.uncertainty) and RetryPolicy.consequential_mutation?(context) and
         RetryPolicy.ambiguous_status?(response.status) do
      Map.put(context, :uncertainty, %{
        reason: {:http_status, response.status},
        status: response.status,
        request_id: ResponseInfo.request_id(response)
      })
    else
      context
    end
  end

  defp remember_uncertainty(context, {:transport, error}) do
    if is_nil(context.uncertainty) and RetryPolicy.consequential_mutation?(context) and
         error.delivery == :unknown do
      Map.put(context, :uncertainty, %{
        reason: error.reason,
        status: ResponseInfo.partial_status(error),
        request_id: ResponseInfo.partial_request_id(error)
      })
    else
      context
    end
  end

  defp prior_uncertainty?(context), do: not is_nil(context.uncertainty)

  defp prior_outcome_unknown(context, terminal_reason, attempt_number) do
    uncertainty = context.uncertainty

    outcome_unknown(
      context,
      {:prior_attempt_ambiguous, uncertainty.reason, terminal_reason},
      attempt_number,
      status: uncertainty.status,
      request_id: uncertainty.request_id
    )
  end
end
