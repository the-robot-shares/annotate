defmodule Annotate.Auth.RefreshTokens do
  @moduledoc """
  Opaque, rotating refresh tokens (30-day TTL).

  Only `sha256(raw)` is stored. Every use rotates: the presented token is
  revoked and a fresh one issued, so a stolen token window is one round trip.
  """

  import Ecto.Query
  alias Annotate.Embed.Policy
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.RefreshToken

  @ttl_days 30

  def ttl_days, do: @ttl_days

  def hash(raw) when is_binary(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)

  @doc "Issues a new refresh token for a commenter/site; returns `{:ok, raw}`."
  def issue(commenter, site, identity_claims \\ nil) do
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = DateTime.add(DateTime.utc_now(), @ttl_days, :day)

    %RefreshToken{}
    |> Ecto.Changeset.change(%{
      commenter_id: commenter.id,
      site_id: site.id,
      token_hash: hash(raw),
      identity_claims: identity_claims,
      expires_at: DateTime.truncate(expires_at, :microsecond)
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> {:ok, raw}
      error -> error
    end
  end

  @doc """
  Rotates `raw`: revokes it and issues a fresh pair for its commenter/site.
  Returns `{:ok, %{commenter:, site:, refresh_token:, identity_claims:}}`,
  `{:error, :invalid}`, or `{:error, :policy}` when the site's CURRENT
  `comment_policy` rejects the identity stored at issuance (the presented
  token is revoked either way — a policy failure kills the session).
  """
  def rotate(raw) when is_binary(raw) do
    now = DateTime.utc_now()

    query =
      from(rt in RefreshToken,
        join: c in assoc(rt, :commenter),
        join: s in assoc(rt, :site),
        where: rt.token_hash == ^hash(raw),
        where: is_nil(rt.revoked_at),
        where: rt.expires_at > ^now,
        preload: [commenter: c, site: s],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:error, :invalid}

      %RefreshToken{} = rt ->
        {:ok, _} = revoke(rt)

        with :ok <- check_current_policy(rt),
             {:ok, fresh_raw} <- issue(rt.commenter, rt.site, rt.identity_claims) do
          {:ok,
           %{
             commenter: rt.commenter,
             site: rt.site,
             refresh_token: fresh_raw,
             identity_claims: rt.identity_claims
           }}
        end
    end
  end

  def rotate(_), do: {:error, :invalid}

  defp revoke(rt),
    do:
      rt
      |> Ecto.Changeset.change(revoked_at: DateTime.truncate(DateTime.utc_now(), :microsecond))
      |> Repo.update()

  # Re-check the site's policy as it stands NOW against the identity claims
  # captured at issuance. Tokens issued before claims were persisted fall back
  # to the commenter's stored email (group membership is then un-evaluable, so
  # a required_groups policy fails closed and forces re-authentication).
  defp check_current_policy(rt) do
    claims =
      case rt.identity_claims do
        %{} = claims -> claims
        _ -> %{"email" => rt.commenter.email, "groups" => nil}
      end

    case Policy.check(claims, rt.site.comment_policy || %{}) do
      :ok -> :ok
      {:error, _reason} -> {:error, :policy}
    end
  end
end
