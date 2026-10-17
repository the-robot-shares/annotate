defmodule AnnotateWeb.Hologram.Middleware.GithubOnly do
  @moduledoc """
  GitHub-only deployments (`Annotate.Auth.LoginMethods`): the scaffold's
  email/password entry pages (`/login`, `/signup`, `/forgot-password`,
  `/join/:token`) redirect to `/sign-in`. Middleware runs before the page
  renders AND before each of its commands, so the password commands on those
  pages cannot be driven by hand either.
  """
  use Hologram.Middleware

  def call(server, _opts) do
    if Annotate.Auth.LoginMethods.password_enabled?(),
      do: server,
      else: Hologram.Server.put_redirect(server, "/sign-in")
  end
end
