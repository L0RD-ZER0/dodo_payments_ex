defmodule DodoStoreWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: DodoStoreWeb.Endpoint,
        router: DodoStoreWeb.Router,
        statics: DodoStoreWeb.static_paths()
    end
  end

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
