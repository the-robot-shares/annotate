defmodule AnnotateWeb.Hologram.Components.GithubAuth do
  @moduledoc """
  Navbar "Sign in" / "Sign up" triggers + floating auth card (FloatingAuth /
  tobor-kit `LoginDropdown` chrome), **GitHub-only**: annotate's dashboard has
  exactly one sign-in method (`Annotate.Auth.LoginMethods`). Sign-up and
  sign-in are the same GitHub round trip; the first sign-in creates the
  account. Until the GitHub OAuth app credentials are deployed the button is
  disabled and says so ("not configured") instead of failing at GitHub.

  Stateful (needs a `cid`): `configured` is read server-side in `init/3`.
  `variant` picks the button family — `"sg"` (style-guide `btn`, app pages)
  or `"nd"` (Night Desk landing `nd-btn`).
  """

  use Hologram.Component

  alias Annotate.Auth.LoginMethods

  prop :variant, :string, default: "sg"

  def init(_props, component, _server) do
    put_state(component,
      open: false,
      mode: "signin",
      configured: LoginMethods.github_configured?()
    )
  end

  def template do
    ~HOLO"""
    <div class={root_class(@variant)} data-cy="github-auth">
      {%if !@open}
        <button type="button" class={trigger_class(@variant, "secondary")} $click={:open_signin} data-cy="github-auth-signin">Sign in</button>
        <button type="button" class={trigger_class(@variant, "primary")} $click={:open_signup} data-cy="github-auth-signup">Sign up</button>
      {/if}

      {%if @open}
        <div class={panel_class(@variant)} role="dialog" aria-modal="false" aria-labelledby="gh-auth-title" data-cy="github-auth-panel">
          <button type="button" class="sg-auth__close" aria-label="Close" $click={:close}>&times;</button>

          {%if @mode == "signup"}
            <h2 id="gh-auth-title" class="sg-auth__title">Create your annotate account</h2>
            <p class="sg-auth__subtitle">Sign up with GitHub. Your first sign-in creates the account; then add your first site from the dashboard.</p>
          {%else}
            <h2 id="gh-auth-title" class="sg-auth__title">Sign in to annotate</h2>
            <p class="sg-auth__subtitle">Site owners sign in with GitHub to manage sites and answer comments.</p>
          {/if}

          <div class="sg-auth__sso">
            {%if @configured}
              <a class={github_class(@variant)} href="/auth/github" data-cy="github-auth-continue">Continue with GitHub</a>
            {%else}
              <button type="button" class={github_class(@variant)} disabled aria-disabled="true" data-cy="github-auth-unconfigured">Continue with GitHub</button>
              <p class="sg-auth__note" role="status">GitHub sign-in is not configured yet.</p>
            {/if}
          </div>

          <p class="sg-auth__note">GitHub is the only sign-in. We use your GitHub account's verified email.</p>
        </div>
      {/if}
    </div>
    """
  end

  def action(:open_signin, _params, component),
    do: put_state(component, open: true, mode: "signin")

  def action(:open_signup, _params, component),
    do: put_state(component, open: true, mode: "signup")

  def action(:close, _params, component), do: put_state(component, :open, false)

  defp root_class("nd"), do: "sg-auth nd-auth"
  defp root_class(_), do: "sg-auth"

  defp panel_class("nd"), do: "sg-auth__panel nd-auth__panel"
  defp panel_class(_), do: "sg-auth__panel"

  defp trigger_class("nd", "primary"), do: "nd-btn nd-btn--primary nd-btn--sm"
  defp trigger_class("nd", _), do: "nd-btn nd-btn--secondary nd-btn--sm"
  defp trigger_class(_, "primary"), do: "btn btn-black btn-sm"
  defp trigger_class(_, _), do: "btn btn-outline btn-sm"

  defp github_class("nd"), do: "nd-btn nd-btn--primary nd-auth__github"
  defp github_class(_), do: "btn btn-black"
end
