defmodule DodoStoreWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dodo_store

  @session_options [
    store: :cookie,
    key: "_dodo_store_key",
    signing_salt: "dodo-store"
  ]

  plug(Plug.Static,
    at: "/",
    from: :dodo_store,
    gzip: false,
    only: DodoStoreWeb.static_paths()
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {DodoStoreWeb.CacheBodyReader, :read_body, []}
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(DodoStoreWeb.Router)
end
