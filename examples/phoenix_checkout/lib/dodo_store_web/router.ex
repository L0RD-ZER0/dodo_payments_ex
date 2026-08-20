defmodule DodoStoreWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", DodoStoreWeb do
    pipe_through(:browser)

    get("/", StoreController, :index)
    post("/checkout", StoreController, :create_checkout)
    get("/checkout/return", StoreController, :checkout_return)
    get("/patterns", PatternController, :index)
    get("/patterns/:id", PatternController, :show)
    post("/patterns/:id/demo", PatternController, :demo)
    post("/patterns/:id/checkout", PatternController, :checkout)
  end

  scope "/webhooks", DodoStoreWeb do
    pipe_through(:api)
    post("/dodo", WebhookController, :create)
  end
end
