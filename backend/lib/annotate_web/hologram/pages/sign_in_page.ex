defmodule AnnotateWeb.Hologram.Pages.SignInPage do
  @moduledoc """
  `/sign-in`: the full-page GitHub sign-in / sign-up (the navbar `GithubAuth`
  card is the usual path; this is the direct-entry and redirect target for
  `RequireAuth`, `/login`, `/signup`, and failed callbacks).
  """

  use Hologram.Page

  alias Annotate.Auth.LoginMethods
  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.MainLayout

  route "/sign-in"
  layout MainLayout, page_title: "Sign in — annotate"

  def init(_params, component, server) do
    put_state(component,
      configured: LoginMethods.github_configured?(),
      signed_in: Auth.current_user(server) != nil
    )
  end

  def template do
    ~HOLO"""
    <div class="content sg-signin" data-cy="sign-in-page">
      <h1 class="sg-page-title">Sign in to annotate</h1>
      <p class="app-muted">
        Site owners sign in with GitHub. Your first sign-in creates your account;
        from the dashboard you can add a site, copy its embed snippet, and answer comments.
      </p>
      {%if @signed_in}
        <p><a class="btn btn-black" href="/dashboard" data-cy="sign-in-dashboard">Go to your dashboard</a></p>
      {%else}
        {%if @configured}
          <p><a class="btn btn-black" href="/auth/github" data-cy="sign-in-github">Continue with GitHub</a></p>
        {%else}
          <p><button type="button" class="btn btn-black" disabled aria-disabled="true">Continue with GitHub</button></p>
          <p class="sg-auth__note" role="status" data-cy="sign-in-unconfigured">GitHub sign-in is not configured yet.</p>
        {/if}
      {/if}
      <p class="sg-auth__note" data-cy="sign-in-legal">By continuing you agree to the <a href="/terms">Terms of Service</a> and <a href="/privacy">Privacy Policy</a>.</p>
      <p class="sg-auth__note">GitHub is the only sign-in method. We use your GitHub account's verified email.</p>
    </div>
    """
  end
end
