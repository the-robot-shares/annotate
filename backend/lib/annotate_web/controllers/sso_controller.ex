defmodule AnnotateWeb.SSOController do
  use AnnotateWeb, :controller

  # Ueberauth's request phase HALTS (302 to the IdP) before the controller
  # action runs, so the invite stash must happen in a plug declared BEFORE
  # `plug Ueberauth`. Anything in the `oauth_request/2` action body is dead
  # code on the request phase — it only runs if a configured strategy does
  # not redirect.
  plug :prepare_oauth when action in [:oauth_request]
  plug :ueberauth when action in [:oauth_request, :oauth_callback]

  alias Annotate.Guardian
  alias Annotate.Organizations

  # <REMOVED UUID HERE> providers :: auto-generated pointer for public function providers
  def providers(conn, _params) do
    providers =
      []
      |> maybe_add(:oidc_enabled, "oidc")
      |> maybe_add(:google_enabled, "google")
      |> maybe_add(:facebook_enabled, "facebook")
      |> maybe_add(:github_enabled, "github")
      |> maybe_add(:linkedin_enabled, "linkedin")
      |> maybe_add(:saml_enabled, "saml")

    json(conn, %{
      providers: providers,
      domains: Annotate.Auth.SSODomains.providers_map(),
      domain_policies: Annotate.Auth.SSODomains.public_policies(),
      # Register open, app gated: an invite is never required to sign up
      # (Annotate.Auth.InviteGate); kept for client compatibility.
      invite_required: false
    })
  end

  # ── OIDC ──────────────────────────────────────────────────────

  # <REMOVED UUID HERE> oidc_init :: auto-generated pointer for public function oidc_init
  def oidc_init(conn, params) do
    config = oidc_config()

    # `state` and `nonce` were both absent before this change, leaving the OIDC
    # flow open to login-CSRF - an attacker completing a flow so the victim is
    # signed in as the attacker - and to id_token replay. Both are checked in
    # `oidc_callback/2`. Ueberauth already does this for the social providers;
    # OIDC was the gap.
    state = random_token()
    nonce = random_token()

    {:ok, uri} =
      OpenIDConnect.authorization_uri(config, config.redirect_uri, %{
        state: state,
        nonce: nonce
      })

    conn
    |> put_session(:sso_state, state)
    |> put_session(:sso_nonce, nonce)
    |> stash_invite_token(params)
    |> redirect(external: uri)
  end

  # <REMOVED UUID HERE> oidc_callback :: auto-generated pointer for public function oidc_callback
  def oidc_callback(conn, %{"code" => code} = params) do
    expected_state = get_session(conn, :sso_state)
    expected_nonce = get_session(conn, :sso_nonce)

    # State is checked before anything else, including reading the provider
    # config: a forged callback is rejected without a token request, a discovery
    # fetch, or any other work done on an attacker's behalf.
    with :ok <- verify_state(expected_state, params["state"]),
         config <- oidc_config(),
         {:ok, tokens} <-
           OpenIDConnect.fetch_tokens(config, %{code: code, redirect_uri: config.redirect_uri}),
         {:ok, claims} <- OpenIDConnect.verify(config, tokens["id_token"]),
         :ok <- verify_nonce(expected_nonce, claims["nonce"]),
         {:ok, email} <- require_email(claims["email"]) do
      handle_sso_callback(conn, :oidc, %{
        email: email,
        name: %{first: claims["given_name"] || "", last: claims["family_name"] || ""},
        sub: claims["sub"],
        invite_token: take_stashed_invite(conn)
      })
    else
      {:error, :state_mismatch} -> redirect_with_error(conn, "state_mismatch")
      {:error, :no_email} -> redirect_with_error(conn, "oidc_no_email")
      _ -> redirect_with_error(conn, "oidc_failed")
    end
  end

  def oidc_callback(conn, _params) do
    redirect_with_error(conn, "oidc_failed")
  end

  # ── Social OAuth (Ueberauth) ──────────────────────────────────

  # <REMOVED UUID HERE> oauth_request :: auto-generated pointer for public function oauth_request
  # Reached only when a configured strategy does NOT redirect on its request
  # phase. All providers configured here (google/github/facebook) are OAuth
  # redirect strategies, so in practice Ueberauth halts before this runs; the
  # invite was already stashed by `prepare_oauth`. A 404 keeps a future
  # pass-through strategy from silently rendering nothing.
  # No usable provider configured (GitHub creds not deployed yet): skip the
  # Ueberauth plug entirely. In the OTP 29 / Elixir 1.20 release the runtime
  # `providers: []` value was observed as `""` (rpc, 2026-10-17), and
  # Ueberauth.init/1 then crashes (`Enum.flat_map("")`) → every /auth/:provider
  # 500'd. With no list of providers the request/callback actions below answer
  # "<provider>_not_configured" instead.
  defp ueberauth(conn, _opts) do
    case Application.get_env(:ueberauth, Ueberauth, [])[:providers] do
      [_ | _] -> run_ueberauth(conn)
      _ -> conn
    end
  end

  # A crash inside a strategy (token exchange / profile fetch: TLS, network,
  # provider API errors) must reach the visitor as the friendly
  # "<provider>_failed" page, never a 500. Logged WITHOUT the exception
  # message or conn: OAuth errors can carry the code, token or client secret.
  defp run_ueberauth(conn) do
    Ueberauth.call(conn, Ueberauth.init([]))
  rescue
    e ->
      require Logger

      Logger.error(
        "[sso] oauth strategy crashed: #{inspect(e.__struct__)} provider=#{inspect(conn.path_params["provider"])}"
      )

      conn
      |> Plug.Conn.assign(:ueberauth_failure, %Ueberauth.Failure{
        provider: conn.path_params["provider"],
        errors: [
          %Ueberauth.Failure.Error{
            message_key: "strategy_crash",
            message: "provider request failed"
          }
        ]
      })
  end

  def oauth_request(conn, %{"provider" => provider}) when provider in ["github", "google"],
    do: redirect_with_error(conn, "#{provider}_not_configured")

  def oauth_request(conn, _params), do: send_resp(conn, :not_found, "")

  # <REMOVED UUID HERE> oauth_callback :: auto-generated pointer for public function oauth_callback
  # GitHub = the dashboard's ONLY sign-in (Annotate.Auth.LoginMethods): a
  # dedicated path that keys on the GitHub numeric id and accepts only a
  # GitHub-VERIFIED email (Annotate.Dashboard.GithubLogin). It deliberately
  # bypasses the scaffold's email-linking SSO path below.
  def oauth_callback(%{assigns: %{ueberauth_auth: %{provider: provider} = auth}} = conn, _params)
      when provider in [:github, :google] do
    name = Atom.to_string(provider)
    # Read the invite carried through the OAuth round trip BEFORE the flow
    # cookie is cleared (`/auth/<provider>?invite=<token>` → prepare_oauth).
    invite_token = take_stashed_invite(conn)
    conn = clear_sso_session(conn)

    builder =
      if provider == :github,
        do: Annotate.Dashboard.GithubLogin,
        else: Annotate.Dashboard.GoogleLogin

    with {:ok, profile} <- builder.profile_from_auth(auth),
         {:ok, %{session: session} = result} <-
           Annotate.Dashboard.OAuthLogin.sign_in(profile, invite_token, conn) do
      {:ok, code} = Annotate.Auth.SSOCode.create(session.id)

      invite_note =
        case result.invite_error do
          nil -> ""
          reason -> "&invite_error=" <> URI.encode_www_form(to_string(reason))
        end

      redirect(conn,
        to: "/auth/sso-callback?code=#{URI.encode_www_form(code)}&provider=#{name}" <> invite_note
      )
    else
      {:error, :no_verified_email} ->
        redirect_with_error(conn, "#{name}_email_unverified")

      {:error, :account_disabled} ->
        redirect_with_error(conn, "account_disabled")

      {:error, :email_linked_to_other_account} ->
        redirect_with_error(conn, "#{name}_email_in_use")

      _ ->
        redirect_with_error(conn, "#{name}_failed")
    end
  end

  def oauth_callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    provider_type = auth.provider |> to_string() |> String.to_existing_atom()

    handle_sso_callback(conn, provider_type, %{
      email: auth.info.email,
      name: %{first: auth.info.first_name || "", last: auth.info.last_name || ""},
      uid: to_string(auth.uid),
      sub: to_string(auth.uid),
      invite_token: take_stashed_invite(conn)
    })
  end

  def oauth_callback(%{assigns: %{ueberauth_failure: _}} = conn, %{"provider" => provider}) do
    redirect_with_error(conn, "#{provider}_failed")
  end

  # Callback with no Ueberauth result: the provider is not configured.
  def oauth_callback(conn, %{"provider" => provider}) when provider in ["github", "google"],
    do: redirect_with_error(conn, "#{provider}_not_configured")

  def oauth_callback(conn, _params), do: send_resp(conn, :not_found, "")

  # ── Code Exchange ────────────────────────────────────────────

  # <REMOVED UUID HERE> exchange :: auto-generated pointer for public function exchange
  def exchange(conn, %{"code" => code}) do
    with {:ok, session_id} <- Annotate.Auth.SSOCode.exchange(code),
         {:ok, session} <- Annotate.Users.Sessions.get(session_id, Noizu.Context.system(), []),
         {:ok, access_token, _} <-
           Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour}),
         {:ok, refresh_token, %{"jti" => refresh_jti}} <-
           Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day}) do
      Annotate.Auth.TokenStore.store_refresh_jti(refresh_jti)
      user = resolve_user_from_session(session)
      orgs = Organizations.list_user_organizations(user.id)

      conn
      |> put_status(:ok)
      |> json(%{
        user: serialize_user(user),
        organizations: orgs,
        access_token: access_token,
        refresh_token: refresh_token
      })
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired SSO code"})
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp handle_sso_callback(conn, provider_type, attrs) do
    conn = clear_sso_session(conn)

    case Annotate.Auth.SSO.authenticate_sso(provider_type, attrs) do
      {:ok, session} ->
        {:ok, code} = Annotate.Auth.SSOCode.create(session.id)

        # Stay on this Phoenix/Hologram host (not a separate Next frontend).
        # Relative redirect so port/host match /auth/oidc/callback.
        redirect(conn,
          to: "/auth/sso-callback?code=#{URI.encode_www_form(code)}&provider=#{provider_type}"
        )

      {:error, :user_not_provisioned} ->
        redirect(conn, to: "/auth/sso-callback?error=not_provisioned")

      {:error, reason} when reason in [:invalid_token, :invite_exhausted] ->
        redirect(conn, to: "/auth/sso-callback?error=invalid_invite")

      {:error, :sso_not_allowed} ->
        redirect(conn, to: "/auth/sso-callback?error=sso_unavailable")

      {:error, _} ->
        redirect(conn, to: "/auth/sso-callback?error=sso_failed")
    end
  end

  defp redirect_with_error(conn, error) do
    conn
    |> clear_sso_session()
    |> redirect(to: "/auth/sso-callback?error=#{URI.encode_www_form(to_string(error))}")
  end

  # `state`/`nonce` are single-use: clearing them once a flow resolves (success
  # or failure) means a replayed callback with the same query string has
  # nothing left in the session to match against. The stashed invite token
  # rides the same lifecycle.
  defp clear_sso_session(conn) do
    conn
    |> delete_session(:sso_state)
    |> delete_session(:sso_nonce)
    |> delete_session(:sso_invite_token)
  end

  # Stashes the invite BEFORE `plug Ueberauth` runs: the request phase
  # redirects+halts (see Ueberauth.Strategies.Helpers.redirect!/2), so an
  # invite placed anywhere after it — including an action body — is dropped
  # before it reaches the IdP round-trip.
  defp prepare_oauth(conn, _opts), do: stash_invite_token(conn, conn.params)

  # An invite presented as `?invite=<raw token>` on the provider entry URL
  # (e.g. /auth/oidc?invite=... or /auth/github?invite=...) survives the
  # IdP redirect round-trip in the signed SSO session cookie. Never logged,
  # never echoed; consumed by the callback via take_stashed_invite/1.
  defp stash_invite_token(conn, params) do
    case params["invite"] do
      token when is_binary(token) and token != "" ->
        put_session(conn, :sso_invite_token, token)

      _ ->
        conn
    end
  end

  defp take_stashed_invite(conn) do
    get_session(conn, :sso_invite_token)
  end

  # Public (not `defp`) so `SSOStateNonceTest` can exercise the actual guard
  # directly - `nonce` is only checked after a real token exchange, which this
  # scaffold has no way to fake without a live/mocked IdP, so a unit test
  # against the real function is the only way to assert the rejection instead
  # of just its presence. Not part of the router surface; `@doc false` keeps
  # it out of generated docs.
  @doc false
  def verify_state(nil, _received), do: {:error, :state_mismatch}
  def verify_state(_expected, nil), do: {:error, :state_mismatch}

  def verify_state(expected, received) do
    if Plug.Crypto.secure_compare(expected, received),
      do: :ok,
      else: {:error, :state_mismatch}
  end

  # A provider that omits the nonce it was given is not proof of replay, but a
  # provider that returns a DIFFERENT one is.
  @doc false
  def verify_nonce(_expected, nil), do: :ok
  def verify_nonce(nil, _received), do: :ok

  def verify_nonce(expected, received) do
    if Plug.Crypto.secure_compare(expected, received), do: :ok, else: {:error, :nonce_mismatch}
  end

  # An ID token with no email claim (or a blank one) carries no identity we can
  # provision against; without this check `authenticate_sso/2` crashes on
  # `String.trim(nil)` and the callback 500s instead of redirecting.
  defp require_email(nil), do: {:error, :no_email}

  defp require_email(email) when is_binary(email) do
    if String.trim(email) == "", do: {:error, :no_email}, else: {:ok, email}
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp oidc_config do
    :openid_connect
    |> Application.fetch_env!(:providers)
    |> Keyword.fetch!(:default)
    |> Map.new()
  end

  defp resolve_user_from_session(%Annotate.Users.Sessions.UserSession{} = session) do
    case session.user do
      {:ref, _, id} ->
        {:ok, user} = Annotate.Users.get_user(id, Noizu.Context.system())
        user

      %Annotate.Users.User{} = user ->
        user
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      user_name: user.user_name,
      handle: user.handle,
      mobile_phone: Map.get(user, :mobile_phone),
      status: user.status,
      verified: user.verified,
      profile_completed_at: Map.get(user, :profile_completed_at),
      profile_complete: !!Map.get(user, :profile_completed_at),
      requires_profile_completion: !Map.get(user, :profile_completed_at),
      invite_required: Annotate.Auth.InviteGate.required?(user)
    }
  end

  defp maybe_add(list, flag, name) do
    if Application.get_env(:annotate, flag) and Annotate.Auth.LoginMethods.enabled?(name),
      do: [name | list],
      else: list
  end
end
