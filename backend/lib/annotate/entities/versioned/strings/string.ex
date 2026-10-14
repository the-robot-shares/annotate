defmodule Annotate.Versioned.Strings.String do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Versioned.Strings
  @sref "versioned-string"
  @persistence ecto_store(Annotate.Schema.Versioned.Strings.String, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :content, nil, :string
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
