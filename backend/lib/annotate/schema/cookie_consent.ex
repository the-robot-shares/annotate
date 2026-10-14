defmodule Annotate.Schema.CookieConsent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "cookie_consents" do
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID
    field :browser_session_id, Ecto.UUID
    field :version, :integer
    field :categories, :map, default: %{}
    field :required_session_allowed, :boolean, default: true
    field :accepted_at, :utc_datetime_usec
    field :updated_choice_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  # <REMOVED UUID HERE> changeset :: auto-generated pointer for public function changeset
  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [
      :user_id,
      :browser_session_id,
      :version,
      :categories,
      :required_session_allowed,
      :accepted_at,
      :updated_choice_at
    ])
    |> validate_required([:version, :categories, :required_session_allowed, :updated_choice_at])
    |> validate_identity()
  end

  defp validate_identity(changeset) do
    user_id = get_field(changeset, :user_id)
    browser_session_id = get_field(changeset, :browser_session_id)

    if user_id || browser_session_id do
      changeset
    else
      add_error(changeset, :browser_session_id, "is required when user is anonymous")
    end
  end
end
