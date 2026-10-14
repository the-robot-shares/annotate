defmodule Starter.Schema.Versioned.Names.Name do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "versioned_names" do
    field :first, :string
    field :last, :string
    field :middle, {:array, :string}, default: []
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  # <REMOVED UUID HERE> changeset :: auto-generated pointer for public function changeset
  def changeset(name, attrs) do
    name
    |> cast(attrs, [:first, :middle, :last])
    |> validate_required([:first, :last])
  end
end
