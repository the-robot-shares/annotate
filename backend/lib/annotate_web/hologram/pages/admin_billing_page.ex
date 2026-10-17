defmodule AnnotateWeb.Hologram.Pages.AdminBillingPage do
  @moduledoc """
  `/app/admin/billing` — platform admin: per-plan signup caps (raise/lower,
  sees claimed vs cap) and per-user invite quotas by email
  (`Annotate.Billing.SignupCaps` / `Annotate.Billing.set_invite_quota_by_email/2`).
  Re-authorized from the DB on every command.
  """

  use Hologram.Page

  alias Annotate.Billing.SignupCaps
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
          checkout start.
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

  def action(:caps_refreshed, params, c),
    do: put_state(c, busy: false, caps: params.caps, flash: params.flash)

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
end
