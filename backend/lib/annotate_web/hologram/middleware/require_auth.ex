defmodule AnnotateWeb.Hologram.Middleware.RequireAuth do
  @moduledoc """
  Redirect unauthenticated visitors to the login page, and hold invite-gated
  users (`Annotate.Auth.InviteGate`) at `/auth/invite-required`.

  Runs before a page renders AND before each of the page's commands, so a
  gated user can neither see nor drive an app page. Pages a gated user may
  still reach (the interstitial itself, profile, complete-registration)
  declare `middleware RequireAuth, invite: :exempt`.
  """
  use Hologram.Middleware

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Pages.InviteRequiredPage
  alias AnnotateWeb.Hologram.Pages.LoginPage

  # <REMOVED UUID HERE> call :: auto-generated pointer for public function call
  def call(server, opts) do
    case Auth.current_user(server) do
      nil ->
        Hologram.Server.put_redirect(server, LoginPage)

      user ->
        if Keyword.get(opts, :invite) != :exempt and Auth.user_needs_invite?(user) do
          Hologram.Server.put_redirect(server, InviteRequiredPage)
        else
          Hologram.Server.put_stash(server, :current_user, user)
        end
    end
  end
end
