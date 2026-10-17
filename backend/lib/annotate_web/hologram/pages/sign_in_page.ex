defmodule AnnotateWeb.Hologram.Pages.SignInPage do
  @moduledoc """
  `/sign-in`: full-page GitHub / Google sign-in (the navbar modal is the usual
  path; this is the direct-entry and redirect target for `RequireAuth`,
  `/login`, `/signup`, and failed callbacks). The dashboard is invite-only;
  invite links land on `/sign-up?invite=…` (`SignUpPage`).
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Components.ProviderButtons
  alias AnnotateWeb.Hologram.Layouts.MainLayout

  route "/sign-in"
  layout MainLayout, page_title: "Sign in — annotate"

  def init(_params, component, server) do
    put_state(component,
      providers: ProviderButtons.providers(),
      signed_in: Auth.current_user(server) != nil
    )
  end

  def template do
    ~HOLO"""
    <div class="content sg-signin" data-cy="sign-in-page">
      <h1 class="sg-page-title">Sign in to annotate</h1>
      <p class="app-muted">
        Site owners sign in with GitHub or Google; we use your account's verified email.
        From the dashboard you can add a site, copy its embed snippet, and answer comments.
      </p>
      {%if @signed_in}
        <p><a class="btn btn-black" href="/dashboard" data-cy="sign-in-dashboard">Go to your dashboard</a></p>
      {%else}
        <ProviderButtons providers={@providers} />
      {/if}
      <p class="sg-auth__note" data-cy="sign-in-invite-only">
        annotate is invite-only. Have an invite link? Open it to sign up.
        No invite yet? <a href="/#waitlist">Join the waitlist</a>.
      </p>
      <p class="sg-auth__note" data-cy="sign-in-legal">By continuing you agree to the <a href="/terms">Terms of Service</a> and <a href="/privacy">Privacy Policy</a>.</p>
    </div>
    """
  end
end
