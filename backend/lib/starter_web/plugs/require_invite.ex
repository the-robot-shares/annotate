defmodule StarterWeb.Plugs.RequireInvite do
  @moduledoc """
  The one fail-closed invite gate for the authenticated REST pipeline (see
  `Starter.Auth.InviteGate`). Runs last in `StarterWeb.AuthPipeline`, so every
  current and future authenticated route is covered; a gated
  (`:pending`/`:waitlist`/`:unverified`) user gets

      403 {"error": "invite_required", "account_status": "pending", "message": …}

  everywhere except the exempt surface that lets them understand their state,
  manage their profile and redeem an invite:

    * identity — `GET /auth/me`, `POST /auth/verify-email` (resend),
    * profile — `GET|PATCH /users/me`, `POST /users/me/complete-registration`,
    * `POST /invites/redeem`.

  Login, refresh, register, logout and `invites/lookup` sit outside the
  authenticated pipeline already. Conns with no user at all pass (anonymous
  traffic was already 401'd upstream); a Guardian resource of an unknown
  shape is refused (fail closed).
  """

  @behaviour Plug
  import Plug.Conn

  alias Starter.Auth.InviteGate
  alias Starter.Schema.Users.User, as: UserSchema

  @exempt [
    {"GET", "/api/v1/auth/me"},
    {"POST", "/api/v1/auth/verify-email"},
    {"GET", "/api/v1/users/me"},
    {"PATCH", "/api/v1/users/me"},
    {"POST", "/api/v1/users/me/complete-registration"},
    {"POST", "/api/v1/invites/redeem"}
  ]

  @doc "`{method, path}` pairs a gated user may still reach (the interstitial contract)."
  def exempt_routes, do: @exempt

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if exempt?(conn.method, conn.request_path) do
      conn
    else
      case principal(conn) do
        nil ->
          conn

        :unresolved ->
          reject(conn, nil)

        user ->
          # One DB read per request at most: the row is loaded here and handed
          # to both the gate decision and the 403 body, instead of re-reading
          # it inside `InviteGate.required?/1` and again in `reject/2`. An
          # unresolvable principal is not a user-invite concern (same as
          # before — pass, the caller authenticated them).
          user = resolve_user(user)

          if user && InviteGate.required?(user), do: reject(conn, user), else: conn
      end
    end
  end

  defp resolve_user(%UserSchema{} = user), do: user

  defp resolve_user(principal) do
    id =
      case principal do
        id when is_binary(id) -> id
        %{id: id} when is_binary(id) -> id
        _ -> nil
      end

    with id when is_binary(id) <- id,
         {:ok, id} <- Ecto.UUID.cast(id),
         %UserSchema{} = user <- Starter.Repo.get(UserSchema, id) do
      user
    else
      _ -> nil
    end
  end

  @doc "True for a route a gated user may still reach."
  def exempt?(method, path), do: {method, String.trim_trailing(path, "/")} in @exempt

  defp principal(conn) do
    case Guardian.Plug.current_resource(conn) do
      nil -> conn.assigns[:current_user]
      %{user: {:ref, _, id}} -> id
      %{user: %{id: id}} -> id
      %Starter.Schema.Users.User{} = user -> user
      %Starter.Users.User{} = user -> user
      _ -> :unresolved
    end
  end

  @doc "Halt with the single 403 `invite_required` body."
  def reject(conn, user) do
    user =
      case user do
        id when is_binary(id) -> Starter.Repo.get(Starter.Schema.Users.User, id)
        %{id: id} when is_binary(id) -> Starter.Repo.get(Starter.Schema.Users.User, id)
        other -> other
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(InviteGate.error_body(user)))
    |> halt()
  end
end
