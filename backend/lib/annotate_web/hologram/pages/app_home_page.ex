defmodule AnnotateWeb.Hologram.Pages.AppHomePage do
  @moduledoc """
  Post-login dashboard (`/app`).

  Landing after auth (password / SSO / magic link). Shows account summary,
  workspaces, getting-started checklist, and optional create-workspace.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias Annotate.Hologram.Auth
  alias Annotate.Organizations
  alias AnnotateWeb.Hologram.Components.AppShell
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth
  alias AnnotateWeb.Hologram.Pages.OrgDashboardPage
  alias AnnotateWeb.Hologram.Pages.ProfilePage

  route "/app"
  layout MainLayout, page_title: "Dashboard"
  middleware RequireAuth

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    orgs = normalize_orgs(organizations || [])
    display = display_name(user)

    put_state(component,
      user: user,
      organizations: orgs,
      org_count: length(orgs),
      display_name: display,
      greeting: greeting_for(),
      flash: nil,
      error: nil,
      show_create: orgs == [],
      new_org_name: "",
      creating: false
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="home" title="Dashboard">
      <div class="app-dash-welcome">
        <div>
          <p class="app-dash-welcome__kicker">{@greeting}</p>
          <h2 class="app-dash-welcome__name">{@display_name}</h2>
          <p class="app-muted app-dash-welcome__email">{@user.email}</p>
        </div>
        <div class="app-dash-welcome__actions">
          <Link to={ProfilePage} class="btn btn-outline btn-sm">Profile</Link>
          {%if @org_count > 0}
            <button type="button" class="btn btn-black btn-sm" $click={:toggle_create}>
              {%if @show_create}Cancel{%else}New workspace{/if}
            </button>
          {/if}
        </div>
      </div>

      {%if @flash}
        <p class="app-flash" role="status">{@flash}</p>
      {/if}
      {%if @error}
        <p class="sg-error" role="alert">{@error}</p>
      {/if}

      <div class="app-kpi-row">
        <div class="app-kpi">
          <div class="app-kpi__value">{@org_count}</div>
          <div class="app-kpi__label">Workspaces</div>
        </div>
        <div class="app-kpi">
          <div class="app-kpi__value">{status_label(@user)}</div>
          <div class="app-kpi__label">Account</div>
        </div>
        <div class="app-kpi">
          <div class="app-kpi__value">{if @user.verified do "Verified" else "Unverified" end}</div>
          <div class="app-kpi__label">Email</div>
        </div>
        <div class="app-kpi">
          <div class="app-kpi__value">{if @user.is_admin do "Admin" else "Member" end}</div>
          <div class="app-kpi__label">Role</div>
        </div>
      </div>

      <div class="app-dash-grid app-dash-grid--home">
        <section class="app-dash-panel">
          <h2 class="app-dash-panel__title">Workspaces</h2>
          <div class="app-dash-panel__body">
            {%if @organizations == []}
              <p class="app-muted" style="margin-bottom: var(--space-3)">
                No workspaces yet. Create one to open an organization dashboard,
                invite members, and start building.
              </p>
            {%else}
              <div class="app-workspace-grid">
                {%for org <- @organizations}
                  <div class="app-workspace-card">
                    <div class="app-workspace-card__top">
                      <div class="app-workspace-card__name">{org.name}</div>
                      {%if org.role}
                        <span class="app-badge">{org.role}</span>
                      {/if}
                    </div>
                    <div class="app-workspace-card__slug"><code>{org.slug}</code></div>
                    <Link to={OrgDashboardPage, org_id: org.id} class="btn btn-black btn-sm">
                      Open dashboard
                    </Link>
                  </div>
                {/for}
              </div>
            {/if}

            {%if @show_create}
              <form class="app-create-org" $submit.prevent_default={:create_org}>
                <h3 class="app-create-org__title">Create workspace</h3>
                <div class="sg-field">
                  <label for="new-org-name">Name</label>
                  <input
                    id="new-org-name"
                    type="text"
                    value={@new_org_name}
                    placeholder="Acme Corp"
                    required
                    $change={:set_org_name}
                  />
                </div>
                <button type="submit" class="btn btn-black" disabled={if @creating do true end}>
                  {%if @creating}Creating…{%else}Create &amp; open{/if}
                </button>
              </form>
            {/if}
          </div>
        </section>

        <section class="app-dash-panel">
          <h2 class="app-dash-panel__title">Getting started</h2>
          <div class="app-dash-panel__body">
            <ol class="app-checklist">
              <li class="app-checklist__item app-checklist__item--done">
                <span class="app-checklist__mark">✓</span>
                <span>Signed in</span>
              </li>
              <li class={checklist_class(@user.verified)}>
                <span class="app-checklist__mark">{if @user.verified do "✓" else "○" end}</span>
                <span>Verify email</span>
              </li>
              <li class={checklist_class(not @user.requires_profile_completion)}>
                <span class="app-checklist__mark">{if @user.requires_profile_completion do "○" else "✓" end}</span>
                <span>
                  Complete profile
                  <Link to={ProfilePage} class="app-checklist__link">edit</Link>
                </span>
              </li>
              <li class={checklist_class(@org_count > 0)}>
                <span class="app-checklist__mark">{if @org_count > 0 do "✓" else "○" end}</span>
                <span>Create or join a workspace</span>
              </li>
              <li class="app-checklist__item">
                <span class="app-checklist__mark">○</span>
                <span>Invite teammates from a workspace dashboard</span>
              </li>
            </ol>

            <div class="app-dash-hint">
              <strong>Next</strong>
              <p class="app-muted">
                {%if @org_count == 0}
                  Create a workspace to open the organization dashboard.
                {%else}
                  Open a workspace dashboard to manage members and projects.
                {/if}
              </p>
            </div>
          </div>
        </section>
      </div>
    </AppShell>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_org_name, params, component) do
    put_state(component, new_org_name: params.event.value || "", error: nil)
  end

  def action(:toggle_create, _params, component) do
    put_state(component, show_create: !component.state.show_create, error: nil)
  end

  def action(:create_org, _params, component) do
    name = String.trim(component.state.new_org_name || "")

    if name == "" do
      put_state(component, error: "Enter a workspace name")
    else
      component
      |> put_state(creating: true, error: nil)
      |> put_command(:create_workspace, name: name)
    end
  end

  def action(:workspace_created, params, component) do
    org = params.org
    orgs = component.state.organizations ++ [org]

    component
    |> put_state(
      creating: false,
      organizations: orgs,
      org_count: length(orgs),
      show_create: false,
      new_org_name: "",
      flash: "Workspace “#{org.name}” created."
    )
    |> put_page(OrgDashboardPage, org_id: org.id)
  end

  def action(:create_failed, params, component) do
    put_state(component, creating: false, error: params.error || "Could not create workspace")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:create_workspace, params, server) do
    case Auth.current_user(server) do
      nil ->
        put_action(server, :create_failed, error: "Not signed in")

      user ->
        name = params.name
        slug = slugify(name)

        case Organizations.create_organization_with_owner(%{name: name, slug: slug}, user.id) do
          {:ok, org} ->
            put_action(server, :workspace_created,
              org: %{
                id: to_string(org.id),
                name: org.name,
                slug: org.slug,
                role: "owner"
              }
            )

          {:error, %Ecto.Changeset{} = cs} ->
            put_action(server, :create_failed, error: format_changeset(cs))

          {:error, reason} ->
            put_action(server, :create_failed, error: inspect(reason))
        end
    end
  end

  # <REMOVED UUID HERE> status_label :: auto-generated pointer for public function status_label
  def status_label(%{status: s}) when s in ["pending", :pending], do: "Pending"
  def status_label(%{status: s}) when s in ["waitlist", :waitlist], do: "Waitlist"
  def status_label(%{status: s}) when s in ["active", :active], do: "Active"
  def status_label(%{"status" => s}) when is_binary(s), do: String.capitalize(s)
  def status_label(_), do: "—"

  # <REMOVED UUID HERE> checklist_class :: auto-generated pointer for public function checklist_class
  def checklist_class(true), do: "app-checklist__item app-checklist__item--done"
  def checklist_class(_), do: "app-checklist__item"

  defp display_name(nil), do: "there"

  defp display_name(user) do
    name = user[:user_name] || user["user_name"] || user[:handle] || user["handle"]
    email = user[:email] || user["email"] || ""

    cond do
      is_binary(name) and name != "" -> name
      is_binary(email) and email != "" -> email |> String.split("@") |> hd()
      true -> "there"
    end
  end

  defp greeting_for do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good morning"
      hour < 18 -> "Good afternoon"
      true -> "Good evening"
    end
  end

  defp slugify(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    base = if base == "", do: "workspace", else: base
    "#{base}-#{System.unique_integer([:positive]) |> rem(100_000)}"
  end

  defp format_changeset(cs) do
    cs.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
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
