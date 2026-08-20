import Config

environment = System.get_env("DODO_PAYMENTS_ENVIRONMENT", "test")

unless environment in ["test", "test_mode", "live", "live_mode"] do
  raise "DODO_PAYMENTS_ENVIRONMENT must be test or live"
end

config :dodo_store, :dodo_payments,
  environment: environment,
  api_key: fn -> System.fetch_env!("DODO_PAYMENTS_API_KEY") end,
  timeout: 30_000,
  max_attempts: 3

if webhook_secrets = System.get_env("DODO_PAYMENTS_WEBHOOK_SECRETS") do
  config :dodo_store,
         :webhook_secrets,
         webhook_secrets
         |> String.split(",", trim: true)
         |> Enum.map(&String.trim/1)
end

if config_env() == :prod do
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  port = String.to_integer(System.get_env("PORT", "4000"))
  host = System.fetch_env!("PHX_HOST")

  config :dodo_store, DodoStoreWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    url: [host: host, port: 443, scheme: "https"]

  config :dodo_store, DodoStore.Repo,
    database: System.get_env("DATABASE_PATH", "/data/dodo_store.db")
end
