defmodule Annotate.Organizations.Organization do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Organizations
  @sref "organization"
  @persistence ecto_store(Annotate.Schema.Organizations.Organization, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :slug, nil, :string
    field :name, nil, :string
    field :settings, %{}, :map
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
