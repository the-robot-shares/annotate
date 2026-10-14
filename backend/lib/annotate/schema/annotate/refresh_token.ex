defmodule Annotate.Schema.Annotate.RefreshToken do
  @moduledoc """
  Opaque rotating refresh token (30-day TTL).

  Only the sha256 of the raw token is stored; rotation revokes the presented
  token and issues a fresh one (see `Annotate.Auth.RefreshTokens`).
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "refresh_tokens" do
    belongs_to :commenter, Annotate.Schema.Annotate.Commenter, type: Ecto.UUID
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
