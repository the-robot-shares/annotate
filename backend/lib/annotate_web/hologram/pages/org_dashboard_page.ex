defmodule AnnotateWeb.Hologram.Pages.OrgDashboardPage do
  @moduledoc """
  Organization dashboard (`/app/:org_id`) — primary workspace view after login.

  Shell: sidebar + KPIs + actions + member snapshot.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias Annotate.Hologram.Auth
  alias Annotate.Organizations
  alias AnnotateWeb.Hologram.Components.AppShell
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth
  alias AnnotateWeb.Hologram.Pages.AppHomePage
  alias AnnotateWeb.Hologram.Pages.OrgMembersPage
  alias AnnotateWeb.Hologram.Pages.ProfilePage

  route "/app/:org_id"
  param :org_id, :string
  layout MainLayout, page_title: "Dashboard"
  middleware RequireAuth

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    org = load_org(params.org_id)
    orgs = normalize_orgs(organizations || [])
    members = list_members(params.org_id)
    role = org_role(orgs, params.org_id)

    put_state(component,
      user: user,
      org: org,
      org_id: params.org_id,
      organizations: orgs,
      member_count: length(members),
      members_preview: Enum.take(members, 5),
      role: role || "member"
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell
      user={@user}
      organizations={@organizations}
      org_id={@org_id}
      active="org"
      title={org_title(@org)}
    >
      {%if @org}
        <div class="app-dash-welcome">
          <div>
            <p class="app-dash-welcome__kicker">Workspace</p>
            <h2 class="app-dash-welcome__name">{@org.name}</h2>
            <p class="app-muted">
              <code>{@org.slug}</code>
              · your role <span class="app-badge">{@role}</span>
            </p>
          </div>
          <div class="app-dash-welcome__actions">
            <Link to={AppHomePage} class="btn btn-outline btn-sm">All workspaces</Link>
            <Link to={OrgMembersPage, org_id: @org_id} class="btn btn-black btn-sm">Members</Link>
          </div>
        </div>

        <div class="app-kpi-row">
          <div class="app-kpi">
            <div class="app-kpi__value">{@member_count}</div>
            <div class="app-kpi__label">Members</div>
          </div>
          <div class="app-kpi">
            <div class="app-kpi__value">{@role}</div>
            <div class="app-kpi__label">Your role</div>
          </div>
          <div class="app-kpi">
            <div class="app-kpi__value">Live</div>
            <div class="app-kpi__label">Status</div>
          </div>
        </div>

        <div class="app-dash-grid">
          <section class="app-dash-panel">
            <h2 class="app-dash-panel__title">Quick actions</h2>
            <div class="app-dash-panel__body app-stack-gap">
              <Link to={OrgMembersPage, org_id: @org_id} class="btn btn-black btn-sm">Manage members</Link>
              <Link to={ProfilePage} class="btn btn-outline btn-sm">Account profile</Link>
              <p class="app-muted">
                Invite teammates from the members page. Membership is PBAC-scoped
                (owner / admin / editor / viewer).
              </p>
            </div>
          </section>

          <section class="app-dash-panel">
            <h2 class="app-dash-panel__title">Overview</h2>
            <div class="app-dash-panel__body">
              <div class="app-overview-cards">
                <div class="app-overview-card">
                  <div class="app-overview-card__title">Projects</div>
                  <p class="app-muted">Scaffold project lists and detail screens for this workspace.</p>
                </div>
                <div class="app-overview-card">
                  <div class="app-overview-card__title">Activity</div>
                  <p class="app-muted">Recent events, audits, and notifications appear here.</p>
                </div>
                <div class="app-overview-card">
                  <div class="app-overview-card__title">Settings</div>
                  <p class="app-muted">Workspace settings, billing, and integrations.</p>
                </div>
              </div>
            </div>
          </section>
        </div>

        <section class="app-dash-panel" style="margin-top: var(--space-3)">
          <h2 class="app-dash-panel__title">Members snapshot</h2>
          <div class="app-dash-panel__body">
            {%if @members_preview == []}
              <p class="app-muted">No members listed yet.</p>
            {%else}
              <table class="app-table">
                <thead>
                  <tr>
                    <th>Identity</th>
                    <th>Role</th>
                  </tr>
                </thead>
                <tbody>
                  {%for m <- @members_preview}
                    <tr>
                      <td>{m.email}</td>
                      <td><span class="app-badge">{m.role}</span></td>
                    </tr>
                  {/for}
                </tbody>
              </table>
              {%if @member_count > 5}
                <p style="margin-top: var(--space-2)">
                  <Link to={OrgMembersPage, org_id: @org_id} class="btn btn-outline btn-sm">
                    View all {@member_count} members
                  </Link>
                </p>
              {/if}
            {/if}
          </div>
        </section>
      {%else}
        <p class="sg-error" role="alert">Organization not found or you do not have access.</p>
        <p><Link to={AppHomePage} class="btn btn-outline btn-sm">Back to dashboard</Link></p>
      {/if}
    </AppShell>
    """
  end

  # <REMOVED UUID HERE> org_title :: auto-generated pointer for public function org_title
  def org_title(nil), do: "Workspace"
  def org_title(%{name: name}), do: name
  def org_title(%{"name" => name}), do: name
  def org_title(_), do: "Workspace"

  defp org_role(orgs, org_id) do
    case Enum.find(orgs, &(to_string(&1.id) == to_string(org_id))) do
      nil -> nil
      org -> org.role
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
    |> Enum.map(fn
      %{email: email, role: role} ->
        %{email: email || "—", role: role || "member"}

      %{"email" => email, "role" => role} ->
        %{email: email || "—", role: role || "member"}

      other when is_map(other) ->
        %{
          email: Map.get(other, :email) || Map.get(other, "email") || Map.get(other, :member_id) || "—",
          role: Map.get(other, :role) || Map.get(other, "role") || "member"
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
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
