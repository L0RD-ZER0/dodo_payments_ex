defmodule DodoPayments.Deadline do
  @moduledoc false

  @max_timeout 4_294_967_295

  @reserved_process_keys [
    :"$ancestors",
    :"$callers",
    :"$initial_call",
    :"$logger_metadata$"
  ]

  @spec remaining(integer()) :: integer()
  def remaining(deadline), do: deadline - now()

  @spec max_timeout() :: pos_integer()
  def max_timeout, do: @max_timeout

  @spec valid_timeout?(term()) :: boolean()
  def valid_timeout?(timeout),
    do: is_integer(timeout) and timeout > 0 and timeout <= @max_timeout

  @spec run((-> result), integer()) :: {:ok, result} | :timeout when result: term()
  def run(fun, timeout) when is_function(fun, 0) and timeout > 0 do
    run(fun, timeout, DodoPayments.DeadlineTaskSupervisor)
  end

  def run(fun, _timeout) when is_function(fun, 0), do: :timeout

  @doc false
  @spec run((-> result), integer(), Supervisor.supervisor()) :: {:ok, result} | :timeout
        when result: term()
  def run(fun, timeout, task_supervisor)
      when is_function(fun, 0) and timeout > 0 do
    execution_context = capture_execution_context()
    deadline = now() + timeout
    caller = self()
    reference = make_ref()

    # Starting a Task through a supervisor is itself a synchronous call. Put
    # that call behind a monitored starter so a missing, restarting, or stuck
    # supervisor cannot escape or outlive the caller's deadline. The worker
    # waits for an explicit go-ahead, which prevents an orphaned callback in
    # the narrow race where startup finishes as the caller times out.
    {starter, starter_monitor} =
      spawn_monitor(fn ->
        worker = fn ->
          receive do
            {^reference, :execute} ->
              result = with_execution_context(execution_context, fun)
              send(caller, {reference, :result, result})
          after
            timeout -> :ok
          end
        end

        send(caller, {reference, :started, start_child(task_supervisor, worker)})
      end)

    await_start(reference, starter, starter_monitor, deadline)
  end

  def run(fun, _timeout, _task_supervisor) when is_function(fun, 0), do: :timeout

  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)

  @doc false
  def capture_execution_context do
    dictionary =
      Process.get()
      |> Enum.reject(fn {key, _value} -> key in @reserved_process_keys end)

    %{
      caller: self(),
      callers: Process.get(:"$callers", []),
      dictionary: dictionary,
      logger_metadata: Logger.metadata()
    }
  end

  @doc false
  def with_execution_context(snapshot, fun) do
    Enum.each(snapshot.dictionary, fn {key, value} -> Process.put(key, value) end)
    inherit_callers(snapshot)
    Logger.metadata(snapshot.logger_metadata)
    fun.()
  end

  defp inherit_callers(snapshot) do
    current_callers = Process.get(:"$callers", [])
    inherited_callers = [snapshot.caller | snapshot.callers]
    Process.put(:"$callers", Enum.uniq(inherited_callers ++ current_callers))
  end

  defp start_child(task_supervisor, fun) do
    Task.Supervisor.start_child(task_supervisor, fun)
  catch
    :exit, reason -> {:error, {:supervisor_exit, reason}}
  end

  defp await_start(reference, starter, starter_monitor, deadline) do
    case receive_until(deadline, reference, starter_monitor) do
      {:started, {:ok, worker}} ->
        Process.demonitor(starter_monitor, [:flush])
        worker_monitor = Process.monitor(worker)
        send(worker, {reference, :execute})
        await_result(reference, worker, worker_monitor, deadline)

      {:started, {:error, _reason}} ->
        Process.demonitor(starter_monitor, [:flush])
        :timeout

      {:down, _reason} ->
        :timeout

      :timeout ->
        Process.exit(starter, :kill)
        Process.demonitor(starter_monitor, [:flush])
        stop_late_worker(reference)
        :timeout
    end
  end

  defp await_result(reference, worker, worker_monitor, deadline) do
    remaining = max(remaining(deadline), 0)

    receive do
      {^reference, :result, result} ->
        Process.demonitor(worker_monitor, [:flush])
        {:ok, result}

      {:DOWN, ^worker_monitor, :process, ^worker, _reason} ->
        receive do
          {^reference, :result, result} -> {:ok, result}
        after
          0 -> :timeout
        end
    after
      remaining ->
        Process.exit(worker, :kill)
        Process.demonitor(worker_monitor, [:flush])
        :timeout
    end
  end

  defp receive_until(deadline, reference, starter_monitor) do
    remaining = max(remaining(deadline), 0)

    receive do
      {^reference, :started, result} -> {:started, result}
      {:DOWN, ^starter_monitor, :process, _pid, reason} -> {:down, reason}
    after
      remaining -> :timeout
    end
  end

  defp stop_late_worker(reference) do
    receive do
      {^reference, :started, {:ok, worker}} -> Process.exit(worker, :kill)
      {^reference, :started, {:error, _reason}} -> :ok
    after
      0 -> :ok
    end
  end
end
