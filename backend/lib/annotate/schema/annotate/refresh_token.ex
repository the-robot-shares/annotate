defmodule Annotate.Schema.Annotate.RefreshToken do
  @moduledoc """
  Opaque rotating refresh token (30-day TTL).

  Only the sha256 of the raw token is stored; rotation revokes the presented
  token and issues a fresh one (see `Annotate.Auth.RefreshTokens`).
  `identity_claims` (jsonb) captures the policy-relevant identity (`email`,
  `groups`) at issuance so rotation can re-check the site's current
  `comment_policy` (see `Annotate.Embed.Policy`).
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "refresh_tokens" do
    belongs_to :commenter, Annotate.Schema.Annotate.Commenter, type: Ecto.UUID
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    field :token_hash, :string
    field :identity_claims, :map
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
