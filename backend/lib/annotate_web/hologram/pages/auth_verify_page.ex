defmodule AnnotateWeb.Hologram.Pages.AuthVerifyPage do
  @moduledoc "Magic-link verification (start-app `/auth/verify`)."
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.AuthLayout
  alias AnnotateWeb.Hologram.Pages.AppHomePage
  alias AnnotateWeb.Hologram.Pages.CompleteRegistrationPage
  alias AnnotateWeb.Hologram.Pages.InviteRequiredPage

  route "/auth/verify"
  layout AuthLayout, page_title: "Verify"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    token = Map.get(server.query || %{}, "token")

    case verify_token(token) do
      {:ok, session} ->
        case Auth.issue_tokens_from_session(server, session) do
          {:ok, server, user, _orgs} ->
            page =
              case Auth.post_auth_path(user) do
                "/complete-registration" -> CompleteRegistrationPage
                "/auth/invite-required" -> InviteRequiredPage
                _ -> AppHomePage
              end

            component = put_state(component, status: "ok", user: user)
            {component, Hologram.Server.put_redirect(server, page)}

          {:error, _} ->
            put_state(component, status: "error", message: "Could not create session")
        end

      {:error, _} ->
        put_state(component, status: "error", message: "Invalid or expired magic link")
    end
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="nd-auth">
      <h1 class="nd-auth__title">Verify</h1>
      {%if @status == "error"}
        <p class="nd-auth__error" role="alert">{@message}</p>
      {%else}
        <p>Signing you in…</p>
      {/if}
    </div>
    """
  end

  defp verify_token(nil), do: {:error, :missing}
  defp verify_token(""), do: {:error, :missing}

  defp verify_token(token) do
    Annotate.Auth.SmartTokenAuth.verify_magic_link(token, %{})
  end
end
