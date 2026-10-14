defmodule Annotate.Users.Sessions.UserSession do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Users.Sessions
  @sref "user-session"
  @persistence ecto_store(Annotate.Schema.Users.Sessions.UserSession, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: true
    @store name: :user_id
    field :user, nil, Annotate.Users.UserReference
    @config auto: true
    @store name: :credential_id
    field :credential, nil, Annotate.Users.Credentials.UserCredentialReference

    field :status,
          nil,
          {:ecto, Annotate.Schema.Users.Sessions.UserSession.__schema__(:type, :status)}

    field :details, %{}, :map
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
