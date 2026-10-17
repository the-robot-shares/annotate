defmodule Annotate.Hologram.Auth do
  @moduledoc """
  Server-side auth helpers for Hologram pages/commands.

  Tokens live in the Hologram session (cookie-backed). The JSON API continues to
  use Bearer tokens; this module bridges the same Guardian session model into
  Hologram `init/3` and `command/3` handlers.
  """

  alias Annotate.Guardian
  alias Annotate.Organizations

  @access_ttl {1, :hour}
  @refresh_ttl {7, :day}

  @type user_map :: map()
  @type org_map :: map()

  @doc "Current serialized user from the Hologram session, or nil."
  # <REMOVED UUID HERE> current_user :: Current serialized user from the Hologram session, or nil.
  def current_user(server) do
    case load_session_user(server) do
      {:ok, user, _orgs} -> serialize_user(user)
      _ -> nil
    end
  end

  @doc "Current user + organizations from the Hologram session."
  # <REMOVED UUID HERE> current_user_and_orgs :: Current user + organizations from the Hologram session.
  def current_user_and_orgs(server) do
    case load_session_user(server) do
      {:ok, user, orgs} -> {serialize_user(user), orgs}
      _ -> {nil, []}
    end
  end

  @doc "Authenticate with email/password and write tokens into the Hologram session."
  # <REMOVED UUID HERE> login :: Authenticate with email/password and write tokens into the Hologram session.
  def login(server, email, password) do
    if Annotate.Auth.LoginMethods.password_enabled?(),
      do: password_login(server, email, password),
      else: {:error, "Email sign-in is disabled. Sign in with GitHub."}
  end

  defp password_login(server, email, password) do
    case Annotate.Users.Credentials.authenticate(
           {:login, {email, password}},
           Noizu.Context.system(),
           []
         ) do
      {:ok, session} ->
        issue_tokens(server, session)

      {:error, :invalid_credentials} ->
        {:error, "Invalid email or password"}

      {:error, {:login, :invalid_credentials}} ->
        {:error, "Invalid email or password"}

      {:error, :invalid_email} ->
        {:error, "Invalid email format"}

      {:error, :invalid_password} ->
        {:error, "Password too short"}

      {:error, :pending_approval} ->
        {:error, "Account is pending approval"}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  @doc """
  Register a password user and issue tokens on success. Register open, app
  gated: a missing invite never fails signup — the status comes from
  `Annotate.Auth.InviteGate.signup_status/3` and a gated account is routed to
  `/auth/invite-required` by `post_auth_path/1`. A supplied but invalid invite
  fails and writes nothing.
  """
  # <REMOVED UUID HERE> register :: Register a password user and issue tokens on success.
  def register(server, attrs) when is_map(attrs) do
    if Annotate.Auth.LoginMethods.password_enabled?(),
      do: password_register(server, attrs),
      else: {:error, "Email sign-up is disabled. Sign up with GitHub."}
  end

  defp password_register(server, attrs) do
    email = Map.get(attrs, :email) || Map.get(attrs, "email")
    password = Map.get(attrs, :password) || Map.get(attrs, "password")
    raw_token = optional_string(Map.get(attrs, :invite_token) || Map.get(attrs, "invite_token"))

    user_name = Map.get(attrs, :user_name) || Map.get(attrs, "user_name") || email
    first_name = Map.get(attrs, :first_name) || Map.get(attrs, "first_name") || ""
    last_name = Map.get(attrs, :last_name) || Map.get(attrs, "last_name") || ""
    mobile_phone = Map.get(attrs, :mobile_phone) || Map.get(attrs, "mobile_phone")

    with {:ok, invite} <- resolve_invite(raw_token, email),
         status = Annotate.Auth.InviteGate.signup_status(email, nil, invite),
         {:ok, user} <-
           Annotate.Auth.Registration.register_user_with_invite(
             %{
               user_name: user_name,
               name: %{first: first_name, last: last_name},
               email: email,
               password: password,
               mobile_phone: mobile_phone,
               invite_token_id: invite && invite.id,
               status: status,
               profile_completed_at: profile_completed_at(attrs)
             },
             {:login, {email, password}},
             [
               status: status,
               invite_token_id: invite && invite.id,
               mobile_phone: mobile_phone,
               profile_completed_at: profile_completed_at(attrs)
             ],
             invite
           ),
         {:ok, session} <- create_session_for_user(user) do
      Annotate.Events.dispatch(:user_registered, %{user_id: user.id, email: user.email})
      Annotate.Auth.InviteGate.after_signup(user)

      issue_tokens(server, session)
    else
      {:error, :invalid_token} ->
        {:error, "Invalid or expired invite token"}

      {:error, :invite_exhausted} ->
        {:error, "That invite has already been used"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_changeset_errors(changeset)}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  @doc "Clear auth tokens from the Hologram session."
  # <REMOVED UUID HERE> logout :: Clear auth tokens from the Hologram session.
  def logout(server) do
    server
    |> Hologram.Server.delete_session(:access_token)
    |> Hologram.Server.delete_session(:refresh_token)
    |> Hologram.Server.delete_user_id()
  end

  @invite_required_path "/auth/invite-required"

  @doc "The invite interstitial path (PATTERN.md `INVITE_REQUIRED_PATH`)."
  def invite_required_path, do: @invite_required_path

  @doc """
  True when the serialized user must stay at the invite interstitial. The
  server-computed `invite_required` flag is authoritative (admin and
  general-release exemptions applied); a map without it falls back to the
  gated statuses. Runs client-side too (transpiled), so plain map access only.
  """
  def user_needs_invite?(user) when is_map(user) do
    case Map.get(user, :invite_required) do
      flag when is_boolean(flag) ->
        flag

      _ ->
        Map.get(user, :status) in [
          :pending,
          :waitlist,
          :unverified,
          "pending",
          "waitlist",
          "unverified"
        ]
    end
  end

  def user_needs_invite?(_), do: false

  @doc """
  Post-auth destination after login / SSO / magic link / signup.

  - held by the invite gate → `/auth/invite-required`
  - otherwise → `/app` (dashboard)

  Profile completion is optional (prompted from the dashboard checklist).
  """
  # <REMOVED UUID HERE> post_auth_path :: Post-auth destination after login / SSO / magic link.
  def post_auth_path(user) when is_map(user) do
    if user_needs_invite?(user), do: @invite_required_path, else: default_post_auth_path()
  end

  def post_auth_path(_), do: default_post_auth_path()

  # annotate lands owners on /dashboard (config :annotate, :post_auth_path).
  defp default_post_auth_path, do: Application.get_env(:annotate, :post_auth_path, "/app")

  @doc """
  Redeem an invite for the signed-in Hologram user. Hologram commands bypass
  the router's rate-limit pipeline, so the same Hammer guard the REST redeem
  route gets (5/min per IP) is applied here.

  Returns `{:ok, serialized_user}` or `{:error, code}` with `code` one of
  `"invalid"`, `"used"`, `"rate_limited"`, `"unauthenticated"`, `"empty"`,
  `"failure"` (the `<noizu-invite-gate>` error codes).
  """
  def redeem_invite(server, raw_token, ip \\ nil) do
    token = optional_string(raw_token)
    ip = ip || Map.get(server, :ip) || "unknown"

    with {:token, token} when is_binary(token) <- {:token, token},
         {:allow, _} <- Hammer.check_rate("invite_redeem:#{inspect(ip)}", 60_000, 5),
         {:ok, user, _orgs} <- load_session_user(server),
         {:ok, _invite} <- Annotate.Auth.InviteGate.redeem(user, token) do
      {:ok, user} = Annotate.Users.get_user(user.id, Noizu.Context.system())
      {:ok, serialize_user(user)}
    else
      {:token, _} -> {:error, "empty"}
      {:deny, _} -> {:error, "rate_limited"}
      :error -> {:error, "unauthenticated"}
      {:error, :invalid_token} -> {:error, "invalid"}
      {:error, :invite_exhausted} -> {:error, "used"}
      _ -> {:error, "failure"}
    end
  end

  @doc "User-facing copy for a failed redeem (PATTERN.md `inviteRedeemErrorMessage`)."
  def invite_error_message("invalid"),
    do: "That invite code is invalid or has expired. Check it and try again."

  def invite_error_message("used"), do: "That invite code has already been used."
  def invite_error_message("rate_limited"), do: "Too many attempts. Wait a minute and try again."

  def invite_error_message("unauthenticated"),
    do: "Your session has ended. Log in again to redeem your invite."

  def invite_error_message("empty"), do: "Enter your invite code."
  def invite_error_message(_), do: "Could not redeem the invite. Try again."

  @doc """
  Re-send the email confirmation link for the signed-in user. Only meaningful
  for an `:unverified` account (password signup on an auto-approve domain): a
  `:pending` account is unlocked by an invite, not by confirming its email,
  so those resends are refused instead of mailed. Rate-limited like the REST
  magic-link routes.
  """
  def resend_confirmation(server) do
    ip = Map.get(server, :ip) || "unknown"

    with {:allow, _} <- Hammer.check_rate("verify_resend:#{inspect(ip)}", 60_000, 5),
         {:ok, user, _orgs} <- load_session_user(server),
         :ok <- ensure_resendable(user) do
      Annotate.Auth.InviteGate.after_signup(%{status: :unverified, email: user.email})
      :ok
    else
      {:deny, _} -> {:error, "rate_limited"}
      {:error, "not_unverified"} -> {:error, "not_unverified"}
      _ -> {:error, "unauthenticated"}
    end
  end

  defp ensure_resendable(%{status: status}) when status in [:unverified, "unverified"], do: :ok
  defp ensure_resendable(_user), do: {:error, "not_unverified"}

  @doc "SSO providers enabled for this deployment + domain policies."
  # <REMOVED UUID HERE> sso_catalog :: SSO providers enabled for this deployment + domain policies.
  def sso_catalog do
    providers =
      []
      |> maybe_add(:oidc_enabled, "oidc")
      |> maybe_add(:google_enabled, "google")
      |> maybe_add(:facebook_enabled, "facebook")
      |> maybe_add(:github_enabled, "github")
      |> maybe_add(:linkedin_enabled, "linkedin")
      |> maybe_add(:saml_enabled, "saml")

    %{
      providers: providers,
      domains: Annotate.Auth.SSODomains.providers_map(),
      domain_policies: Annotate.Auth.SSODomains.public_policies(),
      # Register open, app gated: the signup invite field is always optional.
      invite_required: false
    }
  end

  @doc "Providers that match an email domain and are enabled."
  # <REMOVED UUID HERE> matching_sso_providers :: Providers that match an email domain and are enabled.
  def matching_sso_providers(email, catalog \\ nil) do
    catalog = catalog || sso_catalog()
    domain = email_domain(email)
    policies = catalog.domain_policies || catalog.domains || %{}

    domain_providers =
      case Map.get(policies, domain) do
        nil -> []
        list when is_list(list) -> list
        %{providers: list} when is_list(list) -> list
        %{"providers" => list} when is_list(list) -> list
        _ -> []
      end

    Enum.filter(domain_providers, &(&1 in catalog.providers))
  end

  # <REMOVED UUID HERE> sso_path :: auto-generated pointer for public function sso_path
  def sso_path("oidc"), do: "/auth/oidc"
  def sso_path("google"), do: "/auth/google"
  def sso_path("github"), do: "/auth/github"
  def sso_path("facebook"), do: "/auth/facebook"
  def sso_path("linkedin"), do: "/auth/linkedin"
  def sso_path("saml"), do: "/sso/saml/auth/signin"
  def sso_path(provider), do: "/auth/#{provider}"

  # SSO entry URL carrying an invite across the IdP round-trip. Empty/blank
  # tokens get the plain path — the controller only stashes non-empty values.
  def sso_invite_path(provider, token) when is_binary(token) do
    if String.trim(token) == "" do
      sso_path(provider)
    else
      sso_path(provider) <> "?invite=" <> URI.encode_www_form(token)
    end
  end

  def sso_invite_path(provider, _token), do: sso_path(provider)

  # <REMOVED UUID HERE> sso_label :: auto-generated pointer for public function sso_label
  def sso_label("oidc"), do: "Sign in with SSO"
  def sso_label("google"), do: "Sign in with Google"
  def sso_label("github"), do: "Sign in with GitHub"
  def sso_label("facebook"), do: "Sign in with Facebook"
  def sso_label("linkedin"), do: "Sign in with LinkedIn"
  def sso_label("saml"), do: "Sign in with SAML"
  def sso_label(provider), do: "Sign in with #{provider}"

  def label("login"), do: "Log in"
  def label("signup"), do: "Sign up"

  def password_autocomplete("signup"), do: "new-password"
  def password_autocomplete(_), do: "current-password"

  # <REMOVED UUID HERE> serialize_user :: auto-generated pointer for public function serialize_user
  def serialize_user(user) do
    admin? =
      Map.get(user, :admin, false) == true or Map.get(user, :is_admin, false) == true

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
      is_admin: admin?,
      admin: admin?,
      # Authoritative routing flag (admin + general-release exemptions applied).
      invite_required: Annotate.Auth.InviteGate.required?(user)
    }
  end

  # ── private ──────────────────────────────────────────────────

  defp load_session_user(server) do
    token = Hologram.Server.get_session(server, :access_token)

    with true <- is_binary(token) and token != "",
         {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, session} <- Guardian.resource_from_claims(claims) do
      user = resolve_user_from_session(session)
      orgs = Organizations.list_user_organizations(user.id)
      {:ok, user, orgs}
    else
      _ -> :error
    end
  end

  @doc "Issue tokens for an existing user session entity (magic-link / SSO exchange)."
  # <REMOVED UUID HERE> issue_tokens_from_session :: Issue tokens for an existing user session entity (magic-link / SSO exchange).
  def issue_tokens_from_session(server, session), do: issue_tokens(server, session)

  defp issue_tokens(server, session) do
    with {:ok, access_token, _} <-
           Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: @access_ttl),
         {:ok, refresh_token, %{"jti" => refresh_jti}} <-
           Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: @refresh_ttl) do
      Annotate.Auth.TokenStore.store_refresh_jti(refresh_jti)
      user = resolve_user_from_session(session)
      orgs = Organizations.list_user_organizations(user.id)

      server =
        server
        |> Hologram.Server.put_session(:access_token, access_token)
        |> Hologram.Server.put_session(:refresh_token, refresh_token)
        |> Hologram.Server.put_user_id(user.id)

      {:ok, server, serialize_user(user), orgs}
    end
  end

  defp create_session_for_user(user) do
    user_ref = {:ref, Annotate.Users.User, user.id}

    session_entity = %Annotate.Users.Sessions.UserSession{
      user: user_ref,
      status: :active,
      details: %{}
    }

    Annotate.Users.Sessions.create(session_entity, Noizu.Context.system())
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

  defp resolve_invite(nil, _email), do: {:ok, nil}
  defp resolve_invite("", _email), do: {:ok, nil}

  defp resolve_invite(raw_token, email),
    do: Organizations.find_active_invite_by_raw_token(raw_token, email)

  defp profile_completed_at(attrs) do
    required = [
      Map.get(attrs, :user_name) || Map.get(attrs, "user_name"),
      Map.get(attrs, :first_name) || Map.get(attrs, "first_name"),
      Map.get(attrs, :last_name) || Map.get(attrs, "last_name"),
      Map.get(attrs, :mobile_phone) || Map.get(attrs, "mobile_phone")
    ]

    if Enum.all?(required, &(is_binary(&1) && String.trim(&1) != "")) do
      DateTime.utc_now()
    end
  end

  defp optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_string(_), do: nil

  defp email_domain(email) when is_binary(email) do
    case String.split(String.trim(String.downcase(email)), "@") do
      [_, domain] -> domain
      _ -> ""
    end
  end

  defp email_domain(_), do: ""

  defp maybe_add(list, flag, name) do
    if Application.get_env(:annotate, flag, false), do: list ++ [name], else: list
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
