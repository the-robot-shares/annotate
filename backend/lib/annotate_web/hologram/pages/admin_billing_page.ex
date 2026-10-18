defmodule AnnotateWeb.Hologram.Pages.AdminBillingPage do
  @moduledoc """
  `/app/admin/billing` — platform admin: per-plan signup caps (raise/lower,
  sees claimed vs cap), per-user invite quotas and invite minting by email
  (`Annotate.Billing.SignupCaps` / `Annotate.Billing.set_invite_quota_by_email/2`
  / `Annotate.Dashboard.Invites.create/2`), the subscription rows with
  per-account quota controls (plan / extras / comp / trial extension via
  `Annotate.Billing.admin_*`). Re-authorized from the DB on every command.
  """

  use Hologram.Page

  alias Annotate.Billing.SignupCaps
  alias Annotate.Dashboard.Invites
  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Components.AppShell
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAdmin

  route "/app/admin/billing"
  layout MainLayout, page_title: "Admin · Billing"
  middleware RequireAdmin

  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)

    put_state(component,
      user: user,
      organizations: organizations || [],
      caps: serialize_caps(),
      quota_email: "",
      quota_value: "",
      subs: serialize_subs(),
      selected_email: "",
      plan_input: "",
      extra_users_input: "",
      extra_gb_input: "",
      trial_days_input: "",
      invite_email: "",
      invite_days: "14",
      invite_token: "",
      invite_link: "",
      flash: nil,
      error: nil,
      busy: false
    )
  end

  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="admin_billing" title="Admin · Billing">
      {%if @flash}<p class="app-flash" role="status" data-cy="adm-billing-flash">{@flash}</p>{/if}
      {%if @error}<p class="sg-error" role="alert" data-cy="adm-billing-error">{@error}</p>{/if}

      <section class="sg-page" data-cy="adm-billing-caps">
        <h2 class="sg-section-title">Plan signup caps</h2>
        <p class="sg-page-intro">
          When a plan is full, new checkouts are refused with a waitlist
          invitation. "Claimed" counts reserved slots (checkout started);
          live subscriptions are counted against the cap atomically at
          checkout start. The trial row caps new signups (intake control).
        </p>
        <table class="app-table">
          <thead>
            <tr><th>Plan</th><th>Cap</th><th>Claimed</th><th>State</th><th>Set cap</th></tr>
          </thead>
          <tbody>
            {%for c <- @caps}
              <tr data-cy="adm-billing-cap-row">
                <td>{c.plan}</td>
                <td>{c.cap}</td>
                <td>{c.taken}</td>
                <td>{%if c.full}<span class="dsh-chip">FULL</span>{%else}open{/if}</td>
                <td>
                  <form class="app-inline-form" $submit.prevent_default={action: :set_cap, params: %{plan: c.plan}}>
                    <input type="number" min="0" max="100000" value={c.cap}
                      $change={action: :cap_input, params: %{plan: c.plan}} />
                    <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-cap-save">Save</button>
                  </form>
                </td>
              </tr>
            {/for}
          </tbody>
        </table>
      </section>

      <section class="sg-page" data-cy="adm-billing-subs">
        <h2 class="sg-section-title">Subscriptions</h2>
        <p class="sg-page-intro">
          Local billing rows (billing owner = the dashboard user). Stripe
          webhooks remain the source of truth for plan, status and renewals —
          the Edit controls are admin overrides (plan, extras, comp, trial
          extension) applied to the local row.
        </p>
        <table class="app-table">
          <thead>
            <tr>
              <th>User</th><th>Plan</th><th>Status</th><th>Trial ends</th>
              <th>Renews</th><th>+Users</th><th>+GB</th><th>Comp</th><th></th>
            </tr>
          </thead>
          <tbody>
            {%for s <- @subs}
              <tr data-cy="adm-billing-sub-row">
                <td>{s.email}</td>
                <td>{s.plan}</td>
                <td>{s.status}</td>
                <td>{s.trial_ends_at}</td>
                <td>{s.current_period_end}</td>
                <td>{s.extra_users}</td>
                <td>{s.extra_gb}</td>
                <td>{%if s.comp}<span class="dsh-chip">COMP</span>{%else}—{/if}</td>
                <td>
                  <button type="button" class="app-btn" disabled={@busy}
                    $click={action: :select_sub, params: %{email: s.email}} data-cy="adm-billing-sub-edit">
                    Edit
                  </button>
                </td>
              </tr>
            {/for}
          </tbody>
        </table>

        {%if @selected_email != ""}
          <h3 class="sg-section-title" data-cy="adm-billing-quota-title">Quota controls — {@selected_email}</h3>
          <form class="app-inline-form" $submit.prevent_default={:set_plan}>
            <input type="text" placeholder="plan (empty = none)" value={@plan_input}
              data-cy="adm-billing-plan-input" $change={action: :set, params: %{field: "plan_input"}} />
            <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-plan-save">Set plan</button>
          </form>
          <form class="app-inline-form" $submit.prevent_default={:set_extras}>
            <input type="number" min="0" placeholder="extra users" value={@extra_users_input}
              data-cy="adm-billing-extras-users" $change={action: :set, params: %{field: "extra_users_input"}} />
            <input type="number" min="0" placeholder="extra GB" value={@extra_gb_input}
              data-cy="adm-billing-extras-gb" $change={action: :set, params: %{field: "extra_gb_input"}} />
            <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-extras-save">Set extras</button>
          </form>
          <form class="app-inline-form" $submit.prevent_default={:extend_trial}>
            <input type="number" min="1" placeholder="days" value={@trial_days_input}
              data-cy="adm-billing-trial-days" $change={action: :set, params: %{field: "trial_days_input"}} />
            <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-trial-extend">Extend trial</button>
          </form>
          <form class="app-inline-form" $submit.prevent_default={:toggle_comp}>
            <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-comp-toggle">Toggle comp</button>
          </form>
        {/if}
      </section>

      <section class="sg-page" data-cy="adm-billing-quota">
        <h2 class="sg-section-title">Invite quota</h2>
        <p class="sg-page-intro">
          A user's invite quota limits how many dashboard invites they can
          mint (admins and noizu.com staff are unlimited). Revoking an unused
          invite refunds it. Platform admins set quotas here.
        </p>
        <form class="app-inline-form" $submit.prevent_default={:set_quota}>
          <input type="email" placeholder="user@example.com" value={@quota_email}
            data-cy="adm-billing-quota-email" $change={action: :set, params: %{field: "quota_email"}} />
          <input type="number" min="0" max="10000" placeholder="quota" value={@quota_value}
            data-cy="adm-billing-quota-value" $change={action: :set, params: %{field: "quota_value"}} />
          <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-quota-save">Set quota</button>
        </form>
      </section>

      <section class="sg-page" data-cy="adm-billing-invite">
        <h2 class="sg-section-title">Mint dashboard invite</h2>
        <p class="sg-page-intro">
          Mints a single-use dashboard invite bound to one email (default
          14 days). Admins bypass the issuer quota. The raw token is shown
          exactly once, right here.
        </p>
        {%if @invite_token != ""}
          <div class="sg-auth__invite-note" data-cy="adm-billing-invite-result">
            <p><strong>Invite minted — copy it now, it will not be shown again.</strong></p>
            <p><code>{@invite_token}</code></p>
            <p>Join link: <code>{@invite_link}</code></p>
          </div>
        {/if}
        <form class="app-inline-form" $submit.prevent_default={:mint_invite}>
          <input type="email" placeholder="user@example.com" value={@invite_email}
            data-cy="adm-billing-invite-email" $change={action: :set, params: %{field: "invite_email"}} />
          <input type="number" min="1" max="90" placeholder="days" value={@invite_days}
            data-cy="adm-billing-invite-days" $change={action: :set, params: %{field: "invite_days"}} />
          <button type="submit" class="app-btn" disabled={@busy} data-cy="adm-billing-invite-mint">Mint invite</button>
        </form>
      </section>
    </AppShell>
    """
  end

  # ── actions ───────────────────────────────────────────────────

  def action(:set, params, c),
    do: put_state(c, String.to_existing_atom(params.field), params.event.value)

  def action(:cap_input, params, c) do
    caps =
      Enum.map(c.state.caps, fn cap ->
        if cap.plan == params.plan, do: Map.put(cap, :input, params.event.value), else: cap
      end)

    put_state(c, caps: caps)
  end

  def action(:set_cap, params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:set_cap,
        plan: params.plan,
        cap: input_for(c.state.caps, params.plan)
      )

  def action(:set_quota, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:set_quota, email: c.state.quota_email, quota: c.state.quota_value)

  def action(:select_sub, params, c) do
    row = Enum.find(c.state.subs, &(&1.email == params.email))

    put_state(c,
      selected_email: params.email,
      plan_input: (row && row.plan) || "",
      extra_users_input: (row && Integer.to_string(row.extra_users)) || "0",
      extra_gb_input: (row && Integer.to_string(row.extra_gb)) || "0",
      trial_days_input: "",
      error: nil,
      flash: nil
    )
  end

  def action(:set_plan, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:set_plan, email: c.state.selected_email, plan: c.state.plan_input)

  def action(:set_extras, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:set_extras,
        email: c.state.selected_email,
        extra_users: c.state.extra_users_input,
        extra_gb: c.state.extra_gb_input
      )

  def action(:extend_trial, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:extend_trial, email: c.state.selected_email, days: c.state.trial_days_input)

  def action(:toggle_comp, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:toggle_comp, email: c.state.selected_email)

  def action(:mint_invite, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:mint_invite, email: c.state.invite_email, days: c.state.invite_days)

  def action(:caps_refreshed, params, c),
    do: put_state(c, busy: false, caps: params.caps, flash: params.flash)

  def action(:subs_refreshed, params, c),
    do: put_state(c, busy: false, subs: params.subs, flash: params.flash)

  def action(:invite_minted, params, c),
    do: put_state(c, busy: false, invite_token: params.token, invite_link: params.link)

  def action(:failed, params, c), do: put_state(c, busy: false, error: params.error)

  # ── commands (re-authorized server-side) ──────────────────────

  def command(:set_cap, params, server) do
    with {:ok, _admin} <- admin(server),
         {:ok, cap} <- int(to_string(params.cap)),
         {:ok, _row} <- SignupCaps.set_cap(to_string(params.plan), cap) do
      put_action(server, :caps_refreshed,
        caps: serialize_caps(),
        flash: "Cap saved for #{params.plan}."
      )
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can change caps.")

      {:error, :unknown_plan} ->
        put_action(server, :failed, error: "Unknown plan.")

      _ ->
        put_action(server, :failed, error: "Cap must be a number from 0 up.")
    end
  end

  def command(:set_quota, params, server) do
    email = to_string(params.email || "") |> String.trim() |> String.downcase()
    quota = int(to_string(params.quota || ""))

    with {:ok, _admin} <- admin(server),
         {:ok, quota} <- quota,
         true <- Annotate.Waitlist.valid_email?(email) || {:error, :invalid_email},
         {:ok, _user} <- Annotate.Billing.set_invite_quota_by_email(email, quota) do
      put_action(server, :caps_refreshed,
        caps: serialize_caps(),
        flash: "Quota set: #{email} → #{quota}."
      )
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can set quotas.")

      {:error, :invalid_email} ->
        put_action(server, :failed, error: "That email address doesn't look valid.")

      {:error, :not_found} ->
        put_action(server, :failed, error: "No annotate user with that email.")

      _ ->
        put_action(server, :failed, error: "Quota must be a number from 0 up.")
    end
  end

  def command(:set_plan, params, server) do
    plan = params.plan |> to_string() |> String.trim() |> String.downcase() |> blank_to_nil()

    with {:ok, _admin} <- admin(server),
         {:ok, _row} <- Annotate.Billing.admin_set_plan_by_email(params.email, plan) do
      refresh_subs(server, "Plan updated for #{params.email}.")
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can change plans.")

      {:error, :invalid_plan} ->
        put_action(server, :failed,
          error: "Unknown plan — use start, standard or team (empty = none)."
        )

      {:error, :not_found} ->
        put_action(server, :failed, error: "No annotate user with that email.")

      {:error, :no_subscription} ->
        put_action(server, :failed, error: "That user has no subscription row.")

      _ ->
        put_action(server, :failed, error: "Could not set the plan — try again.")
    end
  end

  def command(:set_extras, params, server) do
    with {:ok, _admin} <- admin(server),
         {:ok, users} <- int(to_string(params.extra_users || "")),
         {:ok, gb} <- int(to_string(params.extra_gb || "")),
         {:ok, _row} <- Annotate.Billing.admin_set_extras_by_email(params.email, users, gb) do
      refresh_subs(server, "Extras updated for #{params.email}.")
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can change extras.")

      {:error, :not_found} ->
        put_action(server, :failed, error: "No annotate user with that email.")

      {:error, :no_subscription} ->
        put_action(server, :failed, error: "That user has no subscription row.")

      _ ->
        put_action(server, :failed, error: "Extras must be numbers from 0 up.")
    end
  end

  def command(:extend_trial, params, server) do
    with {:ok, _admin} <- admin(server),
         {:ok, days} <- int(to_string(params.days || "")),
         true <- days >= 1 || {:error, :invalid_days},
         {:ok, _row} <- Annotate.Billing.admin_extend_trial_by_email(params.email, days) do
      refresh_subs(server, "Trial extended by #{days} days for #{params.email}.")
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can extend trials.")

      {:error, :not_found} ->
        put_action(server, :failed, error: "No annotate user with that email.")

      {:error, :no_subscription} ->
        put_action(server, :failed, error: "That user has no subscription row.")

      _ ->
        put_action(server, :failed, error: "Days must be a number from 1 up.")
    end
  end

  def command(:toggle_comp, params, server) do
    with {:ok, _admin} <- admin(server),
         {:ok, _row} <- Annotate.Billing.admin_toggle_comp_by_email(params.email) do
      refresh_subs(server, "Comp flag toggled for #{params.email}.")
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can toggle comp.")

      {:error, :not_found} ->
        put_action(server, :failed, error: "No annotate user with that email.")

      {:error, :no_subscription} ->
        put_action(server, :failed, error: "That user has no subscription row.")

      _ ->
        put_action(server, :failed, error: "Could not toggle comp — try again.")
    end
  end

  def command(:mint_invite, params, server) do
    email = to_string(params.email || "") |> String.trim() |> String.downcase()

    with {:ok, admin} <- admin(server),
         {:ok, days} <- int(to_string(params.days || "14")),
         true <- Annotate.Waitlist.valid_email?(email) || {:error, :invalid_email},
         {:ok, _invite, raw_token} <- Invites.create(admin, email: email, days: days) do
      put_action(server, :invite_minted, token: raw_token, link: Invites.link(raw_token))
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only platform admins can mint invites.")

      {:error, :invalid_email} ->
        put_action(server, :failed, error: "That email address doesn't look valid.")

      {:error, :invalid_days} ->
        put_action(server, :failed, error: "Days must be between 1 and 90.")

      _ ->
        put_action(server, :failed, error: "Could not mint the invite — try again.")
    end
  end

  # ── helpers ───────────────────────────────────────────────────

  defp admin(server) do
    case Auth.current_user(server) do
      %{id: id} when is_binary(id) ->
        case Annotate.Repo.get(Annotate.Schema.Users.User, id) do
          %{admin: true} = user -> {:ok, user}
          _ -> {:error, :forbidden}
        end

      _ ->
        {:error, :forbidden}
    end
  end

  defp refresh_subs(server, flash) do
    put_action(server, :subs_refreshed, subs: serialize_subs(), flash: flash)
  end

  defp serialize_subs do
    Enum.map(Annotate.Billing.admin_subscriptions(), fn %{subscription: s, email: email} ->
      %{
        email: email,
        plan: s.plan || "",
        status: s.status || "",
        trial_ends_at: date_display(s.trial_ends_at),
        current_period_end: date_display(s.current_period_end),
        extra_users: s.extra_users || 0,
        extra_gb: s.extra_gb || 0,
        comp: s.comp == true
      }
    end)
  end

  defp date_display(nil), do: "—"
  defp date_display(%{} = t), do: Calendar.strftime(t, "%b %-d, %Y")
  defp date_display(_), do: "—"

  defp serialize_caps do
    Enum.map(SignupCaps.list(), fn cap ->
      %{
        plan: cap.plan,
        cap: cap.cap,
        taken: cap.taken,
        full: cap.cap <= cap.taken and SignupCaps.full?(cap.plan),
        input: Integer.to_string(cap.cap)
      }
    end)
  end

  defp input_for(caps, plan) do
    case Enum.find(caps, &(&1.plan == plan)) do
      %{input: input} -> input
      _ -> ""
    end
  end

  defp int(v) do
    case Integer.parse(to_string(v)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, :invalid}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
