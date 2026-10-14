defmodule Annotate.Users.Credentials.UserCredential do
  use Noizu.Entities
  @vsn 1.0
  @repo Annotate.Users.Credentials
  @sref "user-credential"
  @persistence ecto_store(Annotate.Schema.Users.Credentials.UserCredential, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: false
    @store name: :user_id
    field :user, nil, Annotate.Users.UserReference
    @config auto: true
    @store name: :auth_provider_id
    field :auth_provider, nil, Annotate.Auth.Providers.ProviderReference
    @config auto: true
    @store name: :description_id
    field :description, nil, Annotate.Versioned.Descriptions.DescriptionReference

    field :status,
          nil,
          {:ecto, Annotate.Schema.Users.Credentials.UserCredential.__schema__(:type, :status)}

    field :settings, %{}, :map
    field :state, %{}, :map
    field :fingerprint, nil, :string
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
