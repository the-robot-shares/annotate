defmodule StarterWeb.Hologram.Pages.OrgMembersPage do
  @moduledoc """
  Organization members — list, invite, change role, remove.
  Mirrors start-app `/app/[orgId]/members`.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias Starter.Authz.ScopedMemberships
  alias Starter.Hologram.Auth
  alias Starter.Organizations
  alias Starter.Schema.Users.User, as: UserSchema
  alias StarterWeb.Hologram.Components.AppShell
  alias StarterWeb.Hologram.Layouts.MainLayout
  alias StarterWeb.Hologram.Middleware.RequireAuth
  alias StarterWeb.Hologram.Pages.OrgDashboardPage

  import Ecto.Query

  @roles ~w(viewer editor admin owner)

  route "/app/:org_id/members"
  param :org_id, :string
  layout MainLayout, page_title: "Members"
  middleware RequireAuth

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    org = load_org(params.org_id)
    members = list_members(params.org_id)
    orgs = normalize_orgs(organizations || [])
    current_user_id = user && to_string(user.id)

    put_state(component,
      user: user,
      org: org,
      org_id: params.org_id,
      members: members,
      organizations: orgs,
      invite_email: "",
      invite_role: "viewer",
      flash: nil,
      error: nil,
      loading: false,
      current_user_id: current_user_id,
      can_manage: can_manage?(orgs, params.org_id)
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell
      user={@user}
      organizations={@organizations}
      org_id={@org_id}
      active="members"
      title="Members"
    >
      {%if @org}
        <p class="sg-page-intro">
          Members of <strong>{@org.name}</strong>
          (<Link to={OrgDashboardPage, org_id: @org_id}>back to dashboard</Link>).
        </p>
      {%else}
        <p class="sg-page-intro">Organization <code>{@org_id}</code>.</p>
      {/if}

      {%if @flash}
        <p class="app-flash" role="status">{@flash}</p>
      {/if}
      {%if @error}
        <p class="sg-error" role="alert">{@error}</p>
      {/if}

      {%if @can_manage}
        <section class="app-dash-panel" style="margin-bottom: var(--space-4)">
          <h2 class="app-dash-panel__title">Invite member</h2>
          <div class="app-dash-panel__body">
            <form class="sg-form" $submit.prevent_default={:invite}>
              <div class="sg-field">
                <label for="invite-email">Email</label>
                <input
                  id="invite-email"
                  type="email"
                  value={@invite_email}
                  required
                  placeholder="colleague@example.com"
                  $change={:set_invite_email}
                />
              </div>
              <div class="sg-field">
                <label for="invite-role">Role</label>
                <select id="invite-role" $change={:set_invite_role}>
                  <option value="viewer" selected={@invite_role == "viewer"}>viewer</option>
                  <option value="editor" selected={@invite_role == "editor"}>editor</option>
                  <option value="admin" selected={@invite_role == "admin"}>admin</option>
                  <option value="owner" selected={@invite_role == "owner"}>owner</option>
                </select>
              </div>
              <button type="submit" class="btn btn-black" disabled={@loading}>
                {%if @loading}Inviting...{%else}Add member{/if}
              </button>
            </form>
            <p class="app-muted" style="margin-top: var(--space-2)">
              The user must already have an account. Role names match PBAC groups.
            </p>
          </div>
        </section>
      {/if}

      {%if @members == []}
        <p class="app-muted">No members found (or listing is not available in this environment).</p>
      {%else}
        <table class="app-table">
          <thead>
            <tr>
              <th>Email / identity</th>
              <th>Role</th>
              {%if @can_manage}
                <th>Actions</th>
              {/if}
            </tr>
          </thead>
          <tbody>
            {%for member <- @members}
              <tr>
                <td>
                  {member.email}
                  {%if member.user_name != ""}
                    <span class="app-muted">({member.user_name})</span>
                  {/if}
                </td>
                <td>
                  {%if @can_manage && member.role != "owner"}
                    <select $change={:change_role, user_id: member.user_id}>
                      <option value="viewer" selected={member.role == "viewer"}>viewer</option>
                      <option value="editor" selected={member.role == "editor"}>editor</option>
                      <option value="admin" selected={member.role == "admin"}>admin</option>
                      <option value="owner" selected={member.role == "owner"}>owner</option>
                    </select>
                  {%else}
                    <span class="app-badge">{member.role}</span>
                  {/if}
                </td>
                {%if @can_manage}
                  <td>
                    {%if member.role != "owner" && member.user_id != @current_user_id}
                      <button
                        type="button"
                        class="btn btn-outline btn-sm"
                        $click={:remove, user_id: member.user_id}
                      >
                        Remove
                      </button>
                    {/if}
                  </td>
                {/if}
              </tr>
            {/for}
          </tbody>
        </table>
      {/if}
    </AppShell>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_invite_email, params, c), do: put_state(c, :invite_email, params.event.value)
  def action(:set_invite_role, params, c), do: put_state(c, :invite_role, params.event.value)

  def action(:invite, _params, component) do
    component
    |> put_state(loading: true, error: nil, flash: nil)
    |> put_command(:invite_member,
      org_id: component.state.org_id,
      email: component.state.invite_email,
      role: component.state.invite_role,
      inviter_id: component.state.user.id
    )
  end

  def action(:change_role, params, component) do
    component
    |> put_state(error: nil, flash: nil)
    |> put_command(:update_role,
      org_id: component.state.org_id,
      user_id: params.user_id,
      role: params.event.value
    )
  end

  def action(:remove, params, component) do
    component
    |> put_state(error: nil, flash: nil)
    |> put_command(:remove_member, org_id: component.state.org_id, user_id: params.user_id)
  end

  def action(:members_updated, params, component) do
    put_state(component,
      loading: false,
      members: params.members,
      flash: params.flash,
      error: nil,
      invite_email: if(params[:clear_invite], do: "", else: component.state.invite_email)
    )
  end

  def action(:members_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Request failed")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:invite_member, params, server) do
    role = normalize_role(params.role)

    case find_user_id_by_email(params.email) do
      nil ->
        put_action(server, :members_failed, error: "User not found — they must sign up first")

      uid ->
        case ScopedMemberships.add_member(
               "organization",
               params.org_id,
               uid,
               role,
               params.inviter_id
             ) do
          {:ok, _} ->
            put_action(server, :members_updated,
              members: list_members(params.org_id),
              flash: "Member added.",
              clear_invite: true
            )

          {:error, :already_member} ->
            put_action(server, :members_failed, error: "User is already a member")

          {:error, :invalid_role} ->
            put_action(server, :members_failed, error: "Invalid role")

          {:error, reason} ->
            put_action(server, :members_failed, error: to_string(reason))
        end
    end
  end

  def command(:update_role, params, server) do
    role = normalize_role(params.role)

    case ScopedMemberships.update_role("organization", params.org_id, params.user_id, role) do
      {:ok, _} ->
        put_action(server, :members_updated,
          members: list_members(params.org_id),
          flash: "Role updated."
        )

      {:error, :not_found} ->
        put_action(server, :members_failed, error: "Member not found")

      {:error, reason} ->
        put_action(server, :members_failed, error: to_string(reason))
    end
  end

  def command(:remove_member, params, server) do
    case ScopedMemberships.remove_member("organization", params.org_id, params.user_id) do
      {:ok, _} ->
        put_action(server, :members_updated,
          members: list_members(params.org_id),
          flash: "Member removed."
        )

      {:error, :not_found} ->
        put_action(server, :members_failed, error: "Member not found")

      {:error, :sole_owner} ->
        put_action(server, :members_failed, error: "Cannot remove the owner")

      {:error, reason} ->
        put_action(server, :members_failed, error: to_string(reason))
    end
  end

  defp load_org(id) do
    case Organizations.get_organization(id, Noizu.Context.system()) do
      {:ok, org} -> %{id: to_string(org.id), name: org.name, slug: org.slug}
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp list_members(org_id) do
    Organizations.list_members(org_id)
    |> Enum.map(fn m ->
      %{
        user_id: to_string(Map.get(m, :user_id) || Map.get(m, "user_id") || ""),
        email: Map.get(m, :email) || Map.get(m, "email") || "member",
        user_name: Map.get(m, :user_name) || Map.get(m, "user_name") || "",
        role: to_string(Map.get(m, :role) || Map.get(m, "role") || Map.get(m, :group_name) || "viewer")
      }
    end)
  rescue
    _ -> []
  end

  defp find_user_id_by_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    case Starter.Repo.one(from u in UserSchema, where: u.email == ^email, select: u.id) do
      nil -> nil
      id -> id
    end
  end

  defp find_user_id_by_email(_), do: nil

  defp normalize_role(role) when is_binary(role) do
    if role in @roles, do: role, else: "viewer"
  end

  defp normalize_role(_), do: "viewer"

  defp can_manage?(orgs, org_id) do
    role =
      Enum.find_value(orgs, fn o ->
        id = to_string(Map.get(o, :id) || Map.get(o, "id") || "")
        if id == to_string(org_id), do: Map.get(o, :role) || Map.get(o, "role")
      end)

    role in ["owner", "admin"]
  end

  defp normalize_orgs(list) when is_list(list) do
    Enum.map(list, fn
      %{id: id, name: name} = o ->
        %{
          id: to_string(id),
          name: name || "Organization",
          slug: Map.get(o, :slug),
          role: Map.get(o, :role)
        }

      %{"id" => id, "name" => name} = o ->
        %{
          id: to_string(id),
          name: name || "Organization",
          slug: Map.get(o, "slug"),
          role: Map.get(o, "role")
        }

      other when is_map(other) ->
        id = Map.get(other, :id) || Map.get(other, "id")
        name = Map.get(other, :name) || Map.get(other, "name") || "Organization"

        %{
          id: to_string(id),
          name: name,
          slug: Map.get(other, :slug) || Map.get(other, "slug"),
          role: Map.get(other, :role) || Map.get(other, "role")
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_orgs(_), do: []
end
