defmodule AnnotateWeb.Hologram.Pages.LoginPage do
  @moduledoc """
  Multi-step login (email → SSO or password) ported from start-app login page.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Pages.ForgotPasswordPage
  alias AnnotateWeb.Hologram.Pages.SignupPage

  route "/login"
  layout MainLayout, page_title: "Log In"
  middleware AnnotateWeb.Hologram.Middleware.GithubOnly

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server) do
    catalog = Auth.sso_catalog()

    put_state(component,
      step: "email",
      email: "",
      password: "",
      error: nil,
      loading: false,
      sso_providers: catalog.providers,
      sso_domains: catalog.domain_policies || catalog.domains || %{},
      domain_providers: []
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Log In</h1>

      {%if @step == "email"}
        <form class="sg-form" $submit.prevent_default={:submit_email}>
          {%if @error}
            <p class="sg-error" role="alert">{@error}</p>
          {/if}
          <div class="sg-field">
            <label for="login-email">Email</label>
            <input
              id="login-email"
              name="email"
              type="email"
              value={@email}
              required
              autocomplete="email"
              $change={:set_email}
            />
          </div>
          <button type="submit" class="btn btn-black">Continue</button>
          <div class="sg-form-footer">
            <p>Don't have an account? <Link to={SignupPage}>Sign up</Link></p>
          </div>
        </form>
      {/if}

      {%if @step == "sso"}
        <div class="sg-stack">
          <p>{@email}</p>
          {%for provider <- @domain_providers}
            <a href={Auth.sso_path(provider)} class="btn btn-black">{Auth.sso_label(provider)}</a>
          {/for}
          <button type="button" class="btn btn-outline" $click={:use_password}>Use password instead</button>
          <button type="button" class="btn btn-outline" $click={:back_to_email}>Change email</button>
        </div>
      {/if}

      {%if @step == "password"}
        <form class="sg-form" $submit.prevent_default={:submit_password}>
          {%if @error}
            <p class="sg-error" role="alert">{@error}</p>
          {/if}
          <div class="sg-field">
            <label for="login-password-email">Email</label>
            <input
              id="login-password-email"
              name="email"
              type="email"
              value={@email}
              required
              autocomplete="email"
              $change={:set_email}
            />
          </div>
          <div class="sg-field">
            <label for="login-password">Password</label>
            <input
              id="login-password"
              name="password"
              type="password"
              value={@password}
              required
              autocomplete="current-password"
              $change={:set_password}
            />
          </div>
          <button type="submit" class="btn btn-black" disabled={@loading}>
            {%if @loading}Logging in...{%else}Log In{/if}
          </button>
          <div class="sg-form-footer">
            <p><Link to={ForgotPasswordPage}>Forgot password?</Link></p>
            <p><a href="#" $click.prevent_default={:back_to_email}>Change email</a></p>
            <p>Don't have an account? <Link to={SignupPage}>Sign up</Link></p>
          </div>
        </form>
      {/if}
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_email, params, component) do
    put_state(component, :email, params.event.value)
  end

  def action(:set_password, params, component) do
    put_state(component, :password, params.event.value)
  end

  def action(:submit_email, _params, component) do
    email = component.state.email

    providers =
      Auth.matching_sso_providers(email, %{
        providers: component.state.sso_providers,
        domain_policies: component.state.sso_domains,
        domains: component.state.sso_domains
      })

    step = if providers != [], do: "sso", else: "password"

    put_state(component,
      step: step,
      domain_providers: providers,
      error: nil
    )
  end

  def action(:use_password, _params, component), do: put_state(component, :step, "password")

  def action(:back_to_email, _params, component),
    do: put_state(component, step: "email", error: nil)

  def action(:submit_password, _params, component) do
    component
    |> put_state(loading: true, error: nil)
    |> put_command(:login,
      email: component.state.email,
      password: component.state.password
    )
  end

  def action(:login_ok, params, component) do
    path = params.path || Auth.post_auth_path(params.user)
    page = path_to_page(path)

    component
    |> put_state(loading: false, user: params.user, error: nil)
    |> put_page(page)
  end

  def action(:login_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Invalid email or password")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:login, params, server) do
    case Auth.login(server, params.email, params.password) do
      {:ok, server, user, orgs} ->
        path = Auth.post_auth_path(user)

        server
        |> put_action(:login_ok, user: user, organizations: orgs, path: path)

      {:error, message} ->
        put_action(server, :login_failed, error: message)
    end
  end

  defp path_to_page("/auth/invite-required"), do: AnnotateWeb.Hologram.Pages.InviteRequiredPage

  defp path_to_page("/complete-registration"),
    do: AnnotateWeb.Hologram.Pages.CompleteRegistrationPage

  defp path_to_page(_), do: AnnotateWeb.Hologram.Pages.AppHomePage
end
