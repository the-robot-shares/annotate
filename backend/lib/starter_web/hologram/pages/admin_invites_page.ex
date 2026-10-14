defmodule StarterWeb.Hologram.Pages.AdminInvitesPage do
  @moduledoc """
  Admin invite management: mint tokens (raw value shown exactly once),
  inspect usage, revoke. The raw token never persists past the mint response.
  """
  use Hologram.Page

  alias Starter.Hologram.Auth
  alias Starter.Organizations
  alias StarterWeb.Hologram.Components.AppShell
  alias StarterWeb.Hologram.Layouts.MainLayout
  alias StarterWeb.Hologram.Middleware.RequireAdmin

  route "/app/admin/invites"
  layout MainLayout, page_title: "Admin · Invites"
  middleware RequireAdmin

  @roles Organizations.invite_roles()

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    organizations = normalize_orgs(organizations || [])
    org_id = first_org_id(organizations)

    invites = if org_id, do: Organizations.list_invites(org_id), else: []

    put_state(component,
      user: user,
      organizations: organizations,
      org_id: org_id || "",
      invites: serialize_invites(invites),
      roles: @roles,
      # create form
      email: "",
      role: "viewer",
      max_uses: "",
      expires_in_days: "14",
      # one-time mint result
      new_token: "",
      new_link: "",
      flash: nil,
      error: nil
    )
  end

  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="admin_invites" title="Admin · Invites">
      <p class="sg-page-intro">
        Invite tokens grant new members access. The raw token is shown once at
        mint; only a bcrypt hash is stored.
      </p>

      {%if @flash}
        <p class="app-flash" role="status">{@flash}</p>
      {/if}
      {%if @error}
        <p class="sg-error" role="alert">{@error}</p>
      {/if}

      {%if @new_token != ""}
        <div class="sg-auth__invite-note">
          <p><strong>Invite minted — copy it now, it will not be shown again.</strong></p>
          <p><code id="new-invite-token">{@new_token}</code></p>
          <p>Join link: <code>/join/{@new_token}</code></p>
        </div>
      {/if}

      <h2 class="app-dash-section-title">Mint an invite</h2>
      <form class="sg-form" $submit.prevent_default={:create_invite}>
        <div class="sg-field">
          <label for="inv-org">Organization</label>
          <select id="inv-org" $change={:set_org}>
            {%for org <- @organizations}
              <option value={org.id} selected={org.id == @org_id}>{org.name}</option>
            {/for}
          </select>
        </div>
        <div class="sg-field">
          <label for="inv-email">Restrict to email (optional)</label>
          <input id="inv-email" type="email" value={@email} $change={:set_email} />
        </div>
        <div class="sg-field">
          <label for="inv-role">Role</label>
          <select id="inv-role" $change={:set_role}>
            {%for role <- @roles}
              <option value={role} selected={role == @role}>{role}</option>
            {/for}
          </select>
        </div>
        <div class="sg-field">
          <label for="inv-max-uses">Max uses (blank = unlimited)</label>
          <input id="inv-max-uses" type="number" min="1" value={@max_uses} $change={:set_max_uses} />
        </div>
        <div class="sg-field">
          <label for="inv-ttl">Expires in (days)</label>
          <input id="inv-ttl" type="number" min="1" value={@expires_in_days} $change={:set_ttl} />
        </div>
        <button type="submit" class="btn btn-black">Mint invite</button>
      </form>

      <h2 class="app-dash-section-title" style="margin-top: var(--space-4)">Active history</h2>
      {%if @invites == []}
        <p class="app-muted">No invites yet for this organization.</p>
      {%else}
        <table class="app-table">
          <thead>
            <tr>
              <th>Prefix</th>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th>Uses</th>
              <th>Expires</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {%for invite <- @invites}
              <tr>
                <td><code>{invite.key_prefix}…</code></td>
                <td>{invite.email || "anyone"}</td>
                <td><span class="app-badge">{invite.role || "viewer"}</span></td>
                <td>{invite.status || "active"}</td>
                <td>{invite.uses}{%if invite.max_uses} / {invite.max_uses}{/if}</td>
                <td>{invite.expires_at}</td>
                <td>
                  {%if invite.revoked}
                    <span class="app-muted">revoked</span>
                  {%else}
                    <button
                      type="button"
                      class="btn btn-outline btn-sm"
                      $click={:revoke, invite_id: invite.id}
                    >
                      Revoke
                    </button>
                  {/if}
                </td>
              </tr>
            {/for}
          </tbody>
        </table>
      {/if}
    </AppShell>
    """
  end

  # -- actions ----------------------------------------------------------------

  def action(:set_org, params, component) do
    org_id = params.event.value

    component
    |> put_state(:org_id, org_id)
    |> put_command(:reload, org_id: org_id)
  end

  def action(:set_email, params, component), do: put_state(component, :email, params.event.value)
  def action(:set_role, params, component), do: put_state(component, :role, params.event.value)
  def action(:set_max_uses, params, component), do: put_state(component, :max_uses, params.event.value)
  def action(:set_ttl, params, component), do: put_state(component, :expires_in_days, params.event.value)

  def action(:create_invite, _params, component) do
    component
    |> put_state(flash: nil, error: nil, new_token: "", new_link: "")
    |> put_command(:mint,
      org_id: component.state.org_id,
      email: component.state.email,
      role: component.state.role,
      max_uses: component.state.max_uses,
      expires_in_days: component.state.expires_in_days,
      created_by: component.state.user.id
    )
  end

  def action(:invite_minted, params, component) do
    put_state(component,
      flash: "Invite minted.",
      new_token: params.token,
      new_link: "/join/" <> params.token,
      invites: params.invites
    )
  end

  def action(:mint_failed, params, component) do
    put_state(component, error: params.error || "Could not mint invite")
  end

  def action(:revoke, params, component) do
    component
    |> put_state(flash: nil, error: nil)
    |> put_command(:revoke_invite, org_id: component.state.org_id, invite_id: params.invite_id)
  end

  def action(:revoked, params, component) do
    put_state(component, flash: "Invite revoked.", invites: params.invites)
  end

  def action(:revoke_failed, params, component) do
    put_state(component, error: params.error || "Revoke failed")
  end

  def action(:reloaded, params, component) do
    put_state(component, invites: params.invites, error: nil)
  end

  # -- commands ---------------------------------------------------------------

  def command(:mint, params, server) do
    # Same gate as the REST controller: an invite can never carry `owner`.
    # (The changeset rejects it too — this gives the admin UI a clean error
    # instead of a changeset round-trip.)
    with {:ok, role} <- Organizations.validate_invite_role(params.role) do
      attrs = %{
        organization_id: params.org_id,
        created_by_user_id: params.created_by,
        email: optional(params.email),
        role: role,
        max_uses: parse_int(params.max_uses),
        expires_at: expiry(params.expires_in_days)
      }

      case Organizations.create_invite_token(attrs) do
        {:ok, _invite, raw_token} ->
          invites = serialize_invites(Organizations.list_invites(params.org_id))
          put_action(server, :invite_minted, token: raw_token, invites: invites)

        {:error, %Ecto.Changeset{} = changeset} ->
          put_action(server, :mint_failed, error: format_errors(changeset))

        {:error, reason} ->
          put_action(server, :mint_failed, error: to_string(reason))
      end
    else
      {:error, :invalid_role} ->
        put_action(server, :mint_failed,
          error: "Invalid role — must be one of " <> Enum.join(Organizations.invite_roles(), ", ")
        )
    end
  end

  def command(:revoke_invite, params, server) do
    case Organizations.revoke_invite(params.org_id, params.invite_id) do
      :ok ->
        invites = serialize_invites(Organizations.list_invites(params.org_id))
        put_action(server, :revoked, invites: invites)

      {:error, :not_found} ->
        put_action(server, :revoke_failed, error: "Invite not found")
    end
  end

  def command(:reload, params, server) do
    invites = serialize_invites(Organizations.list_invites(params.org_id))
    put_action(server, :reloaded, invites: invites)
  end

  # -- helpers ----------------------------------------------------------------

  defp serialize_invites(invites) do
    Enum.map(invites, fn invite ->
      %{
        id: invite.id,
        email: invite.email,
        role: invite.role,
        key_prefix: invite.key_prefix,
        status: invite.status,
        revoked: invite.revoked,
        uses: invite.uses,
        max_uses: invite.max_uses,
        expires_at: format_date(invite.expires_at)
      }
    end)
  end

  defp format_date(nil), do: "never"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_date(other) when is_binary(other), do: other

  defp normalize_orgs(orgs) do
    Enum.map(orgs, fn org ->
      %{id: org[:id] || org["id"], name: org[:name] || org["name"] || "Organization"}
    end)
  end

  defp first_org_id([]), do: nil
  defp first_org_id([org | _]), do: org.id

  defp optional(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional(_), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value) and value > 0, do: value
  defp parse_int(_), do: nil

  defp expiry(value), do: parse_int(value) |> expiry_from()

  defp expiry_from(nil),
    do: DateTime.utc_now() |> DateTime.add(14 * 86_400, :second)

  defp expiry_from(days),
    do: DateTime.utc_now() |> DateTime.add(days * 86_400, :second)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
