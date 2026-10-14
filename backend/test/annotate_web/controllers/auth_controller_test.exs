defmodule AnnotateWeb.AuthControllerTest do
  use AnnotateWeb.ConnCase
  import Ecto.Query

  alias Annotate.Schema.Organizations.InviteToken
  alias Annotate.Schema.Organizations.InviteTokenRedemption
  alias Annotate.Schema.Users.User

  describe "POST /api/v1/auth/login" do
    test "returns tokens on valid credentials", %{conn: conn} do
      %{user: user, password: password} = setup_user_and_token()

      conn = post(conn, "/api/v1/auth/login", %{email: user.email, password: password})
      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["refresh_token"]
      assert response["user"]["email"] == user.email
    end

    test "returns 401 on invalid credentials", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/login", %{email: "nobody@example.com", password: "wrongpassword"})

      assert json_response(conn, 401)["error"]
    end
  end

  describe "POST /api/v1/auth/register" do
    test "creates complete password registrations as pending without invite", %{conn: conn} do
      email = unique_email()

      conn = post(conn, "/api/v1/auth/register", %{user: registration_params(email)})
      response = json_response(conn, 201)

      assert response["access_token"]
      assert response["refresh_token"]
      assert response["user"]["email"] == email
      assert response["user"]["status"] == "pending"
      assert response["user"]["profile_complete"] == true

      user = Annotate.Repo.get_by!(User, email: email)
      assert user.status == :pending
      assert user.approved_at == nil
      assert user.profile_completed_at
    end

    test "valid invite activates the user and records redemption", %{conn: conn} do
      email = unique_email()
      {:ok, invite, raw_token} = create_invite(email, max_uses: 1)

      conn =
        post(conn, "/api/v1/auth/register", %{
          user: registration_params(email),
          invite_token: raw_token
        })

      response = json_response(conn, 201)
      assert response["user"]["status"] == "active"

      user = Annotate.Repo.get_by!(User, email: email)
      invite = Annotate.Repo.get!(InviteToken, invite.id)

      assert user.status == :active
      assert user.invite_token_id == invite.id
      assert user.approved_at
      assert invite.uses == 1
      assert invite.redemption_count == 1
      assert invite.accepted_by == user.id

      redemption_count =
        Annotate.Repo.aggregate(
          from(r in InviteTokenRedemption, where: r.invite_token_id == ^invite.id),
          :count
        )

      assert redemption_count == 1
    end

    test "invalid invite is rejected", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/register", %{
          user: registration_params(unique_email()),
          invite_token: "not-a-valid-token"
        })

      assert json_response(conn, 401)["error"] =~ "Invalid"
    end

    test "registers at the invite's role, not a hardcoded viewer", %{conn: conn} do
      email = unique_email()

      org =
        Annotate.Repo.insert!(%Annotate.Schema.Organizations.Organization{
          slug: "role-org-#{System.unique_integer([:positive])}",
          name: "Role Org"
        })

      {:ok, _invite, raw_token} = create_invite(email, role: "member", organization_id: org.id)

      conn =
        post(conn, "/api/v1/auth/register", %{
          user: registration_params(email),
          invite_token: raw_token
        })

      assert json_response(conn, 201)

      user = Annotate.Repo.get_by!(User, email: email)

      assert {:ok, %{role: "member"}} =
               Annotate.Authz.authorize(user.id, "organization", org.id, "member")
    end

    test "single-use invite cannot be redeemed twice", %{conn: conn} do
      email = unique_email()
      {:ok, invite, raw_token} = create_invite(email, max_uses: 1)

      conn1 =
        post(conn, "/api/v1/auth/register", %{
          user: registration_params(email),
          invite_token: raw_token
        })

      assert json_response(conn1, 201)
      assert Annotate.Repo.get!(InviteToken, invite.id).uses == 1

      # A second registration attempt with the spent token is rejected. The
      # lookup pre-filters exhausted invites, so this surfaces as the same
      # invalid-token response as any dead link (uniform oracle); the
      # invite_exhausted 409 branch only fires inside the redeem race window.
      email2 = unique_email()

      conn2 =
        post(conn, "/api/v1/auth/register", %{
          user: registration_params(email2),
          invite_token: raw_token
        })

      assert json_response(conn2, 401)["error"] =~ "Invalid"
      assert Annotate.Repo.get_by(User, email: email2) == nil
    end

    test "register open, app gated: no invite → 201 :pending session held by the gate, for both flag values",
         %{conn: conn} do
      gate = Application.get_env(:annotate, :sso_require_invite)
      on_exit(fn -> Application.put_env(:annotate, :sso_require_invite, gate) end)

      for flag <- [true, false] do
        Application.put_env(:annotate, :sso_require_invite, flag)
        email = unique_email()

        resp = post(conn, "/api/v1/auth/register", %{user: registration_params(email)})
        body = json_response(resp, 201)

        assert body["user"]["status"] == "pending"
        assert body["user"]["invite_required"] == true
        assert body["access_token"]
        assert Annotate.Repo.get_by!(User, email: email).status == :pending

        gated =
          conn
          |> authenticated_conn(body["access_token"])
          |> get("/api/v1/organizations")

        assert %{"error" => "invite_required", "account_status" => "pending"} =
                 json_response(gated, 403)
      end
    end
  end

  describe "POST /api/v1/auth/refresh" do
    test "rotates tokens on valid refresh", %{conn: conn} do
      %{refresh_token: refresh_token} = setup_user_and_token()

      conn = post(conn, "/api/v1/auth/refresh", %{refresh_token: refresh_token})
      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["refresh_token"]
    end

    test "rejects reused refresh token", %{conn: conn} do
      %{refresh_token: refresh_token} = setup_user_and_token()

      # First refresh succeeds
      conn1 = post(conn, "/api/v1/auth/refresh", %{refresh_token: refresh_token})
      assert json_response(conn1, 200)["access_token"]

      # Second refresh with same token fails (JTI was revoked)
      conn2 = post(conn, "/api/v1/auth/refresh", %{refresh_token: refresh_token})
      assert json_response(conn2, 401)["error"]
    end
  end

  describe "GET /api/v1/auth/me" do
    test "returns current user when authenticated", %{conn: conn} do
      %{access_token: token, user: user} = setup_user_and_token()

      conn = conn |> authenticated_conn(token) |> get("/api/v1/auth/me")
      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
    end

    test "returns 401 without token", %{conn: conn} do
      conn = get(conn, "/api/v1/auth/me")
      assert conn.status == 401
    end
  end

  describe "POST /api/v1/auth/verify-email" do
    test "sends verification email when authenticated", %{conn: conn} do
      %{access_token: token} = setup_user_and_token()

      conn = conn |> authenticated_conn(token) |> post("/api/v1/auth/verify-email")
      response = json_response(conn, 200)

      assert response["message"] =~ "Verification"
    end
  end

  defp registration_params(email) do
    uniq = System.unique_integer([:positive])

    %{
      email: email,
      password: "password123",
      user_name: "user#{uniq}",
      first_name: "Ada",
      last_name: "Lovelace",
      mobile_phone: "+15555550123"
    }
  end

  defp unique_email do
    "test-#{System.unique_integer([:positive])}@example.com"
  end

  defp create_invite(email, attrs) do
    defaults = %{
      email: email,
      starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      max_uses: 1
    }

    Annotate.Organizations.create_invite_token(Map.merge(defaults, Map.new(attrs)))
  end
end
