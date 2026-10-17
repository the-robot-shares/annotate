defmodule Annotate.Auth.RefreshTokens do
  @moduledoc """
  Opaque, rotating refresh tokens (30-day TTL, `ttl_days/0`).

  Only `sha256(raw)` is stored. Every use rotates: the presented token is
  revoked and a fresh one issued, so a stolen token window is one round trip.

  Families (T-02): every token issued by a sign-in starts a family whose id
  rides in `identity_claims["family"]` (jsonb, no schema change); rotations
  inherit it. Rotation is a compare-and-set (`UPDATE … WHERE revoked_at IS
  NULL`), so two concurrent presentations cannot both succeed. Presenting an
  already-revoked token more than `reuse_leeway_seconds/0` after it was
  revoked is treated as theft and revokes the whole family; inside the
  leeway it is a benign tab race (the widget serialises rotations with a Web
  Lock and re-reads storage on a 401) and only fails. `revoke_family/1` backs
  `POST /api/v1/token/revoke` (sign-out).
  """

  import Ecto.Query
  alias Annotate.Embed.Policy
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.RefreshToken

  @ttl_days 30
  @reuse_leeway_seconds 10

  def ttl_days, do: @ttl_days
  def reuse_leeway_seconds, do: @reuse_leeway_seconds

  def hash(raw) when is_binary(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)

  @doc "Issues a new refresh token for a commenter/site; returns `{:ok, raw}`."
  def issue(commenter, site, identity_claims \\ nil, origin \\ nil) do
    # The issuing origin rides in the existing `identity_claims` jsonb column
    # (key "origin") so no schema change is needed. A nil `identity_claims`
    # keeps its legacy meaning (policy falls back to the commenter's email), so
    # materialise that fallback before attaching the origin.
    # Every token carries a family id (fresh sign-in → new family; rotation
    # passes the parent's claims, so the family is inherited). Attaching it
    # materialises the nil-claims fallback exactly like the origin does.
    identity_claims =
      (identity_claims || %{"email" => commenter.email, "groups" => nil})
      |> Map.put_new_lazy("family", &Ecto.UUID.generate/0)

    identity_claims =
      if is_binary(origin), do: Map.put(identity_claims, "origin", origin), else: identity_claims

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
  `{:error, :invalid}`, `{:error, :origin}` or `{:error, :policy}` when the site's CURRENT
  `comment_policy` rejects the identity stored at issuance (the presented
  token is revoked either way — a policy failure kills the session).
  """
  def rotate(raw, request_origin) when is_binary(raw) do
    now = DateTime.utc_now()

    query =
      from(rt in RefreshToken,
        join: c in assoc(rt, :commenter),
        join: s in assoc(rt, :site),
        where: rt.token_hash == ^hash(raw),
        preload: [commenter: c, site: s],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:error, :invalid}

      %RefreshToken{revoked_at: %DateTime{} = revoked_at} = rt ->
        # Reuse of a revoked token. Past the leeway it can only be a replay of
        # a leaked token (or a client bug): kill the family so neither the
        # thief's nor the victim's chain survives. Inside the leeway it is a
        # benign race between tabs — fail without collateral.
        if DateTime.diff(now, revoked_at, :second) > @reuse_leeway_seconds do
          revoke_family_of(rt)
        end

        {:error, :invalid}

      %RefreshToken{} = rt ->
        if DateTime.compare(rt.expires_at, now) == :gt do
          rotate_live(rt, request_origin)
        else
          {:error, :invalid}
        end
    end
  end

  def rotate(_, _), do: {:error, :invalid}

  defp rotate_live(rt, request_origin) do
    # Origin gate runs BEFORE revoke: a forged-Origin probe must not burn
    # the legitimate holder's token.
    with :ok <- check_origin(rt, request_origin) do
      Repo.transaction(fn ->
        with :ok <- revoke_if_live(rt),
             :ok <- check_current_policy(rt),
             {:ok, fresh_raw} <-
               issue(
                 rt.commenter,
                 rt.site,
                 rt.identity_claims,
                 issuing_origin(rt) || request_origin
               ) do
          %{
            commenter: rt.commenter,
            site: rt.site,
            refresh_token: fresh_raw,
            identity_claims: rt.identity_claims
          }
        else
          # A policy failure still revokes the presented token (committed).
          {:error, :policy} -> {:policy_revoked}
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {:policy_revoked}} -> {:error, :policy}
        {:ok, result} -> {:ok, result}
        {:error, :lost_race} -> {:error, :invalid}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Revokes the family `raw` belongs to (sign-out). Unknown, expired or
  already-revoked tokens are a no-op; returns the number of rows revoked.
  """
  def revoke_family(raw) when is_binary(raw) do
    case Repo.one(from(rt in RefreshToken, where: rt.token_hash == ^hash(raw), limit: 1)) do
      nil -> 0
      %RefreshToken{} = rt -> revoke_family_of(rt)
    end
  end

  def revoke_family(_), do: 0

  @doc "Family id of a token (legacy rows without one are their own family)."
  def family(%RefreshToken{identity_claims: %{"family" => f}}) when is_binary(f), do: f
  def family(%RefreshToken{id: id}), do: id

  defp revoke_family_of(rt) do
    fam = family(rt)
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    {n, _} =
      from(t in RefreshToken,
        where: is_nil(t.revoked_at),
        where: t.id == ^rt.id or fragment("(?->>'family') = ?", t.identity_claims, ^fam)
      )
      |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    n
  end

  @doc "Origin the token was issued for (nil for tokens minted before binding)."
  def issuing_origin(%RefreshToken{identity_claims: %{"origin" => o}}) when is_binary(o), do: o
  def issuing_origin(_), do: nil

  # The request Origin must be (a) an exact member of the site's current
  # allowed_origins and (b) when the token recorded its issuing origin, equal
  # to it. No Origin header ⇒ rejected (browsers always send one on a
  # cross-origin POST; an Origin-less caller cannot prove the binding).
  # Tokens issued before binding existed have no recorded origin and are
  # constrained by (a) only; the first rotation re-binds them.
  defp check_origin(rt, request_origin) when is_binary(request_origin) do
    bound = issuing_origin(rt)

    if Annotate.Sites.allowed_origin?(rt.site, request_origin) and
         (is_nil(bound) or bound == request_origin) do
      :ok
    else
      {:error, :origin}
    end
  end

  defp check_origin(_rt, _), do: {:error, :origin}

  # Compare-and-set: only the first concurrent presentation wins.
  defp revoke_if_live(rt) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    case Repo.update_all(
           from(t in RefreshToken, where: t.id == ^rt.id and is_nil(t.revoked_at)),
           set: [revoked_at: now, updated_at: now]
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :lost_race}
    end
  end

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
