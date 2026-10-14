defmodule AnnotateWeb do
  # <REMOVED UUID HERE> static_paths :: auto-generated pointer for public function static_paths
  def static_paths,
    do: ~w(themes css hologram favicon.ico robots.txt sitemap.xml site.xml llms.txt llm.txt)

  # <REMOVED UUID HERE> router :: auto-generated pointer for public function router
  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  # <REMOVED UUID HERE> channel :: auto-generated pointer for public function channel
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  # <REMOVED UUID HERE> controller :: auto-generated pointer for public function controller
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  # <REMOVED UUID HERE> verified_routes :: auto-generated pointer for public function verified_routes
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: AnnotateWeb.Endpoint,
        router: AnnotateWeb.Router,
        statics: AnnotateWeb.static_paths()
    end
  end

  # <REMOVED UUID HERE> __using__ :: auto-generated pointer for public function __using__
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
