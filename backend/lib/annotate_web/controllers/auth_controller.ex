defmodule AnnotateWeb.AuthController do
  use AnnotateWeb, :controller

  alias Annotate.Guardian
  alias Annotate.Organizations

  # Register open, app gated: a missing invite never fails signup. The status
  # comes from Annotate.Auth.InviteGate.signup_status/3 (valid invite → :active,
  # auto-approve domain → :unverified until the email is confirmed, otherwise
  # :pending) and the session it gets is held at /auth/invite-required by
  # RequireInvite. A supplied but invalid invite fails and writes nothing.
  # <REMOVED UUID HERE> register :: auto-generated pointer for public function register
  def register(conn, %{"user" => user_params} = params) do
    raw_token = optional_string(params["invite_token"])
    email = user_params["email"]

    with {:ok, invite} <- resolve_invite(raw_token, email),
         status = Annotate.Auth.InviteGate.signup_status(email, nil, invite),
         {:ok, user} <-
           Annotate.Auth.Registration.register_user_with_invite(
             %{
               user_name: user_params["user_name"] || email,
               name: %{
                 first: user_params["first_name"] || "",
                 last: user_params["last_name"] || ""
               },
               email: email,
               password: user_params["password"],
               mobile_phone: user_params["mobile_phone"],
               invite_token_id: invite && invite.id,
               status: status,
               profile_completed_at: profile_completed_at(user_params)
             },
             {:login, {email, user_params["password"]}},
             [
               status: status,
               invite_token_id: invite && invite.id,
               mobile_phone: user_params["mobile_phone"],
               profile_completed_at: profile_completed_at(user_params)
             ],
             invite,
             conn
           ),
         {:ok, session} <- create_session_for_user(user),
         {:ok, access_token, _} <-
           Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour}),
         {:ok, refresh_token, %{"jti" => refresh_jti}} <-
           Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day}) do
      Annotate.Auth.TokenStore.store_refresh_jti(refresh_jti)
      Annotate.Events.dispatch(:user_registered, %{user_id: user.id, email: user.email})
      Annotate.Auth.InviteGate.after_signup(user)

      orgs = Organizations.list_user_organizations(user.id)

      conn
      |> put_status(:created)
      |> json(%{
        user: serialize_user(user),
        organizations: orgs,
        access_token: access_token,
        refresh_token: refresh_token
      })
    else
      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired invite token"})

      {:error, :invite_exhausted} ->
        conn |> put_status(:conflict) |> json(%{error: "This invite has already been used"})

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def register(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user params required"})
  end

  # <REMOVED UUID HERE> login :: auto-generated pointer for public function login
  def login(conn, %{"email" => email, "password" => password}) do
    case Annotate.Users.Credentials.authenticate(
           {:login, {email, password}},
           Noizu.Context.system(),
           []
         ) do
      {:ok, session} ->
        {:ok, access_token, _} =
          Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

        {:ok, refresh_token, %{"jti" => refresh_jti}} =
          Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day})

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

      {:error, :invalid_credentials} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid email or password"})

      {:error, {:login, :invalid_credentials}} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid email or password"})

      {:error, :invalid_email} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid email format"})

      {:error, :invalid_password} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Password too short"})

      {:error, :pending_approval} ->
        conn |> put_status(:forbidden) |> json(%{error: "Account is pending approval"})
    end
  end

  # <REMOVED UUID HERE> request_magic_link :: auto-generated pointer for public function request_magic_link
  def request_magic_link(conn, %{"email" => email}) do
    frontend_url = Application.get_env(:annotate, :frontend_url, "http://localhost:8080")

    case Annotate.Auth.SmartTokenAuth.request_magic_link(email) do
      {:ok, %{encoded_key: encoded_key, user: _user}} ->
        magic_link = "#{frontend_url}/auth/verify?token=#{encoded_key}"
        Annotate.Auth.SmartTokenEmail.send_magic_link(email, magic_link)

        response = %{message: "If an account exists with that email, a magic link has been sent."}

        response =
          if Application.get_env(:annotate, :dev_routes) do
            Map.put(response, :dev_link, magic_link)
          else
            response
          end

        conn |> put_status(:ok) |> json(response)

      {:error, :not_found} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "If an account exists with that email, a magic link has been sent."})
    end
  end

  # <REMOVED UUID HERE> verify_magic_link :: auto-generated pointer for public function verify_magic_link
  def verify_magic_link(conn, %{"token" => token_key}) do
    case Annotate.Auth.SmartTokenAuth.verify_magic_link(token_key, conn) do
      {:ok, session} ->
        {:ok, access_token, _} =
          Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

        {:ok, refresh_token, %{"jti" => refresh_jti}} =
          Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day})

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

      {:error, _reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired magic link"})
    end
  end

  # <REMOVED UUID HERE> request_otp_login :: auto-generated pointer for public function request_otp_login
  def request_otp_login(conn, %{"email" => email}) do
    case Annotate.Auth.SmartTokenAuth.request_otp_login(email) do
      {:ok, %{otp_code: otp_code, user: _user}} ->
        Annotate.Auth.SmartTokenEmail.send_otp_login(email, otp_code)

        response = %{message: "If an account exists with that email, a login code has been sent."}

        response =
          if Application.get_env(:annotate, :dev_routes) do
            Map.put(response, :dev_code, otp_code)
          else
            response
          end

        conn |> put_status(:ok) |> json(response)

      {:error, :not_found} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "If an account exists with that email, a login code has been sent."})
    end
  end

  # <REMOVED UUID HERE> verify_otp_login :: auto-generated pointer for public function verify_otp_login
  def verify_otp_login(conn, %{"email" => email, "code" => code}) do
    case Annotate.Auth.SmartTokenAuth.verify_otp_login(email, code, conn) do
      {:ok, session} ->
        {:ok, access_token, _} =
          Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

        {:ok, refresh_token, %{"jti" => refresh_jti}} =
          Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day})

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

      {:error, _reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired code"})
    end
  end

  # <REMOVED UUID HERE> request_password_reset :: auto-generated pointer for public function request_password_reset
  def request_password_reset(conn, %{"email" => email}) do
    case Annotate.Auth.SmartTokenAuth.request_password_reset(email) do
      {:ok, %{otp_code: otp_code, user: _user}} ->
        Annotate.Auth.SmartTokenEmail.send_password_reset(email, otp_code)

        response = %{message: "If an account exists with that email, a reset code has been sent."}

        response =
          if Application.get_env(:annotate, :dev_routes) do
            Map.put(response, :dev_code, otp_code)
          else
            response
          end

        conn |> put_status(:ok) |> json(response)

      {:error, :not_found} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "If an account exists with that email, a reset code has been sent."})
    end
  end

  # <REMOVED UUID HERE> verify_password_reset :: auto-generated pointer for public function verify_password_reset
  def verify_password_reset(conn, %{
        "email" => email,
        "code" => code,
        "new_password" => new_password
      }) do
    case Annotate.Auth.SmartTokenAuth.verify_password_reset(email, code, new_password, conn) do
      {:ok, _credential} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Password has been reset. You can now log in."})

      {:error, _reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired code"})
    end
  end

  # <REMOVED UUID HERE> refresh :: auto-generated pointer for public function refresh
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    alias Annotate.Auth.TokenStore

    case Guardian.decode_and_verify(refresh_token, %{"typ" => "refresh"}) do
      {:ok, claims} ->
        jti = claims["jti"]

        if jti && TokenStore.valid_refresh_jti?(jti) do
          case Guardian.resource_from_claims(claims) do
            {:ok, session} ->
              TokenStore.revoke_refresh_jti(jti)

              {:ok, access_token, _} =
                Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

              {:ok, new_refresh_token, %{"jti" => new_jti}} =
                Guardian.encode_and_sign(session, %{}, token_type: "refresh", ttl: {7, :day})

              TokenStore.store_refresh_jti(new_jti)

              conn
              |> put_status(:ok)
              |> json(%{access_token: access_token, refresh_token: new_refresh_token})

            {:error, _} ->
              conn |> put_status(:unauthorized) |> json(%{error: "Invalid refresh token"})
          end
        else
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid refresh token"})
        end

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid refresh token"})
    end
  end

  # <REMOVED UUID HERE> me :: auto-generated pointer for public function me
  def me(conn, _params) do
    session = Guardian.Plug.current_resource(conn)
    user = resolve_user_from_session(session)
    orgs = Organizations.list_user_organizations(user.id)

    conn
    |> put_status(:ok)
    |> json(%{user: serialize_user(user), organizations: orgs})
  end

  # <REMOVED UUID HERE> send_verification :: auto-generated pointer for public function send_verification
  def send_verification(conn, _params) do
    session = Guardian.Plug.current_resource(conn)
    user = resolve_user_from_session(session)
    frontend_url = Application.get_env(:annotate, :frontend_url, "http://localhost:8080")

    case Annotate.Auth.SmartTokenAuth.request_email_verification(user.email) do
      {:ok, %{encoded_key: encoded_key}} ->
        verification_link = "#{frontend_url}/auth/verify-email?token=#{encoded_key}"
        Annotate.Auth.SmartTokenEmail.send_verification_email(user.email, verification_link)

        response = %{message: "Verification email sent."}

        response =
          if Application.get_env(:annotate, :dev_routes) do
            Map.put(response, :dev_link, verification_link)
          else
            response
          end

        conn |> put_status(:ok) |> json(response)

      {:error, _} ->
        conn |> put_status(:ok) |> json(%{message: "Verification email sent."})
    end
  end

  # <REMOVED UUID HERE> verify_email :: auto-generated pointer for public function verify_email
  def verify_email(conn, %{"token" => token_key}) do
    case Annotate.Auth.SmartTokenAuth.verify_email_token(token_key) do
      {:ok, user} ->
        Annotate.Events.dispatch(:user_verified, %{user_id: user.id})
        conn |> put_status(:ok) |> json(%{message: "Email verified successfully."})

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired verification link"})
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
      # Authoritative routing flag (admin + general-release exemptions
      # applied): true → the client sends the user to /auth/invite-required.
      invite_required: Annotate.Auth.InviteGate.required?(user)
    }
  end

  defp resolve_invite(nil, _email), do: {:ok, nil}
  defp resolve_invite("", _email), do: {:ok, nil}

  defp resolve_invite(raw_token, email),
    do: Organizations.find_active_invite_by_raw_token(raw_token, email)

  defp profile_completed_at(params) do
    required = [
      params["user_name"],
      params["first_name"],
      params["last_name"],
      params["mobile_phone"]
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

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
