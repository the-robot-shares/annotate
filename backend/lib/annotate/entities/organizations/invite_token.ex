defmodule Annotate.Organizations.InviteToken do
  use Noizu.Entities

  @vsn 1.0
  @repo Annotate.Organizations.InviteTokens
  @sref "invite-token"
  @persistence ecto_store(Annotate.Schema.Organizations.InviteToken, Annotate.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: false
    @store name: :organization_id
    field :organization, nil, Annotate.Organizations.OrganizationReference
    @config auto: false
    @store name: :created_by_user_id
    field :created_by, nil, Annotate.Users.UserReference
    field :token_hash, nil, :string
    field :key_prefix, nil, :string
    field :email, nil, :string
    field :starts_at, nil, :utc_datetime_usec
    field :max_uses, nil, :integer
    field :uses, 0, :integer
    field :redemption_count, 0, :integer
    field :expires_at, nil, :utc_datetime_usec
    field :revoked, false, :boolean
    field :status, nil, :string
    @config auto: false
    @store name: :accepted_by
    field :accepted_by, nil, Annotate.Users.UserReference
    field :accepted_at, nil, :utc_datetime_usec
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Annotate.Support.NoizuJasonEncoder
end
