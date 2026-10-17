defmodule Annotate.Schema.Annotate.SiteMember do
  @moduledoc """
  A dashboard-team membership row: `site_id` × scaffold `user_id` with a
  `site_member_role_enum` role (`owner` / `admin` / `member`).

  The dashboard realm authenticates scaffold `users` (Guardian sessions via
  `Annotate.Hologram.Auth`); the embed realm authenticates `commenters`
  (15-minute JWTs). The two are bridged at access-token issuance by Authentik
  email — see `Annotate.SiteMembers.team_role_for_commenter/3`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "site_members" do
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID
    field :role, Ecto.Enum, values: [:owner, :admin, :member], default: :member
    belongs_to :inviter, Annotate.Schema.Users.User, type: Ecto.UUID, foreign_key: :invited_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(site_member, attrs) do
    site_member
    |> cast(attrs, [:site_id, :user_id, :role, :invited_by])
    |> validate_required([:site_id, :user_id])
    |> unique_constraint([:site_id, :user_id], name: :site_members_site_user_key)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:user_id)
  end
end
