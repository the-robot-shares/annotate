defmodule Annotate.Organizations.Memberships do
  @moduledoc """
  Repo for Annotate.Organizations.Membership
  """
  alias Annotate.Organizations.Membership, as: Entity
  alias Annotate.Schema.Organizations.Membership, as: Schema
  use Noizu.Repo
  def_repo(entity: Entity)

  # <REMOVED UUID HERE> list_for_org :: auto-generated pointer for public function list_for_org
  def list_for_org(org_id, context, options \\ []) do
    import Ecto.Query
    settings = Noizu.Entity.Meta.persistence(Entity) |> hd

    Annotate.Repo.all(from m in Schema, where: m.organization_id == ^org_id)
    |> Enum.map(fn record ->
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      {:ok, entity} = __after_get__(entity, context, options)
      entity
    end)
  end
end
