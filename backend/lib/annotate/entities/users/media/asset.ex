defmodule Annotate.Users.Media.Asset do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Users.Media
  @sref "user-media"
  @persistence ecto_store(Annotate.Schema.Users.Media.Asset, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: false
    @store name: :user_id
    field :user, nil, Annotate.Users.UserReference
    @config auto: true
    @store name: :media_id
    field :media, nil, Annotate.Media.AssetReference
    @config auto: true
    @store name: :description_id
    field :description, nil, Annotate.Versioned.Descriptions.DescriptionReference

    field :media_type,
          nil,
          {:ecto, Annotate.Schema.Users.Media.Asset.__schema__(:type, :media_type)}

    field :settings, %{}, :map
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
