defmodule Annotate.Auth.ApiToken do
  @moduledoc """
  Annotate API access tokens: HS256 JWTs, 15-minute TTL.

  Claims: `sub` (commenter id), `site` (site id), `origin` (the registered
  origin the token was issued for). `AnnotateWeb.Plugs.AnnotateAuth` rejects
  tokens whose `origin` claim differs from the request's Origin header or
  whose `site` claim differs from the site addressed by the path.

  Secret comes from `ANNOTATE_JWT_SECRET` (config `:annotate,
  Annotate.Auth.ApiToken`). Refresh tokens are opaque and live in
  `Annotate.Auth.RefreshTokens`, not in JWTs.
  """

  @access_ttl_seconds 15 * 60
  @type_typ "annotate_access"

  def secret do
    case Application.get_env(:annotate, __MODULE__, [])[:secret] do
      nil -> raise "Annotate.Auth.ApiToken secret not configured (ANNOTATE_JWT_SECRET)"
      secret -> secret
    end
  end

  def access_ttl, do: @access_ttl_seconds

  @doc "Signs an arbitrary claims map with HS256 and an `exp` `ttl` seconds out."
  def sign(claims, ttl_seconds) do
    now = System.system_time(:second)

    payload =
      claims
      |> Map.put("iat", now)
      |> Map.put("exp", now + ttl_seconds)

    jwk()
    |> JOSE.JWT.sign(%{"alg" => "HS256"}, payload)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  @doc """
  Verifies signature (HS256 only), expiry, and `typ`. Returns
  `{:ok, claims}` or `{:error, :invalid | :expired}`.
  """
  def verify(token) when is_binary(token) do
    # JOSE argument order is (jwk, signed) — the reverse raises/bounces to
    # {false, ...}-style failures that look like bad signatures.
    case JOSE.JWT.verify(jwk(), token) do
      {true, jwt, _jws} ->
        # JOSE's verify(jwk, signed) result does not reliably expose alg in
        # the returned structs — peek the (unauthenticated) header directly.
        alg = token_alg(token)
        claims = jwt.fields

        cond do
          alg != "HS256" -> {:error, :invalid}
          claims["typ"] != @type_typ -> {:error, :invalid}
          not is_integer(claims["exp"]) -> {:error, :invalid}
          claims["exp"] < System.system_time(:second) -> {:error, :expired}
          true -> {:ok, claims}
        end

      {false, _, _} ->
        {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end

  def verify(_), do: {:error, :invalid}

  @doc false
  # alg from the token's protected header (pre-verification peek; the sig is
  # still checked by JOSE before callers trust anything).
  def token_alg(token) when is_binary(token) do
    case String.split(token, ".", parts: 3) do
      [header_b64 | _] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, %{"alg" => alg}} -> alg
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  def token_alg(_), do: nil

  @doc "Issues an access token for a commenter on a site, bound to `origin`."
  def issue_access(commenter, site, origin) do
    sign(
      %{
        "sub" => commenter.id,
        "site" => site.id,
        "origin" => origin,
        "typ" => @type_typ
      },
      @access_ttl_seconds
    )
  end

  @doc """
  Issues an access token + a fresh rotating refresh token. `identity_claims`
  (see `Annotate.Embed.Policy.identity_claims/1`) are persisted on the refresh
  token so rotation can re-check the site's current `comment_policy`.
  """
  def issue_pair(commenter, site, origin, identity_claims \\ nil) do
    access = issue_access(commenter, site, origin)
    {:ok, refresh} = Annotate.Auth.RefreshTokens.issue(commenter, site, identity_claims, origin)
    {:ok, %{access_token: access, refresh_token: refresh}}
  end

  # The raw secret is hashed to a stable 32-byte oct key so any secret string
  # (any length/alphabet) yields a valid base64url JWK "k" for JOSE.
  defp jwk do
    key = :crypto.hash(:sha256, secret()) |> Base.url_encode64(padding: false)
    %{"kty" => "oct", "k" => key}
  end
end
