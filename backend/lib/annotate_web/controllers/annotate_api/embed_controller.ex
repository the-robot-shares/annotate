defmodule AnnotateWeb.AnnotateAPI.EmbedController do
  @moduledoc """
  Popup auth broker for the embeddable widget.

  - `GET /embed/login?site=<slug>&origin=<origin>[&provider=sso|github|google]`
    — validates the origin against `sites.allowed_origins`, then:

      * `sso` (default): stashes (site, origin, nonce, state) in the signed
        session and redirects to Authentik OIDC;
      * `github` / `google`: stashes (site, origin, provider, state) and
        redirects to the SAME ueberauth request phase the dashboard uses
        (`/auth/<provider>?via=embed`) — the dashboard's OAuth clients, its
        profile builders and its session machinery are reused; only the
        landing differs (below).

  - `GET /embed/callback` — exchanges the code server-side, enforces
    `comment_policy`, upserts the commenter by `authentik_sub`, then renders a
    tiny HTML page that postMessages the token pair to the registered origin
    (exactly) and closes. Policy failures postMessage
    `{type: "annotate-auth-error", reason}`.
  - `social_callback/3` — the github/google leg's landing: reached from
    `SSOController.oauth_callback/2` when the session carries the embed
    social context. Builds the SAME profile the dashboard would
    (`GithubLogin`/`GoogleLogin.profile_from_auth/1` — verified email only),
    enforces `comment_policy`, upserts a site-scoped commenter keyed
    `"provider:uid"` (`Sites.upsert_commenter_by_social/4`) and mints the
    embed COMMENTER token pair — never a dashboard session. Rendering reuses
    the popup postMessage contract (`PopupPayload`).

  Only an IdP the site's policy accepts can mint tokens: github/google have
  no group claims, so a policy with `required_groups` can only be satisfied
  via `sso`.
  """
  use AnnotateWeb, :controller

  require Logger

  alias Annotate.Auth.ApiToken
  alias Annotate.Embed.OIDC
  alias Annotate.Embed.Policy
  alias Annotate.Sites
  alias AnnotateWeb.AnnotateAPI.PopupPayload

  @state_session_key "embed_state"
  # github/google popup leg: stashed at /embed/login, consumed at the
  # ueberauth callback (SSOController) — armed/cleared via the `embed_via`
  # session key set by the same controller's `prepare_oauth` plug.
  @social_session_key "embed_social"

  @providers ~w(sso github google)

  # IdP error redirects (user denied consent at Authentik etc.) postMessage one
  # of these stable reasons; anything unmapped collapses to "auth_failed".
  @idp_error_reasons ["access_denied"]

  def login(conn, %{"site" => slug, "origin" => origin} = params) do
    provider = normalize_provider(params["provider"])
    site = Sites.get_site_by_slug(slug)

    cond do
      is_nil(site) ->
        conn |> put_status(:not_found) |> json(%{"error" => "site_not_found"})

      not Sites.allowed_origin?(site, origin) ->
        conn |> put_status(:forbidden) |> json(%{"error" => "origin_not_allowed"})

      provider == :invalid ->
        conn |> put_status(:bad_request) |> json(%{"error" => "invalid_provider"})

      provider == :sso and not OIDC.configured?() ->
        conn |> put_status(:service_unavailable) |> json(%{"error" => "oidc_not_configured"})

      provider != :sso and not social_enabled?(provider) ->
        conn |> put_status(:service_unavailable) |> json(%{"error" => "provider_not_configured"})

      true ->
        start_login(conn, provider, site, origin)
    end
  end

  def login(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "site_and_origin_required"})
  end

  defp start_login(conn, :sso, site, origin) do
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

  # github/google: hand the round trip to the dashboard's ueberauth machinery
  # (its strategies validate the provider-side state); the signed-session
  # stash below binds the callback back to THIS popup (site + origin), and
  # SSOController arms/clears `embed_via` so a dashboard sign-in can never be
  # mistaken for the popup leg.
  defp start_login(conn, provider, site, origin) do
    conn
    |> put_session(@social_session_key, %{
      "provider" => Atom.to_string(provider),
      "site_id" => site.id,
      "origin" => origin,
      "state" => random_token()
    })
    |> redirect(external: "/auth/#{provider}?via=embed")
  end

  # ── github/google landing (from SSOController.oauth_callback/2) ──

  @doc false
  def social_callback(conn, st, auth) do
    provider = st["provider"]
    site = st["site_id"] && Sites.get_site(st["site_id"])

    # Same defense-in-depth as the OIDC exchange: a raise anywhere below must
    # reach the widget as the error postMessage, never an opaque 500.
    try do
      with %{} = site <- site,
           :ok <- verify_provider(provider, auth),
           {:ok, profile} <- social_builder(provider).profile_from_auth(auth),
           claims = Policy.identity_claims(%{"email" => profile.email}),
           :ok <- Policy.check(claims, site.comment_policy || %{}),
           {:ok, commenter} <- Sites.upsert_commenter_by_social(site, provider, profile.uid, profile),
           {:ok, %{access_token: access, refresh_token: refresh}} <-
             ApiToken.issue_pair(commenter, site, st["origin"], claims, :bridge) do
        render_postmessage(conn, PopupPayload.success(access, refresh, commenter), st["origin"])
      else
        {:error, :no_verified_email} ->
          render_error(conn, "email_unverified", st["origin"])

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
    rescue
      e ->
        Logger.warning(
          "[embed] social callback failed, rendering auth_failed: " <>
            redact(Exception.format(:error, e, __STACKTRACE__))
        )

        render_error(conn, "auth_failed", st["origin"])
    end
  end

  # A callback from a DIFFERENT provider than the popup started (stale
  # context) must never mint tokens for the wrong identity/site.
  defp verify_provider(provider, %{provider: p}) when is_atom(p),
    do: if(Atom.to_string(p) == provider, do: :ok, else: {:error, :provider_mismatch})

  defp verify_provider(_, _), do: {:error, :provider_mismatch}

  defp social_builder("github"), do: Annotate.Dashboard.GithubLogin
  defp social_builder("google"), do: Annotate.Dashboard.GoogleLogin

  defp normalize_provider(nil), do: :sso
  defp normalize_provider(p) when p in @providers, do: String.to_existing_atom(p)
  defp normalize_provider(_), do: :invalid

  defp social_enabled?(:github),
    do: Application.get_env(:annotate, :github_enabled, false) == true

  defp social_enabled?(:google),
    do: Application.get_env(:annotate, :google_enabled, false) == true

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

  # Public for the social leg: SSOController's ueberauth-failure branch
  # renders the SAME popup error postMessage (shared PopupPayload contract).
  @doc false
  def render_error(conn, reason, origin) do
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
