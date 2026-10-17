defmodule AnnotateWeb.Hologram.Pages.SignupPage do
  @moduledoc "Multi-step signup ported from start-app signup page."
  use Hologram.Page

  alias Hologram.UI.Link
  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.AuthLayout
  alias AnnotateWeb.Hologram.Pages.LoginPage

  route "/signup"
  layout AuthLayout, page_title: "Sign Up"
  middleware AnnotateWeb.Hologram.Middleware.GithubOnly

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server) do
    # Register open, app gated: the invite field is always optional.
    catalog = Auth.sso_catalog()

    put_state(component,
      step: "email",
      email: "",
      password: "",
      user_name: "",
      first_name: "",
      last_name: "",
      mobile_phone: "",
      invite_token: "",
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
    <div class="nd-auth">
      <h1 class="nd-auth__title">Sign Up</h1>

      {%if @step == "email"}
        <form class="nd-auth__form" $submit.prevent_default={:submit_email}>
          {%if @error}
            <p class="nd-auth__error" role="alert">{@error}</p>
          {/if}
          <div class="nd-auth__field">
            <label for="signup-email">Email</label>
            <input id="signup-email" name="email" type="email" value={@email} required autocomplete="email" $change={:set_email} />
          </div>
          <button type="submit" class="nd-btn nd-btn--primary">Continue</button>
          <div class="nd-auth__footer">
            <p>Already have an account? <Link to={LoginPage}>Log in</Link></p>
          </div>
        </form>
      {/if}

      {%if @step == "sso"}
        <div class="nd-auth__stack">
          <p>{@email}</p>
          {%for provider <- @domain_providers}
            <a href={Auth.sso_invite_path(provider, @invite_token)} class="nd-btn nd-btn--primary">{Auth.sso_label(provider)}</a>
          {/for}
          <button type="button" class="nd-btn nd-btn--ghost" $click={:use_password}>Use password instead</button>
          <button type="button" class="nd-btn nd-btn--ghost" $click={:back_to_email}>Change email</button>
        </div>
      {/if}

      {%if @step == "password"}
        <form class="nd-auth__form" $submit.prevent_default={:submit_register}>
          {%if @error}
            <p class="nd-auth__error" role="alert">{@error}</p>
          {/if}
          <div class="nd-auth__field">
            <label for="signup-email-2">Email</label>
            <input id="signup-email-2" type="email" value={@email} required autocomplete="email" $change={:set_email} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-password">Password</label>
            <input id="signup-password" type="password" value={@password} required autocomplete="new-password" $change={:set_password} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-username">Username</label>
            <input id="signup-username" type="text" value={@user_name} required autocomplete="username" $change={:set_user_name} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-first">First name</label>
            <input id="signup-first" type="text" value={@first_name} required autocomplete="given-name" $change={:set_first_name} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-last">Last name</label>
            <input id="signup-last" type="text" value={@last_name} required autocomplete="family-name" $change={:set_last_name} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-phone">Mobile phone</label>
            <input id="signup-phone" type="tel" value={@mobile_phone} required autocomplete="tel" $change={:set_mobile_phone} />
          </div>
          <div class="nd-auth__field">
            <label for="signup-invite">Invite code (optional)</label>
            <input id="signup-invite" type="text" value={@invite_token} autocomplete="off" data-cy="invite-token-input" $change={:set_invite_token} />
            <p class="nd-auth__hint" data-cy="invite-token-hint">No invite? Sign up and join the queue; add an invite token at any time.</p>
          </div>
          <button type="submit" class="nd-btn nd-btn--primary" disabled={@loading}>
            {%if @loading}Creating account...{%else}Create account{/if}
          </button>
          <div class="nd-auth__footer">
            <p><a href="#" $click.prevent_default={:back_to_email}>Change email</a></p>
            <p>Already have an account? <Link to={LoginPage}>Log in</Link></p>
          </div>
        </form>
      {/if}
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_email, params, c), do: put_state(c, :email, params.event.value)
  def action(:set_password, params, c), do: put_state(c, :password, params.event.value)
  def action(:set_user_name, params, c), do: put_state(c, :user_name, params.event.value)
  def action(:set_first_name, params, c), do: put_state(c, :first_name, params.event.value)
  def action(:set_last_name, params, c), do: put_state(c, :last_name, params.event.value)
  def action(:set_mobile_phone, params, c), do: put_state(c, :mobile_phone, params.event.value)
  def action(:set_invite_token, params, c), do: put_state(c, :invite_token, params.event.value)

  def action(:submit_email, _params, component) do
    email = component.state.email

    providers =
      Auth.matching_sso_providers(email, %{
        providers: component.state.sso_providers,
        domain_policies: component.state.sso_domains,
        domains: component.state.sso_domains
      })

    user_name =
      if component.state.user_name == "" do
        email |> String.split("@") |> List.first() || ""
      else
        component.state.user_name
      end

    put_state(component,
      step: if(providers != [], do: "sso", else: "password"),
      domain_providers: providers,
      user_name: user_name,
      error: nil
    )
  end

  def action(:use_password, _p, c), do: put_state(c, :step, "password")
  def action(:back_to_email, _p, c), do: put_state(c, step: "email", error: nil)

  def action(:submit_register, _params, component) do
    component
    |> put_state(loading: true, error: nil)
    |> put_command(:register,
      email: component.state.email,
      password: component.state.password,
      user_name: component.state.user_name,
      first_name: component.state.first_name,
      last_name: component.state.last_name,
      mobile_phone: component.state.mobile_phone,
      invite_token: component.state.invite_token
    )
  end

  def action(:register_ok, params, component) do
    page =
      case Auth.post_auth_path(params.user) do
        "/auth/invite-required" -> AnnotateWeb.Hologram.Pages.InviteRequiredPage
        _ -> AnnotateWeb.Hologram.Pages.AppHomePage
      end

    component
    |> put_state(loading: false)
    |> put_page(page)
  end

  def action(:register_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Registration failed")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:register, params, server) do
    case Auth.register(server, params) do
      {:ok, server, user, orgs} ->
        put_action(server, :register_ok, user: user, organizations: orgs)

      {:error, message} ->
        put_action(server, :register_failed, error: message)
    end
  end
end
