defmodule Annotate.Schema.Annotate.GithubIdentity do
  @moduledoc """
  A GitHub account linked to a dashboard (scaffold) user.

  Keyed by GitHub's immutable numeric `github_id` — never by `login` (users
  can rename) or email (users can change it). `email` is the VERIFIED email
  chosen at the last sign-in (`Annotate.Dashboard.GithubLogin`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "github_identities" do
    field :github_id, :integer
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID
    field :login, :string
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:github_id, :user_id, :login, :email, :name, :avatar_url])
    |> validate_required([:github_id, :user_id, :login])
    |> unique_constraint(:github_id, name: :github_identities_github_id_key)
    |> unique_constraint(:user_id, name: :github_identities_user_id_key)
    |> foreign_key_constraint(:user_id)
  end
end
