defmodule Annotate.Schema.Organizations.CustomRolePermission do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "custom_role_permissions" do
    belongs_to :role, Annotate.Schema.Organizations.CustomRole, type: Ecto.UUID
    field :permission, :string

    timestamps(type: :utc_datetime_usec)
  end

  # <REMOVED UUID HERE> changeset :: auto-generated pointer for public function changeset
  def changeset(perm, attrs) do
    perm
    |> cast(attrs, [:role_id, :permission])
    |> validate_required([:role_id, :permission])
    |> unique_constraint([:role_id, :permission])
  end
end
