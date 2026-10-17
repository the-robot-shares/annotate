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

  require Logger

  alias Annotate.Auth.ApiToken
  alias Annotate.Embed.OIDC
  alias Annotate.Embed.Policy
  alias Annotate.Sites

  @state_session_key "embed_state"

  # IdP error redirects (user denied consent at Authentik etc.) postMessage one
  # of these stable reasons; anything unmapped collapses to "auth_failed".
  @idp_error_reasons ["access_denied"]

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

        case OIDC.authorization_uri(%{state: state, nonce: nonce}) do
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

  # IdP error redirect (no code): verify state first so an attacker cannot use
  # this leg to probe, then surface the (allowlisted) reason to the widget.
  def callback(conn, %{"error" => idp_error} = params) do
    st = get_session(conn, @state_session_key) || %{}
    conn = put_session(conn, @state_session_key, nil)

    with :ok <- verify_state(st["state"], params["state"]) do
      reason = if idp_error in @idp_error_reasons, do: idp_error, else: "auth_failed"
      Logger.warning("[embed] callback IdP error, reason=#{inspect(reason)}")
      render_error(conn, reason, st["origin"])
    else
      {:error, :state_mismatch} ->
        render_error(conn, "state_mismatch", st["origin"])
    end
  end

  def callback(conn, %{"code" => code} = params) do
    st = get_session(conn, @state_session_key) || %{}
    conn = put_session(conn, @state_session_key, nil)

    with :ok <- verify_state(st["state"], params["state"]) do
      # Defense-in-depth: any unexpected raise below (library crash, DB error)
      # must surface as the widget error postMessage — never an opaque 500.
      # The prod incident this guards: OpenIDConnect.fetch_tokens/2 raised
      # BadMapError mid-exchange (2026-10-16).
      try do
        exchange(conn, code, st)
      rescue
        e ->
          Logger.warning(
            "[embed] callback exchange failed, rendering auth_failed: " <>
              redact(Exception.format(:error, e, __STACKTRACE__))
          )

          render_error(conn, "auth_failed", st["origin"])
      end
    else
      {:error, :state_mismatch} ->
        render_error(conn, "state_mismatch", st["origin"])
    end
  end

  def callback(conn, _params) do
    render_error(conn, "auth_failed", nil)
  end

  # Runs after the state check: code exchange → claim verification → policy →
  # token mint → postMessage page. Error tuples render the widget error page
  # with a stable reason; nothing here should ever escape as a 500.
  defp exchange(conn, code, st) do
    site = st["site_id"] && Sites.get_site(st["site_id"])

    with %{} = site <- site,
         {:ok, tokens} <-
           OIDC.fetch_tokens(%{"code" => code, "redirect_uri" => OIDC.config().redirect_uri}),
         {:ok, claims} <- OIDC.verify(tokens["id_token"]),
         :ok <- verify_nonce(st["nonce"], claims["nonce"]),
         :ok <- Policy.check(claims, site.comment_policy || %{}),
         {:ok, commenter} <- Sites.upsert_commenter_by_sub(site, claims),
         {:ok, %{access_token: access, refresh_token: refresh}} =
           ApiToken.issue_pair(
             commenter,
             site,
             st["origin"],
             Policy.identity_claims(claims),
             :bridge
           ) do
      render_postmessage(
        conn,
        AnnotateWeb.AnnotateAPI.PopupPayload.success(access, refresh, commenter),
        st["origin"]
      )
    else
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
    # html_safe: escapes "/" (and U+2028/9) so a display name can never
    # close the inline <script> (T-07).
    send_html(conn, postmessage_body(Jason.encode!(payload, escape: :html_safe), origin))
  end

  defp render_error(conn, reason, origin) do
    send_html(
      conn,
      postmessage_body(
        Jason.encode!(AnnotateWeb.AnnotateAPI.PopupPayload.error(to_string(reason)),
          escape: :html_safe
        ),
        origin
      )
    )
  end

  defp postmessage_body(encoded_payload, origin) do
    # Visible fallback text: the popup is transient, but when the postMessage/
    # close dance cannot run (no opener, JS disabled, popup blocked from
    # closing) the user must not be left staring at a blank page.
    """
    <!doctype html><html><body style="font-family:system-ui,sans-serif;padding:2rem;text-align:center">
    <p id="msg">Signing you in&hellip;</p>
    <script>
    (function(){
      var payload = #{encoded_payload};
      var origin = #{Jason.encode!(origin || "")};
      var sent = false;
      if (window.opener && origin) { window.opener.postMessage(payload, origin); sent = true; }
      var msg = document.getElementById("msg");
      if (msg) { msg.textContent = sent ? "Signed in — you can close this window." : "Sign-in could not complete. Please close this window and try again."; }
      window.close();
    })();
    </script></body></html>
    """
  end

  # Token-shaped strings (one-time codes, states, nonces, JWTs) must never
  # reach the logs: library exceptions interpolate request params — the
  # BadMapError behind the 2026-10-16 prod 500 printed the authorization code
  # verbatim. Collapse any long urlsafe token to a marker before logging.
  defp redact(text) do
    String.replace(text, ~r/[A-Za-z0-9_\-]{20,}/, "[redacted]")
  end

  # Plain Plug send (Phoenix's html/2 macro cannot be composed here).
  defp send_html(conn, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, body)
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
