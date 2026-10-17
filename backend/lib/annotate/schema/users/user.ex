defmodule Annotate.Schema.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "users" do
    field :user_name, :string
    field :handle, :string
    belongs_to :name, Annotate.Schema.Versioned.Names.Name, type: Ecto.UUID
    belongs_to :description, Annotate.Schema.Versioned.Descriptions.Description, type: Ecto.UUID
    belongs_to :invite_token, Annotate.Schema.Organizations.InviteToken, type: Ecto.UUID
    belongs_to :approved_by_user, __MODULE__, type: Ecto.UUID
    field :email, :string
    field :hashed_password, :string

    field :status, Ecto.Enum,
      values: [:active, :pending, :unverified, :waitlist, :suspended, :deleted, :other],
      default: :active

    field :mobile_phone, :string
    field :profile_completed_at, :utc_datetime_usec
    field :approved_at, :utc_datetime_usec
    field :verified, :boolean, default: false
    field :flagged, :boolean, default: false
    field :admin, :boolean, default: false
    field :deleted_at, :utc_datetime_usec
    field :invite_quota, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  # <REMOVED UUID HERE> changeset :: auto-generated pointer for public function changeset
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :user_name,
      :handle,
      :name_id,
      :description_id,
      :invite_token_id,
      :approved_by_user_id,
      :email,
      :hashed_password,
      :status,
      :mobile_phone,
      :profile_completed_at,
      :approved_at,
      :verified,
      :flagged,
      :admin
    ])
    |> validate_required([:email])
    |> unique_constraint(:email)
    |> unique_constraint(:user_name)
    |> unique_constraint(:handle)
  end
end
