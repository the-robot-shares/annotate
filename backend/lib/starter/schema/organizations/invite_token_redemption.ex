defmodule Starter.Schema.Organizations.InviteTokenRedemption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "invite_token_redemptions" do
    belongs_to :invite_token, Starter.Schema.Organizations.InviteToken, type: Ecto.UUID
    belongs_to :user, Starter.Schema.Users.User, type: Ecto.UUID
    field :redeemed_at, :utc_datetime_usec
    field :remote_ip, :string
    field :user_agent, :string
    timestamps(type: :utc_datetime_usec)
  end

  # <REMOVED UUID HERE> changeset :: auto-generated pointer for public function changeset
  def changeset(redemption, attrs) do
    redemption
    |> cast(attrs, [:invite_token_id, :user_id, :redeemed_at, :remote_ip, :user_agent])
    |> validate_required([:invite_token_id, :user_id, :redeemed_at])
  end
end
