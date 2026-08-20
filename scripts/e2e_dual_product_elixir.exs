Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualProductElixir do
  @moduledoc false

  @product_id "pdt_0Nlf5fSRt2eLjquLq5KIV"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, _} = DodoPayments.Products.unarchive(client, @product_id)

    {:ok, _} =
      DodoPayments.Products.update(client, @product_id, %{
        name: "Elixir Dual Product #{marker} Updated",
        description: "Updated dual-driver product"
      })

    {:ok, updated} = DodoPayments.Products.retrieve(client, @product_id)

    {:ok, file} =
      DodoPayments.Products.update_files(client, @product_id, %{file_name: "dual-driver.txt"})

    {:ok, image} = DodoPayments.Products.Images.update(client, @product_id, %{force_update: true})
    slug = "elixir-dual-" <> String.slice(marker, -10, 10)

    {:ok, short_link} =
      DodoPayments.Products.ShortLinks.create(client, @product_id, %{slug: slug})

    {:ok, short_links} =
      DodoPayments.Products.ShortLinks.list(client, %{product_id: @product_id, page_size: 100})

    {:ok, localized} =
      DodoPayments.Products.LocalizedPrices.create(client, @product_id, %{
        amount: 999,
        currency: :usd,
        country_code: :ca
      })

    localized_id = field(localized, :id)

    {:ok, localized_updated} =
      DodoPayments.Products.LocalizedPrices.update(client, @product_id, localized_id, %{
        amount: 949
      })

    {:ok, localized_retrieved} =
      DodoPayments.Products.LocalizedPrices.retrieve(client, @product_id, localized_id)

    {:ok, localized_list} = DodoPayments.Products.LocalizedPrices.list(client, @product_id)
    {:ok, _} = DodoPayments.Products.archive(client, @product_id)
    {:ok, archived} = DodoPayments.Products.list(client, %{archived: true, page_size: 100})
    {:ok, _} = DodoPayments.Products.unarchive(client, @product_id)
    {:ok, final} = DodoPayments.Products.retrieve(client, @product_id)
    {:ok, active} = DodoPayments.Products.list(client, %{archived: false, page_size: 100})
    {:ok, observed_mcp} = DodoPayments.Products.retrieve(client, mcp["id"])

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: @product_id,
      updated: compact_product(updated),
      file_id_present: present?(field(file, :file_id)),
      file_url_present: present?(field(file, :url)),
      image_id_present: present?(field(image, :image_id)),
      image_url_present: present?(field(image, :url)),
      short_link: %{
        slug: slug,
        short_url_present: present?(field(short_link, :short_url)),
        full_url_present: present?(field(short_link, :full_url)),
        listed: includes?(short_links, :product_id, @product_id)
      },
      localized: %{
        id: localized_id,
        updated: compact_localized(localized_updated),
        retrieved: compact_localized(localized_retrieved),
        listed: includes?(localized_list, :id, localized_id),
        cleanup_pending: "MCP must observe and archive this localized price"
      },
      archived_listed: includes?(archived, :product_id, @product_id),
      final: compact_product(final),
      active_listed: includes?(active, :product_id, @product_id),
      observed_mcp: compact_product(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_product_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_product_elixir_report=#{path}")
  end

  defp compact_product(item) do
    price = field(item, :price) || %{}

    %{
      product_id: field(item, :product_id),
      name: field(item, :name),
      pricing_mode: field(item, :pricing_mode),
      price: field(price, :price),
      currency: field(price, :currency),
      tax_category: field(item, :tax_category),
      brand_id: field(item, :brand_id)
    }
  end

  defp compact_localized(item) do
    %{
      id: field(item, :id),
      amount: field(item, :amount),
      mode: field(item, :mode),
      country_code: field(item, :country_code),
      currency: field(item, :currency),
      product_id: field(item, :product_id)
    }
  end

  defp includes?(page, key, value) do
    Enum.any?(field(page, :items) || [], &(field(&1, key) == value))
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_product_lifecycle.json"])
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

DodoPayments.E2E.DualProductElixir.run()
