defmodule Annotate.Organizations.Membership do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Organizations.Memberships
  @sref "membership"
  @persistence ecto_store(Annotate.Schema.Organizations.Membership, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: false
    @store name: :organization_id
    field :organization, nil, Annotate.Organizations.OrganizationReference
    @config auto: false
    @store name: :user_id
    field :user, nil, Annotate.Users.UserReference
    field :role, nil, :string
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
