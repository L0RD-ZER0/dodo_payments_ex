defmodule DodoStore.BillingReliabilityTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias DodoStore.Billing
  alias DodoStore.Billing.{InboxEvent, OutboxCommand}
  alias DodoStore.Repo

  defmodule BlockingTransport do
    @behaviour DodoPayments.ClientModule

    @impl true
    def request({owner, calls}, _request) do
      Agent.update(calls, &(&1 + 1))
      send(owner, {:transport_entered, self()})

      receive do
        :release ->
          {:ok,
           %DodoPayments.HTTP.Response{
             status: 200,
             headers: [],
             body: ~s({"ingested_count":1})
           }}
      end
    end
  end

  defmodule UnknownTransport do
    @behaviour DodoPayments.ClientModule

    @impl true
    def request(calls, _request) do
      Agent.update(calls, &(&1 + 1))

      {:error, %DodoPayments.HTTP.TransportError{reason: :closed, delivery: :unknown}}
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "a command is claimed before I/O and two stale dispatches make one remote call" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    client = client(BlockingTransport, {self(), calls})

    assert {:ok, command, :accepted} =
             Billing.enqueue("usage:once", "usage_ingest", %{
               "events" => [
                 %{
                   "event_id" => "cus_1:once",
                   "event_name" => "api.call",
                   "customer_id" => "cus_1",
                   "metadata" => %{"value" => 1}
                 }
               ]
             })

    first = Task.async(fn -> DodoStore.Billing.OutboxDispatcher.dispatch(command, client) end)
    assert_receive {:transport_entered, transport_pid}

    second = Task.async(fn -> DodoStore.Billing.OutboxDispatcher.dispatch(command, client) end)
    assert {:error, :not_dispatchable} = Task.await(second)

    send(transport_pid, :release)
    assert {:ok, %DodoPayments.UsageEventIngestResponse{ingested_count: 1}} = Task.await(first)
    assert Agent.get(calls, & &1) == 1

    delivered = Repo.get!(OutboxCommand, command.id)
    assert delivered.state == "delivered"
    assert delivered.attempts == 1
  end

  test "an uncertain consequential command requires reconciliation and is never pending" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    client = client(UnknownTransport, calls)

    assert {:ok, command, :accepted} =
             Billing.enqueue("charge:invoice_1", "subscription_charge", %{
               "subscription_id" => "sub_1",
               "params" => %{"product_price" => 500}
             })

    assert {:error, %DodoPayments.Error.OutcomeUnknown{}} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, client)

    persisted = Repo.get!(OutboxCommand, command.id)
    assert persisted.state == "reconciliation_required"
    assert persisted.attempts == 1
    assert Billing.pending_commands() == []

    assert {:error, :not_dispatchable} =
             DodoStore.Billing.OutboxDispatcher.dispatch(command, client)

    assert Agent.get(calls, & &1) == 1
  end

  test "expired claims recover only replay-safe operations" do
    assert {:ok, usage, :accepted} =
             Billing.enqueue("usage:abandoned", "usage_ingest", %{"events" => []})

    assert {:ok, charge, :accepted} =
             Billing.enqueue("charge:abandoned", "subscription_charge", %{
               "subscription_id" => "sub_1",
               "params" => %{"product_price" => 500}
             })

    assert {:ok, usage_claim} = Billing.claim_command(usage)
    assert {:ok, charge_claim} = Billing.claim_command(charge)
    expire_claim(usage_claim)
    expire_claim(charge_claim)

    assert [%OutboxCommand{id: usage_id, state: "retryable"}] = Billing.pending_commands()
    assert usage_id == usage.id
    assert Repo.get!(OutboxCommand, charge.id).state == "reconciliation_required"
  end

  test "duplicate command IDs require an identical immutable intent" do
    assert {:ok, original, :accepted} =
             Billing.enqueue("stable", "usage_ingest", %{"events" => []})

    assert {:ok, duplicate, :duplicate} =
             Billing.enqueue("stable", "usage_ingest", %{"events" => []})

    assert duplicate.id == original.id

    assert {:error, :idempotency_conflict} =
             Billing.enqueue("stable", "usage_ingest", %{"events" => [%{"event_id" => "changed"}]})

    assert {:error, :idempotency_conflict} =
             Billing.enqueue("stable", "refund_create", %{"payment_id" => "pay_1"})
  end

  test "active reconciliation commands are coalesced by remote resource" do
    payload = %{"subscription_id" => "sub_same"}

    assert {:ok, first, :accepted} =
             Billing.enqueue("reconcile:webhook_1", "reconcile_subscription", payload)

    assert {:ok, second, :duplicate} =
             Billing.enqueue("reconcile:webhook_2", "reconcile_subscription", payload)

    assert second.id == first.id
    assert Repo.aggregate(OutboxCommand, :count) == 1
  end

  test "a webhook arriving during reconciliation schedules one follow-up read" do
    payload = %{"subscription_id" => "sub_inflight"}

    assert {:ok, command, :accepted} =
             Billing.enqueue("reconcile:webhook_before", "reconcile_subscription", payload)

    assert {:ok, claimed} = Billing.claim_command(command)

    assert {:ok, duplicate, :duplicate} =
             Billing.enqueue("reconcile:webhook_during", "reconcile_subscription", payload)

    assert duplicate.id == command.id
    assert Repo.get!(OutboxCommand, command.id).reconcile_again
    assert {:ok, requeued} = Billing.mark_command_delivered(claimed)
    assert requeued.state == "pending"
    refute requeued.reconcile_again
    assert [%OutboxCommand{id: id}] = Billing.pending_commands()
    assert id == command.id
  end

  test "webhook failures back off and eventually dead-letter without stale claim writes" do
    event = insert_inbox_event("wh_fails")
    assert {:ok, claimed} = Billing.claim_next_webhook()
    assert claimed.id == event.id
    assert {:error, :stale_claim} = Billing.mark_webhook_processed(event)

    final =
      Enum.reduce(1..5, claimed, fn attempt, current ->
        assert {:ok, failed} =
                 Billing.mark_webhook_failed(current, RuntimeError.exception("boom"))

        assert failed.attempts == attempt

        if attempt < 5 do
          assert failed.state == "retryable"
          make_due(failed)
          assert {:ok, reclaimed} = Billing.claim_next_webhook()
          reclaimed
        else
          failed
        end
      end)

    assert final.state == "dead_letter"
    assert final.dead_lettered_at
    assert Billing.claim_next_webhook() == :none
  end

  test "reservation replays compare the full intent and bucket limit" do
    assert {:ok, bucket, :accepted} =
             Billing.reserve_usage_once("action_1", "acct_1", "exports", "2026-08", 1, 3)

    assert bucket.used == 1

    assert {:ok, replayed, :duplicate} =
             Billing.reserve_usage_once("action_1", "acct_1", "exports", "2026-08", 1, 3)

    assert replayed.used == 1

    assert {:error, :idempotency_conflict} =
             Billing.reserve_usage_once("action_1", "acct_1", "exports", "2026-08", 2, 3)

    assert {:error, :limit_mismatch, mismatched} =
             Billing.reserve_usage_once("action_2", "acct_1", "exports", "2026-08", 1, 4)

    assert mismatched.limit == 3
    assert mismatched.used == 1
  end

  test "a duplicate reservation repairs a missing identical accounting command" do
    payload = %{"events" => [%{"event_id" => "cus_1:repair"}]}

    assert {:ok, _bucket, :accepted} =
             Billing.reserve_and_enqueue_usage(
               "reservation:repair",
               "acct_repair",
               "credits",
               "2026-08",
               1,
               10,
               "usage:repair",
               payload
             )

    Repo.delete_all(from(command in OutboxCommand, where: command.command_id == "usage:repair"))

    assert {:ok, repaired, :accepted} =
             Billing.reserve_and_enqueue_usage(
               "reservation:repair",
               "acct_repair",
               "credits",
               "2026-08",
               1,
               10,
               "usage:repair",
               payload
             )

    assert repaired.used == 1
    assert Repo.get_by!(OutboxCommand, command_id: "usage:repair").payload == payload
  end

  defp insert_inbox_event(webhook_id) do
    %InboxEvent{}
    |> InboxEvent.changeset(%{
      webhook_id: webhook_id,
      event_type: "example.failed",
      payload: %{"data" => %{}},
      state: "pending"
    })
    |> Repo.insert!()
  end

  defp make_due(event) do
    past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(from(candidate in InboxEvent, where: candidate.id == ^event.id),
      set: [available_at: past]
    )
  end

  defp expire_claim(command) do
    past = DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(from(candidate in OutboxCommand, where: candidate.id == ^command.id),
      set: [claimed_at: past]
    )
  end

  defp client(module, state) do
    DodoPayments.Client.new!(
      api_key: "test_key",
      client: {module, state},
      max_attempts: 1,
      retry_base_delay: 0,
      retry_max_delay: 0
    )
  end
end
