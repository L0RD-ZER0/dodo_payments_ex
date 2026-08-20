import Config

config :dodo_store, ecto_repos: [DodoStore.Repo]

config :dodo_store, DodoStore.Repo,
  database: Path.expand("../tmp/dodo_store.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: false

config :dodo_store, :inbox_processor, enabled: true, interval: 1_000
config :dodo_store, :outbox_processor, enabled: true, interval: 1_000, batch_size: 20

config :dodo_store, DodoStoreWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [html: DodoStoreWeb.ErrorHTML], layout: false],
  pubsub_server: DodoStore.PubSub

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
