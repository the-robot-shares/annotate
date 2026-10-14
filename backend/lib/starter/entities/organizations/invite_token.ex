defmodule Starter.Organizations.InviteToken do
  use Noizu.Entities

  @vsn 1.0
  @repo Starter.Organizations.InviteTokens
  @sref "invite-token"
  @persistence ecto_store(Starter.Schema.Organizations.InviteToken, Starter.Repo)
  use Noizu.Entity.Store.Ecto.EntityProtocol.Behaviour

  def_entity do
    id(:uuid)
    @config auto: false
    @store name: :organization_id
    field :organization, nil, Starter.Organizations.OrganizationReference
    @config auto: false
    @store name: :created_by_user_id
    field :created_by, nil, Starter.Users.UserReference
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
    field :accepted_by, nil, Starter.Users.UserReference
    field :accepted_at, nil, :utc_datetime_usec
    field :time_stamp, nil, Noizu.Entity.TimeStamp
  end

  use Starter.Support.NoizuJasonEncoder
end
