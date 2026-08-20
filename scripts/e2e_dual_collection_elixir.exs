Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualCollectionElixir do
  @moduledoc false

  @collection_id "pdc_0Nlf5zvbRbNjinPOIBgGs"

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, helper1} = create_helper(client, "Elixir Collection Group Helper #{marker}", 349)
    {:ok, helper2} = create_helper(client, "Elixir Collection Item Helper #{marker}", 449)
    helper1_id = field(helper1, :product_id)
    helper2_id = field(helper2, :product_id)
    {:ok, _} = DodoPayments.ProductCollections.unarchive(client, @collection_id)

    {:ok, _} =
      DodoPayments.ProductCollections.update(client, @collection_id, %{
        name: "Elixir Dual Collection #{marker} Updated",
        description: "Updated workflow collection"
      })

    {:ok, updated} = DodoPayments.ProductCollections.retrieve(client, @collection_id)

    {:ok, image} =
      DodoPayments.ProductCollections.update_images(client, @collection_id, %{force_update: true})

    {:ok, group} =
      DodoPayments.ProductCollections.Groups.create(client, @collection_id, %{
        group_name: "Captured Group #{marker}",
        status: true,
        products: [%{product_id: helper1_id, status: true}]
      })

    group_id = field(group, :group_id)

    {:ok, _} =
      DodoPayments.ProductCollections.Groups.update(client, @collection_id, group_id, %{
        group_name: "Captured Group #{marker} Updated",
        status: false
      })

    {:ok, after_group_update} = DodoPayments.ProductCollections.retrieve(client, @collection_id)

    {:ok, items} =
      DodoPayments.ProductCollections.Groups.Items.create(client, @collection_id, group_id, %{
        products: [%{product_id: helper2_id, status: true}]
      })

    item = Enum.find(items, &(field(&1, :product_id) == helper2_id))
    item_id = field(item, :id)

    {:ok, _} =
      DodoPayments.ProductCollections.Groups.Items.update(
        client,
        @collection_id,
        group_id,
        item_id,
        %{status: false}
      )

    {:ok, after_item_update} = DodoPayments.ProductCollections.retrieve(client, @collection_id)

    {:ok, _} =
      DodoPayments.ProductCollections.Groups.Items.delete(
        client,
        @collection_id,
        group_id,
        item_id
      )

    {:ok, after_item_delete} = DodoPayments.ProductCollections.retrieve(client, @collection_id)
    {:ok, _} = DodoPayments.ProductCollections.Groups.delete(client, @collection_id, group_id)
    {:ok, after_group_delete} = DodoPayments.ProductCollections.retrieve(client, @collection_id)
    {:ok, _} = DodoPayments.ProductCollections.archive(client, @collection_id)

    {:ok, archived} =
      DodoPayments.ProductCollections.list(client, %{archived: true, page_size: 100})

    {:ok, _} = DodoPayments.ProductCollections.unarchive(client, @collection_id)
    {:ok, final} = DodoPayments.ProductCollections.retrieve(client, @collection_id)

    {:ok, active} =
      DodoPayments.ProductCollections.list(client, %{archived: false, page_size: 100})

    {:ok, _} = DodoPayments.Products.archive(client, helper1_id)
    {:ok, _} = DodoPayments.Products.archive(client, helper2_id)

    report = %{
      run_id: run_id,
      engine: "elixir_sdk",
      marker: marker,
      id: @collection_id,
      updated: compact_collection(updated),
      image_id_present: present?(field(image, :image_id)),
      image_url_present: present?(field(image, :url)),
      group: %{
        id: group_id,
        updated: compact_group(find_group(after_group_update, group_id)),
        deleted: is_nil(find_group(after_group_delete, group_id))
      },
      item: %{
        id: item_id,
        product_id: helper2_id,
        updated: compact_item(find_item(after_item_update, item_id)),
        deleted: is_nil(find_item(after_item_delete, item_id))
      },
      archived_listed: includes?(archived, @collection_id),
      final: compact_collection(final),
      active_listed: includes?(active, @collection_id),
      helper_products_archived: true
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_collection_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_collection_elixir_report=#{path}")
  end

  defp create_helper(client, name, price) do
    DodoPayments.Products.create(client, %{
      name: name,
      price: %{
        currency: :usd,
        discount: 0,
        price: price,
        purchasing_power_parity: false,
        type: "one_time_price"
      },
      tax_category: :saas
    })
  end

  defp compact_collection(item) do
    %{id: field(item, :id), name: field(item, :name), description: field(item, :description)}
  end

  defp compact_group(nil), do: nil

  defp compact_group(group) do
    %{
      group_id: field(group, :group_id),
      group_name: field(group, :group_name),
      status: field(group, :status)
    }
  end

  defp compact_item(nil), do: nil

  defp compact_item(item),
    do: %{
      id: field(item, :id),
      product_id: field(item, :product_id),
      status: field(item, :status)
    }

  defp find_group(collection, group_id) do
    Enum.find(field(collection, :groups) || [], &(field(&1, :group_id) == group_id))
  end

  defp find_item(collection, item_id) do
    collection
    |> field(:groups)
    |> List.wrap()
    |> Enum.flat_map(&(field(&1, :products) || []))
    |> Enum.find(&(field(&1, :id) == item_id))
  end

  defp includes?(page, id), do: Enum.any?(field(page, :items) || [], &(field(&1, :id) == id))
  defp present?(value), do: is_binary(value) and value != ""

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

DodoPayments.E2E.DualCollectionElixir.run()
