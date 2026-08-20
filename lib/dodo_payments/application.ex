defmodule DodoPayments.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    config = DodoPayments.Telemetry.validate_config!()

    children =
      [{Task.Supervisor, name: DodoPayments.DeadlineTaskSupervisor}] ++
        telemetry_children(config)

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: DodoPayments.Supervisor
    )
  end

  defp telemetry_children(%{mode: :async} = config) do
    [{DodoPayments.Telemetry.Supervisor, config: config}]
  end

  defp telemetry_children(%{mode: :request_bounded}), do: []
end
