defmodule StarterWeb.Hologram.Pages.InviteRequiredPage do
  @moduledoc """
  The invite interstitial (`/auth/invite-required`) — register open, app
  gated (see `Starter.Auth.InviteGate`).

  A signed-in user whose account is held (`:pending`/`:waitlist` on an
  invite-required domain, or `:unverified` after a password signup on an
  auto-approve domain) lands here from `post_auth_path/1` and from every app
  page (`RequireAuth`). They can redeem an invite code, re-send their email
  confirmation, reach profile/settings, or sign out. Users who are not held
  are sent on to `/app`.

  `data-cy` hooks match the fleet contract (PATTERN.md §7 / tobor-kit
  `<noizu-invite-gate>`): `invite-required`, `invite-code-input`,
  `invite-redeem-submit`, `invite-error`, `invite-profile-link`,
  `invite-settings-link`, `invite-sign-out`.
  """
  use Hologram.Page

  alias Starter.Hologram.Auth
  alias StarterWeb.Hologram.Layouts.MainLayout
  alias StarterWeb.Hologram.Middleware.RequireAuth
  alias StarterWeb.Hologram.Pages.AppHomePage

  route "/auth/invite-required"
  layout MainLayout, page_title: "Invite required"
  middleware RequireAuth, invite: :exempt

  def init(_params, component, server) do
    user = Auth.current_user(server)

    if Auth.user_needs_invite?(user) do
      put_state(component,
        email: user.email,
        unverified: user.status in [:unverified, "unverified"],
        token: "",
        error: nil,
        notice: nil,
        loading: false
      )
    else
      {component, Hologram.Server.put_redirect(server, AppHomePage)}
    end
  end

  def template do
    ~HOLO"""
    <div class="content sg-auth-page" data-cy="invite-required">
      <h1 class="sg-page-title">invite required</h1>

      {%if @unverified}
        <p class="sg-page-intro">
          Your account ({@email}) was created. Confirm your email to continue — we sent a
          confirmation link to that address. An invite code works too.
        </p>
        <p>
          <button type="button" class="btn btn-outline btn-sm" data-cy="invite-resend-confirmation" $click={:resend}>
            resend confirmation email
          </button>
        </p>
      {%else}
        <p class="sg-page-intro">
          Your account ({@email}) was created but needs an invite code. Redeem one to continue.
        </p>
      {/if}

      {%if @notice}
        <p class="app-flash" role="status">{@notice}</p>
      {/if}

      <form class="sg-form" $submit.prevent_default={:redeem}>
        {%if @error}
          <p class="sg-error" role="alert" data-cy="invite-error">{@error}</p>
        {/if}
        <div class="sg-field">
          <label for="invite-code">invite code</label>
          <input id="invite-code" name="invite_code" type="text" value={@token} required
            autocomplete="off" data-cy="invite-code-input" $change={:set_token} />
        </div>
        <button type="submit" class="btn btn-black" data-cy="invite-redeem-submit" disabled={@loading}>
          {%if @loading}redeeming...{%else}redeem invite{/if}
        </button>
      </form>

      <div class="sg-form-footer">
        <p>
          <a href="/app/profile" data-cy="invite-profile-link">profile</a>
          ·
          <a href="/app/profile#settings" data-cy="invite-settings-link">settings</a>
          ·
          <button type="button" class="btn btn-outline btn-sm" data-cy="invite-sign-out" $click={action: :logout, target: "layout"}>sign out</button>
        </p>
      </div>
    </div>
    """
  end

  def action(:set_token, params, component), do: put_state(component, :token, params.event.value)

  def action(:redeem, _params, component) do
    component
    |> put_state(loading: true, error: nil, notice: nil)
    |> put_command(:redeem, token: component.state.token)
  end

  def action(:redeemed, _params, component) do
    component
    |> put_state(loading: false)
    |> put_page(AppHomePage)
  end

  def action(:redeem_failed, params, component) do
    put_state(component, loading: false, error: params.error)
  end

  def action(:resend, _params, component) do
    component
    |> put_state(error: nil, notice: nil)
    |> put_command(:resend)
  end

  def action(:resent, params, component), do: put_state(component, notice: params.notice)

  def command(:redeem, params, server) do
    case Auth.redeem_invite(server, params.token) do
      {:ok, _user} -> put_action(server, :redeemed)
      {:error, code} -> put_action(server, :redeem_failed, error: Auth.invite_error_message(code))
    end
  end

  def command(:resend, _params, server) do
    notice =
      case Auth.resend_confirmation(server) do
        :ok ->
          "Confirmation email sent. Check your inbox."

        {:error, "rate_limited"} ->
          "Too many attempts. Wait a minute and try again."

        {:error, "not_unverified"} ->
          "Your account is waiting for an invite code — email confirmation won't unlock it."

        {:error, _} ->
          "Could not send the confirmation email. Log in again and retry."
      end

    put_action(server, :resent, notice: notice)
  end
end
