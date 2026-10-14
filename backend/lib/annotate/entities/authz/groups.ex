defmodule Annotate.Authz.Groups do
  alias Annotate.Authz.Groups.Group, as: Entity
  alias Annotate.Schema.Authz.Group, as: Schema
  alias Annotate.Schema.Authz.GroupPolicy, as: GroupPolicySchema
  alias Annotate.Schema.Authz.Policy, as: PolicySchema

  use Noizu.Repo
  def_repo(entity: Entity)

  import Ecto.Query

  # <REMOVED UUID HERE> list_all :: auto-generated pointer for public function list_all
  def list_all do
    Annotate.Repo.all(from g in Schema, order_by: g.name)
  end

  # <REMOVED UUID HERE> get_by_name :: auto-generated pointer for public function get_by_name
  def get_by_name(name) when is_binary(name) do
    Annotate.Repo.one(from g in Schema, where: g.name == ^name)
  end

  # <REMOVED UUID HERE> list_policies :: auto-generated pointer for public function list_policies
  def list_policies(group_id) do
    from(gp in GroupPolicySchema,
      join: p in PolicySchema,
      on: p.id == gp.policy_id,
      where: gp.group_id == ^group_id,
      order_by: gp.priority,
      select: %{
        id: p.id,
        name: p.name,
        description: p.description,
        policy_document: p.policy_document,
        is_system: p.is_system,
        is_active: p.is_active,
        priority: gp.priority
      }
    )
    |> Annotate.Repo.all()
  end
end
