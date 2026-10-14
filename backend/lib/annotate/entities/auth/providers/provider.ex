defmodule Annotate.Auth.Providers.Provider do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Auth.Providers
  @sref "auth-provider"
  @persistence ecto_store(Annotate.Schema.Auth.Providers.Provider, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :title, nil, :string
    field :description, nil, :string
    field :settings, %{}, :any
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
