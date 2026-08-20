Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualAddonBrandElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, addon_created} =
      DodoPayments.Addons.create(client, %{
        currency: :usd,
        name: "Elixir Dual Addon #{marker}",
        price: 525,
        tax_category: :saas,
        description: "139 endpoint workflow"
      })

    addon_id = field(addon_created, :id)

    {:ok, addon_updated} =
      DodoPayments.Addons.update(client, addon_id, %{
        name: "Elixir Dual Addon #{marker} Updated",
        price: 575
      })

    {:ok, addon_retrieved} = DodoPayments.Addons.retrieve(client, addon_id)
    {:ok, addon_list} = DodoPayments.Addons.list(client, %{page_size: 100})
    {:ok, addon_image} = DodoPayments.Addons.update_images(client, addon_id)
    {:ok, observed_mcp_addon} = DodoPayments.Addons.retrieve(client, mcp["addon"]["id"])

    {:ok, brand_created} =
      DodoPayments.Brands.create(client, %{
        name: "Elixir Dual Brand #{marker}",
        description: "139 endpoint workflow",
        statement_descriptor: "ELIXIR",
        support_email: "billing@example.com",
        url: "https://example.com"
      })

    brand_id = field(brand_created, :brand_id)

    {:ok, brand_updated} =
      DodoPayments.Brands.update(client, brand_id, %{
        name: "Elixir Dual Brand #{marker} Updated",
        description: "Updated workflow brand"
      })

    {:ok, brand_retrieved} = DodoPayments.Brands.retrieve(client, brand_id)
    {:ok, brand_list} = DodoPayments.Brands.list(client)
    {:ok, brand_image} = DodoPayments.Brands.update_images(client, brand_id)
    {:ok, observed_mcp_brand} = DodoPayments.Brands.retrieve(client, mcp["brand"]["id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      addon: %{
        id: addon_id,
        updated: compact_addon(addon_updated),
        retrieved: compact_addon(addon_retrieved),
        listed: includes?(addon_list, :id, addon_id),
        image_id_present: present?(field(addon_image, :image_id)),
        image_url_present: present?(field(addon_image, :url)),
        observed_mcp: compact_addon(observed_mcp_addon)
      },
      brand: %{
        id: brand_id,
        updated: compact_brand(brand_updated),
        retrieved: compact_brand(brand_retrieved),
        listed: includes?(brand_list, :brand_id, brand_id),
        image_id_present: present?(field(brand_image, :image_id)),
        image_url_present: present?(field(brand_image, :url)),
        observed_mcp: compact_brand(observed_mcp_brand)
      }
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_addon_brand_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_addon_brand_elixir_report=#{path}")
  end

  defp compact_addon(item) do
    %{
      id: field(item, :id),
      name: field(item, :name),
      price: field(item, :price),
      currency: field(item, :currency),
      tax_category: field(item, :tax_category)
    }
  end

  defp compact_brand(item) do
    %{
      brand_id: field(item, :brand_id),
      name: field(item, :name),
      description: field(item, :description),
      statement_descriptor: field(item, :statement_descriptor)
    }
  end

  defp includes?(page, key, value) do
    Enum.any?(field(page, :items) || [], &(field(&1, key) == value))
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_addon_brand_lifecycle.json"])
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

DodoPayments.E2E.DualAddonBrandElixir.run()
