defmodule AnnotateWeb.Hologram.Pages.AdminOrgsPage do
  @moduledoc "Platform admin: list organizations."
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Schema.Organizations.Organization, as: OrgSchema
  alias AnnotateWeb.Hologram.Components.AppShell
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAdmin

  import Ecto.Query

  route "/app/admin/orgs"
  layout MainLayout, page_title: "Admin · Organizations"
  middleware RequireAdmin

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    {orgs, total} = list_orgs(1)

    put_state(component,
      user: user,
      organizations: normalize_orgs(organizations || []),
      orgs: orgs,
      total: total,
      page: 1,
      can_prev: false,
      can_next: length(orgs) >= 50
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="admin_orgs" title="Admin · Organizations">
      <p class="sg-page-intro">
        Organizations ({@total}).
        <a href="/app/admin/users">Users</a>
      </p>

      {%if @orgs == []}
        <p class="app-muted">No organizations found.</p>
      {%else}
        <table class="app-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {%for o <- @orgs}
              <tr>
                <td>{o.name}</td>
                <td><code>{o.slug}</code></td>
                <td>{o.created_at}</td>
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

  def action(:page_loaded, params, component) do
    put_state(component,
      orgs: params.orgs,
      total: params.total,
      page: params.page,
      can_prev: params.page > 1,
      can_next: length(params.orgs) >= 50
    )
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:load_orgs, params, server) do
    {orgs, total} = list_orgs(params.page)
    put_action(server, :page_loaded, orgs: orgs, total: total, page: params.page)
  end

  defp load_page(component, page) do
    component
    |> put_state(page: page)
    |> put_command(:load_orgs, page: page)
  end

  defp list_orgs(page) do
    per_page = 50
    offset = (page - 1) * per_page

    orgs =
      from(o in OrgSchema,
        order_by: [desc: o.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> Annotate.Repo.all()
      |> Enum.map(fn o ->
        %{
          id: to_string(o.id),
          name: o.name || "",
          slug: o.slug || "",
          created_at: format_date(Map.get(o, :inserted_at) || Map.get(o, :created_at))
        }
      end)

    total = Annotate.Repo.aggregate(OrgSchema, :count, :id)
    {orgs, total}
  rescue
    _ -> {[], 0}
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_date(_), do: ""

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
