defmodule Starter.Projects do
  alias Starter.Projects.Project, as: Entity
  alias Starter.Schema.Projects.Project, as: Schema

  use Noizu.Repo
  def_repo(entity: Entity)

  # <REMOVED UUID HERE> create_with_owner :: auto-generated pointer for public function create_with_owner
  def create_with_owner(attrs, user_id, _context \\ Noizu.Context.system()) do
    Starter.Repo.transaction(fn ->
      with {:ok, project} <-
             %Schema{}
             |> Schema.changeset(Map.put(attrs, :created_by, user_id))
             |> Starter.Repo.insert(),
           {:ok, _membership} <-
             Starter.Authz.ScopedMemberships.add_member("project", project.id, user_id, "owner") do
        project
      else
        {:error, reason} -> Starter.Repo.rollback(reason)
      end
    end)
  end

  # <REMOVED UUID HERE> list_for_user :: auto-generated pointer for public function list_for_user
  def list_for_user(user_id, organization_id \\ nil) do
    sql = "SELECT * FROM list_user_accessible_projects($1::uuid, $2::uuid)"
    params = [user_id, organization_id]

    case Ecto.Adapters.SQL.query(Starter.Repo, sql, params) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row -> Enum.zip(cols, row) |> Map.new() end)

      _ ->
        []
    end
  end

  # <REMOVED UUID HERE> get_project :: auto-generated pointer for public function get_project
  def get_project(id) do
    Starter.Repo.get(Schema, id)
  end

  # <REMOVED UUID HERE> update_project :: auto-generated pointer for public function update_project
  def update_project(id, attrs) do
    case Starter.Repo.get(Schema, id) do
      nil -> {:error, :not_found}
      project -> project |> Schema.changeset(attrs) |> Starter.Repo.update()
    end
  end

  # <REMOVED UUID HERE> archive :: auto-generated pointer for public function archive
  def archive(id) do
    case Starter.Repo.get(Schema, id) do
      nil ->
        {:error, :not_found}

      project ->
        project
        |> Schema.changeset(%{status: "archived", archived_at: DateTime.utc_now()})
        |> Starter.Repo.update()
    end
  end

  # <REMOVED UUID HERE> unarchive :: auto-generated pointer for public function unarchive
  def unarchive(id) do
    case Starter.Repo.get(Schema, id) do
      nil ->
        {:error, :not_found}

      project ->
        project
        |> Schema.changeset(%{status: "active", archived_at: nil})
        |> Starter.Repo.update()
    end
  end

  # <REMOVED UUID HERE> delete_project :: auto-generated pointer for public function delete_project
  def delete_project(id) do
    case Starter.Repo.get(Schema, id) do
      nil ->
        {:error, :not_found}

      project ->
        project
        |> Schema.changeset(%{status: "deleted"})
        |> Starter.Repo.update()
    end
  end

  # <REMOVED UUID HERE> list_members :: auto-generated pointer for public function list_members
  def list_members(project_id) do
    Starter.Authz.ScopedMemberships.list_for_resource("project", project_id)
  end
end
