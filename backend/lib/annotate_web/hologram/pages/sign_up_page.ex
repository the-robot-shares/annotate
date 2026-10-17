defmodule AnnotateWeb.Hologram.Pages.SignUpPage do
  @moduledoc """
  `/sign-up?invite=<token>` — the invite link landing page. The token is NOT
  validated here (no validity oracle on an unauthenticated page); it rides
  `?invite=` into `/auth/<provider>`, is stashed in the signed SSO flow cookie,
  and is redeemed atomically on first sign-in
  (`Annotate.Dashboard.OAuthLogin`). A signed-in account still held at the
  gate is sent to the interstitial to redeem it there. Without an invite the
  page explains that annotate is invite-only.
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Components.ProviderButtons
  alias AnnotateWeb.Hologram.Layouts.AuthLayout

  route "/sign-up"
  layout AuthLayout, page_title: "Sign up — annotate"

  def init(_params, component, server) do
    invite =
      case (Map.get(server, :query) || %{})["invite"] do
        token when is_binary(token) and byte_size(token) in 16..200 -> String.trim(token)
        _ -> ""
      end

    user = Auth.current_user(server)

    put_state(component,
      providers: ProviderButtons.providers(),
      invite: invite,
      signed_in: user != nil,
      needs_invite: user != nil and Auth.user_needs_invite?(user)
    )
  end

  def template do
    ~HOLO"""
    <div class="nd-auth" data-cy="sign-up-page">
      {%if @invite != ""}
        <h1 class="nd-auth__title">You're invited to annotate</h1>
        <p class="nd-auth__muted">Sign up with GitHub or Google. Your first sign-in creates the account and uses this invite.</p>
      {%else}
        <h1 class="nd-auth__title">annotate is invite-only</h1>
        <p class="nd-auth__muted">
          The owner dashboard is open to invited users for now. Have an invite link? Open it to sign up.
          No invite yet? <a href="/#waitlist">Join the waitlist</a>.
        </p>
      {/if}

      {%if @signed_in}
        {%if @needs_invite}
          <p><a class="nd-btn nd-btn--primary" href="/auth/invite-required" data-cy="sign-up-redeem">Redeem your invite</a></p>
        {%else}
          <p><a class="nd-btn nd-btn--primary" href="/dashboard" data-cy="sign-up-dashboard">Go to your dashboard</a></p>
        {/if}
      {%else}
        <ProviderButtons providers={@providers} invite={@invite} />
        <p class="nd-auth__note">Already have access? <a href="/sign-in">Sign in</a>.</p>
      {/if}
      <p class="nd-auth__note" data-cy="sign-up-legal">By continuing you agree to the <a href="/terms">Terms of Service</a> and <a href="/privacy">Privacy Policy</a>.</p>
    </div>
    """
  end
end
