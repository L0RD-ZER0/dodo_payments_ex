import Config

config :dodo_store, DodoStoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  url: [scheme: "http", host: "localhost", port: 4002],
  secret_key_base: "test-only-secret-key-base-at-least-sixty-four-bytes-00000000000000",
  server: false

config :dodo_store, DodoStore.Repo,
  database: Path.expand("../tmp/dodo_store_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :dodo_store, :inbox_processor, enabled: false
config :dodo_store, :outbox_processor, enabled: false

config :dodo_store, :webhook_secrets, ["whsec_" <> Base.encode64("test-webhook-secret")]

config :logger, level: :warning
