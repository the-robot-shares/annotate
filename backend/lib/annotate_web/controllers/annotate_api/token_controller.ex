defmodule AnnotateWeb.AnnotateAPI.TokenController do
  @moduledoc """
  Token issuance endpoints:

  - `POST /api/v1/token/refresh` — rotating refresh (opaque token, hashed at
    rest, 30-day TTL; reuse of a rotated token fails). The site's CURRENT
    `comment_policy` is re-checked against the identity captured at issuance;
    on failure the presented token is revoked → `403 policy_violation`.
  - `POST /api/v1/sites/:site/token/assert` — host-asserted identity: a JWT
    signed HS256 with the site's SERVICE KEY (claims `sub`, `name`, `email?`,
    `avatar?`, `groups?`, `exp` ≤ 5 min). The site's `comment_policy` is
    enforced (`allowed_email_domains` against the asserted email,
    `required_groups` against the optional `groups` claim) before an
    access/refresh pair is issued for the `(site_id, external_id)` commenter.
  """
  use AnnotateWeb, :controller

  alias Annotate.Auth.ApiToken
  alias Annotate.Auth.RefreshTokens
  alias Annotate.Auth.ServiceKey
  alias Annotate.Embed.Policy
  alias Annotate.Sites
  alias AnnotateWeb.AnnotateAPI.Renderer

  @host_assert_max_skew_seconds 5 * 60

  def refresh(conn, %{"refresh_token" => raw}) do
    # The access token's `origin` is the REQUEST Origin, which `rotate/2` has
    # already proven is in the site's allowed_origins and matches the origin
    # the refresh token was issued for. Missing/forged Origin → 401.
    request_origin =
      case get_req_header(conn, "origin") do
        [origin | _] -> origin
        [] -> nil
      end

    case RefreshTokens.rotate(raw, request_origin) do
      {:ok, %{commenter: commenter, site: site, refresh_token: fresh}} ->
        access = ApiToken.issue_access(commenter, site, request_origin)

        json(conn, %{
          "access_token" => access,
          "refresh_token" => fresh,
          "commenter" => Renderer.commenter(commenter)
        })

      {:error, :policy} ->
        conn |> put_status(:forbidden) |> json(%{"error" => "policy_violation"})

      {:error, :origin} ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "origin_mismatch"})

      {:error, :invalid} ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "invalid_refresh_token"})
    end
  end

  def refresh(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "refresh_token_required"})
  end

  def host_assert(conn, %{"token" => token}) do
    site = conn.assigns[:annotate_site] || Sites.get_site_by_slug(conn.params["site"])

    with %{} = site <- site || {:error, :site_not_found},
         {:ok, service_key} <- decrypt_key(site),
         {:ok, claims} <- verify_host_assert(service_key, token),
         # comment_policy applies to host-asserted identities too: the email
         # domain rule reads the asserted email, required_groups the optional
         # `groups` claim.
         :ok <- Policy.check(claims, site.comment_policy || %{}),
         {:ok, commenter} <- Sites.upsert_commenter_by_external(site, claims["sub"], claims) do
      origin = claims_origin(conn, site)

      case ApiToken.issue_pair(commenter, site, origin, Policy.identity_claims(claims)) do
        {:ok, %{access_token: access, refresh_token: refresh}} ->
          conn
          |> put_status(:created)
          |> json(%{
            "access_token" => access,
            "refresh_token" => refresh,
            "commenter" => Renderer.commenter(commenter)
          })
      end
    else
      {:error, :site_not_found} ->
        conn |> put_status(:not_found) |> json(%{"error" => "site_not_found"})

      {:error, :no_service_key} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "service_key_not_configured"})

      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "invalid_assertion"})

      {:error, :expired} ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "expired_assertion"})

      {:error, :missing_sub} ->
        conn |> put_status(:unprocessable_entity) |> json(%{"error" => "sub_required"})

      {:error, :exp_too_far} ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "exp_window_exceeded"})

      {:error, policy_reason}
      when policy_reason in [:group_not_allowed, :email_domain_not_allowed] ->
        conn |> put_status(:forbidden) |> json(%{"error" => to_string(policy_reason)})
    end
  end

  def host_assert(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "token_required"})
  end

  # ── Host-assert verification ─────────────────────────────────

  defp decrypt_key(site) do
    case ServiceKey.decrypt(site.service_key_encrypted) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :no_service_key}
    end
  end

  @doc false
  def verify_host_assert(service_key, token) do
    jwk = %{
      "kty" => "oct",
      "k" => Base.url_encode64(:crypto.hash(:sha256, service_key), padding: false)
    }

    with {true, jwt, _jws} <- JOSE.JWT.verify(jwk, token),
         "HS256" <- ApiToken.token_alg(token),
         claims = jwt.fields,
         true <- (is_binary(claims["sub"]) && claims["sub"] != "") || {:error, :missing_sub},
         :ok <- check_exp_window(claims) do
      {:ok, claims}
    else
      {false, _, _} ->
        {:error, :invalid_token}

      alg when is_binary(alg) ->
        {:error, :invalid_token}

      {:error, reason} when reason in [:missing_sub, :exp_too_far, :expired, :invalid_token] ->
        {:error, reason}

      false ->
        {:error, :missing_sub}

      _ ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  defp check_exp_window(%{"exp" => exp}) when is_integer(exp) do
    now = System.system_time(:second)

    cond do
      exp < now -> {:error, :expired}
      exp - now > @host_assert_max_skew_seconds -> {:error, :exp_too_far}
      true -> :ok
    end
  end

  defp check_exp_window(_), do: {:error, :invalid_token}

  # host_assert is authenticated by the site's service key (server-to-server,
  # normally Origin-less). A PRESENTED Origin must still be on the allowlist;
  # otherwise fall back to the site's first registered origin, never echo an
  # arbitrary header into a token claim.
  defp claims_origin(conn, site) do
    case get_req_header(conn, "origin") do
      [origin | _] when is_binary(origin) ->
        if site && Sites.allowed_origin?(site, origin), do: origin, else: default_origin(site)

      [] ->
        default_origin(site)
    end
  end

  defp default_origin(site) do
    case site && site.allowed_origins do
      [first | _] when is_binary(first) -> first
      _ -> "unknown"
    end
  end
end
