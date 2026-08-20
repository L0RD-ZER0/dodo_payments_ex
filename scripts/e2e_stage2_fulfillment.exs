Mix.Task.run("app.start")

defmodule DodoPayments.E2E.Stage2Fulfillment do
  @moduledoc false

  @customer_id "cus_0NlOsoRzDK8gRlyyLlbqk"

  def run do
    Logger.configure(level: :warning)
    vars = load_env!()
    refuse_live!(vars)

    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    client = client!(vars)
    state = %{run_id: run_id, operations: [], resources: [], findings: []}

    state
    |> feature_entitlement_wave(client)
    |> digital_files_wave(client)
    |> license_wave(client)
    |> persist!()
    |> summarize!()
  end

  defp feature_entitlement_wave(state, client) do
    {state, created} =
      call(state, :entitlements_create, fn ->
        DodoPayments.Entitlements.create(client, %{
          name: "Elixir E2E feature #{state.run_id}",
          description: "Automated test fixture; safe to delete",
          integration_type: :feature_flag,
          integration_config: %{feature_id: "elixir_e2e", feature_type: "boolean"},
          metadata: %{e2e_run: state.run_id}
        })
      end)

    case created do
      {:ok, entitlement} ->
        id = field!(entitlement, :id)
        state = resource(state, "entitlement", id, "soft_deleted")

        {state, _} =
          call(state, :entitlements_retrieve, fn ->
            DodoPayments.Entitlements.retrieve(client, id)
          end)

        {state, _} =
          call(state, :entitlements_update, fn ->
            DodoPayments.Entitlements.update(client, id, %{
              name: "Elixir E2E feature updated #{state.run_id}",
              metadata: %{e2e_run: state.run_id, updated: true}
            })
          end)

        {state, _} =
          call(state, :entitlement_grants_list, fn ->
            DodoPayments.EntitlementGrants.list(client, id, %{page_size: 10})
          end)

        {state, _} =
          call(state, :entitlements_delete, fn -> DodoPayments.Entitlements.delete(client, id) end)

        state

      {:error, _error} ->
        state
    end
  end

  defp digital_files_wave(state, client) do
    {state, created} =
      call(state, :entitlements_create, fn ->
        DodoPayments.Entitlements.create(client, %{
          name: "Elixir E2E digital files #{state.run_id}",
          description: "Automated upload contract probe; safe to delete",
          integration_type: :digital_files,
          integration_config: %{
            digital_file_ids: [],
            external_url: "https://example.com/elixir-e2e",
            instructions: "Automated test fixture"
          },
          metadata: %{e2e_run: state.run_id}
        })
      end)

    case created do
      {:ok, entitlement} ->
        id = field!(entitlement, :id)
        state = resource(state, "digital_files_entitlement", id, "soft_deleted")

        {state, uploaded} =
          call(state, :entitlement_files_upload, fn ->
            DodoPayments.Entitlements.Files.upload(client, id)
          end)

        state =
          case uploaded do
            {:ok, file} ->
              file_id = field!(file, :file_id)

              {state, _} =
                call(state, :entitlement_files_delete, fn ->
                  DodoPayments.Entitlements.Files.delete(client, id, file_id)
                end)

              state

            {:error, error} ->
              finding(state, :entitlement_files_upload, error)
          end

        {_cleanup_state, _} =
          call_without_record(state, fn -> DodoPayments.Entitlements.delete(client, id) end)

        state

      {:error, _error} ->
        state
    end
  end

  defp license_wave(state, client) do
    {state, product_result} =
      call_without_record(state, fn ->
        DodoPayments.Products.create(client, %{
          name: "Elixir E2E licensed product #{state.run_id}",
          description: "Automated license fixture",
          price: %{
            currency: :USD,
            discount: 0,
            price: 100,
            purchasing_power_parity: false,
            type: "one_time_price"
          },
          tax_category: :saas,
          license_key_enabled: true,
          license_key_activations_limit: 3,
          license_key_activation_message: "Automated E2E fixture",
          metadata: %{e2e_run: state.run_id}
        })
      end)

    case product_result do
      {:ok, product} ->
        product_id = field!(product, :product_id)
        key = "ELIXIR-E2E-#{System.system_time(:microsecond)}"
        state = resource(state, "licensed_product", product_id, "archived")

        {state, created} =
          call(state, :license_keys_create, fn ->
            DodoPayments.LicenseKeys.create(client, %{
              customer_id: @customer_id,
              key: key,
              product_id: product_id,
              activations_limit: 3
            })
          end)

        state =
          case created do
            {:ok, license} -> license_lifecycle(state, client, license, key)
            {:error, _error} -> state
          end

        {_cleanup_state, _} =
          call_without_record(state, fn -> DodoPayments.Products.archive(client, product_id) end)

        state

      {:error, error} ->
        finding(state, :license_fixture_product, error)
    end
  end

  defp license_lifecycle(state, client, license, key) do
    license_id = field!(license, :id)
    state = resource(state, "license_key", license_id, "retained_no_delete_endpoint")

    {state, _} =
      call(state, :license_keys_retrieve, fn ->
        DodoPayments.LicenseKeys.retrieve(client, license_id)
      end)

    {state, _} =
      call(state, :license_keys_update, fn ->
        DodoPayments.LicenseKeys.update(client, license_id, %{activations_limit: 4})
      end)

    {state, activated} =
      call(state, :licenses_activate, fn ->
        DodoPayments.Licenses.activate(client, %{license_key: key, name: "elixir-e2e-device"})
      end)

    case activated do
      {:ok, instance} ->
        instance_id = field!(instance, :id)
        state = resource(state, "license_key_instance", instance_id, "deactivated")

        {state, _} =
          call(state, :license_key_instances_retrieve, fn ->
            DodoPayments.LicenseKeyInstances.retrieve(client, instance_id)
          end)

        {state, _} =
          call(state, :license_key_instances_update, fn ->
            DodoPayments.LicenseKeyInstances.update(client, instance_id, %{
              name: "elixir-e2e-device-updated"
            })
          end)

        {state, _} =
          call(state, :licenses_validate, fn ->
            DodoPayments.Licenses.validate(client, %{
              license_key: key,
              license_key_instance_id: instance_id
            })
          end)

        {state, _} =
          call(state, :licenses_deactivate, fn ->
            DodoPayments.Licenses.deactivate(client, %{
              license_key: key,
              license_key_instance_id: instance_id
            })
          end)

        revoke_matching_grant(state, client, key)

      {:error, _error} ->
        state
    end
  end

  defp revoke_matching_grant(state, client, key) do
    case DodoPayments.Customers.Entitlements.list_grants(client, @customer_id, %{
           integration_type: :license_key,
           status: :delivered,
           page_size: 100
         }) do
      {:ok, page} ->
        grant =
          page.items
          |> Enum.find(fn item ->
            item
            |> field(:license_key)
            |> then(&(is_map(&1) and field(&1, :key) == key))
          end)

        if grant do
          entitlement_id = field!(grant, :entitlement_id)
          grant_id = field!(grant, :id)

          {state, _} =
            call(state, :entitlement_grants_revoke, fn ->
              DodoPayments.EntitlementGrants.revoke(client, entitlement_id, grant_id)
            end)

          state
        else
          %{
            state
            | findings: [
                %{operation: "entitlement_grants_revoke", message: "matching grant not found"}
                | state.findings
              ]
          }
        end

      {:error, error} ->
        finding(state, :entitlement_grants_revoke_fixture, error)
    end
  end

  defp call(state, operation, fun) do
    {state, result} = call_without_record(state, fun)

    row =
      case result do
        {:ok, value} ->
          %{
            operation: Atom.to_string(operation),
            status: "live_passed",
            response_shape: response_shape(value),
            wave: "fulfillment_lifecycle"
          }

        {:error, error} ->
          %{
            operation: Atom.to_string(operation),
            status: "live_failed",
            response_shape: "error",
            wave: "fulfillment_lifecycle",
            error_class: error.__struct__ |> inspect(),
            http_status: Map.get(error, :status),
            message: safe_message(error)
          }
      end

    next = %{state | operations: upsert(state.operations, row)}
    persist!(next)
    {next, result}
  end

  defp call_without_record(state, fun), do: {state, fun.()}

  defp resource(state, kind, id, cleanup) do
    entry = %{kind: kind, id: id, cleanup: cleanup}
    %{state | resources: [entry | state.resources]}
  end

  defp finding(state, operation, error) do
    entry = %{
      operation: Atom.to_string(operation),
      error_class: error.__struct__ |> inspect(),
      http_status: Map.get(error, :status),
      message: safe_message(error)
    }

    %{state | findings: [entry | state.findings]}
  end

  defp persist!(state) do
    directory = Path.join([File.cwd!(), "tmp", "e2e", state.run_id])
    File.mkdir_p!(directory)

    wave_path = Path.join(directory, "stage2_fulfillment.json")

    wave = %{
      run_id: state.run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      environment: "test",
      operations: Enum.reverse(state.operations),
      resources: Enum.reverse(state.resources),
      findings: Enum.reverse(state.findings)
    }

    write_private!(wave_path, wave)
    merge_observed!(directory, state.operations)
    state
  end

  defp merge_observed!(directory, rows) do
    path = Path.join(directory, "stage2_observed.json")
    existing = path |> File.read!() |> Jason.decode!()
    operations = Map.fetch!(existing, "operations")

    merged =
      (operations ++ Enum.map(rows, &stringify_keys/1))
      |> Enum.reverse()
      |> Enum.uniq_by(& &1["operation"])
      |> Enum.reverse()

    write_private!(path, Map.put(existing, "operations", merged))
  end

  defp write_private!(path, value) do
    File.write!(path, Jason.encode!(value, pretty: true), [:binary])
    File.chmod!(path, 0o600)
  end

  defp summarize!(state) do
    counts = Enum.frequencies_by(state.operations, & &1.status)

    IO.puts(
      "fulfillment_wave=#{state.run_id} passed=#{Map.get(counts, "live_passed", 0)} failed=#{Map.get(counts, "live_failed", 0)}"
    )

    if Map.get(counts, "live_failed", 0) > 0, do: System.halt(2)
  end

  defp upsert(rows, row) do
    [row | Enum.reject(rows, &(&1.operation == row.operation))]
  end

  defp field!(value, key) do
    field(value, key) ||
      raise "missing #{key} in #{inspect(value, limit: 20)}"
  end

  defp field(nil, _key), do: nil
  defp field(value, key), do: Map.get(value, key) || Map.get(value, Atom.to_string(key))

  defp response_shape(%DodoPayments.Page.Numbered{}), do: "numbered_page"
  defp response_shape(%DodoPayments.Page.Cursor{}), do: "cursor_page"
  defp response_shape(value) when is_list(value), do: "list"
  defp response_shape(value) when is_map(value), do: "map"
  defp response_shape(value) when is_binary(value), do: "binary"
  defp response_shape(nil), do: "empty"
  defp response_shape(_value), do: "other"

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp safe_message(error) do
    error
    |> Exception.message()
    |> String.replace(~r/(Bearer|api[_-]?key)\s+[^\s]+/i, "[REDACTED]")
    |> String.slice(0, 500)
  end

  defp load_env! do
    ".env"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      [key, value] = String.split(line, "=", parts: 2)
      {String.trim(key), value |> String.trim() |> String.trim("\"")}
    end)
  end

  defp client!(vars) do
    DodoPayments.client!(
      api_key: Map.fetch!(vars, "DODO_PAYMENTS_API_KEY"),
      environment: :test,
      max_attempts: 1
    )
  end

  defp refuse_live!(vars) do
    unless Map.get(vars, "DODO_PAYMENTS_ENVIRONMENT", "test") in ["test", "test_mode"] do
      raise "refusing to run E2E tests outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.Stage2Fulfillment.run()
