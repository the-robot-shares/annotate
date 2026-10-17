defmodule AnnotateWeb.Hologram.Pages.DashboardInvitesPage do
  @moduledoc """
  `/dashboard/invites` — issue, list and revoke dashboard invites
  (`Annotate.Dashboard.Invites`). Staff only: platform admins or active
  verified @noizu.com users (`Annotate.Dashboard.Access.can_issue_invites?/1`),
  re-checked from the DB on render AND every command.

  The raw token / link exists only in the create command's reply (shown once
  in a modal, copied from the DOM); the list shows only the 8-char prefix.
  Waitlist sign-ups (landing form) can be invited in one click (email-bound).
  """

  use Hologram.Page

  alias Annotate.Dashboard.Access
  alias Annotate.Dashboard.Invites
  alias Annotate.Hologram.Auth
  alias Annotate.Hologram.DashboardAuth
  alias AnnotateWeb.Hologram.Components.DashboardShell
  alias AnnotateWeb.Hologram.Layouts.DashboardLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/dashboard/invites"
  layout DashboardLayout, page_title: "Invites — annotate dashboard"
  middleware RequireAuth

  def init(_params, component, server) do
    user = Auth.current_user(server)
    allowed = staff?(user)

    put_state(component,
      user: DashboardAuth.shell_user(user),
      allowed: allowed,
      invites: if(allowed, do: serialize(Invites.list()), else: []),
      waitlist: if(allowed, do: waitlist(), else: []),
      email: "",
      days: Integer.to_string(Invites.default_days()),
      max_uses: "1",
      link_modal: nil,
      error: nil,
      flash: nil,
      busy: false,
      remaining_display: if(allowed, do: remaining_display(user), else: nil)
    )
  end

  def template do
    ~HOLO"""
    <DashboardShell user={@user} sites={[]} title="Invites"
      subtitle="annotate is invite-only. Invite links are single-use by default and expire.">
      {%if !@allowed}
        <section class="dsh-panel" data-cy="dsh-invites-forbidden">
          <div class="dsh-panel__body"><p>Only annotate staff can issue invites.</p></div>
        </section>
      {%else}
        {%if @flash}<p class="dsh-flash" role="status">{@flash}</p>{/if}
        {%if @error}<p class="dsh-error" role="alert" data-cy="dsh-invite-error">{@error}</p>{/if}

        <section class="dsh-panel" data-cy="dsh-invite-form">
          <h2 class="dsh-panel__title">New invite</h2>
          <div class="dsh-panel__body">
            <form class="dsh-form" $submit.prevent_default={:create}>
              <div class="dsh-grid-2">
                <div class="dsh-field">
                  <label for="inv-email">Bind to email (optional)</label>
                  <input id="inv-email" type="email" value={@email} placeholder="person@example.com" $change={action: :set, params: %{field: "email"}} />
                  <p class="dsh-hint">If set, only a sign-in whose provider-verified email matches can use it.</p>
                </div>
                <div class="dsh-field">
                  <label for="inv-days">Expires in (days)</label>
                  <input id="inv-days" type="number" min="1" max="90" value={@days} $change={action: :set, params: %{field: "days"}} />
                </div>
                <div class="dsh-field">
                  <label for="inv-uses">Max uses</label>
                  <input id="inv-uses" type="number" min="1" max="100" value={@max_uses} $change={action: :set, params: %{field: "max_uses"}} />
                </div>
              </div>
              {%if @remaining_display}
                <p class="dsh-hint" data-cy="dsh-invite-quota">Invite quota: {@remaining_display}</p>
              {/if}
              <div class="dsh-actions">
                <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@busy} data-cy="dsh-invite-create">Create invite link</button>
              </div>
            </form>
          </div>
        </section>

        <section class="dsh-panel" data-cy="dsh-invite-list">
          <h2 class="dsh-panel__title">Invites ({length(@invites)})</h2>
          <div class="dsh-panel__body">
            <table class="dsh-table">
              <thead><tr><th>Invite</th><th>Email</th><th>Uses</th><th>Expires</th><th>State</th><th></th></tr></thead>
              <tbody>
                {%for i <- @invites}
                  <tr data-cy="dsh-invite-row">
                    <td><code>{i.prefix}…</code></td>
                    <td>{i.email}</td>
                    <td>{i.uses}/{i.max_uses}</td>
                    <td>{i.expires}</td>
                    <td><span class="dsh-chip">{i.state}</span></td>
                    <td>
                      {%if i.state == "active"}
                        <button type="button" class="dsh-btn dsh-btn--danger dsh-btn--sm" $click={action: :revoke, params: %{id: i.id}} data-cy="dsh-invite-revoke">Revoke</button>
                      {/if}
                    </td>
                  </tr>
                {/for}
              </tbody>
            </table>
          </div>
        </section>

        {%if @waitlist != []}
          <section class="dsh-panel" data-cy="dsh-waitlist">
            <h2 class="dsh-panel__title">Waitlist</h2>
            <div class="dsh-panel__body">
              <table class="dsh-table">
                <thead><tr><th>Email</th><th>Interests</th><th></th></tr></thead>
                <tbody>
                  {%for w <- @waitlist}
                    <tr>
                      <td>{w.email}</td>
                      <td>{w.interests}</td>
                      <td><button type="button" class="dsh-btn dsh-btn--sm" $click={action: :invite_waitlist, params: %{email: w.email}} data-cy="dsh-waitlist-invite">Invite</button></td>
                    </tr>
                  {/for}
                </tbody>
              </table>
            </div>
          </section>
        {/if}

        {%if @link_modal}
          <div class="dsh-modal-overlay" role="dialog" aria-modal="true" aria-labelledby="dsh-link-title" data-cy="dsh-invite-modal">
            <div class="dsh-modal">
              <h2 class="dsh-modal__title" id="dsh-link-title">Invite link</h2>
              <p class="dsh-modal__warn">Shown once. Only a hash is stored; if you lose it, revoke and create a new one.</p>
              <code class="dsh-modal__key" id="dsh-invite-link">{@link_modal}</code>
              <div class="dsh-modal__actions">
                <button type="button" class="dsh-btn dsh-btn--ghost" $click={:copy}>Copy</button>
                <button type="button" class="dsh-btn dsh-btn--primary" $click={:close_modal}>Done</button>
              </div>
            </div>
          </div>
        {/if}
      {/if}
    </DashboardShell>
    """
  end

  # ── actions ───────────────────────────────────────────────────

  def action(:set, params, c),
    do: put_state(c, String.to_existing_atom(params.field), params.event.value)

  def action(:create, _params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:create,
        email: c.state.email,
        days: c.state.days,
        max_uses: c.state.max_uses
      )

  def action(:invite_waitlist, params, c),
    do:
      c
      |> put_state(busy: true, error: nil, flash: nil)
      |> put_command(:create,
        email: params.email,
        days: Integer.to_string(Invites.default_days()),
        max_uses: "1"
      )

  def action(:revoke, params, c), do: put_command(c, :revoke, id: params.id)

  def action(:copy, _params, c) do
    Hologram.JS.exec(
      "var e=document.getElementById('dsh-invite-link');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    put_state(c, flash: "Link copied.")
  end

  def action(:close_modal, _params, c), do: put_state(c, link_modal: nil)

  def action(:created, params, c),
    do:
      put_state(c,
        busy: false,
        invites: params.invites,
        remaining_display: params.remaining,
        link_modal: params.link,
        email: "",
        flash: nil
      )

  def action(:revoked, params, c),
    do:
      put_state(
        c,
        invites: params.invites,
        remaining_display: params.remaining,
        flash: "Invite revoked."
      )

  def action(:failed, params, c), do: put_state(c, busy: false, error: params.error)

  # ── commands (re-authorized every call) ──────────────────────

  def command(:create, params, server) do
    with {:ok, user} <- staff(server),
         {:ok, days} <- int(params.days),
         {:ok, max_uses} <- int(params.max_uses),
         {:ok, _invite, raw} <-
           Invites.create(user, email: to_string(params.email), days: days, max_uses: max_uses) do
      put_action(server, :created,
        invites: serialize(Invites.list()),
        remaining: remaining_display(user),
        link: Invites.link(raw)
      )
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only annotate staff can issue invites.")

      {:error, :no_quota} ->
        put_action(server, :failed,
          error: "You're out of invite quota — ask a platform admin for more."
        )

      {:error, :invalid_email} ->
        put_action(server, :failed, error: "That email address doesn't look valid.")

      {:error, _} ->
        put_action(server, :failed, error: "Check the values: 1–90 days, 1–100 uses.")
    end
  end

  def command(:revoke, params, server) do
    with {:ok, user} <- staff(server),
         :ok <- Invites.revoke(to_string(params.id)) do
      put_action(server, :revoked,
        invites: serialize(Invites.list()),
        remaining: remaining_display(user)
      )
    else
      {:error, :forbidden} ->
        put_action(server, :failed, error: "Only annotate staff can revoke invites.")

      _ ->
        put_action(server, :failed, error: "Could not revoke that invite.")
    end
  end

  # ── helpers ───────────────────────────────────────────────────

  defp staff(server) do
    user = Auth.current_user(server)
    if staff?(user), do: {:ok, user}, else: {:error, :forbidden}
  end

  defp staff?(%{id: id}),
    do: Access.can_issue_invites?(Annotate.Repo.get(Annotate.Schema.Users.User, id))

  defp staff?(_), do: false

  # nil issuer / admin = unlimited -> nil (the template hides the line).
  defp remaining_display(user) do
    case Invites.remaining_quota(user) do
      nil -> nil
      0 -> "0 left - ask a platform admin for more"
      1 -> "1 left"
      n -> Integer.to_string(n) <> " left"
    end
  end

  defp int(v) do
    case Integer.parse(to_string(v)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid}
    end
  end

  defp serialize(invites) do
    Enum.map(invites, fn i ->
      %{
        id: i.id,
        prefix: i.prefix,
        email: i.email || "—",
        uses: i.uses,
        max_uses: i.max_uses || "∞",
        expires: if(i.expires_at, do: Calendar.strftime(i.expires_at, "%Y-%m-%d"), else: "never"),
        state: i.state
      }
    end)
  end

  defp waitlist do
    import Ecto.Query

    from(w in Annotate.Schema.Annotate.WaitlistSignup,
      group_by: w.email,
      order_by: [desc: max(w.created_at)],
      limit: 50,
      select: {w.email, fragment("string_agg(?, ', ')", w.interest)}
    )
    |> Annotate.Repo.all()
    |> Enum.map(fn {email, interests} -> %{email: email, interests: interests} end)
  rescue
    _ -> []
  end
end
