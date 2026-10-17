defmodule AnnotateWeb.Hologram.Pages.JoinPage do
  @moduledoc """
  `/join/:token` — an invite link's landing page.

  Resolves the token server-side (validity oracle, same rules as
  `InviteTokenController.lookup/2`), shows who you're joining, then hands off:
  SSO buttons carry `?invite=` so the token survives the IdP round-trip; the
  password form is the signup flow with the token pinned.
  """
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.MainLayout

  route "/join/:token"
  layout MainLayout, page_title: "Join"
  middleware AnnotateWeb.Hologram.Middleware.GithubOnly

  def init(params, component, _server) do
    catalog = Auth.sso_catalog()
    token = Map.get(params, "token") || Map.get(params, :token) || ""

    component =
      put_state(component,
        token: token,
        status: "checking",
        organization_name: "",
        role: "",
        email: "",
        password: "",
        user_name: "",
        first_name: "",
        last_name: "",
        mobile_phone: "",
        error: nil,
        loading: false,
        sso_providers: catalog.providers
      )

    put_command(component, :lookup, token: token)
  end

  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Join</h1>

      {%if @status == "checking"}
        <p class="app-muted">Checking your invite…</p>
      {/if}

      {%if @status == "invalid"}
        <p class="sg-error" role="alert">
          This invite link is invalid or has expired. Ask your inviter for a new one.
        </p>
        <p><a href="/" class="btn btn-outline">Back to home</a></p>
      {/if}

      {%if @status == "valid"}
        {%if @organization_name != ""}
          <p class="sg-auth__invite-note">
            You've been invited to join <strong>{@organization_name}</strong>
            as <strong>{@role}</strong>.
          </p>
        {/if}

        {%if @error}
          <p class="sg-error" role="alert">{@error}</p>
        {/if}

        {%if @sso_providers != []}
          <div class="sg-stack">
            {%for provider <- @sso_providers}
              <a href={Auth.sso_invite_path(provider, @token)} class="btn btn-black">
                {Auth.sso_label(provider)}
              </a>
            {/for}
            <p class="app-muted">— or sign up with a password —</p>
          </div>
        {/if}

        <form class="sg-form" $submit.prevent_default={:submit_register}>
          <div class="sg-field">
            <label for="join-email">Email</label>
            <input id="join-email" type="email" value={@email} required autocomplete="email" $change={:set_email} />
          </div>
          <div class="sg-field">
            <label for="join-password">Password</label>
            <input id="join-password" type="password" value={@password} required autocomplete="new-password" $change={:set_password} />
          </div>
          <div class="sg-field">
            <label for="join-username">Username</label>
            <input id="join-username" type="text" value={@user_name} required autocomplete="username" $change={:set_user_name} />
          </div>
          <div class="sg-field">
            <label for="join-first">First name</label>
            <input id="join-first" type="text" value={@first_name} required autocomplete="given-name" $change={:set_first_name} />
          </div>
          <div class="sg-field">
            <label for="join-last">Last name</label>
            <input id="join-last" type="text" value={@last_name} required autocomplete="family-name" $change={:set_last_name} />
          </div>
          <div class="sg-field">
            <label for="join-phone">Mobile phone</label>
            <input id="join-phone" type="tel" value={@mobile_phone} required autocomplete="tel" $change={:set_mobile_phone} />
          </div>
          <div class="sg-field">
            <label for="join-invite">Invite token</label>
            <input id="join-invite" type="text" value={@token} required $change={:set_token} />
          </div>
          <button type="submit" class="btn btn-black" disabled={@loading}>
            {%if @loading}Creating account...{%else}Create account{/if}
          </button>
        </form>
      {/if}
    </div>
    """
  end

  # -- actions ----------------------------------------------------------------

  def action(:set_email, params, c), do: put_state(c, :email, params.event.value)
  def action(:set_password, params, c), do: put_state(c, :password, params.event.value)
  def action(:set_user_name, params, c), do: put_state(c, :user_name, params.event.value)
  def action(:set_first_name, params, c), do: put_state(c, :first_name, params.event.value)
  def action(:set_last_name, params, c), do: put_state(c, :last_name, params.event.value)
  def action(:set_mobile_phone, params, c), do: put_state(c, :mobile_phone, params.event.value)
  def action(:set_token, params, c), do: put_state(c, :token, params.event.value)

  def action(:invite_ok, params, component) do
    put_state(component,
      status: "valid",
      organization_name: params.organization_name || "",
      role: params.role || "viewer"
    )
  end

  def action(:invite_invalid, _params, component),
    do: put_state(component, :status, "invalid")

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
      invite_token: component.state.token
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

  # -- commands ---------------------------------------------------------------

  # Same validity-oracle exposure as the REST lookup route, and this command
  # bypasses the router's rate-limit pipeline — Hammer guard applies here too.
  def command(:lookup, params, server) do
    with {:allow, _} <-
           Hammer.check_rate("invite_lookup:#{server.ip}", 60_000, 10),
         {:ok, invite} <- Annotate.Organizations.find_active_invite_by_raw_token(params.token) do
      put_action(server, :invite_ok,
        organization_name: Annotate.Organizations.organization_name(invite.organization_id),
        role: invite.role || "viewer"
      )
    else
      _ -> put_action(server, :invite_invalid, %{})
    end
  end

  def command(:register, params, server) do
    case Auth.register(server, params) do
      {:ok, server, user, orgs} ->
        put_action(server, :register_ok, user: user, organizations: orgs)

      {:error, message} ->
        put_action(server, :register_failed, error: message)
    end
  end
end
