defmodule AnnotateWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :annotate

  socket "/socket", AnnotateWeb.UserSocket,
    websocket: [timeout: 45_000],
    longpoll: false

  # Style-guide CSS + Hologram client bundles
  plug Plug.Static,
    at: "/",
    from: :annotate,
    gzip: false,
    only: ~w(themes css hologram favicon.ico robots.txt)

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :annotate
  end

  plug AnnotateWeb.Plugs.CORS
  plug Plug.RequestId
  plug AnnotateWeb.Plugs.OtelLoggerMetadata
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  # Plug options are evaluated at compile time, so the session's signing salt
  # is read at runtime by AnnotateWeb.Plugs.Session instead of being committed
  # here as a literal.
  plug AnnotateWeb.Plugs.Session

  # Hologram pages/commands BEFORE the Phoenix JSON API router
  plug Hologram.Router
  plug AnnotateWeb.Router
end
