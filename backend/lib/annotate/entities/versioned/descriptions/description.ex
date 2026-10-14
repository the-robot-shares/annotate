defmodule Annotate.Versioned.Descriptions.Description do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Versioned.Descriptions
  @sref "versioned-description"
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour
  @persistence ecto_store(Annotate.Schema.Versioned.Descriptions.Description, Annotate.Repo)
  def_entity do
    id(:uuid)
    field :title, nil, :string
    field :body, nil, :string
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
