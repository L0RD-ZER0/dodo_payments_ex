defmodule DodoStore.Billing do
  @moduledoc """
  Small durable primitives shared by the billing-pattern examples.

  The tables are intentionally generic enough to keep the example approachable.
  A production system would normally use domain-specific orders, subscriptions,
  entitlements, and an established job runner while preserving these invariants.
  """

  import Ecto.Query

  alias DodoStore.Billing.{InboxEvent, OutboxCommand, Record, UsageBucket, UsageReservation}
  alias DodoStore.Repo

  @active_outbox_states ["pending", "retryable", "dispatching"]
  @max_outbox_attempts 5
  @max_inbox_attempts 5
  @inbox_claim_timeout_seconds 60
  @outbox_claim_timeout_seconds 60
  @replay_safe_kinds [
    "usage_ingest",
    "reconcile_subscription",
    "reconcile_refund",
    "reconcile_dispute"
  ]

  @spec accept_webhook(DodoPayments.Webhooks.Event.t()) ::
          {:ok, :accepted | :duplicate} | {:error, Ecto.Changeset.t()}
  def accept_webhook(%DodoPayments.Webhooks.Event{} = event) do
    attrs = %{
      webhook_id: event.webhook_id,
      event_type: DodoPayments.Enums.dump!(:webhook_event_type, event.type),
      resource_id: resource_id(event.payload),
      payload: event.payload,
      state: "pending"
    }

    case %InboxEvent{}
         |> InboxEvent.changeset(attrs)
         |> Repo.insert(on_conflict: :nothing, conflict_target: [:webhook_id]) do
      {:ok, %InboxEvent{id: nil}} ->
        {:ok, :duplicate}

      {:ok, _event} ->
        {:ok, :accepted}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec pending_webhooks(pos_integer()) :: [InboxEvent.t()]
  def pending_webhooks(limit \\ 20) do
    InboxEvent
    |> where([event], event.state in ["pending", "retryable", "processing"])
    |> order_by([event], asc: event.inserted_at, asc: event.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Atomically claims one due webhook, recovering only expired processing claims."
  @spec claim_next_webhook() :: {:ok, InboxEvent.t()} | :none
  def claim_next_webhook do
    timestamp = now()
    expired_at = DateTime.add(timestamp, -@inbox_claim_timeout_seconds, :second)

    query =
      from(event in InboxEvent,
        where:
          (event.state in ["pending", "retryable"] and
             (is_nil(event.available_at) or event.available_at <= ^timestamp)) or
            (event.state == "processing" and event.claimed_at < ^expired_at),
        order_by: [asc: event.inserted_at, asc: event.id],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        :none

      event ->
        token = claim_token()

        eligible =
          from(candidate in InboxEvent,
            where:
              candidate.id == ^event.id and
                ((candidate.state in ["pending", "retryable"] and
                    (is_nil(candidate.available_at) or candidate.available_at <= ^timestamp)) or
                   (candidate.state == "processing" and candidate.claimed_at < ^expired_at))
          )

        case Repo.update_all(eligible,
               set: [state: "processing", claimed_at: timestamp, claim_token: token]
             ) do
          {1, _rows} -> {:ok, Repo.get!(InboxEvent, event.id)}
          {0, _rows} -> claim_next_webhook()
        end
    end
  end

  @spec mark_webhook_processed(InboxEvent.t()) ::
          {:ok, InboxEvent.t()} | {:error, Ecto.Changeset.t()}
  def mark_webhook_processed(event) do
    timestamp = now()

    case Repo.update_all(owned_inbox_claim(event),
           set: [
             state: "processed",
             processed_at: timestamp,
             last_error: nil,
             claim_token: nil,
             claimed_at: nil
           ]
         ) do
      {1, _rows} -> {:ok, Repo.get!(InboxEvent, event.id)}
      {0, _rows} -> {:error, :stale_claim}
    end
  end

  @spec mark_webhook_failed(InboxEvent.t(), term()) ::
          {:ok, InboxEvent.t()} | {:error, Ecto.Changeset.t()}
  def mark_webhook_failed(event, error) do
    summary = error |> safe_error_summary() |> Jason.encode!()
    attempts = event.attempts + 1
    timestamp = now()
    dead_letter? = attempts >= @max_inbox_attempts
    state = if dead_letter?, do: "dead_letter", else: "retryable"

    available_at =
      if dead_letter?, do: nil, else: DateTime.add(timestamp, backoff(attempts), :second)

    case Repo.update_all(owned_inbox_claim(event),
           set: [
             state: state,
             attempts: attempts,
             last_error: summary,
             available_at: available_at,
             dead_lettered_at: if(dead_letter?, do: timestamp, else: nil),
             claim_token: nil,
             claimed_at: nil
           ]
         ) do
      {1, _rows} -> {:ok, Repo.get!(InboxEvent, event.id)}
      {0, _rows} -> {:error, :stale_claim}
    end
  end

  @spec enqueue(String.t(), String.t(), map()) ::
          {:ok, OutboxCommand.t(), :accepted | :duplicate}
          | {:error, Ecto.Changeset.t() | :idempotency_conflict}
  def enqueue(command_id, kind, payload)
      when is_binary(command_id) and is_binary(kind) and is_map(payload) do
    attrs = %{
      command_id: command_id,
      kind: kind,
      payload: payload,
      state: "pending",
      resource_key: reconciliation_resource_key(kind, payload)
    }

    case %OutboxCommand{} |> OutboxCommand.changeset(attrs) |> Repo.insert() do
      {:ok, command} ->
        {:ok, command, :accepted}

      {:error, changeset} ->
        resolve_enqueue_conflict(changeset, attrs)
    end
  end

  @spec pending_commands() :: [OutboxCommand.t()]
  def pending_commands do
    recover_abandoned_commands()
    timestamp = now()

    OutboxCommand
    |> where(
      [command],
      command.state in ["pending", "retryable"] and
        (is_nil(command.available_at) or command.available_at <= ^timestamp)
    )
    |> order_by([command], asc: command.inserted_at, asc: command.id)
    |> Repo.all()
  end

  @spec get_command(String.t()) :: OutboxCommand.t() | nil
  def get_command(command_id) when is_binary(command_id) do
    Repo.get_by(OutboxCommand, command_id: command_id)
  end

  @doc "Claims a command exactly once and persists its attempt before network I/O."
  @spec claim_command(OutboxCommand.t()) ::
          {:ok, OutboxCommand.t()} | {:error, :not_dispatchable}
  def claim_command(%OutboxCommand{id: id}) do
    recover_abandoned_commands()
    timestamp = now()
    token = claim_token()

    query =
      from(command in OutboxCommand,
        where:
          command.id == ^id and command.state in ["pending", "retryable"] and
            (is_nil(command.available_at) or command.available_at <= ^timestamp)
      )

    case Repo.update_all(query,
           set: [state: "dispatching", claimed_at: timestamp, claim_token: token],
           inc: [attempts: 1]
         ) do
      {1, _rows} -> {:ok, Repo.get!(OutboxCommand, id)}
      {0, _rows} -> {:error, :not_dispatchable}
    end
  end

  @doc "Recovers expired claims without ever replaying an uncertain charge or refund."
  @spec recover_abandoned_commands() :: :ok
  def recover_abandoned_commands do
    expired_at = DateTime.add(now(), -@outbox_claim_timeout_seconds, :second)

    safe =
      from(command in OutboxCommand,
        where:
          command.state == "dispatching" and command.claimed_at < ^expired_at and
            command.kind in ^@replay_safe_kinds
      )

    Repo.update_all(safe,
      set: [state: "retryable", available_at: now(), claim_token: nil, claimed_at: nil]
    )

    unsafe =
      from(command in OutboxCommand,
        where:
          command.state == "dispatching" and command.claimed_at < ^expired_at and
            command.kind not in ^@replay_safe_kinds
      )

    Repo.update_all(unsafe,
      set: [
        state: "reconciliation_required",
        result: %{"error" => %{"category" => "abandoned_dispatch"}},
        claim_token: nil,
        claimed_at: nil
      ]
    )

    :ok
  end

  @spec mark_command_delivered(OutboxCommand.t(), map()) ::
          {:ok, OutboxCommand.t()} | {:error, Ecto.Changeset.t()}
  def mark_command_delivered(command, result \\ %{}) do
    complete_claimed_command(command, result)
  end

  @spec mark_command_attempted(OutboxCommand.t(), term()) ::
          {:ok, OutboxCommand.t()} | {:error, Ecto.Changeset.t()}
  def mark_command_attempted(command, error) do
    retry_or_fail_command(command, error)
  end

  @spec retry_or_fail_command(OutboxCommand.t(), term()) ::
          {:ok, OutboxCommand.t()} | {:error, :stale_claim}
  def retry_or_fail_command(command, error) do
    if command.attempts >= @max_outbox_attempts do
      transition_claimed_command(command, "failed", error_result(error))
    else
      transition_claimed_command(command, "retryable", error_result(error),
        available_at: DateTime.add(now(), backoff(command.attempts), :second)
      )
    end
  end

  @spec require_command_reconciliation(OutboxCommand.t(), term()) ::
          {:ok, OutboxCommand.t()} | {:error, :stale_claim}
  def require_command_reconciliation(command, error) do
    transition_claimed_command(command, "reconciliation_required", error_result(error))
  end

  @spec fail_command(OutboxCommand.t(), term()) ::
          {:ok, OutboxCommand.t()} | {:error, :stale_claim}
  def fail_command(command, error) do
    transition_claimed_command(command, "failed", error_result(error))
  end

  @spec put_record(1..10, String.t(), String.t(), map()) ::
          {:ok, Record.t()} | {:error, Ecto.Changeset.t()}
  def put_record(pattern, business_key, status, data \\ %{}) do
    attrs = %{pattern: pattern, business_key: business_key, status: status, data: data}
    changeset = Record.changeset(%Record{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace, [:status, :data, :updated_at]},
      conflict_target: [:pattern, :business_key],
      returning: true
    )
  end

  @spec records(pos_integer() | nil) :: [Record.t()]
  def records(pattern \\ nil)

  def records(nil), do: Repo.all(from(record in Record, order_by: [desc: record.updated_at]))

  def records(pattern) do
    Repo.all(
      from(record in Record,
        where: record.pattern == ^pattern,
        order_by: [desc: record.updated_at]
      )
    )
  end

  @spec usage_buckets() :: [UsageBucket.t()]
  def usage_buckets, do: Repo.all(from(bucket in UsageBucket, order_by: [asc: bucket.id]))

  @doc "Atomically applies a reservation once for a stable business-action ID."
  @spec reserve_usage_once(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, UsageBucket.t(), :accepted | :duplicate}
          | {:error, :limit_exceeded, UsageBucket.t()}
          | {:error, :limit_mismatch, UsageBucket.t()}
          | {:error, :idempotency_conflict}
  def reserve_usage_once(reservation_id, account_id, metric, period, amount, limit) do
    Repo.transaction(fn ->
      case do_reserve_usage_once(reservation_id, account_id, metric, period, amount, limit) do
        {:ok, bucket, disposition} -> {bucket, disposition}
        {:error, :limit_exceeded, bucket} -> Repo.rollback({:limit_exceeded, bucket})
        {:error, :limit_mismatch, bucket} -> Repo.rollback({:limit_mismatch, bucket})
        {:error, :idempotency_conflict} -> Repo.rollback(:idempotency_conflict)
      end
    end)
    |> case do
      {:ok, {bucket, disposition}} -> {:ok, bucket, disposition}
      {:error, {:limit_exceeded, bucket}} -> {:error, :limit_exceeded, bucket}
      {:error, {:limit_mismatch, bucket}} -> {:error, :limit_mismatch, bucket}
      {:error, :idempotency_conflict} -> {:error, :idempotency_conflict}
    end
  end

  @doc "Commits an idempotent local reservation and its remote accounting command together."
  @spec reserve_and_enqueue_usage(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          pos_integer(),
          String.t(),
          map()
        ) ::
          {:ok, UsageBucket.t(), :accepted | :duplicate}
          | {:error, :limit_exceeded, UsageBucket.t()}
          | {:error, :limit_mismatch, UsageBucket.t()}
          | {:error, :idempotency_conflict | Ecto.Changeset.t()}
  def reserve_and_enqueue_usage(
        reservation_id,
        account_id,
        metric,
        period,
        amount,
        limit,
        command_id,
        payload
      ) do
    Repo.transaction(fn ->
      case do_reserve_usage_once(reservation_id, account_id, metric, period, amount, limit) do
        {:ok, bucket, :duplicate} ->
          case enqueue(command_id, "usage_ingest", payload) do
            {:ok, _command, disposition} -> {bucket, disposition}
            {:error, error} -> Repo.rollback(error)
          end

        {:ok, bucket, :accepted} ->
          case enqueue(command_id, "usage_ingest", payload) do
            {:ok, _command, _disposition} -> {bucket, :accepted}
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, :limit_exceeded, bucket} ->
          Repo.rollback({:limit_exceeded, bucket})

        {:error, :limit_mismatch, bucket} ->
          Repo.rollback({:limit_mismatch, bucket})

        {:error, :idempotency_conflict} ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
    |> case do
      {:ok, {bucket, disposition}} -> {:ok, bucket, disposition}
      {:error, {:limit_exceeded, bucket}} -> {:error, :limit_exceeded, bucket}
      {:error, {:limit_mismatch, bucket}} -> {:error, :limit_mismatch, bucket}
      {:error, :idempotency_conflict} -> {:error, :idempotency_conflict}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp do_reserve_usage_once(reservation_id, account_id, metric, period, amount, limit)
       when is_binary(reservation_id) and is_integer(amount) and amount > 0 and is_integer(limit) and
              limit > 0 do
    timestamp = now()
    existing_reservation = Repo.get_by(UsageReservation, reservation_id: reservation_id)
    existing_bucket = Repo.one(bucket_query(account_id, metric, period))

    cond do
      existing_reservation &&
          reservation_intent(existing_reservation) != {account_id, metric, period, amount, limit} ->
        {:error, :idempotency_conflict}

      existing_reservation && existing_bucket && existing_bucket.limit == limit ->
        {:ok, existing_bucket, :duplicate}

      existing_reservation ->
        {:error, :limit_mismatch, existing_bucket}

      existing_bucket && existing_bucket.limit != limit ->
        {:error, :limit_mismatch, existing_bucket}

      true ->
        insert_or_replay_reservation(
          reservation_id,
          account_id,
          metric,
          period,
          amount,
          limit,
          timestamp
        )
    end
  end

  defp insert_or_replay_reservation(
         reservation_id,
         account_id,
         metric,
         period,
         amount,
         limit,
         timestamp
       ) do
    {inserted, _rows} =
      Repo.insert_all(
        UsageReservation,
        [
          %{
            reservation_id: reservation_id,
            account_id: account_id,
            metric: metric,
            period: period,
            amount: amount,
            requested_limit: limit,
            inserted_at: timestamp,
            updated_at: timestamp
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:reservation_id]
      )

    if inserted == 0 do
      reservation = Repo.get_by!(UsageReservation, reservation_id: reservation_id)

      if reservation_intent(reservation) == {account_id, metric, period, amount, limit} do
        {:ok, Repo.one!(bucket_query(account_id, metric, period)), :duplicate}
      else
        {:error, :idempotency_conflict}
      end
    else
      attrs = %{account_id: account_id, metric: metric, period: period, used: 0, limit: limit}

      %UsageBucket{}
      |> UsageBucket.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :metric, :period])

      persisted_bucket = Repo.one!(bucket_query(account_id, metric, period))

      if persisted_bucket.limit != limit do
        {:error, :limit_mismatch, persisted_bucket}
      else
        query =
          from(bucket in UsageBucket,
            where:
              bucket.account_id == ^account_id and bucket.metric == ^metric and
                bucket.period == ^period and bucket.limit == ^limit and
                bucket.used + ^amount <= bucket.limit
          )

        case Repo.update_all(query, inc: [used: amount], set: [updated_at: timestamp]) do
          {1, _rows} ->
            {:ok, Repo.one!(bucket_query(account_id, metric, period)), :accepted}

          {0, _rows} ->
            {:error, :limit_exceeded, Repo.one!(bucket_query(account_id, metric, period))}
        end
      end
    end
  end

  defp reservation_intent(reservation) do
    {
      reservation.account_id,
      reservation.metric,
      reservation.period,
      reservation.amount,
      reservation.requested_limit
    }
  end

  defp bucket_query(account_id, metric, period) do
    from(bucket in UsageBucket,
      where:
        bucket.account_id == ^account_id and bucket.metric == ^metric and
          bucket.period == ^period
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp owned_inbox_claim(%InboxEvent{id: id, claim_token: token}) when is_binary(token) do
    from(event in InboxEvent,
      where: event.id == ^id and event.state == "processing" and event.claim_token == ^token
    )
  end

  defp owned_inbox_claim(%InboxEvent{}) do
    from(event in InboxEvent, where: false)
  end

  defp transition_claimed_command(command, state, result, extra \\ []) do
    updates =
      [
        state: state,
        result: result,
        claim_token: nil,
        claimed_at: nil,
        available_at: Keyword.get(extra, :available_at),
        delivered_at: Keyword.get(extra, :delivered_at)
      ]

    query =
      from(candidate in OutboxCommand,
        where:
          candidate.id == ^command.id and candidate.state == "dispatching" and
            candidate.claim_token == ^command.claim_token
      )

    case Repo.update_all(query, set: updates) do
      {1, _rows} -> {:ok, Repo.get!(OutboxCommand, command.id)}
      {0, _rows} -> {:error, :stale_claim}
    end
  end

  defp complete_claimed_command(command, result) do
    claimed = owned_outbox_claim(command)

    rerun = from(candidate in claimed, where: candidate.reconcile_again == true)

    case Repo.update_all(rerun,
           set: [
             state: "pending",
             result: result,
             reconcile_again: false,
             claim_token: nil,
             claimed_at: nil,
             available_at: now()
           ]
         ) do
      {1, _rows} ->
        {:ok, Repo.get!(OutboxCommand, command.id)}

      {0, _rows} ->
        delivered = from(candidate in claimed, where: candidate.reconcile_again == false)

        case Repo.update_all(delivered,
               set: [
                 state: "delivered",
                 result: result,
                 delivered_at: now(),
                 claim_token: nil,
                 claimed_at: nil,
                 available_at: nil
               ]
             ) do
          {1, _rows} ->
            {:ok, Repo.get!(OutboxCommand, command.id)}

          # A webhook may have toggled reconcile_again between the two guarded
          # updates. Retry the two-way compare-and-set rather than losing it.
          {0, _rows} ->
            case Repo.get(OutboxCommand, command.id) do
              %OutboxCommand{state: "dispatching", claim_token: token}
              when token == command.claim_token ->
                complete_claimed_command(command, result)

              _stale ->
                {:error, :stale_claim}
            end
        end
    end
  end

  defp owned_outbox_claim(command) do
    from(candidate in OutboxCommand,
      where:
        candidate.id == ^command.id and candidate.state == "dispatching" and
          candidate.claim_token == ^command.claim_token
    )
  end

  defp error_result(error), do: %{"error" => safe_error_summary(error)}

  defp resolve_enqueue_conflict(changeset, attrs) do
    existing =
      Repo.get_by(OutboxCommand, command_id: attrs.command_id) ||
        active_reconciliation(attrs.resource_key)

    cond do
      existing && existing.kind == attrs.kind && existing.payload == attrs.payload ->
        mark_reconciliation_again(existing, attrs.command_id)
        {:ok, existing, :duplicate}

      existing ->
        {:error, :idempotency_conflict}

      duplicate?(changeset) ->
        {:error, :idempotency_conflict}

      true ->
        {:error, changeset}
    end
  end

  defp mark_reconciliation_again(
         %OutboxCommand{state: "dispatching", resource_key: resource_key} = existing,
         incoming_command_id
       )
       when is_binary(resource_key) and incoming_command_id != existing.command_id do
    Repo.update_all(
      from(command in OutboxCommand,
        where: command.id == ^existing.id and command.state == "dispatching"
      ),
      set: [reconcile_again: true]
    )

    :ok
  end

  defp mark_reconciliation_again(_existing, _incoming_command_id), do: :ok

  defp active_reconciliation(nil), do: nil

  defp active_reconciliation(resource_key) do
    Repo.one(
      from(command in OutboxCommand,
        where: command.resource_key == ^resource_key and command.state in ^@active_outbox_states,
        limit: 1
      )
    )
  end

  defp reconciliation_resource_key("reconcile_subscription", %{"subscription_id" => id}),
    do: "subscription:" <> id

  defp reconciliation_resource_key("reconcile_refund", %{"refund_id" => id}),
    do: "refund:" <> id

  defp reconciliation_resource_key("reconcile_dispute", %{"dispute_id" => id}),
    do: "dispute:" <> id

  defp reconciliation_resource_key(_kind, _payload), do: nil

  defp claim_token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp backoff(attempts), do: min(round(:math.pow(2, max(attempts - 1, 0))), 300)

  defp duplicate?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, options}} ->
      options[:constraint] == :unique
    end)
  end

  defp resource_id(payload) do
    data = Map.get(payload, "data", %{})

    Enum.find_value(
      ["payment_id", "subscription_id", "refund_id", "dispute_id", "customer_id"],
      &Map.get(data, &1)
    )
  end

  defp safe_error_summary(%_{} = error), do: DodoPayments.Error.safe_summary(error)
  defp safe_error_summary(_error), do: %{category: :unknown_error}
end
