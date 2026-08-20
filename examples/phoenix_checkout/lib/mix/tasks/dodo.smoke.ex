defmodule Mix.Tasks.Dodo.Smoke do
  @shortdoc "Runs the DodoStore production-shaped smoke harness"

  @moduledoc """
  Plans or runs an isolated DodoStore smoke profile.

      mix dodo.smoke --profile local --features core --dry-run

  `--dry-run` loads configuration and expands the exact scenario set, but does
  not start DodoStore, open a listener, migrate a database, or call Dodo.
  """

  use Mix.Task

  alias DodoStore.Smoke.{Options, PaymentMethodRegistry, Report, Reporter}

  # Runtime owns application start because it must install the ephemeral
  # database, HTTP listener, and worker configuration first.
  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    case Options.parse(argv) do
      {:ok, %Options{help: true}} ->
        Mix.shell().info(Options.help())

      {:ok, %Options{} = options} ->
        Mix.shell().info("Dodo smoke seed: #{options.seed}")
        dispatch(options)

      {:error, error} ->
        Mix.raise(error.message)
    end
  end

  defp dispatch(%Options{dry_run: true} = options), do: print_plan(options)

  defp dispatch(%Options{} = options) do
    Logger.configure(level: :warning)
    runner = DodoStore.Smoke.Runner

    if Code.ensure_loaded?(runner) and function_exported?(runner, :run, 1) do
      case apply(runner, :run, [options]) do
        :ok ->
          :ok

        {:ok, %Report{} = report} ->
          emit_report(options, report)

        {:error, %Report{} = report} ->
          emit_report(options, report)
          Mix.raise("Dodo smoke failed: #{report.outcome}")

        {:error, reason} ->
          Mix.raise("Dodo smoke failed: #{safe_reason(reason)}")

        other ->
          Mix.raise("Dodo smoke runner returned an invalid result: #{safe_reason(other)}")
      end
    else
      Mix.raise("DodoStore.Smoke.Runner is not available; use --dry-run to inspect the plan")
    end
  end

  defp emit_report(options, report) do
    Mix.shell().info(Reporter.format(report))

    if options.report do
      write_report!(options.report, Reporter.to_json(report))
      Mix.shell().info("Report: #{Path.expand(options.report)}")
    end

    :ok
  end

  defp write_report!(path, json) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, json <> "\n", [:binary])
      File.rename!(temporary, path)
    after
      if File.exists?(temporary), do: File.rm!(temporary)
    end
  end

  defp print_plan(options) do
    scenarios = PaymentMethodRegistry.expand(options)

    Mix.shell().info(
      "profile=#{cli(options.profile)} features=#{join(options.features)} " <>
        "interaction=#{options.interaction} execution=#{options.execution} " <>
        "coverage=#{options.coverage} scenarios=#{length(scenarios)}"
    )

    Enum.each(scenarios, fn scenario ->
      Mix.shell().info(
        "PLAN #{scenario.id} target=#{scenario.verification_target} " <>
          "support=#{scenario.support_expectation} interaction=#{scenario.declared_interaction}"
      )
    end)

    :ok
  end

  defp join(values), do: Enum.map_join(values, ",", &cli/1)
  defp cli(value), do: value |> Atom.to_string() |> String.replace("_", "-")

  # Inspect protocol implementations for SDK secrets and response capability
  # wrappers are redacted. Limit output so an unexpected runner result cannot
  # flood CI logs.
  defp safe_reason(reason), do: inspect(reason, limit: 20, printable_limit: 500)
end
