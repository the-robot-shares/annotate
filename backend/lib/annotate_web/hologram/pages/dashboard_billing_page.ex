defmodule AnnotateWeb.Hologram.Pages.DashboardBillingPage do
  @moduledoc """
  `/dashboard/billing` — the signed-in user's subscription: plan + trial
  countdown, usage meters (apps / users / storage), upgrade Checkout,
  Stripe Customer Portal, Team add-on quantities, agent add-on waitlist.

  Stripe-backed state lives in `Annotate.Billing`. When Stripe is not
  configured (`ANNOTATE_STRIPE_SECRET_KEY` absent) the page shows the trial
  as-is and states that billing is not enabled — nothing is locked (the
  2026-10-17 fail-soft decision). Every template value is a precomputed
  plain string (serialized server-side in init/commands) — no domain module
  calls from client-executed template/action code.
  """

  use Hologram.Page

  alias Annotate.Billing
  alias Annotate.Billing.Plans
  alias Annotate.Billing.SignupCaps
  alias Annotate.Billing.Subscriptions
  alias Annotate.Hologram.Auth
  alias Annotate.Hologram.DashboardAuth
  alias AnnotateWeb.Hologram.Components.DashboardShell
  alias AnnotateWeb.Hologram.Layouts.DashboardLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/dashboard/billing"
  layout DashboardLayout, page_title: "Billing — annotate dashboard"
  middleware RequireAuth

  def init(_params, component, server) do
    user = Auth.current_user(server)

    # A plan picked on the landing/pricing page rides through sign-in as
    # ?return_to=/dashboard/billing%3Fplan%3D<key> — highlight it here.
    selected = selected_plan(server)

    put_state(component, snapshot(user, selected) |> Map.merge(base_ui(selected)))
  end

  def template do
    ~HOLO"""
    <DashboardShell user={@user} sites={[]} title="Billing"
      subtitle="Plans, usage and payments for your annotate account.">
      {%if @flash}<p class="dsh-flash" role="status" data-cy="dsh-billing-flash">{@flash}</p>{/if}
      {%if @error}<p class="dsh-error" role="alert" data-cy="dsh-billing-error">{@error}</p>{/if}

      {%if !@billing.stripe_configured}
        <section class="dsh-panel" data-cy="dsh-billing-not-configured">
          <div class="dsh-panel__body">
            <p><strong>Billing is not enabled yet.</strong> Your 14-day trial
            countdown below is informational only — nothing is locked while
            payments are being set up.</p>
          </div>
        </section>
      {/if}

      {%if @billing.comp}
        <section class="dsh-panel" data-cy="dsh-billing-comp">
          <div class="dsh-panel__body">
            <p><strong>Comp account.</strong> Every feature is unlocked — no
            subscription needed.</p>
          </div>
        </section>
      {/if}

      <section class="dsh-panel" data-cy="dsh-billing-status">
        <h2 class="dsh-panel__title">Your plan</h2>
        <div class="dsh-panel__body">
          {%if @billing.locked}
            {%if @billing.trial_at_capacity}
              <p class="dsh-error" role="alert" data-cy="dsh-billing-locked">
                {@billing.capacity_message} Your sites are read-only —
                visitors still see every comment. Pick a plan below to
                restore commenting.
              </p>
            {%else}
              <p class="dsh-error" role="alert" data-cy="dsh-billing-locked">
                Your trial has ended and no subscription is active. Your sites
                are read-only — visitors still see every comment. Pick a plan
                below to restore commenting.
              </p>
            {/if}
          {/if}
          <p>
            {%if @billing.comp}
              Plan: comp (unlimited)
            {%else}
              Plan: {@billing.plan_display}
            {/if}
            · Status: <span class="dsh-chip">{@billing.status_display}</span>
            {%if @billing.trial_display}
              · {@billing.trial_display}
            {/if}
            {%if @billing.renews_display}
              · {@billing.renews_display}
            {/if}
          </p>
        </div>
      </section>

      <section class="dsh-panel" data-cy="dsh-billing-usage">
        <h2 class="dsh-panel__title">Usage</h2>
        <div class="dsh-panel__body">
          <table class="dsh-table">
            <thead><tr><th>Meter</th><th>Used</th><th>Plan limit</th></tr></thead>
            <tbody>
              <tr data-cy="dsh-billing-usage-apps"><td>Sites</td><td>{@usage.apps_used}</td><td>{@limits.apps_display}</td></tr>
              <tr data-cy="dsh-billing-usage-users"><td>Users</td><td>{@usage.users_used}</td><td>{@limits.users_display}</td></tr>
              <tr data-cy="dsh-billing-usage-storage"><td>Storage</td><td>{@usage.storage_display}</td><td>{@limits.storage_display}</td></tr>
            </tbody>
          </table>
          <p class="dsh-hint">Comments are unlimited on every plan.</p>
        </div>
      </section>

      {%if @billing.plan == "team" && @billing.stripe_active}
        <section class="dsh-panel" data-cy="dsh-billing-extras">
          <h2 class="dsh-panel__title">Add-on capacity</h2>
          <div class="dsh-panel__body">
            <p>Extra users (+$0.99/user/mo) and storage (+$0.99/GB/mo) ride
            your Team subscription as quantities. Changes apply on the next
            invoice.</p>
            <div class="dsh-actions">
              <button type="button" class="dsh-btn dsh-btn--sm" disabled={@busy}
                $click={action: :extras, params: %{kind: "users", delta: 1}} data-cy="dsh-extras-users-add">+1 extra user</button>
              {%if @billing.can_remove_users}
                <button type="button" class="dsh-btn dsh-btn--sm dsh-btn--ghost" disabled={@busy}
                  $click={action: :extras, params: %{kind: "users", delta: -1}} data-cy="dsh-extras-users-remove">−1</button>
              {/if}
              <span>current: {@billing.extra_users}</span>
            </div>
            <div class="dsh-actions">
              <button type="button" class="dsh-btn dsh-btn--sm" disabled={@busy}
                $click={action: :extras, params: %{kind: "gb", delta: 1}} data-cy="dsh-extras-gb-add">+1 extra GB</button>
              {%if @billing.can_remove_gb}
                <button type="button" class="dsh-btn dsh-btn--sm dsh-btn--ghost" disabled={@busy}
                  $click={action: :extras, params: %{kind: "gb", delta: -1}} data-cy="dsh-extras-gb-remove">−1</button>
              {/if}
              <span>current: {@billing.extra_gb}</span>
            </div>
          </div>
        </section>
      {/if}

      {%if @billing.stripe_configured}
        <section class="dsh-panel" data-cy="dsh-billing-plans">
          <h2 class="dsh-panel__title">Plans</h2>
          <div class="dsh-panel__body">
            <table class="dsh-table">
              <thead><tr><th>Plan</th><th>Price</th><th>Sites</th><th>Users</th><th>Storage</th><th></th></tr></thead>
              <tbody>
                {%for p <- @plans}
                  <tr data-cy="dsh-billing-plan-row">
                    <td><strong>{p.name}</strong>
                      {%if p.selected}<span class="dsh-chip" data-cy="dsh-plan-picked">your pick</span>{/if}
                    </td>
                    <td>{p.price}</td>
                    <td>{p.apps}</td>
                    <td>{p.users}</td>
                    <td>{p.storage}</td>
                    <td>
                      {%if p.current}
                        <span class="dsh-chip">current</span>
                      {%else}
                        {%if p.full}
                          <button type="button" class="dsh-btn dsh-btn--sm dsh-btn--ghost" disabled={@busy}
                            $click={action: :waitlist_form, params: %{plan: p.key}} data-cy="dsh-plan-waitlist">
                            Full — join waitlist ({p.taken}/{p.cap})
                          </button>
                        {%else}
                          <button type="button" class="dsh-btn dsh-btn--sm dsh-btn--primary" disabled={@busy}
                            $click={action: :checkout, params: %{plan: p.key}} data-cy="dsh-plan-checkout">
                            {p.cta}
                          </button>
                        {/if}
                      {/if}
                    </td>
                  </tr>
                {/for}
              </tbody>
            </table>

            {%if @waitlist_plan}
              <div class="dsh-panel__body" data-cy="dsh-billing-plan-waitlist">
                <p><strong>{@waitlist_plan} is at capacity.</strong> Leave your
                email and we'll invite you as soon as a spot opens.</p>
                <form class="dsh-form" $submit.prevent_default={:join_waitlist}>
                  <div class="dsh-field">
                    <label for="wl-email">Email</label>
                    <input id="wl-email" type="email" value={@waitlist_email}
                      $change={action: :set, params: %{field: "waitlist_email"}} />
                  </div>
                  <div class="dsh-actions">
                    <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@busy} data-cy="dsh-waitlist-join">Join waitlist</button>
                    <button type="button" class="dsh-btn dsh-btn--ghost" $click={:waitlist_cancel}>Cancel</button>
                  </div>
                </form>
              </div>
            {/if}
          </div>
        </section>

        <section class="dsh-panel" data-cy="dsh-billing-agent">
          <h2 class="dsh-panel__title">Agent add-on — coming soon</h2>
          <div class="dsh-panel__body">
            <p>An AI agent that triages your comment inbox for
            <strong>$4.95/mo</strong>. Not purchasable yet — join the waitlist
            and we'll email you when it ships.</p>
            {%if @agent_joined}
              <p class="dsh-flash" role="status" data-cy="dsh-agent-waitlisted">You're on the agent add-on waitlist.</p>
            {%else}
              <form class="dsh-form" $submit.prevent_default={:join_agent_waitlist}>
                <div class="dsh-actions">
                  <button type="submit" class="dsh-btn dsh-btn--sm" disabled={@busy} data-cy="dsh-agent-waitlist-join">Join agent waitlist</button>
                </div>
              </form>
            {/if}
          </div>
        </section>

        {%if @billing.stripe_active}
          <section class="dsh-panel">
            <div class="dsh-panel__body">
              <button type="button" class="dsh-btn" disabled={@busy}
                $click={:portal} data-cy="dsh-billing-portal">
                Manage billing (invoices, payment method)
              </button>
            </div>
          </section>
        {/if}
      {/if}
    </DashboardShell>
    """
  end

  # ── actions (client-side: pure state + commands only) ─────────

  def action(:set, params, c),
    do: put_state(c, String.to_existing_atom(params.field), params.event.value)

  def action(:checkout, params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil, waitlist_plan: nil)
      |> put_command(:checkout, plan: params.plan)

  def action(:portal, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil)
      |> put_command(:portal)

  def action(:extras, params, c),
    do: put_command(c, :extras, kind: params.kind, delta: params.delta)

  def action(:waitlist_form, params, c),
    do: put_state(c, waitlist_plan: params.plan, error: nil)

  def action(:waitlist_cancel, _params, c), do: put_state(c, waitlist_plan: nil)

  def action(:join_waitlist, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil)
      |> put_command(:join_waitlist, plan: c.state.waitlist_plan, email: c.state.waitlist_email)

  def action(:join_agent_waitlist, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil)
      |> put_command(:join_waitlist, plan: "agent_addon", email: c.state.user.email)

  # Checkout/Portal hand off to Stripe's hosted pages in the same tab.
  def action(:redirected, params, _c),
    do: Hologram.JS.exec("window.location.href = " <> js_string(params.url) <> ";")

  def action(:refreshed, params, c),
    do:
      put_state(c,
        busy: false,
        billing: params.billing,
        plans: params.plans,
        flash: params.flash || nil
      )

  def action(:waitlisted, params, c),
    do:
      put_state(c,
        busy: false,
        waitlist_plan: nil,
        waitlist_email: "",
        agent_joined: params.agent_joined,
        flash: params.flash
      )

  def action(:failed, params, c), do: put_state(c, busy: false, error: params.error)

  # ── commands (server-side) ────────────────────────────────────

  def command(:checkout, params, server) do
    user = Auth.current_user(server)

    case user && Subscriptions.start_checkout(user, to_string(params.plan)) do
      {:ok, url} ->
        put_action(server, :redirected, url: url)

      # Purchases are blocked at capacity (intake control, 2026-10-18):
      # a full plan refuses checkout; a 0-cap plan is switched off entirely.
      {:error, :plan_full} ->
        put_action(server, :failed, error: Plans.purchases_unavailable_message())

      {:error, :plan_unavailable} ->
        put_action(server, :failed, error: Plans.unavailable_message())

      {:error, :not_purchasable} ->
        put_action(server, :failed, error: "That plan isn't open for signups yet.")

      {:error, :stripe_disabled} ->
        put_action(server, :failed, error: "Billing is not configured yet — check back soon.")

      {:error, :unauthenticated} ->
        put_action(server, :failed, error: "Please sign in again.")

      _ ->
        put_action(server, :failed, error: "Could not start checkout — try again.")
    end
  end

  def command(:portal, _params, server) do
    user = Auth.current_user(server)

    case user && Subscriptions.start_portal(user) do
      {:ok, url} ->
        put_action(server, :redirected, url: url)

      {:error, :no_customer} ->
        put_action(server, :failed, error: "No billing profile yet — upgrade to a plan first.")

      {:error, :stripe_disabled} ->
        put_action(server, :failed, error: "Billing is not configured yet.")

      _ ->
        put_action(server, :failed, error: "Could not open the billing portal — try again.")
    end
  end

  def command(:extras, params, server) do
    user = Auth.current_user(server)
    delta = int_or(params.delta, 0)

    cond do
      is_nil(user) ->
        put_action(server, :failed, error: "Please sign in again.")

      delta not in [-1, 1] ->
        put_action(server, :failed, error: "Invalid change.")

      true ->
        {:ok, row} = Subscriptions.ensure(user.id)

        users =
          max((row.extra_users || 0) + delta * if(params.kind == "users", do: 1, else: 0), 0)

        gb = max((row.extra_gb || 0) + delta * if(params.kind == "gb", do: 1, else: 0), 0)

        case Subscriptions.set_extras(user, users, gb) do
          :ok ->
            refresh(server, "Add-on updated — applies on the next invoice.")

          {:error, :not_team} ->
            put_action(server, :failed, error: "Add-ons need the Team plan.")

          {:error, :no_subscription} ->
            put_action(server, :failed, error: "No active subscription found.")

          {:error, :stripe_disabled} ->
            put_action(server, :failed, error: "Billing is not configured yet.")

          _ ->
            put_action(server, :failed, error: "Could not update add-ons — try again.")
        end
    end
  end

  def command(:join_waitlist, params, server) do
    user = Auth.current_user(server)
    plan = to_string(params.plan || "")
    email = to_string(params.email || "") |> String.trim()
    agent? = plan == "agent_addon"

    interest = if agent?, do: "agent-addon", else: "plan-" <> plan

    cond do
      is_nil(user) ->
        put_action(server, :failed, error: "Please sign in again.")

      not Annotate.Waitlist.valid_email?(email) ->
        put_action(server, :failed, error: "That email address doesn't look valid.")

      true ->
        case Annotate.Waitlist.signup(%{"email" => email, "interests" => [interest]}) do
          {:ok, _} ->
            put_action(server, :waitlisted,
              agent_joined: agent?,
              flash:
                if agent? do
                  nil
                else
                  "You're on the #{plan_label(plan)} waitlist — we'll email you when a spot opens."
                end
            )

          {:error, _} ->
            put_action(server, :failed, error: "Could not join the waitlist — try again.")
        end
    end
  end

  # ── serialization (server-side only) ──────────────────────────

  defp base_ui(selected_plan) do
    name =
      case selected_plan && Plans.get(selected_plan) do
        %{name: n} -> n
        _ -> selected_plan
      end

    %{
      error: nil,
      flash: if(selected_plan, do: "Finish picking the #{name} plan below.", else: nil),
      busy: false,
      waitlist_plan: nil,
      waitlist_email: "",
      agent_joined: false
    }
  end

  defp snapshot(user, selected_plan) do
    {:ok, row} = Billing.ensure_subscription(user.id)
    state = Billing.state(user.id)
    limits = Billing.limits(row)

    %{
      user: DashboardAuth.shell_user(user),
      billing: %{
        stripe_configured: state.stripe_configured,
        comp: state.comp,
        locked: state.locked,
        trial_at_capacity: trial_at_capacity?(state),
        capacity_message: SignupCaps.intake_capacity_message(),
        plan: state.plan || "trial",
        plan_display: plan_display(state),
        status_display: state.status || "trialing",
        stripe_active: stripe_active?(state),
        trial_display: trial_display(state),
        renews_display: renews_display(state),
        extra_users: state.extra_users || 0,
        extra_gb: state.extra_gb || 0,
        can_remove_users: (state.extra_users || 0) > 0,
        can_remove_gb: (state.extra_gb || 0) > 0
      },
      usage: %{
        apps_used: Integer.to_string(state.sites),
        users_used: Integer.to_string(state.users),
        storage_display: format_bytes(state.storage_bytes)
      },
      limits: %{
        apps_display: limit_display(limits.apps),
        users_display: limit_display(limits.users),
        storage_display: limit_bytes_display(limits.storage_bytes)
      },
      plans: serialize_plans(state.plan, selected_plan)
    }
  end

  defp selected_plan(server) do
    case server |> Map.get(:query, %{}) |> Map.get("plan") do
      key when is_binary(key) ->
        if key in Plans.purchasable(), do: key, else: nil

      _ ->
        nil
    end
  end

  defp refresh(server, flash) do
    user = Auth.current_user(server)

    case user do
      %{id: id} when is_binary(id) ->
        snap = snapshot(user, nil)

        put_action(server, :refreshed,
          billing: snap.billing,
          plans: snap.plans,
          flash: flash
        )

      _ ->
        put_action(server, :failed, error: "Please sign in again.")
    end
  end

  defp serialize_plans(current_plan, selected_plan) do
    Enum.map(Plans.purchasable(), fn key ->
      plan = Plans.get(key)
      status = SignupCaps.status(key)

      %{
        key: key,
        name: plan.name,
        price: format_cents(plan.price_cents) <> "/mo",
        apps: plan_display_value(plan.apps),
        users: Integer.to_string(plan.users),
        storage: format_bytes(plan.storage_bytes),
        current: current_plan == key,
        selected: selected_plan == key,
        cta: if(current_plan == key, do: "Renew / manage", else: "Choose " <> plan.name),
        full: status != nil and status.full,
        taken: (status && status.taken) || 0,
        cap: (status && status.cap) || 0
      }
    end)
  end

  defp plan_display(%{comp: true}), do: "comp (unlimited)"
  defp plan_display(%{plan: nil}), do: "Trial (no plan yet)"
  defp plan_display(%{plan: plan}), do: plan_label(plan)

  defp plan_label(plan) when is_binary(plan) do
    case Plans.get(plan) do
      %{name: name} -> name
      _ -> plan
    end
  end

  defp plan_label(_), do: "Trial (no plan yet)"

  defp stripe_active?(%{status: status, current_period_end: cpe}) do
    status in ["active", "trialing"] and
      case cpe do
        %DateTime{} -> DateTime.compare(cpe, DateTime.utc_now()) == :gt
        _ -> false
      end
  end

  defp trial_display(%{comp: true}), do: nil

  defp trial_display(%{status: "trialing", trial_days_left: days}) when is_integer(days) do
    cond do
      days <= 0 -> "Trial ended"
      days == 1 -> "1 day of trial left"
      true -> "#{days} days of trial left"
    end
  end

  defp trial_display(_), do: nil

  # Corrected model (2026-10-18): signups are never capacity-blocked — a full
  # trial intake means the account was minted with NO trial. `locked: true`
  # already excludes any active Stripe subscription, so a locked planless
  # account with the cap still full shows the capacity copy.
  defp trial_at_capacity?(%{locked: true, comp: false, plan: nil}),
    do: SignupCaps.full?(SignupCaps.trial_plan())

  defp trial_at_capacity?(_), do: false

  defp renews_display(%{status: "active", current_period_end: %DateTime{} = t}),
    do: "Renews " <> format_date(t)

  defp renews_display(%{status: "past_due"}),
    do: "Payment failed — update your card in the billing portal"

  defp renews_display(_), do: nil

  defp plan_display_value(:unlimited), do: "Unlimited"
  defp plan_display_value(v) when is_integer(v), do: Integer.to_string(v)
  defp plan_display_value(_), do: "—"

  defp limit_display(nil), do: "—"
  defp limit_display(:unlimited), do: "Unlimited"
  defp limit_display(v) when is_integer(v), do: Integer.to_string(v)

  defp limit_bytes_display(nil), do: "—"
  defp limit_bytes_display(v) when is_integer(v), do: format_bytes(v)

  defp format_bytes(b) when is_integer(b) and b >= 1_073_741_824,
    do: :erlang.float_to_binary(b / 1_073_741_824, decimals: 1) <> " GB"

  defp format_bytes(b) when is_integer(b) and b >= 1_048_576,
    do: :erlang.float_to_binary(b / 1_048_576, decimals: 1) <> " MB"

  defp format_bytes(b) when is_integer(b) and b >= 1024,
    do: Integer.to_string(div(b, 1024)) <> " KB"

  defp format_bytes(b) when is_integer(b), do: Integer.to_string(b) <> " B"
  defp format_bytes(_), do: "—"

  defp format_cents(c) when is_integer(c),
    do: "$" <> :erlang.float_to_binary(c / 100, decimals: 2)

  defp format_date(t), do: Calendar.strftime(t, "%b %-d, %Y")

  defp int_or(v, default) do
    case Integer.parse(to_string(v)) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp js_string(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"" <> escaped <> "\""
  end
end
