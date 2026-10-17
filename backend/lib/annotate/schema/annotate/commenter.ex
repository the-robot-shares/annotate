defmodule Annotate.Schema.Annotate.Commenter do
  @moduledoc """
  A comment author identity.

  Three provenances:
  - Authentik SSO: `authentik_sub` set (globally unique).
  - Host-asserted: `external_id` set, unique per `site_id`.
  - Team (dashboard): `user_id` set — a dashboard user replying from the site
    inbox; unique per `(site_id, user_id)`, never authenticates on the embed.
  - Guest/anonymous: neither — rows are only created for identified commenters;
    guest comments have a nil author.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "commenters" do
    field :authentik_sub, :string
    field :external_id, :string
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    field :display_name, :string
    field :avatar_url, :string
    field :email, :string
    # True when the IdP asserted `email_verified` at upsert — gates the
    # team-role email bridge (Annotate.SiteMembers.team_role_for_commenter/3).
    field :email_verified, :boolean
    # Dashboard user behind a team commenter row (inbox replies). Set only by
    # `Annotate.Sites.team_commenter_for_user/2`, never cast from input.
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(commenter, attrs) do
    commenter
    |> cast(attrs, [
      :authentik_sub,
      :external_id,
      :site_id,
      :display_name,
      :avatar_url,
      :email,
      :email_verified
    ])
    |> unique_constraint(:authentik_sub, name: :commenters_authentik_sub_key)
    |> unique_constraint([:site_id, :external_id], name: :commenters_site_external_key)
  end
end
