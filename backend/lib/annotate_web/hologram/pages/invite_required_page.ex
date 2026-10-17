defmodule AnnotateWeb.Hologram.Pages.InviteRequiredPage do
  @moduledoc """
  The invite interstitial (`/auth/invite-required`) — register open, app
  gated (see `Annotate.Auth.InviteGate`).

  A signed-in user whose account is held (`:pending`/`:waitlist` on an
  invite-required domain, or `:unverified` after a password signup on an
  auto-approve domain) lands here from `post_auth_path/1` and from every app
  page (`RequireAuth`). They can redeem an invite code, join the waitlist,
  pay the one-time $19.95 beta join (`Annotate.Billing.BetaJoin` — webhook
  clears the gate and grants a 90-day Team trial), re-send their email
  confirmation, reach profile/settings, or sign out. Users who are not held
  are sent on to `/app`.

  `data-cy` hooks match the fleet contract (PATTERN.md §7 / tobor-kit
  `<noizu-invite-gate>`): `invite-required`, `invite-code-input`,
  `invite-redeem-submit`, `invite-error`, `invite-profile-link`,
  `invite-settings-link`, `invite-sign-out`.
  """
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Layouts.AuthLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/auth/invite-required"
  layout AuthLayout, page_title: "Invite required"
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

    beta_notice =
      case query_param(server, "beta") do
        "joined" ->
          "Payment received — activating your beta access. Give it a few seconds, then check again."

        "cancelled" ->
          "Checkout cancelled — you haven't been charged."

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
      beta_notice: beta_notice,
      beta_error: nil,
      beta_loading: false,
      loading: false
    )
  end

  def template do
    ~HOLO"""
    <div class="nd-auth" data-cy="invite-required">
      {%if @active}
        <h1 class="nd-auth__title">you're in</h1>
        <p><a class="nd-btn nd-btn--primary" href="/dashboard">Open your dashboard</a></p>
      {%else}
      <h1 class="nd-auth__title">annotate is invite-only</h1>

      {%if @unverified}
        <p class="nd-auth__intro">
          Your account ({@email}) was created. Confirm your email to continue — we sent a
          confirmation link to that address. An invite code works too.
        </p>
        <p>
          <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" data-cy="invite-resend-confirmation" $click={:resend}>
            resend confirmation email
          </button>
        </p>
      {%else}
        <p class="nd-auth__intro">
          You're signed in as {@email}, but the annotate dashboard is invite-only right now.
          Have an invite link? Open it, or paste the code below.
          No invite? <a href="/#waitlist">Sign up and join the queue</a> — or skip it below.
        </p>
      {/if}

      {%if @notice}
        <p class="nd-auth__flash" role="status">{@notice}</p>
      {/if}

      {%if @beta_notice}
        <p class="nd-auth__flash" role="status" data-cy="invite-beta-notice">{@beta_notice}</p>
        <p><button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" data-cy="invite-beta-check" $click={:check_activation} disabled={@beta_loading}>
          Check again
        </button></p>
      {/if}

      <form class="nd-auth__form" $submit.prevent_default={:redeem}>
        {%if @error}
          <p class="nd-auth__error" role="alert" data-cy="invite-error">{@error}</p>
        {/if}
        <div class="nd-auth__field">
          <label for="invite-code">invite code</label>
          <input id="invite-code" name="invite_code" type="text" value={@token} required
            autocomplete="off" data-cy="invite-code-input" $change={:set_token} />
        </div>
        <button type="submit" class="nd-btn nd-btn--primary" data-cy="invite-redeem-submit" disabled={@loading}>
          {%if @loading}redeeming...{%else}redeem invite{/if}
        </button>
      </form>

      <div class="nd-auth__beta" data-cy="invite-beta">
        <h2 class="nd-auth__beta-title">No invite? Skip the queue.</h2>
        <p>
          Join the beta now for <strong>$19.95</strong> — one-time, non-refundable.
          Includes 3 months of Team, on us.
        </p>
        {%if @beta_error}
          <p class="nd-auth__error" role="alert" data-cy="invite-beta-error">{@beta_error}</p>
        {/if}
        <button type="button" class="nd-btn nd-btn--primary" data-cy="invite-beta-join"
          $click={:beta_join} disabled={@beta_loading}>
          {%if @beta_loading}opening checkout...{%else}I want it now — $19.95{/if}
        </button>
      </div>

      <div class="nd-auth__footer">
        <p>
          <a href="/app/profile" data-cy="invite-profile-link">profile</a>
          ·
          <a href="/app/profile#settings" data-cy="invite-settings-link">settings</a>
          ·
          <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" data-cy="invite-sign-out" $click={action: :logout, target: "layout"}>sign out</button>
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

  def action(:beta_join, _params, component) do
    component
    |> put_state(beta_loading: true, beta_error: nil)
    |> put_command(:beta_checkout)
  end

  # Same hand-off as the billing page: Stripe's hosted checkout takes the tab.
  def action(:redirected, params, _c),
    do: Hologram.JS.exec("window.location.href = " <> js_string(params.url) <> ";")

  def action(:beta_failed, params, c), do: put_state(c, beta_loading: false, beta_error: params.error)

  def action(:activated, _params, component) do
    component
    |> put_state(active: true, beta_loading: false)
    |> put_page(AnnotateWeb.Hologram.Pages.DashboardSitesPage)
  end

  def action(:still_waiting, params, c),
    do: put_state(c, beta_loading: false, beta_notice: params.notice)

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

  def command(:beta_checkout, _params, server) do
    user = Auth.current_user(server)

    case user && Annotate.Billing.Subscriptions.start_beta_checkout(user) do
      {:ok, url} ->
        put_action(server, :redirected, url: url)

      {:error, :stripe_disabled} ->
        put_action(server, :beta_failed, error: "Payments aren't set up yet — check back soon.")

      {:error, :price_not_found} ->
        put_action(server, :beta_failed, error: "Payments aren't set up yet — check back soon.")

      _ ->
        put_action(server, :beta_failed, error: "Could not open checkout — try again.")
    end
  end

  def command(:check_activation, _params, server) do
    user = Auth.current_user(server)

    if user && not Auth.user_needs_invite?(user) do
      put_action(server, :activated)
    else
      put_action(server, :still_waiting,
        notice: "Not active yet — the payment is still processing. Give it a moment and check again."
      )
    end
  end

  defp query_param(server, key) do
    q = Map.get(server, :query) || %{}
    Map.get(q, key)
  end

  defp js_string(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"" <> escaped <> "\""
  end
end
