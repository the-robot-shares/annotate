defmodule Annotate.Users.User do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Users
  @sref "user"
  @persistence ecto_store(Annotate.Schema.Users.User, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    field :user_name, nil, :string
    field :handle, nil, :string

    @config auto: true
    @store name: :name_id
    field :name, nil, Annotate.Versioned.Names.NameReference

    @config auto: true
    @store name: :description_id
    field :description, nil, Annotate.Versioned.Descriptions.DescriptionReference

    field :email, nil, :string
    field :hashed_password, nil, :string
    field :status, nil, {:ecto, Annotate.Schema.Users.User.__schema__(:type, :status)}
    field :mobile_phone, nil, :string
    field :profile_completed_at, nil, :utc_datetime_usec
    field :approved_at, nil, :utc_datetime_usec

    @config auto: false
    @store name: :invite_token_id
    field :invite_token, nil, Annotate.Organizations.InviteTokenReference

    @config auto: false
    @store name: :approved_by_user_id
    field :approved_by, nil, Annotate.Users.UserReference

    field :verified, nil, :boolean
    field :flagged, nil, :boolean
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
