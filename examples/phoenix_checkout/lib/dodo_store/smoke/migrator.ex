defmodule DodoStore.Smoke.Migrator do
  @moduledoc false

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc false
  def start_link(_opts) do
    path = Application.app_dir(:dodo_store, "priv/repo/migrations")
    Ecto.Migrator.run(DodoStore.Repo, path, :up, all: true)
    :ignore
  end
end
