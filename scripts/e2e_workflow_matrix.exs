Mix.Task.run("app.start")

defmodule DodoPayments.E2E.WorkflowMatrix do
  @moduledoc false

  @required_workflow_fields ~w(
    elixir_action
    mcp_action
    mcp_observation
    elixir_observation
  )a

  def run do
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    directory = Path.join([File.cwd!(), "tmp", "e2e", run_id])
    stage2 = read_json!(Path.join(directory, "stage2.json"))

    evidence =
      read_optional_json(Path.join(directory, "workflow_evidence.json"), %{"operations" => []})

    evidence_by_operation = Map.new(evidence["operations"], &{&1["operation"], &1})

    operations =
      stage2
      |> catalog_operations()
      |> Enum.map(fn operation ->
        existing = Map.get(evidence_by_operation, operation["operation"], %{})
        build_row(operation, existing)
      end)

    report = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      operation_count: length(operations),
      counts: Enum.frequencies_by(operations, & &1.completion),
      operations: operations
    }

    unless length(operations) == DodoPayments.operation_count() do
      raise "workflow matrix catalog drift: source lock and catalogue disagree"
    end

    path = Path.join(directory, "workflow_matrix.json")
    write_private!(path, report)
    IO.puts("workflow_matrix=#{path} counts=#{inspect(report.counts)}")
  end

  defp build_row(operation, evidence) do
    base = %{
      operation: operation["operation"],
      method: operation["method"],
      path: operation["path"],
      workflow_kind: if(operation["method"] == "get", do: "read", else: "transition"),
      prior_elixir_probe: %{
        status: operation["status"],
        response_shape: operation["response_shape"],
        http_status: operation["http_status"],
        evidence_strength: "single_driver_probe"
      },
      elixir_action: pending(),
      mcp_action: pending(),
      mcp_observation: pending(),
      elixir_observation: pending(),
      transition_verified: false,
      divergence: "not_assessed",
      flags: [],
      notes: []
    }

    merged = deep_merge(base, atomize_top_level(evidence))
    Map.put(merged, :completion, completion(merged))
  end

  defp completion(row) do
    flags = Map.get(row, :flags, [])

    cond do
      row.workflow_kind == "read" and
        get_in(row, [:mcp_observation, :status]) == "passed" and
        get_in(row, [:elixir_observation, :status]) == "passed" and
          row.divergence in ["none", "explained"] ->
        "verified"

      "readback_not_supported" in flags and
        get_in(row, [:elixir_action, :status]) == "passed" and
        get_in(row, [:mcp_action, :status]) == "passed" and
        row.transition_verified == true and row.divergence == "explained" ->
        "flagged_complete"

      Enum.any?(
        flags,
        &(&1 in [
            "mcp_only_transition",
            "human_action_required",
            "account_state_unavailable",
            "external_contract_defect"
          ])
      ) and
          observations_satisfied?(row) ->
        "flagged_complete"

      Enum.all?(@required_workflow_fields, &(get_in(row, [&1, :status]) == "passed")) and
        row.transition_verified == true and row.divergence in ["none", "explained"] ->
        "verified"

      any_failed?(row) ->
        "diverged_or_failed"

      true ->
        "pending"
    end
  end

  defp observations_satisfied?(row) do
    get_in(row, [:mcp_observation, :status]) == "passed" and
      get_in(row, [:elixir_observation, :status]) in ["passed", "not_supported"]
  end

  defp any_failed?(row) do
    Enum.any?(@required_workflow_fields, &(get_in(row, [&1, :status]) == "failed"))
  end

  defp pending, do: %{status: "pending", evidence: nil}

  defp catalog_operations(stage2) do
    prior = Map.new(stage2["operations"], &{&1["operation"], &1})

    Enum.map(DodoPayments.Operation.all(), fn operation ->
      id = Atom.to_string(operation.id)

      Map.merge(
        %{
          "operation" => id,
          "method" => Atom.to_string(operation.method),
          "path" => operation.path,
          "status" => "not_run",
          "response_shape" => nil,
          "http_status" => nil
        },
        Map.get(prior, id, %{})
      )
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp atomize_top_level(map) do
    Map.new(map, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key
      {atom_key, atomize_nested(value)}
    end)
  end

  defp atomize_nested(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key
      {atom_key, atomize_nested(value)}
    end)
  end

  defp atomize_nested(list) when is_list(list), do: Enum.map(list, &atomize_nested/1)
  defp atomize_nested(value), do: value

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp read_optional_json(path, default) do
    if File.exists?(path), do: read_json!(path), else: default
  end

  defp write_private!(path, value) do
    File.write!(path, Jason.encode!(value, pretty: true), [:binary])
    File.chmod!(path, 0o600)
  end
end

DodoPayments.E2E.WorkflowMatrix.run()
