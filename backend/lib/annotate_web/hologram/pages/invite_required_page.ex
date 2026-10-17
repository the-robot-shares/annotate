defmodule AnnotateWeb.Hologram.Pages.InviteRequiredPage do
  @moduledoc """
  The invite interstitial (`/auth/invite-required`) — register open, app
  gated (see `Annotate.Auth.InviteGate`).

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

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/auth/invite-required"
  layout MainLayout, page_title: "Invite required"
  middleware RequireAuth, invite: :exempt

  def init(_params, component, server) do
    user = Auth.current_user(server)

    invite_error =
      case query_param(server, "invite_error") do
        "invalid_token" ->
          "That invite link is invalid, expired, revoked, or for a different email address."

        "invite_exhausted" ->
          "That invite link has already been used."

        _ ->
          nil
      end

    # Hologram ignores a redirect set in page init/3, so an already-active user
    # gets a link to the dashboard instead of the redeem form.
    put_state(component,
      active: not Auth.user_needs_invite?(user),
      email: user && user.email,
      unverified: user != nil and user.status in [:unverified, "unverified"],
      token: "",
      error: invite_error,
      notice: nil,
      loading: false
    )
  end

  def template do
    ~HOLO"""
    <div class="content sg-auth-page" data-cy="invite-required">
      {%if @active}
        <h1 class="sg-page-title">you're in</h1>
        <p><a class="btn btn-black" href="/dashboard">Open your dashboard</a></p>
      {%else}
      <h1 class="sg-page-title">annotate is invite-only</h1>

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
          You're signed in as {@email}, but the annotate dashboard is invite-only right now.
          Have an invite link? Open it, or paste the code below.
          No invite yet? <a href="/#waitlist">Join the waitlist</a>.
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
      {/if}
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
    |> put_page(AnnotateWeb.Hologram.Pages.DashboardSitesPage)
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

  defp query_param(server, key) do
    q = Map.get(server, :query) || %{}
    Map.get(q, key)
  end
end
