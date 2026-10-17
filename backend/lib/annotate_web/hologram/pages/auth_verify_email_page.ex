defmodule AnnotateWeb.Hologram.Pages.AuthVerifyEmailPage do
  use Hologram.Page

  alias AnnotateWeb.Hologram.Layouts.AuthLayout

  route "/auth/verify-email"
  layout AuthLayout, page_title: "Verify email"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    token = Map.get(server.query || %{}, "token")

    status =
      case token do
        t when is_binary(t) and t != "" ->
          case Annotate.Auth.SmartTokenAuth.verify_email_token(t) do
            {:ok, user} ->
              Annotate.Events.dispatch(:user_verified, %{user_id: user.id})
              "ok"

            _ ->
              "error"
          end

        _ ->
          "error"
      end

    put_state(component, status: status)
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="nd-auth">
      <h1 class="nd-auth__title">Verify email</h1>
      {%if @status == "ok"}
        <p role="status">Email verified successfully.</p>
        <p><a href="/login" class="nd-btn nd-btn--primary">Log in</a></p>
      {%else}
        <p class="nd-auth__error" role="alert">Invalid or expired verification link.</p>
      {/if}
    </div>
    """
  end
end
