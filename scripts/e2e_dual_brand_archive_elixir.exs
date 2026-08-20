Mix.Task.run("app.start")

defmodule DodoPayments.E2E.DualBrandArchiveElixir do
  @moduledoc false

  def run do
    vars = load_env!()
    refuse_live!(vars)
    client = client!(vars)
    run_id = System.get_env("DODO_E2E_RUN_ID", "e2e-20260818-02")
    mcp = fixture!(run_id)
    marker = Integer.to_string(System.system_time(:millisecond))

    {:ok, created} =
      DodoPayments.Brands.create(client, %{
        name: "Elixir Archive Fixture #{marker}",
        description: "Isolated 2.47 archive test",
        statement_descriptor: "ELIXIRARCHIVE",
        support_email: "billing@example.com",
        url: "https://example.com"
      })

    brand_id = field(created, :brand_id)
    {:ok, archived} = DodoPayments.Brands.archive(client, brand_id, %{})
    {:ok, all} = DodoPayments.Brands.list(client, %{include_archived: true})
    observed_elixir = find_brand(all, brand_id)
    observed_mcp = find_brand(all, mcp["brand_id"])

    report = %{
      brand_id: brand_id,
      archive: %{
        module: archived.__struct__ |> inspect(),
        archived_at_present: present?(field(archived, :archived_at)),
        brand_id: field(archived, :brand_id),
        collections_moved: field(archived, :collections_moved),
        products_moved: field(archived, :products_moved),
        subscriptions_moved: field(archived, :subscriptions_moved),
        moved_to_brand_id: field(archived, :moved_to_brand_id),
        extra_keys: archived.extra |> Map.keys() |> Enum.sort()
      },
      observed_elixir: compact(observed_elixir),
      observed_mcp: compact(observed_mcp)
    }

    path = Path.join([File.cwd!(), "tmp", "e2e", run_id, "dual_brand_archive_elixir.json"])
    File.write!(path, Jason.encode!(report, pretty: true), [:binary])
    File.chmod!(path, 0o600)
    IO.puts("dual_brand_archive_elixir_report=#{path}")
  end

  defp find_brand(response, id) do
    response
    |> field(:items)
    |> Enum.find(&(field(&1, :brand_id) == id))
  end

  defp compact(value) do
    %{
      brand_id: field(value, :brand_id),
      archived_at_present: present?(field(value, :archived_at))
    }
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp fixture!(run_id) do
    Path.join([File.cwd!(), "tmp", "e2e", run_id, "mcp_brand_archive.json"])
    |> File.read!()
    |> Jason.decode!()
  end

  defp field(nil, _key), do: nil

  defp field(value, key) do
    case Map.fetch(value, key) do
      {:ok, result} -> result
      :error -> Map.get(value, Atom.to_string(key))
    end
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
      raise "refusing to mutate resources outside Dodo test mode"
    end
  end
end

DodoPayments.E2E.DualBrandArchiveElixir.run()
