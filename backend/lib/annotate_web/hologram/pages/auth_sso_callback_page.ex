defmodule AnnotateWeb.Hologram.Pages.AuthSsoCallbackPage do
  @moduledoc """
  SSO code exchange (`/auth/sso-callback?code=`).

  After Authentik OIDC, Phoenix redirects here on the **same host**. We issue
  Hologram session tokens and hard-redirect to the post-login destination (`/app`).
  """
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.MainLayout

  route "/auth/sso-callback"
  layout MainLayout, page_title: "Signing in…"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    code = query_param(server, "code")
    error = query_param(server, "error")

    cond do
      is_binary(error) and error != "" ->
        put_state(component,
          status: "error",
          message: human_error(error)
        )

      is_binary(code) and code != "" ->
        exchange_code(component, server, code)

      true ->
        put_state(component, status: "error", message: "Missing SSO code. Try signing in again.")
    end
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  # Hologram ignores a redirect set in page init/3 (only middleware redirects
  # are terminal), so the hand-off to the post-auth path is a meta refresh;
  # the "Continue" link is the no-refresh fallback.
  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Signing in…</h1>
      {%if @status == "error"}
        <p class="sg-error" role="alert">{@message}</p>
        <p><a href="/sign-in" class="btn btn-outline">Back to sign in</a></p>
      {%else}
        <meta http-equiv="refresh" content={"0;url=" <> (@redirect_path || "/dashboard")} />
        <p class="app-muted">Completing sign-in and opening your dashboard…</p>
        <p><a href={@redirect_path || "/dashboard"} class="btn btn-black btn-sm">Continue to dashboard</a></p>
      {/if}
    </div>
    """
  end

  defp exchange_code(component, server, code) do
    with {:ok, session_id} <- Annotate.Auth.SSOCode.exchange(code),
         {:ok, session} <- Annotate.Users.Sessions.get(session_id, Noizu.Context.system(), []),
         {:ok, server, user, _orgs} <- Auth.issue_tokens_from_session(server, session) do
      path = Auth.post_auth_path(user)

      component =
        put_state(component,
          status: "ok",
          user: user,
          redirect_path: path
        )

      # Hard HTTP redirect so the browser lands on /app with session cookies set
      {component, Hologram.Server.put_redirect(server, path)}
    else
      {:error, reason} ->
        put_state(component,
          status: "error",
          message: "Sign-in failed (#{inspect(reason)}). Try again."
        )

      _ ->
        put_state(component,
          status: "error",
          message: "Invalid or expired SSO code. Try signing in again."
        )
    end
  end

  defp query_param(server, key) do
    q = Map.get(server, :query) || %{}
    Map.get(q, key) || Map.get(q, String.to_atom(key))
  end

  defp human_error("not_provisioned"), do: "Your account is not provisioned for SSO."

  defp human_error("invite_required"),
    do: "Sign-up is invite-only. Open an invite link, then continue with SSO."

  defp human_error("invalid_invite"),
    do: "That invite link is invalid or has expired. Ask your inviter for a new one."

  defp human_error("sso_unavailable"), do: "SSO is not available for this email domain."
  defp human_error("sso_failed"), do: "SSO failed. Try again or contact support."
  defp human_error("oidc_failed"), do: "Authentik sign-in failed. Try again."

  defp human_error("github_email_unverified"),
    do:
      "Your GitHub account has no verified email. Verify an email at github.com/settings/emails, then sign in again."

  defp human_error("github_email_in_use"),
    do: "That email is already linked to a different GitHub account."

  defp human_error("github_not_configured"), do: "GitHub sign-in is not configured yet."
  defp human_error("github_failed"), do: "GitHub sign-in failed. Try again."
  defp human_error("account_disabled"), do: "This account is disabled."
  defp human_error(other), do: "SSO error: #{other}"
end
