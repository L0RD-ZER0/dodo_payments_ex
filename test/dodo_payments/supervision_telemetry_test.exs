defmodule DodoPayments.SupervisionTelemetryTest do
  use ExUnit.Case, async: false

  alias DodoPayments.Deadline

  setup do
    previous = Application.get_env(:dodo_payments, DodoPayments.Telemetry)

    on_exit(fn ->
      if previous do
        Application.put_env(:dodo_payments, DodoPayments.Telemetry, previous)
      else
        Application.delete_env(:dodo_payments, DodoPayments.Telemetry)
      end
    end)

    :ok
  end

  test "deadline worker exits never take down the caller" do
    caller = self()

    task =
      Task.async(fn ->
        assert :timeout == Deadline.run(fn -> Process.exit(self(), :kill) end, 100)
        send(caller, :caller_survived)
        :ok
      end)

    assert :ok == Task.await(task)
    assert_received :caller_survived
  end

  test "deadline worker preserves process dictionary and logger metadata" do
    Process.put(:dodo_payments_test_context, :preserved)
    Logger.metadata(ansi_color: :preserved)

    assert {:ok, {context, metadata}} =
             Deadline.run(
               fn ->
                 {Process.get(:dodo_payments_test_context), Logger.metadata()}
               end,
               100
             )

    assert context == :preserved
    assert {:ansi_color, :preserved} in metadata
  end

  test "deadline startup failure is bounded when the supervisor is missing" do
    started = System.monotonic_time(:millisecond)

    assert :timeout ==
             Deadline.run(
               fn -> flunk("callback must not run") end,
               20,
               :missing_deadline_supervisor
             )

    assert System.monotonic_time(:millisecond) - started < 500
  end

  test "deadline startup is bounded when the supervisor call does not reply" do
    supervisor_name = :blocked_deadline_supervisor
    blocked = spawn(fn -> Process.sleep(:infinity) end)
    Process.register(blocked, supervisor_name)

    on_exit(fn ->
      if Process.alive?(blocked), do: Process.exit(blocked, :kill)
    end)

    started = System.monotonic_time(:millisecond)

    assert :timeout ==
             Deadline.run(fn -> flunk("callback must not run") end, 20, supervisor_name)

    assert System.monotonic_time(:millisecond) - started < 500
  end

  test "default telemetry mode remains request bounded" do
    assert %{mode: :request_bounded, max_concurrency: max, timeout: timeout} =
             DodoPayments.Telemetry.validate_config!()

    assert max > 0
    assert timeout > 0
    refute Process.whereis(DodoPayments.Telemetry.TaskSupervisor)
  end

  test "telemetry configuration rejects invalid startup values" do
    assert_raise ArgumentError, ~r/mode/, fn ->
      DodoPayments.Telemetry.validate_config!(mode: :later)
    end

    assert_raise ArgumentError, ~r/max_concurrency/, fn ->
      DodoPayments.Telemetry.validate_config!(max_concurrency: 0)
    end

    assert_raise ArgumentError, ~r/timeout/, fn ->
      DodoPayments.Telemetry.validate_config!(timeout: -1)
    end

    assert_raise ArgumentError, ~r/expected only/, fn ->
      DodoPayments.Telemetry.validate_config!(max_concurreny: 10)
    end
  end

  test "async telemetry dispatch does not block the request process" do
    {task_supervisor, _supervisor_name} = start_async_telemetry_supervisor()
    handler_id = "dodo-async-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler_id,
      [:dodo_payments, :test, :async],
      fn event, _measurements, _metadata, pid ->
        send(pid, {:telemetry_callback_started, self()})

        receive do
          :release -> :ok
        end

        send(pid, {:telemetry_event, event})
      end,
      parent
    )

    try do
      dispatch =
        Task.async(fn ->
          DodoPayments.Telemetry.Supervisor.dispatch(
            [:dodo_payments, :test, :async],
            %{},
            %{},
            1_000,
            task_supervisor
          )
        end)

      assert {:ok, :ok} = Task.yield(dispatch, 200)
      assert_receive {:telemetry_callback_started, callback_pid}, 500
      refute_receive {:telemetry_event, _}, 0
      send(callback_pid, :release)
      assert_receive {:telemetry_event, [:dodo_payments, :test, :async]}, 500
    after
      :telemetry.detach(handler_id)
    end
  end

  test "async telemetry callback is independently timed out" do
    {task_supervisor, _supervisor_name} = start_async_telemetry_supervisor()
    event = [:dodo_payments, :test, :async_timeout]
    handler_id = "dodo-async-timeout-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler_id,
      event,
      fn _event, _measurements, _metadata, pid ->
        send(pid, :callback_started)
        Process.sleep(200)
        send(pid, :callback_finished)
      end,
      parent
    )

    try do
      assert :ok ==
               DodoPayments.Telemetry.Supervisor.dispatch(
                 event,
                 %{},
                 %{},
                 20,
                 task_supervisor
               )

      assert_receive :callback_started, 200
      refute_receive :callback_finished, 100
    after
      :telemetry.detach(handler_id)
    end
  end

  test "async telemetry drops work when its task supervisor is saturated" do
    suffix = System.unique_integer([:positive])
    supervisor_name = String.to_atom("dodo_telemetry_supervisor_#{suffix}")
    task_supervisor = String.to_atom("dodo_telemetry_tasks_#{suffix}")
    event = [:dodo_payments, :test, :async_saturated]
    handler_id = "dodo-async-saturated-#{suffix}"
    parent = self()

    start_supervised!(
      {DodoPayments.Telemetry.Supervisor,
       config: %{mode: :async, max_concurrency: 1, timeout: 500},
       name: supervisor_name,
       task_supervisor: task_supervisor}
    )

    :telemetry.attach(
      handler_id,
      event,
      fn _event, _measurements, _metadata, pid ->
        send(pid, {:saturated_callback_started, self()})

        receive do
          :release -> :ok
        end
      end,
      parent
    )

    try do
      assert :ok ==
               DodoPayments.Telemetry.Supervisor.dispatch(
                 event,
                 %{},
                 %{},
                 500,
                 task_supervisor
               )

      assert_receive {:saturated_callback_started, callback_pid}, 200

      assert :ok ==
               DodoPayments.Telemetry.Supervisor.dispatch(
                 event,
                 %{},
                 %{},
                 500,
                 task_supervisor
               )

      refute_receive {:saturated_callback_started, _}, 100
      send(callback_pid, :release)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp start_async_telemetry_supervisor do
    suffix = System.unique_integer([:positive])
    supervisor_name = String.to_atom("dodo_async_telemetry_supervisor_#{suffix}")
    task_supervisor = String.to_atom("dodo_async_telemetry_tasks_#{suffix}")

    start_supervised!(
      {DodoPayments.Telemetry.Supervisor,
       config: %{mode: :async, max_concurrency: 4, timeout: 500},
       name: supervisor_name,
       task_supervisor: task_supervisor}
    )

    {task_supervisor, supervisor_name}
  end
end
