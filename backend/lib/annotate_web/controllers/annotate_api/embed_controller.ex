defmodule AnnotateWeb.AnnotateAPI.EmbedController do
  @moduledoc """
  Popup auth broker for the embeddable widget.

  - `GET /embed/login?site=<slug>&origin=<origin>` — validates the origin
    against `sites.allowed_origins`, stashes (site, origin, nonce, state) in
    the signed session, and redirects to Authentik OIDC.
  - `GET /embed/callback` — exchanges the code server-side, enforces
    `comment_policy`, upserts the commenter by `authentik_sub`, then renders a
    tiny HTML page that postMessages the token pair to the registered origin
    (exactly) and closes. Policy failures postMessage
    `{type: "annotate-auth-error", reason}`.
  """
  use AnnotateWeb, :controller

  alias Annotate.Auth.ApiToken
  alias Annotate.Embed.OIDC
  alias Annotate.Embed.Policy
  alias Annotate.Sites

  @state_session_key "embed_state"

  def login(conn, %{"site" => slug, "origin" => origin}) do
    site = Sites.get_site_by_slug(slug)

    cond do
      is_nil(site) ->
        conn |> put_status(:not_found) |> json(%{"error" => "site_not_found"})

      not Sites.allowed_origin?(site, origin) ->
        conn |> put_status(:forbidden) |> json(%{"error" => "origin_not_allowed"})

      not OIDC.configured?() ->
        conn |> put_status(:service_unavailable) |> json(%{"error" => "oidc_not_configured"})

      true ->
        state = random_token()
        nonce = random_token()

        case OIDC.authorization_uri(%{"state" => state, "nonce" => nonce}) do
          {:ok, uri} ->
            conn
            |> put_session(@state_session_key, %{
              "site_id" => site.id,
              "origin" => origin,
              "state" => state,
              "nonce" => nonce
            })
            |> redirect(external: uri)

          {:error, _} ->
            conn |> put_status(:bad_gateway) |> json(%{"error" => "oidc_unavailable"})
        end
    end
  end

  def login(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "site_and_origin_required"})
  end

  def callback(conn, %{"code" => code} = params) do
    st = get_session(conn, @state_session_key) || %{}
    conn = put_session(conn, @state_session_key, nil)

    site = st["site_id"] && Sites.get_site(st["site_id"])

    with :ok <- verify_state(st["state"], params["state"]),
         %{} = site <- site,
         {:ok, tokens} <-
           OIDC.fetch_tokens(%{"code" => code, "redirect_uri" => OIDC.config().redirect_uri}),
         {:ok, claims} <- OIDC.verify(tokens["id_token"]),
         :ok <- verify_nonce(st["nonce"], claims["nonce"]),
         :ok <- Policy.check(claims, site.comment_policy || %{}),
         {:ok, commenter} <- Sites.upsert_commenter_by_sub(site, claims),
         {:ok, %{access_token: access, refresh_token: refresh}} =
           ApiToken.issue_pair(commenter, site, st["origin"], Policy.identity_claims(claims)) do
      render_postmessage(
        conn,
        %{
          "type" => "annotate-auth",
          "access" => access,
          "refresh" => refresh,
          "commenter" => commenter.id,
          "display_name" => commenter.display_name
        },
        st["origin"]
      )
    else
      {:error, :state_mismatch} ->
        render_error(conn, "state_mismatch", st["origin"])

      {:error, :nonce_mismatch} ->
        render_error(conn, "nonce_mismatch", st["origin"])

      {:error, :group_not_allowed} ->
        render_error(conn, "group_not_allowed", st["origin"])

      {:error, :email_domain_not_allowed} ->
        render_error(conn, "email_domain_not_allowed", st["origin"])

      {:error, _} ->
        render_error(conn, "auth_failed", st["origin"])

      nil ->
        render_error(conn, "unknown_session", st["origin"])

      _ ->
        render_error(conn, "auth_failed", st["origin"])
    end
  end

  def callback(conn, _params) do
    render_error(conn, "auth_failed", nil)
  end

  # ── Helpers ──────────────────────────────────────────────────

  # Public for tests (same rationale as SSOController.verify_state).
  @doc false
  def verify_state(nil, _received), do: {:error, :state_mismatch}
  def verify_state(_expected, nil), do: {:error, :state_mismatch}

  def verify_state(expected, received) do
    if Plug.Crypto.secure_compare(expected, received), do: :ok, else: {:error, :state_mismatch}
  end

  # Fail closed: a nonce from the session AND a nonce from the id token must
  # both be present and match. Either side nil → mismatch (a missing claim
  # must not bypass replay protection).
  @doc false
  def verify_nonce(expected, received) when is_binary(expected) and is_binary(received) do
    if Plug.Crypto.secure_compare(expected, received), do: :ok, else: {:error, :nonce_mismatch}
  end

  def verify_nonce(_expected, _received), do: {:error, :nonce_mismatch}

  defp render_postmessage(conn, payload, origin) do
    send_html(conn, postmessage_body(Jason.encode!(payload), origin))
  end

  defp render_error(conn, reason, origin) do
    send_html(
      conn,
      postmessage_body(
        "{type: \"annotate-auth-error\", reason: " <> Jason.encode!(reason) <> "}",
        origin
      )
    )
  end

  defp postmessage_body(encoded_payload, origin) do
    """
    <!doctype html><html><body><script>
    (function(){
      var payload = #{encoded_payload};
      var origin = #{Jason.encode!(origin || "")};
      if (window.opener && origin) { window.opener.postMessage(payload, origin); }
      window.close();
    })();
    </script></body></html>
    """
  end

  # Plain Plug send (Phoenix's html/2 macro cannot be composed here).
  defp send_html(conn, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, body)
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
