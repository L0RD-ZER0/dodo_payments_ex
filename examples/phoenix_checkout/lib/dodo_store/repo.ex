defmodule DodoStore.Repo do
  use Ecto.Repo,
    otp_app: :dodo_store,
    adapter: Ecto.Adapters.SQLite3
end
