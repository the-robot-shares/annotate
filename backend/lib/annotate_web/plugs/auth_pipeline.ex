defmodule AnnotateWeb.AuthPipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :annotate,
    module: Annotate.Guardian,
    error_handler: AnnotateWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
  # Last: the invite gate covers every current and future authenticated route.
  plug AnnotateWeb.Plugs.RequireInvite
end
