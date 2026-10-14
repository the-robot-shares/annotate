defmodule Starter.Auth.Providers.Provider do
  use Noizu.Entities

  @vsn 1.0
  @repo Starter.Auth.Providers
  @sref "auth-provider"
  @persistence ecto_store(Starter.Schema.Auth.Providers.Provider, Starter.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :title, nil, :string
    field :description, nil, :string
    field :settings, %{}, :any
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Starter.Support.NoizuJasonEncoder
end
