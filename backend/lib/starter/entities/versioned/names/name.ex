defmodule Starter.Versioned.Names.Name do
  use Noizu.Entities

  @vsn 1.0
  @repo Starter.Versioned.Names
  @sref "versioned-name"
  @persistence ecto_store(Starter.Schema.Versioned.Names.Name, Starter.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :first, nil, :string
    field :middle, [], {:array, :string}
    field :last, nil, :string
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Starter.Support.NoizuJasonEncoder

  # <REMOVED UUID HERE> equal? :: auto-generated pointer for public function equal?
  def equal?(_, _), do: false

  # <REMOVED UUID HERE> __schema__ :: auto-generated pointer for public function __schema__
  def __schema__(:primary_key), do: [:id]
  def __schema__(:redact_fields), do: []
  def __schema__(_), do: true

  # <REMOVED UUID HERE> __changeset__ :: auto-generated pointer for public function __changeset__
  def __changeset__() do
    Noizu.Entity.Meta.meta(__MODULE__).changeset_fields
  end
end
