defmodule Annotate.Schema.Annotate.OAuthIdentity do
  @moduledoc """
  A dashboard sign-in identity at an OAuth provider (`"github"`, `"google"`)
  linked to a scaffold user. Keyed by the provider's immutable account id
  (`provider_uid`: GitHub numeric id, Google `sub`) — never login or email.
  `email` is the provider-VERIFIED email seen at the last sign-in.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "oauth_identities" do
    field :provider, :string
    field :provider_uid, :string
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID
    field :login, :string
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :user_id, :login, :email, :name, :avatar_url])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> validate_inclusion(:provider, ~w(github google))
    |> unique_constraint([:provider, :provider_uid], name: :oauth_identities_provider_uid_key)
    |> unique_constraint([:user_id, :provider], name: :oauth_identities_user_provider_key)
    |> foreign_key_constraint(:user_id)
  end
end
