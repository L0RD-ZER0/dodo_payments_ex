defmodule DodoStore.OutboxProcessorTest do
  use ExUnit.Case, async: false

  alias DodoStore.Billing
  alias DodoStore.Billing.{OutboxCommand, OutboxProcessor}
  alias DodoStore.Repo

  defmodule SuccessfulTransport do
    @behaviour DodoPayments.ClientModule

    @impl true
    def request(calls, _request) do
      Agent.update(calls, &(&1 + 1))

      {:ok,
       %DodoPayments.HTTP.Response{
         status: 200,
         headers: [],
         body: ~s({"ingested_count":1})
       }}
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    %{calls: calls, client: client(SuccessfulTransport, calls)}
  end

  test "the supervised poller dispatches a bounded durable batch", %{calls: calls, client: client} do
    first = enqueue("processor:first")
    second = enqueue("processor:second")

    pid =
      start_supervised!(
        {OutboxProcessor,
         name: :smoke_outbox_processor, interval: 60_000, batch_size: 1, client: client}
      )

    send(pid, :process)
    assert_eventually(fn -> Repo.get!(OutboxCommand, first.id).state == "delivered" end)
    assert Repo.get!(OutboxCommand, second.id).state == "pending"
    assert Agent.get(calls, & &1) == 1

    send(pid, :process)
    assert_eventually(fn -> Repo.get!(OutboxCommand, second.id).state == "delivered" end)
    assert Agent.get(calls, & &1) == 2
  end

  test "a supervisor restarts the poller and durable work remains dispatchable", %{client: client} do
    name = :restarting_smoke_outbox_processor

    original =
      start_supervised!(
        {OutboxProcessor, name: name, interval: 60_000, batch_size: 20, client: client}
      )

    monitor = Process.monitor(original)
    Process.exit(original, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^original, :killed}

    restarted = assert_eventually(fn -> Process.whereis(name) end)
    refute restarted == original

    command = enqueue("processor:after_restart")
    send(restarted, :process)

    assert_eventually(fn -> Repo.get!(OutboxCommand, command.id).state == "delivered" end)
  end

  test "an injected client provider and per-command isolation keep a batch moving", %{
    calls: calls,
    client: client
  } do
    first = enqueue("processor:raises")
    second = enqueue("processor:continues")
    test_process = self()

    dispatcher = fn command, provided_client ->
      send(test_process, {:provided_client, provided_client})

      if command.id == first.id do
        raise "simulated dispatcher crash"
      else
        DodoStore.Billing.OutboxDispatcher.dispatch(command, provided_client)
      end
    end

    assert :ok =
             OutboxProcessor.run_once(
               client: fn -> client end,
               dispatcher: dispatcher,
               batch_size: 2
             )

    assert_receive {:provided_client, ^client}
    assert_receive {:provided_client, ^client}
    assert Repo.get!(OutboxCommand, first.id).state == "pending"
    assert Repo.get!(OutboxCommand, second.id).state == "delivered"
    assert Agent.get(calls, & &1) == 1
  end

  defp enqueue(command_id) do
    assert {:ok, command, :accepted} =
             Billing.enqueue(command_id, "usage_ingest", %{
               "events" => [
                 %{
                   "event_id" => command_id,
                   "event_name" => "smoke.event",
                   "customer_id" => "cus_smoke",
                   "metadata" => %{"value" => 1}
                 }
               ]
             })

    command
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

  defp assert_eventually(fun, attempts \\ 50)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    case fun.() do
      value when value in [false, nil] ->
        Process.sleep(10)
        assert_eventually(fun, attempts - 1)

      value ->
        value
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition did not become true")
end
