import Config

config :dodo_store, DodoStoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  url: [scheme: "http", host: "localhost", port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-at-least-sixty-four-bytes-000000000000000000"
