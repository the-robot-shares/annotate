defmodule Annotate.Auth.RefreshTokens do
  @moduledoc """
  Opaque, rotating refresh tokens (30-day TTL).

  Only `sha256(raw)` is stored. Every use rotates: the presented token is
  revoked and a fresh one issued, so a stolen token window is one round trip.
  """

  import Ecto.Query
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.RefreshToken

  @ttl_days 30

  def ttl_days, do: @ttl_days

  def hash(raw) when is_binary(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)

  @doc "Issues a new refresh token for a commenter/site; returns `{:ok, raw}`."
  def issue(commenter, site) do
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = DateTime.add(DateTime.utc_now(), @ttl_days, :day)

    %RefreshToken{}
    |> Ecto.Changeset.change(%{
      commenter_id: commenter.id,
      site_id: site.id,
      token_hash: hash(raw),
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
  Returns `{:ok, %{commenter:, site:, refresh_token:}}` or `{:error, :invalid}`.
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
        {:ok, _} =
          rt
          |> Ecto.Changeset.change(revoked_at: DateTime.truncate(now, :microsecond))
          |> Repo.update()

        with {:ok, fresh_raw} <- issue(rt.commenter, rt.site) do
          {:ok, %{commenter: rt.commenter, site: rt.site, refresh_token: fresh_raw}}
        end
    end
  end

  def rotate(_), do: {:error, :invalid}
end
