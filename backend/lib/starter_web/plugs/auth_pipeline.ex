defmodule StarterWeb.AuthPipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :starter,
    module: Starter.Guardian,
    error_handler: StarterWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
  # Last: the invite gate covers every current and future authenticated route.
  plug StarterWeb.Plugs.RequireInvite
end
