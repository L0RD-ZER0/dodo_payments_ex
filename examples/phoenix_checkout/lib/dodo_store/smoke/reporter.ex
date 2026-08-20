defmodule DodoStore.Smoke.Reporter do
  @moduledoc "Renders smoke reports without capability URLs or secrets."

  alias DodoStore.Smoke.{Outcome, Report, SecretSafe}

  @spec to_map(Report.t()) :: map()
  def to_map(%Report{} = report) do
    map = %{
      "run_id" => report.run_id,
      "profile" => to_string(report.profile),
      "seed" => report.seed,
      "outcome" => to_string(report.outcome),
      "started_at" => encode_time(report.started_at),
      "finished_at" => encode_time(report.finished_at),
      "preflight_error" => safe_error(report.preflight_error),
      "coverage" => stringify(report.coverage),
      "claims" => stringify(report.claims),
      "results" => Enum.map(report.results, &outcome_map/1)
    }

    :ok = assert_safe!(map)
    map
  end

  @spec to_json(Report.t()) :: String.t()
  def to_json(%Report{} = report), do: report |> to_map() |> Jason.encode!()

  @spec format(Report.t()) :: String.t()
  def format(%Report{} = report) do
    heading =
      "Dodo smoke #{String.upcase(to_string(report.outcome))} " <>
        "profile=#{report.profile} seed=#{report.seed} run=#{report.run_id}"

    claims =
      "Claims external_network=#{report.claims.external_network} " <>
        "webhook_delivery=#{report.claims.webhook_delivery} " <>
        "proves_dodo_origin=#{report.claims.proves_dodo_origin}."

    coverage = format_coverage(report.coverage)

    rows =
      Enum.map_join(report.results, "\n", fn result ->
        "[#{String.upcase(to_string(result.outcome))}] #{result.scenario_id} " <>
          "lifecycle=#{result.lifecycle_outcome} verification=#{result.verification_level}"
      end)

    Enum.reject([heading, claims, coverage, rows], &(&1 == "")) |> Enum.join("\n")
  end

  defp outcome_map(%Outcome{} = result) do
    %{
      "scenario_id" => result.scenario_id,
      "target" => stringify(result.target || %{}),
      "lifecycle_outcome" => to_string(result.lifecycle_outcome),
      "outcome" => to_string(result.outcome),
      "verification_level" => to_string(result.verification_level),
      "support_expectation" => to_string(result.support_expectation),
      "duration_ms" => result.duration_ms,
      "signature_provenance" => to_string(result.signature_provenance),
      "processor_mode" => to_string(result.processor_mode),
      "observations" => stringify(result.observations),
      "errors" => stringify(result.errors)
    }
  end

  defp format_coverage(%{selected: selected} = coverage) do
    "Coverage mode=#{coverage.mode} selected=#{selected} " <>
      "passed=#{coverage.passed} skipped=#{coverage.skipped} " <>
      "failed=#{coverage.failed} inconclusive=#{coverage.inconclusive}"
  end

  defp format_coverage(_coverage), do: "Coverage not executed."

  defp safe_error(nil), do: nil
  defp safe_error(%{reason: reason}), do: %{"reason" => to_string(reason)}
  defp safe_error(_error), do: %{"reason" => "preflight_failed"}

  defp stringify(%_{} = struct), do: struct |> Map.from_struct() |> stringify()

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value) when is_boolean(value) or is_nil(value), do: value
  defp stringify(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify(value), do: value

  defp encode_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp encode_time(_time), do: nil

  defp assert_safe!(map) do
    case SecretSafe.check(map) do
      :ok -> :ok
      {:error, path} -> raise ArgumentError, "unsafe smoke report field at #{path}"
    end
  end
end
