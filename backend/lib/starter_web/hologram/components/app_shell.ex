defmodule StarterWeb.Hologram.Components.AppShell do
  @moduledoc """
  Authenticated app chrome — sidebar + main region.

  Mirrors the style-guide `dashboard` shell layout (sidebar-left) without requiring
  `body[data-shell]` so it composes under the global Navbar.
  """
  use Hologram.Component

  alias Hologram.UI.Link
  alias StarterWeb.Hologram.Pages.AdminInvitesPage
  alias StarterWeb.Hologram.Pages.AdminOrgsPage
  alias StarterWeb.Hologram.Pages.AdminUsersPage
  alias StarterWeb.Hologram.Pages.AppHomePage
  alias StarterWeb.Hologram.Pages.OrgDashboardPage
  alias StarterWeb.Hologram.Pages.OrgMembersPage
  alias StarterWeb.Hologram.Pages.ProfilePage

  prop :user, :map, default: nil
  prop :organizations, :list, default: []
  prop :active, :string, default: "home"
  prop :org_id, :string, default: nil
  prop :title, :string, default: nil

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="app-shell">
      <aside class="app-shell__sidebar" aria-label="App navigation">
        <div class="app-shell__sidebar-head">
          <span class="app-shell__sidebar-label">Workspace</span>
          {%if @user}
            <span class="app-shell__sidebar-user">{@user.email}</span>
          {/if}
        </div>
        <nav class="app-shell__nav">
          <Link
            to={AppHomePage}
            class={nav_class(@active, "home")}
          >
            Dashboard
          </Link>
          <Link
            to={ProfilePage}
            class={nav_class(@active, "profile")}
          >
            Profile
          </Link>
          {%if @org_id}
            <div class="app-shell__nav-section">Workspace</div>
            <Link
              to={OrgDashboardPage, org_id: @org_id}
              class={nav_class(@active, "org")}
            >
              Overview
            </Link>
            <Link
              to={OrgMembersPage, org_id: @org_id}
              class={nav_class(@active, "members")}
            >
              Members
            </Link>
          {/if}
          {%if is_admin(@user)}
            <div class="app-shell__nav-section">Admin</div>
            <Link
              to={AdminUsersPage}
              class={nav_class(@active, "admin_users")}
            >
              Users
            </Link>
            <Link
              to={AdminOrgsPage}
              class={nav_class(@active, "admin_orgs")}
            >
              Organizations
            </Link>
            <Link
              to={AdminInvitesPage}
              class={nav_class(@active, "admin_invites")}
            >
              Invites
            </Link>
          {/if}
        </nav>
        {%if @organizations != []}
          <div class="app-shell__orgs">
            <div class="app-shell__nav-section">Organizations</div>
            {%for org <- @organizations}
              <Link
                to={OrgDashboardPage, org_id: org.id}
                class={org_nav_class(@org_id, org.id)}
              >
                {org.name}
              </Link>
            {/for}
          </div>
        {/if}
      </aside>
      <div class="app-shell__main">
        {%if @title}
          <header class="app-shell__header">
            <h1 class="sg-page-title">{@title}</h1>
          </header>
        {/if}
        <div class="app-shell__body">
          <slot />
        </div>
      </div>
    </div>
    """
  end

  # <REMOVED UUID HERE> nav_class :: auto-generated pointer for public function nav_class
  def nav_class(active, id) when active == id, do: "app-shell__link app-shell__link--active"
  def nav_class(_, _), do: "app-shell__link"

  # <REMOVED UUID HERE> org_nav_class :: auto-generated pointer for public function org_nav_class
  def org_nav_class(current, id) when current == id, do: "app-shell__link app-shell__link--active"
  def org_nav_class(_, _), do: "app-shell__link"

  # <REMOVED UUID HERE> is_admin :: auto-generated pointer for public function is_admin
  def is_admin(nil), do: false

  def is_admin(user) when is_map(user) do
    user[:is_admin] == true or user["is_admin"] == true or
      user[:admin] == true or user["admin"] == true
  end

  def is_admin(_), do: false
end
