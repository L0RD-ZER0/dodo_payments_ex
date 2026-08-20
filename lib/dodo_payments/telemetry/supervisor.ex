defmodule DodoPayments.Telemetry.Supervisor do
  @moduledoc false

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    task_supervisor = Keyword.get(opts, :task_supervisor, DodoPayments.Telemetry.TaskSupervisor)

    children = [
      {Task.Supervisor, name: task_supervisor, max_children: config.max_concurrency}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @spec dispatch(term(), map(), map(), pos_integer(), atom()) :: :ok
  def dispatch(
        event,
        measurements,
        metadata,
        timeout,
        task_supervisor \\ DodoPayments.Telemetry.TaskSupervisor
      ) do
    execution_context = DodoPayments.Deadline.capture_execution_context()

    task = fn ->
      DodoPayments.Deadline.with_execution_context(execution_context, fn ->
        {:ok, timer} = :timer.kill_after(timeout)

        try do
          :telemetry.execute(event, measurements, metadata)
        after
          :timer.cancel(timer)
        end
      end)
    end

    case Task.Supervisor.start_child(task_supervisor, task) do
      {:ok, _pid} -> :ok
      {:error, :max_children} -> :ok
      {:error, _reason} -> :ok
    end
  catch
    :exit, _reason -> :ok
  end
end
