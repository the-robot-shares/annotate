defmodule StarterWeb.AdminController do
  use StarterWeb, :controller

  alias Starter.Schema.Users.User, as: UserSchema
  alias Starter.Schema.Organizations.Organization, as: OrgSchema
  import Ecto.Query

  # <REMOVED UUID HERE> list_users :: auto-generated pointer for public function list_users
  def list_users(conn, params) do
    page = String.to_integer(Map.get(params, "page", "1"))
    per_page = String.to_integer(Map.get(params, "per_page", "50"))
    offset = (page - 1) * per_page

    users =
      from(u in UserSchema,
        order_by: [desc: u.inserted_at],
        limit: ^per_page,
        offset: ^offset,
        select: %{
          id: u.id,
          email: u.email,
          user_name: u.user_name,
          status: u.status,
          mobile_phone: u.mobile_phone,
          profile_completed_at: u.profile_completed_at,
          verified: u.verified,
          admin: u.admin,
          created_at: u.inserted_at
        }
      )
      |> Starter.Repo.all()

    total = Starter.Repo.aggregate(UserSchema, :count, :id)

    conn |> put_status(:ok) |> json(%{users: users, total: total, page: page, per_page: per_page})
  end

  # <REMOVED UUID HERE> show_user :: auto-generated pointer for public function show_user
  def show_user(conn, %{"id" => id}) do
    case Starter.Repo.get(UserSchema, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "User not found"})

      user ->
        conn
        |> put_status(:ok)
        |> json(%{
          user: %{
            id: user.id,
            email: user.email,
            user_name: user.user_name,
            handle: user.handle,
            status: user.status,
            mobile_phone: user.mobile_phone,
            profile_completed_at: user.profile_completed_at,
            verified: user.verified,
            admin: user.admin,
            created_at: user.inserted_at
          }
        })
    end
  end

  # <REMOVED UUID HERE> approve_user :: auto-generated pointer for public function approve_user
  def approve_user(conn, %{"id" => id}) do
    admin_user = conn.assigns[:admin_user]

    case Starter.Repo.get(UserSchema, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "User not found"})

      user ->
        attrs = %{
          status: :active,
          approved_at: DateTime.utc_now(),
          approved_by_user_id: admin_user.id
        }

        case user |> UserSchema.changeset(attrs) |> Starter.Repo.update() do
          {:ok, updated_user} ->
            conn |> put_status(:ok) |> json(%{user: serialize_user(updated_user)})

          {:error, changeset} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
        end
    end
  end

  # <REMOVED UUID HERE> list_organizations :: auto-generated pointer for public function list_organizations
  def list_organizations(conn, params) do
    page = String.to_integer(Map.get(params, "page", "1"))
    per_page = String.to_integer(Map.get(params, "per_page", "50"))
    offset = (page - 1) * per_page

    orgs =
      from(o in OrgSchema,
        order_by: [desc: o.inserted_at],
        limit: ^per_page,
        offset: ^offset,
        select: %{
          id: o.id,
          slug: o.slug,
          name: o.name,
          created_at: o.inserted_at
        }
      )
      |> Starter.Repo.all()

    total = Starter.Repo.aggregate(OrgSchema, :count, :id)

    conn
    |> put_status(:ok)
    |> json(%{organizations: orgs, total: total, page: page, per_page: per_page})
  end

  # <REMOVED UUID HERE> show_organization :: auto-generated pointer for public function show_organization
  def show_organization(conn, %{"id" => id}) do
    case Starter.Repo.get(OrgSchema, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        members = Starter.Organizations.list_members(org.id)

        conn
        |> put_status(:ok)
        |> json(%{
          organization: %{
            id: org.id,
            slug: org.slug,
            name: org.name,
            created_at: org.inserted_at
          },
          members: members
        })
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      user_name: user.user_name,
      handle: user.handle,
      status: user.status,
      mobile_phone: user.mobile_phone,
      profile_completed_at: user.profile_completed_at,
      verified: user.verified,
      admin: user.admin,
      created_at: user.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
