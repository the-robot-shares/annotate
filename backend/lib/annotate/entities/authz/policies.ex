defmodule Annotate.Authz.Policies do
  alias Annotate.Authz.Policies.Policy, as: Entity
  alias Annotate.Schema.Authz.Policy, as: Schema
  alias Annotate.Schema.Authz.UserPolicy, as: UserPolicySchema

  use Noizu.Repo
  def_repo(entity: Entity)

  import Ecto.Query

  # <REMOVED UUID HERE> list_active :: auto-generated pointer for public function list_active
  def list_active(opts \\ []) do
    query = from(p in Schema, where: p.is_active == true, order_by: p.name)

    query =
      if Keyword.get(opts, :system_only, false) do
        from(p in query, where: p.is_system == true)
      else
        query
      end

    Annotate.Repo.all(query)
  end

  # <REMOVED UUID HERE> get_by_name :: auto-generated pointer for public function get_by_name
  def get_by_name(name) do
    Annotate.Repo.one(from p in Schema, where: p.name == ^name and p.is_active == true)
  end

  # <REMOVED UUID HERE> create_policy :: auto-generated pointer for public function create_policy
  def create_policy(attrs) do
    %Schema{}
    |> Schema.changeset(attrs)
    |> Annotate.Repo.insert()
  end

  # <REMOVED UUID HERE> update_policy :: auto-generated pointer for public function update_policy
  def update_policy(id, attrs) do
    case Annotate.Repo.get(Schema, id) do
      nil ->
        {:error, :not_found}

      policy ->
        if policy.is_system do
          {:error, :cannot_modify_system_policy}
        else
          policy |> Schema.changeset(attrs) |> Annotate.Repo.update()
        end
    end
  end

  # <REMOVED UUID HERE> delete_policy :: auto-generated pointer for public function delete_policy
  def delete_policy(id) do
    case Annotate.Repo.get(Schema, id) do
      nil ->
        {:error, :not_found}

      policy ->
        if policy.is_system do
          {:error, :cannot_delete_system_policy}
        else
          Annotate.Repo.delete(policy)
        end
    end
  end

  # <REMOVED UUID HERE> list_user_policies :: auto-generated pointer for public function list_user_policies
  def list_user_policies(user_id) do
    from(up in UserPolicySchema,
      join: p in Schema,
      on: p.id == up.policy_id,
      where: up.user_id == ^user_id,
      order_by: up.priority,
      select: %{
        id: up.id,
        policy_id: p.id,
        policy_name: p.name,
        resource_type: up.resource_type,
        resource_id: up.resource_id,
        priority: up.priority
      }
    )
    |> Annotate.Repo.all()
  end

  # <REMOVED UUID HERE> attach_to_user :: auto-generated pointer for public function attach_to_user
  def attach_to_user(user_id, policy_id, opts \\ []) do
    %UserPolicySchema{}
    |> UserPolicySchema.changeset(%{
      user_id: user_id,
      policy_id: policy_id,
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id),
      priority: Keyword.get(opts, :priority, 0)
    })
    |> Annotate.Repo.insert()
  end

  # <REMOVED UUID HERE> detach_from_user :: auto-generated pointer for public function detach_from_user
  def detach_from_user(user_id, policy_id) do
    case Annotate.Repo.one(
           from up in UserPolicySchema,
             where: up.user_id == ^user_id and up.policy_id == ^policy_id
         ) do
      nil -> {:error, :not_found}
      user_policy -> Annotate.Repo.delete(user_policy)
    end
  end
end
