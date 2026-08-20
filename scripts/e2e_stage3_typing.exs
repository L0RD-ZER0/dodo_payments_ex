Mix.Task.run("app.start")

defmodule DodoPayments.E2E.Stage3Typing do
  @moduledoc false

  alias DodoPayments.{Enums, Operation, RequestTypes}

  def run do
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    operations = Operation.all()
    live_statuses = live_statuses(run_id)
    workflow_completions = workflow_completions(run_id)
    residuals = RequestTypes.generic_nested_residuals()
    enum_result = validate_enums()
    response = response_inventory(operations, live_statuses, workflow_completions)

    report = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      source_sdk_version: DodoPayments.source_sdk_version(),
      operation_count: length(operations),
      request_contracts: %{
        typed_parameter_maps: length(RequestTypes.schema_ids()),
        upstream_interfaces:
          Enum.count(
            RequestTypes.schema_ids(),
            &match?({:upstream, _, _}, RequestTypes.source(&1))
          ),
        schema_first_interfaces:
          Enum.count(RequestTypes.schema_ids(), &(RequestTypes.source(&1) == :schema_first)),
        path_or_options_only: Enum.count(operations, &(RequestTypes.source(&1.id) == nil)),
        generic_nested_residual_count: length(residuals),
        generic_nested_residuals:
          Enum.map(residuals, &residual_row(&1, live_statuses, workflow_completions))
      },
      response_contracts: response,
      enum_contracts: enum_result,
      explicit_response_residuals: [
        %{
          model: "DodoPayments.Subscription",
          field: "business_id",
          type: "term() | nil",
          reason: "legacy field absent from the locked upstream subscription declaration"
        }
      ]
    }

    assert_contract!(report)
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage3_typing.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)

    IO.puts(
      "stage3_run=#{run_id} operations=#{length(operations)} request_residuals=#{length(residuals)} generic_responses=#{response.generic_json_count} enum_values=#{enum_result.value_count}"
    )

    IO.puts("stage3_report=#{path}")
  end

  defp response_inventory(operations, live_statuses, workflow_completions) do
    rows = Enum.map(operations, &response_row(&1, live_statuses, workflow_completions))
    generic = Enum.filter(rows, &(&1.contract in ["generic_json", "generic_page_items"]))

    %{
      counts: Enum.frequencies_by(rows, & &1.contract),
      generic_json_count: length(generic),
      generic_json_operations: generic,
      operations: rows
    }
  end

  defp response_row(operation, live_statuses, workflow_completions) do
    contract =
      cond do
        operation.pagination != nil and operation.item_schema != nil -> "typed_page_items"
        operation.pagination != nil -> "generic_page_items"
        operation.response_mode == :empty -> "empty"
        operation.response_mode in [:binary, :pdf, :csv] -> "binary"
        operation.response_schema != nil -> "typed_struct"
        operation.item_schema != nil -> "typed_list_items"
        true -> "generic_json"
      end

    %{
      operation: Atom.to_string(operation.id),
      contract: contract,
      live_status: Map.get(live_statuses, operation.id, "not_run"),
      workflow_completion: Map.get(workflow_completions, operation.id, "not_run"),
      response_schema: module_name(operation.response_schema),
      item_schema: module_name(operation.item_schema)
    }
  end

  defp residual_row({operation, field, descriptor}, live_statuses, workflow_completions) do
    %{
      operation: Atom.to_string(operation),
      field: Atom.to_string(field),
      descriptor: inspect(descriptor),
      live_status: Map.get(live_statuses, operation, "not_run"),
      workflow_completion: Map.get(workflow_completions, operation, "not_run")
    }
  end

  defp validate_enums do
    results =
      for enum <- Enums.names(), value <- Enums.values(enum) do
        with {:ok, wire} <- Enums.dump(enum, value),
             ^value <- Enums.load(enum, wire) do
          %{enum: enum, value: value, wire: wire, status: "passed"}
        else
          result -> %{enum: enum, value: value, status: "failed", result: inspect(result)}
        end
      end

    atom_count_before = :erlang.system_info(:atom_count)

    unknowns =
      for index <- 1..2_000 do
        Enums.load(:currency, "__elixir_e2e_unknown_#{index}__")
      end

    atom_count_after = :erlang.system_info(:atom_count)

    unless Enum.all?(unknowns, &match?(%DodoPayments.UnknownEnum{}, &1)) do
      raise "unknown enum values did not remain lossless wrappers"
    end

    %{
      domain_count: length(Enums.names()),
      value_count: length(results),
      round_trip_failures: Enum.filter(results, &(&1.status == "failed")),
      unknown_value_probe_count: length(unknowns),
      atom_count_before: atom_count_before,
      atom_count_after: atom_count_after,
      atom_growth: atom_count_after - atom_count_before
    }
  end

  defp live_statuses(run_id) do
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "stage2.json"])

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("operations")
    |> Map.new(fn row -> {String.to_existing_atom(row["operation"]), row["status"]} end)
  end

  defp workflow_completions(run_id) do
    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "workflow_matrix.json"])

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("operations")
    |> Map.new(fn row -> {String.to_existing_atom(row["operation"]), row["completion"]} end)
  end

  defp assert_contract!(report) do
    request = report.request_contracts
    enum = report.enum_contracts

    unless report.operation_count == 140 and request.typed_parameter_maps == 82 and
             request.upstream_interfaces == 80 and request.schema_first_interfaces == 2 and
             request.path_or_options_only == 58 and request.generic_nested_residual_count == 0 do
      raise "request typing contract drifted; inspect the Stage 3 report"
    end

    unless enum.round_trip_failures == [] and enum.atom_growth == 0 do
      raise "enum typing safety probe failed; inspect the Stage 3 report"
    end

    unless report.response_contracts.generic_json_count == 0 do
      raise "generic response contracts remain; inspect the Stage 3 report"
    end
  end

  defp module_name(nil), do: nil
  defp module_name(module), do: inspect(module)
end

DodoPayments.E2E.Stage3Typing.run()
