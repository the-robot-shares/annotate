defmodule StarterWeb.Hologram.Components.FloatingAuth do
  @moduledoc """
  Floating login/signup card (tobor-kit / TRP `LoginDropdown` chrome):
  ~380px `rounded-2xl` panel, opaque `--surface` background so hero art
  never bleeds through, `shadow-2xl`, anchored under the navbar buttons.

  Renders its own trigger buttons so open/close/mode state never has to
  cross component boundaries. The full-page `/login` and `/signup` routes
  remain as direct-entry fallbacks; this component is the navbar path.

  Invites (register open, app gated): the signup flow always shows an
  optional invite-code field with a live lookup ("Joining <org> as <role>");
  SSO links carry `?invite=` so the code survives the IdP redirect round-trip
  in the signed session cookie. Without a code the account may be held at
  `/auth/invite-required` (`Starter.Auth.InviteGate`).

  On success the component hard-navigates via JS interop (kit `LoginFlow`
  precedent) — `put_page/2` is page-only, unavailable from a component.
  """

  use Hologram.Component
  use Hologram.JS

  alias Starter.Hologram.Auth

  def template do
    ~HOLO"""
    <div class="sg-auth">
      {%if @open}
      {%else}
        <button type="button" class="btn btn-outline btn-sm" $click={:open_login}>Log In</button>
        <button type="button" class="btn btn-black btn-sm" $click={:open_signup}>Sign Up</button>
      {/if}

      {%if @open}
        <div class="sg-auth__panel" role="dialog" aria-label={Auth.label(@mode)}>
          <button type="button" class="sg-auth__close" aria-label="Close" $click={:close}>&times;</button>

          {%if @mode == "login"}
            <h2 class="sg-auth__title">Welcome back</h2>
          {%else}
            <h2 class="sg-auth__title">Create your account</h2>
          {/if}

          {%if @invite_note != ""}
            <p class="sg-auth__invite-note">{@invite_note}</p>
          {/if}

          {%if @error}
            <p class="sg-error" role="alert">{@error}</p>
          {/if}

          {%if @step == "email"}
            <form class="sg-form" $submit.prevent_default={:submit_email}>
              <div class="sg-field">
                <label for="fa-email">Email</label>
                <input id="fa-email" name="email" type="email" value={@email} required autocomplete="email" $change={:set_email} />
              </div>

              {%if @mode == "signup"}
                <div class="sg-field">
                  <label for="fa-invite">Invite code (optional)</label>
                  <input id="fa-invite" name="invite_token" type="text" value={@invite_token} autocomplete="off" data-cy="invite-token-input" $change={:set_invite_token} $blur={:lookup_invite} />
                  <p class="sg-field__hint" data-cy="invite-token-hint">have an invite? enter it now — otherwise you can add it after signing up.</p>
                </div>
              {/if}

              <button type="submit" class="btn btn-black" disabled={@loading}>
                {%if @loading}Checking...{%else}Continue{/if}
              </button>
            </form>
          {/if}

          {%if @step == "sso"}
            <div class="sg-auth__divider">or continue with</div>
            <div class="sg-auth__sso">
              <p class="sg-auth__subtitle">{@email}</p>
              {%for provider <- @domain_providers}
                <a href={Auth.sso_invite_path(provider, @invite_token)} class="btn btn-black">{Auth.sso_label(provider)}</a>
              {/for}
              {%if @mode == "signup"}
                <a href={Auth.sso_invite_path("oidc", @invite_token)} class="btn btn-outline">Sign in with SSO</a>
              {/if}
              <button type="button" class="btn btn-outline" $click={:use_password}>Use password instead</button>
              <button type="button" class="btn btn-outline" $click={:back_to_email}>Change email</button>
            </div>
          {/if}

          {%if @step == "password"}
            <form class="sg-form" $submit.prevent_default={:submit_auth}>
              <div class="sg-field">
                <label for="fa-password-email">Email</label>
                <input id="fa-password-email" type="email" value={@email} required autocomplete="email" $change={:set_email} />
              </div>
              <div class="sg-field">
                <label for="fa-password">Password</label>
                <input id="fa-password" type="password" value={@password} required
                  autocomplete={Auth.password_autocomplete(@mode)} $change={:set_password} />
              </div>

              {%if @mode == "signup"}
                <div class="sg-field">
                  <label for="fa-username">Username</label>
                  <input id="fa-username" type="text" value={@user_name} required autocomplete="username" $change={:set_user_name} />
                </div>
                <div class="sg-field">
                  <label for="fa-first">First name</label>
                  <input id="fa-first" type="text" value={@first_name} required autocomplete="given-name" $change={:set_first_name} />
                </div>
                <div class="sg-field">
                  <label for="fa-last">Last name</label>
                  <input id="fa-last" type="text" value={@last_name} required autocomplete="family-name" $change={:set_last_name} />
                </div>
                <div class="sg-field">
                  <label for="fa-phone">Mobile phone</label>
                  <input id="fa-phone" type="tel" value={@mobile_phone} required autocomplete="tel" $change={:set_mobile_phone} />
                </div>
                <div class="sg-field">
                  <label for="fa-invite-2">Invite code (optional)</label>
                  <input id="fa-invite-2" type="text" value={@invite_token} autocomplete="off" $change={:set_invite_token} $blur={:lookup_invite} />
                </div>
              {/if}

              <button type="submit" class="btn btn-black" disabled={@loading}>
                {%if @loading}
                  {%if @mode == "signup"}Creating account...{%else}Logging in...{/if}
                {%else}
                  {%if @mode == "signup"}Create account{%else}Log In{/if}
                {/if}
              </button>

              <div class="sg-form-footer">
                {%if @mode == "login"}
                  <p>Forgot password? <a href="/forgot-password">Reset it</a></p>
                {/if}
                <p><a href="#" $click.prevent_default={:back_to_email}>Change email</a></p>
              </div>
            </form>
          {/if}

          <div class="sg-form-footer">
            {%if @mode == "login"}
              <p>Don't have an account? <a href="#" $click.prevent_default={:switch_mode}>Sign up</a></p>
            {%else}
              <p>Already have an account? <a href="#" $click.prevent_default={:switch_mode}>Log in</a></p>
            {/if}
          </div>
        </div>
      {/if}
    </div>
    """
  end

  def init(_props, component, _server) do
    catalog = Auth.sso_catalog()

    put_state(component,
      open: false,
      mode: "login",
      step: "email",
      email: "",
      password: "",
      user_name: "",
      first_name: "",
      last_name: "",
      mobile_phone: "",
      invite_token: "",
      invite_note: "",
      error: nil,
      loading: false,
      sso_providers: catalog.providers,
      sso_domains: catalog.domain_policies || catalog.domains || %{},
      domain_providers: []
    )
  end

  # -- client actions --------------------------------------------------------

  def action(:open_login, _params, component),
    do: open_panel(component, "login")

  def action(:open_signup, _params, component),
    do: open_panel(component, "signup")

  def action(:close, _params, component),
    do: put_state(component, open: false, error: nil)

  def action(:switch_mode, _params, component) do
    component
    |> put_state(mode: other_mode(component.state.mode), step: "email", error: nil)
    |> maybe_lookup_invite()
  end

  def action(:set_email, params, component), do: put_state(component, :email, params.event.value)

  def action(:set_password, params, component), do: put_state(component, :password, params.event.value)

  def action(:set_user_name, params, component), do: put_state(component, :user_name, params.event.value)

  def action(:set_first_name, params, component), do: put_state(component, :first_name, params.event.value)

  def action(:set_last_name, params, component), do: put_state(component, :last_name, params.event.value)

  def action(:set_mobile_phone, params, component), do: put_state(component, :mobile_phone, params.event.value)

  # Typing only updates state — the token lookup runs on blur (or when the
  # user submits), so a keystroke never triggers a bcrypt round on the server.
  def action(:set_invite_token, params, component),
    do: put_state(component, :invite_token, params.event.value)

  def action(:lookup_invite, _params, component), do: maybe_lookup_invite(component)

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

    component
    |> put_state(
      step: if(providers != [], do: "sso", else: "password"),
      domain_providers: providers,
      user_name: user_name,
      error: nil
    )
    |> maybe_lookup_invite()
  end

  def action(:use_password, _params, component), do: put_state(component, :step, "password")

  def action(:back_to_email, _params, component),
    do: put_state(component, step: "email", error: nil)

  def action(:submit_auth, _params, component) do
    command =
      if component.state.mode == "signup" do
        :register
      else
        :login
      end

    component
    |> put_state(loading: true, error: nil)
    |> put_command(command,
      email: component.state.email,
      password: component.state.password,
      user_name: component.state.user_name,
      first_name: component.state.first_name,
      last_name: component.state.last_name,
      mobile_phone: component.state.mobile_phone,
      invite_token: component.state.invite_token
    )
  end

  def action(:auth_ok, params, component) do
    # Components cannot put_page/2 — hard-navigate instead (kit LoginFlow
    # precedent). The browser leaves either way; the state is cosmetic.
    location = JS.get(:window, :location)
    JS.call(location, :assign, [params.path])

    put_state(component, loading: false, error: nil)
  end

  def action(:auth_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Authentication failed")
  end

  def action(:invite_lookup_ok, params, component) do
    note =
      if params.organization_name in [nil, ""] do
        "Valid invite — you'll join as #{params.role}."
      else
        "Joining #{params.organization_name} as #{params.role}."
      end

    put_state(component, invite_note: note)
  end

  def action(:invite_lookup_failed, _params, component) do
    put_state(component,
      invite_note: "",
      error: "That invite token is invalid or has expired. Ask your inviter for a new one."
    )
  end

  # No-op catch-all: a stray event must never crash the host page.
  def action(_name, _params, component), do: component

  # -- server commands -------------------------------------------------------

  def command(:login, params, server) do
    case Auth.login(server, params.email, params.password) do
      {:ok, server, user, _orgs} ->
        put_action(server, :auth_ok, path: Auth.post_auth_path(user))

      {:error, message} ->
        put_action(server, :auth_failed, error: message)
    end
  end

  def command(:register, params, server) do
    case Auth.register(server, params) do
      {:ok, server, user, _orgs} ->
        put_action(server, :auth_ok, path: Auth.post_auth_path(user))

      {:error, message} ->
        put_action(server, :auth_failed, error: message)
    end
  end

  # The lookup is a bcrypt-verified token-validity oracle — same exposure as
  # the REST `/invites/lookup` route, so it gets the same Hammer guard the
  # router applies there (10/min per IP). Hologram commands bypass the router
  # pipelines, hence the check living here.
  def command(:lookup_invite, params, server) do
    with {:allow, _} <-
           Hammer.check_rate("invite_lookup:#{server.ip}", 60_000, 10),
         {:ok, invite} <- Starter.Organizations.find_active_invite_by_raw_token(params.token) do
      put_action(server, :invite_lookup_ok,
        organization_name: Starter.Organizations.organization_name(invite.organization_id),
        role: invite.role || "viewer"
      )
    else
      {:deny, _} ->
        put_action(server, :invite_lookup_failed, %{})

      {:error, _} ->
        put_action(server, :invite_lookup_failed, %{})
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp open_panel(component, mode) do
    component
    |> put_state(open: true, mode: mode, step: "email", error: nil, invite_note: "")
    |> maybe_lookup_invite()
  end

  # Only worth a server round-trip when the token is non-blank; the lookup
  # doubles as validation feedback for the signup form.
  defp maybe_lookup_invite(component) do
    token = String.trim(component.state.invite_token || "")

    if token != "" do
      put_command(component, :lookup_invite, token: token)
    else
      put_state(component, invite_note: "")
    end
  end

  defp other_mode("login"), do: "signup"
  defp other_mode(_), do: "login"
end
