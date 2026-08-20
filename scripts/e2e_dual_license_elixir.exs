Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualLicenseElixir do
  @moduledoc false

  @customer_id "cus_0NlfOKxVjKiEIFLUhrFHI"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))
    key = "ELIXIR-E2E-#{marker}"

    {:ok, observed_mcp_license} = DodoPayments.LicenseKeys.retrieve(client, mcp["license_id"])

    {:ok, observed_mcp_instance} =
      DodoPayments.LicenseKeyInstances.retrieve(client, mcp["instance_id"])

    {:ok, observed_mcp_validation} =
      DodoPayments.Licenses.validate(client, %{
        license_key: mcp["license_key"],
        license_key_instance_id: mcp["instance_id"]
      })

    {:ok, product} = create_product(client, marker)
    product_id = field(product, :product_id)

    {:ok, license} =
      DodoPayments.LicenseKeys.create(client, %{
        customer_id: @customer_id,
        key: key,
        product_id: product_id,
        activations_limit: 3
      })

    license_id = field(license, :id)

    {:ok, updated_license} =
      DodoPayments.LicenseKeys.update(client, license_id, %{activations_limit: 4})

    {:ok, retrieved_license} = DodoPayments.LicenseKeys.retrieve(client, license_id)

    {:ok, listed_licenses} =
      DodoPayments.LicenseKeys.list(client, %{
        customer_id: @customer_id,
        product_id: product_id,
        page_size: 100
      })

    {:ok, instance} =
      DodoPayments.Licenses.activate(client, %{license_key: key, name: "elixir-e2e-device"})

    instance_id = field(instance, :id)

    {:ok, updated_instance} =
      DodoPayments.LicenseKeyInstances.update(client, instance_id, %{
        name: "elixir-e2e-device-updated"
      })

    {:ok, retrieved_instance} = DodoPayments.LicenseKeyInstances.retrieve(client, instance_id)

    {:ok, listed_instances} =
      DodoPayments.LicenseKeyInstances.list(client, %{
        license_key_id: license_id,
        page_size: 100
      })

    {:ok, validation} =
      DodoPayments.Licenses.validate(client, %{
        license_key: key,
        license_key_instance_id: instance_id
      })

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      product_id: product_id,
      license_key: key,
      license_id: license_id,
      instance_id: instance_id,
      license: %{
        updated_limit: field(updated_license, :activations_limit),
        retrieved: compact_license(retrieved_license),
        listed: includes?(listed_licenses, license_id)
      },
      instance: %{
        updated_name: field(updated_instance, :name),
        retrieved: compact_instance(retrieved_instance),
        listed: includes?(listed_instances, instance_id)
      },
      validation: field(validation, :valid),
      observed_mcp: %{
        license: compact_license(observed_mcp_license),
        instance: compact_instance(observed_mcp_instance),
        valid: field(observed_mcp_validation, :valid)
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_license_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_license_elixir_report=#{path}")
  end

  defp create_product(client, marker) do
    DodoPayments.Products.create(client, %{
      name: "Elixir Dual Licensed Product #{marker}",
      description: "Automated dual-driver license fixture",
      price: %{
        currency: :usd,
        discount: 0,
        price: 100,
        purchasing_power_parity: false,
        type: "one_time_price"
      },
      tax_category: :saas,
      license_key_enabled: true,
      license_key_activations_limit: 3,
      license_key_activation_message: "Automated E2E fixture",
      metadata: %{workflow: "dual_driver_license", marker: marker}
    })
  end

  defp compact_license(value) do
    %{
      id: field(value, :id),
      product_id: field(value, :product_id),
      customer_id: field(value, :customer_id),
      activations_limit: field(value, :activations_limit),
      instances_count: field(value, :instances_count),
      source: field(value, :source),
      status: field(value, :status)
    }
  end

  defp compact_instance(value) do
    %{
      id: field(value, :id),
      license_key_id: field(value, :license_key_id),
      name: field(value, :name)
    }
  end

  defp includes?(page, id) do
    Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))
  end

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_license_lifecycle.json"])
    |> File.read!()
    |> Jason.decode!()
  end

  defp field(nil, _key), do: nil
  defp field(value, key), do: Map.get(value, key) || Map.get(value, Atom.to_string(key))

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
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.DualLicenseElixir.run()
