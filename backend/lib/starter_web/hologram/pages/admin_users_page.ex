defmodule StarterWeb.Hologram.Pages.AdminUsersPage do
  @moduledoc "Platform admin: list users and approve pending accounts."
  use Hologram.Page

  alias Starter.Hologram.Auth
  alias Starter.Schema.Users.User, as: UserSchema
  alias StarterWeb.Hologram.Components.AppShell
  alias StarterWeb.Hologram.Layouts.MainLayout
  alias StarterWeb.Hologram.Middleware.RequireAdmin

  import Ecto.Query

  route "/app/admin/users"
  layout MainLayout, page_title: "Admin · Users"
  middleware RequireAdmin

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    {users, total} = list_users(1)

    put_state(component,
      user: user,
      organizations: normalize_orgs(organizations || []),
      users: users,
      total: total,
      page: 1,
      can_prev: false,
      can_next: length(users) >= 50,
      flash: nil,
      error: nil
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="admin_users" title="Admin · Users">
      <p class="sg-page-intro">
        Platform users ({@total}).
        <a href="/app/admin/orgs">Organizations</a>
      </p>

      {%if @flash}
        <p class="app-flash" role="status">{@flash}</p>
      {/if}
      {%if @error}
        <p class="sg-error" role="alert">{@error}</p>
      {/if}

      {%if @users == []}
        <p class="app-muted">No users found.</p>
      {%else}
        <table class="app-table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Username</th>
              <th>Status</th>
              <th>Verified</th>
              <th>Admin</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {%for u <- @users}
              <tr>
                <td>{u.email}</td>
                <td>{u.user_name}</td>
                <td><span class="app-badge">{u.status}</span></td>
                <td>{if u.verified do "Yes" else "No" end}</td>
                <td>{if u.admin do "Yes" else "No" end}</td>
                <td>
                  {%if u.status == "pending"}
                    <button
                      type="button"
                      class="btn btn-outline btn-sm"
                      $click={:approve, user_id: u.id}
                    >
                      Approve
                    </button>
                  {/if}
                </td>
              </tr>
            {/for}
          </tbody>
        </table>
      {/if}

      <div class="app-kpi-row" style="margin-top: var(--space-3)">
        <button type="button" class="btn btn-outline btn-sm" disabled={if @can_prev do false else true end} $click={:prev_page}>
          Prev
        </button>
        <span class="app-muted">Page {@page}</span>
        <button type="button" class="btn btn-outline btn-sm" disabled={if @can_next do false else true end} $click={:next_page}>
          Next
        </button>
      </div>
    </AppShell>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:prev_page, _params, component) do
    page = max(component.state.page - 1, 1)
    load_page(component, page)
  end

  def action(:next_page, _params, component) do
    load_page(component, component.state.page + 1)
  end

  def action(:approve, params, component) do
    component
    |> put_state(flash: nil, error: nil)
    |> put_command(:approve_user, user_id: params.user_id, admin_id: component.state.user.id)
  end

  def action(:approved, params, component) do
    users =
      Enum.map(component.state.users, fn u ->
        if u.id == params.user.id, do: params.user, else: u
      end)

    put_state(component, users: users, flash: "User approved.")
  end

  def action(:approve_failed, params, component) do
    put_state(component, error: params.error || "Approve failed")
  end

  def action(:page_loaded, params, component) do
    put_state(component,
      users: params.users,
      total: params.total,
      page: params.page,
      can_prev: params.page > 1,
      can_next: length(params.users) >= 50,
      flash: nil,
      error: nil
    )
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:approve_user, params, server) do
    case Starter.Repo.get(UserSchema, params.user_id) do
      nil ->
        put_action(server, :approve_failed, error: "User not found")

      user ->
        attrs = %{
          status: :active,
          approved_at: DateTime.utc_now(),
          approved_by_user_id: params.admin_id
        }

        case user |> UserSchema.changeset(attrs) |> Starter.Repo.update() do
          {:ok, updated} ->
            put_action(server, :approved, user: serialize(updated))

          {:error, changeset} ->
            put_action(server, :approve_failed, error: inspect(changeset.errors))
        end
    end
  end

  def command(:load_users, params, server) do
    {users, total} = list_users(params.page)
    put_action(server, :page_loaded, users: users, total: total, page: params.page)
  end

  defp load_page(component, page) do
    component
    |> put_state(page: page)
    |> put_command(:load_users, page: page)
  end

  defp list_users(page) do
    per_page = 50
    offset = (page - 1) * per_page

    users =
      from(u in UserSchema,
        order_by: [desc: u.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> Starter.Repo.all()
      |> Enum.map(&serialize/1)

    total = Starter.Repo.aggregate(UserSchema, :count, :id)
    {users, total}
  rescue
    _ -> {[], 0}
  end

  defp serialize(user) do
    status =
      case user.status do
        s when is_atom(s) -> Atom.to_string(s)
        s when is_binary(s) -> s
        _ -> "unknown"
      end

    %{
      id: to_string(user.id),
      email: user.email || "",
      user_name: user.user_name || "",
      status: status,
      verified: user.verified == true,
      admin: user.admin == true
    }
  end

  defp normalize_orgs(list) when is_list(list) do
    Enum.map(list, fn
      %{id: id, name: name} = o ->
        %{id: to_string(id), name: name || "Organization", slug: Map.get(o, :slug)}

      %{"id" => id, "name" => name} = o ->
        %{id: to_string(id), name: name || "Organization", slug: Map.get(o, "slug")}

      other when is_map(other) ->
        id = Map.get(other, :id) || Map.get(other, "id")
        name = Map.get(other, :name) || Map.get(other, "name") || "Organization"
        %{id: to_string(id), name: name, slug: Map.get(other, :slug) || Map.get(other, "slug")}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_orgs(_), do: []
end
