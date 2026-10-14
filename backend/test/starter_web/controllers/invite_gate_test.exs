defmodule StarterWeb.InviteGateTest do
  @moduledoc """
  Register open, app gated (`Starter.Auth.InviteGate`): signup never needs an
  invite, gated accounts get a session but every authenticated surface except
  the interstitial contract refuses them until they redeem an invite (or, for
  an auto-approve-domain password signup, confirm their email).
  """
  use StarterWeb.ConnCase
  import Ecto.Query, only: [from: 2]

  alias Starter.Auth.InviteGate
  alias Starter.Schema.Users.User
  alias StarterWeb.Plugs.RequireInvite

  setup do
    previous_flags = Application.get_env(:starter, :feature_flags)
    previous_policies = Application.get_env(:starter, :sso_domain_policies)
    previous_auto = Application.get_env(:starter, :sso_auto_approve_domains)

    on_exit(fn ->
      Application.put_env(:starter, :feature_flags, previous_flags)
      Application.put_env(:starter, :sso_domain_policies, previous_policies)
      Application.put_env(:starter, :sso_auto_approve_domains, previous_auto)
    end)

    Application.put_env(:starter, :sso_domain_policies, %{})
    Application.put_env(:starter, :sso_auto_approve_domains, [])
    :ok
  end

  # ── router walk: every authenticated route except the exempt list ─────────

  describe "router walk" do
    test "every non-exempt authenticated route answers 403 invite_required to a pending user",
         %{conn: conn} do
      %{access_token: token} = user_with_status(:pending)

      routes = gated_routes()
      # An empty walk must never pass.
      assert length(routes) > 40

      for {verb, path} <- routes do
        resp =
          conn
          |> recycle()
          |> authenticated_conn(token)
          |> put_req_header("content-type", "application/json")
          |> dispatch(@endpoint, verb, path, "{}")

        assert resp.status == 403, "#{verb} #{path} → #{resp.status} (expected 403)"

        assert %{"error" => "invite_required", "account_status" => "pending"} =
                 Jason.decode!(resp.resp_body),
               "#{verb} #{path} body: #{resp.resp_body}"
      end
    end

    test "the same routes pass the gate for an active user (no 403 invite_required)",
         %{conn: conn} do
      %{access_token: token} = setup_user_and_token()

      for {verb, path} <- gated_routes() do
        # Past the gate a handler may reject the empty params (raise) — that
        # still proves the gate let the active user through.
        try do
          resp =
            conn
            |> recycle()
            |> authenticated_conn(token)
            |> put_req_header("content-type", "application/json")
            |> dispatch(@endpoint, verb, path, "{}")

          refute resp.status == 403 and resp.resp_body =~ "invite_required",
                 "#{verb} #{path} refused an active user"
        rescue
          e in [ExUnit.AssertionError] -> reraise e, __STACKTRACE__
          _ -> :passed_the_gate
        end
      end
    end
  end

  # ── the interstitial contract ─────────────────────────────────────────────

  describe "exempt surface" do
    test "auth/me, users/me and complete-registration stay reachable; auth/me flags invite_required",
         %{conn: conn} do
      %{access_token: token} = user_with_status(:pending)
      authed = authenticated_conn(conn, token)

      me = json_response(get(authed, "/api/v1/auth/me"), 200)
      assert me["user"]["invite_required"] == true
      assert me["user"]["status"] == "pending"

      assert json_response(get(authed, "/api/v1/users/me"), 200)
    end

    test "waitlist and unverified are held too; admins and active users are not", %{conn: conn} do
      for status <- [:waitlist, :unverified] do
        %{access_token: token} = user_with_status(status)
        resp = conn |> authenticated_conn(token) |> get("/api/v1/organizations")
        assert %{"error" => "invite_required"} = json_response(resp, 403)
      end

      %{access_token: admin_token} = user_with_status(:pending, admin: true)
      assert json_response(conn |> authenticated_conn(admin_token) |> get("/api/v1/organizations"), 200)

      %{access_token: active_token} = setup_user_and_token()
      assert json_response(conn |> authenticated_conn(active_token) |> get("/api/v1/organizations"), 200)
    end

    test "old pending accounts are held — no grandfather cutoff", %{conn: conn} do
      %{user: user, access_token: token} = user_with_status(:pending)

      Starter.Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]]
      )

      assert json_response(conn |> authenticated_conn(token) |> get("/api/v1/organizations"), 403)
    end

    test "general release turns the gate off", %{conn: conn} do
      %{access_token: token} = user_with_status(:pending)
      flags = Application.get_env(:starter, :feature_flags, %{})
      Application.put_env(:starter, :feature_flags, Map.put(flags, :general_release, true))

      assert json_response(conn |> authenticated_conn(token) |> get("/api/v1/organizations"), 200)
    end

    test "unauthenticated requests are still 401, not 403", %{conn: conn} do
      assert get(conn, "/api/v1/organizations").status == 401
    end

    test "an unrecognised Guardian resource is refused (fail closed)" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_private(:guardian_default_resource, %{unexpected: true})
        |> Map.put(:request_path, "/api/v1/organizations")
        |> RequireInvite.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "a federated/shared-key principal in assigns is gated by the plug" do
      %{user: user} = user_with_status(:pending)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.assign(:current_user, user)
        |> Map.put(:request_path, "/api/v1/organizations")
        |> RequireInvite.call([])

      assert conn.halted and conn.status == 403
    end
  end

  # ── side doors ────────────────────────────────────────────────────────────

  describe "UserSocket" do
    test "refuses a pending user, accepts an active one" do
      %{access_token: pending_token} = user_with_status(:pending)
      %{access_token: active_token} = setup_user_and_token()

      assert {:error, %{reason: "invite_required"}} =
               StarterWeb.UserSocket.connect(%{"token" => pending_token}, socket_stub(), %{})

      assert {:ok, _} = StarterWeb.UserSocket.connect(%{"token" => active_token}, socket_stub(), %{})
    end
  end

  describe "Hologram RequireAuth middleware" do
    test "redirects a gated user to /auth/invite-required; exempt pages render" do
      %{access_token: token} = user_with_status(:pending)
      server = %Hologram.Server{session: %{"access_token" => token}}

      gated = StarterWeb.Hologram.Middleware.RequireAuth.call(server, [])
      assert gated.status == 302
      assert gated.response_headers["location"] == "/auth/invite-required"

      exempt = StarterWeb.Hologram.Middleware.RequireAuth.call(server, invite: :exempt)
      assert exempt.status == nil
    end

    test "lets an active user through" do
      %{access_token: token} = setup_user_and_token()
      server = %Hologram.Server{session: %{"access_token" => token}}
      assert StarterWeb.Hologram.Middleware.RequireAuth.call(server, []).status == nil
    end

    test "post_auth_path routes gated users to the interstitial" do
      assert Starter.Hologram.Auth.post_auth_path(%{invite_required: true}) == "/auth/invite-required"
      assert Starter.Hologram.Auth.post_auth_path(%{invite_required: false, status: :pending}) == "/app"
      assert Starter.Hologram.Auth.post_auth_path(%{status: "waitlist"}) == "/auth/invite-required"
      assert Starter.Hologram.Auth.post_auth_path(%{status: :active}) == "/app"
    end
  end

  describe "pages" do
    test "the interstitial is a Hologram page at /auth/invite-required; the legacy route redirects" do
      assert StarterWeb.Hologram.Pages.InviteRequiredPage.__route__() == "/auth/invite-required"
      assert StarterWeb.Hologram.Pages.PendingApprovalPage.__route__() == "/pending-approval"

      redirected =
        StarterWeb.Hologram.Pages.PendingApprovalPage.to_interstitial(%Hologram.Server{}, [])

      assert redirected.response_headers["location"] == "/auth/invite-required"
    end
  end

  # ── signup status ─────────────────────────────────────────────────────────

  describe "signup" do
    test "password signup on an invite-required domain → :pending", %{conn: conn} do
      email = "p-#{uniq()}@gated.example"
      body = json_response(post(conn, "/api/v1/auth/register", %{user: reg(email)}), 201)
      assert body["user"]["status"] == "pending"
      assert body["user"]["invite_required"] == true
    end

    test "password signup on an auto-approve domain → :unverified until the email is confirmed",
         %{conn: conn} do
      Application.put_env(:starter, :sso_auto_approve_domains, ["auto.example"])
      email = "a-#{uniq()}@auto.example"

      body = json_response(post(conn, "/api/v1/auth/register", %{user: reg(email)}), 201)
      assert body["user"]["status"] == "unverified"
      assert body["user"]["invite_required"] == true

      gated = conn |> authenticated_conn(body["access_token"]) |> get("/api/v1/organizations")
      assert %{"account_status" => "unverified"} = json_response(gated, 403)

      {:ok, %{encoded_key: key}} = Starter.Auth.SmartTokenAuth.request_email_verification(email)
      assert json_response(post(recycle(conn), "/api/v1/auth/verify-email/confirm", %{token: key}), 200)

      user = Starter.Repo.get_by!(User, email: email)
      assert user.status == :active
      assert user.approved_at

      open = conn |> recycle() |> authenticated_conn(body["access_token"]) |> get("/api/v1/organizations")
      assert json_response(open, 200)
    end

    test "confirming the email never activates an invite-required (:pending) account" do
      %{user: user} = user_with_status(:pending)
      InviteGate.confirm_email(user.id)
      assert Starter.Repo.get!(User, user.id).status == :pending
    end

    test "valid code at signup → :active; invalid code → error and no row", %{conn: conn} do
      email = "i-#{uniq()}@gated.example"
      {:ok, _invite, raw} = invite(email: email)

      body =
        json_response(
          post(conn, "/api/v1/auth/register", %{user: reg(email), invite_token: raw}),
          201
        )

      assert body["user"]["status"] == "active"
      assert body["user"]["invite_required"] == false

      bad = "b-#{uniq()}@gated.example"
      resp = post(conn, "/api/v1/auth/register", %{user: reg(bad), invite_token: "nope-nope-nope"})
      assert resp.status in [401, 403, 422]
      assert Starter.Repo.get_by(User, email: bad) == nil
    end

    test "signup_status/3 is the one rule" do
      Application.put_env(:starter, :sso_domain_policies, %{
        "sso.example" => %{providers: ["google"], auto_approve: true}
      })

      assert InviteGate.signup_status("x@gated.example") == :pending
      assert InviteGate.signup_status("x@gated.example", nil, %{id: "i"}) == :active
      assert InviteGate.signup_status("x@sso.example", :google) == :active
      assert InviteGate.signup_status("x@sso.example", :github) == :pending
      assert InviteGate.signup_status("x@sso.example") == :unverified
    end
  end

  # ── redeem ────────────────────────────────────────────────────────────────

  describe "POST /api/v1/invites/redeem" do
    test "valid code flips a pending user :active and opens the app", %{conn: conn} do
      %{user: user, access_token: token} = user_with_status(:pending)
      {:ok, invite, raw} = invite([])

      resp = conn |> authenticated_conn(token) |> post("/api/v1/invites/redeem", %{token: raw})
      assert %{"invite_required" => false} = json_response(resp, 200)

      stored = Starter.Repo.get!(User, user.id)
      assert stored.status == :active
      assert stored.invite_token_id == invite.id
      assert stored.approved_at

      open = conn |> recycle() |> authenticated_conn(token) |> get("/api/v1/organizations")
      assert json_response(open, 200)
    end

    test "unknown, expired and other-email-bound codes are 404; used is 409", %{conn: conn} do
      %{user: user, access_token: token} = user_with_status(:pending)
      authed = authenticated_conn(conn, token)

      {:ok, _, expired} =
        invite(
          starts_at: DateTime.add(DateTime.utc_now(), -7200, :second),
          expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        )

      {:ok, _, foreign} = invite(email: "someone-else-#{uniq()}@example.com")

      for raw <- ["garbage-token-x", expired, foreign] do
        assert json_response(post(authed, "/api/v1/invites/redeem", %{token: raw}), 404)
      end

      {:ok, _, used} = invite(max_uses: 1)
      %{access_token: other} = setup_user_and_token()
      assert json_response(conn |> authenticated_conn(other) |> post("/api/v1/invites/redeem", %{token: used}), 200)

      resp = conn |> recycle() |> authenticated_conn(token) |> post("/api/v1/invites/redeem", %{token: used})
      assert %{"error" => "This invite has already been used"} = json_response(resp, 409)

      assert Starter.Repo.get!(User, user.id).status == :pending
    end

    test "is idempotent for an invite the user already redeemed", %{conn: conn} do
      %{access_token: token} = user_with_status(:pending)
      {:ok, _, raw} = invite(max_uses: 5)
      authed = authenticated_conn(conn, token)

      assert json_response(post(authed, "/api/v1/invites/redeem", %{token: raw}), 200)
      assert json_response(post(recycle(authed) |> authenticated_conn(token), "/api/v1/invites/redeem", %{token: raw}), 200)
    end
  end

  # ── resend is only for :unverified accounts ───────────────────────────────

  describe "resend confirmation" do
    test "an :unverified account may resend; a :pending account may not" do
      %{access_token: pending_token} = user_with_status(:pending)
      %{access_token: unverified_token} = user_with_status(:unverified)

      assert {:error, "not_unverified"} =
               Starter.Hologram.Auth.resend_confirmation(%Hologram.Server{
                 session: %{"access_token" => pending_token}
               })

      assert :ok =
               Starter.Hologram.Auth.resend_confirmation(%Hologram.Server{
                 session: %{"access_token" => unverified_token}
               })
    end
  end

  # ── complete-registration: redeem and profile save are atomic ─────────────

  describe "POST /api/v1/users/me/complete-registration" do
    test "a failed step consumes neither the invite nor the profile completion",
         %{conn: conn} do
      %{user: user, access_token: token} = user_with_status(:pending)
      {:ok, invite, raw} = invite(max_uses: 5)

      # Force the profile-save half to fail after the redeem half ran: with no
      # password credential the optional new_password update rolls back.
      Starter.Repo.delete_all(
        from(c in Starter.Schema.Users.Credentials.UserCredential, where: c.user_id == ^user.id)
      )

      params = %{
        "user" => %{
          "user_name" => "u#{uniq()}",
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "mobile_phone" => "+15555550123",
          "invite_token" => raw,
          "new_password" => "newpassword123"
        }
      }

      resp =
        conn
        |> authenticated_conn(token)
        |> post("/api/v1/users/me/complete-registration", params)

      assert resp.status == 422

      stored = Starter.Repo.get!(User, user.id)
      assert stored.status == :pending
      assert stored.profile_completed_at == nil

      assert Starter.Repo.get!(Starter.Schema.Organizations.InviteToken, invite.id).uses == 0

      # The invite is still whole: retrying without the password change
      # completes registration and activates the account.
      retry =
        conn
        |> recycle()
        |> authenticated_conn(token)
        |> post("/api/v1/users/me/complete-registration", %{
          "user" => Map.delete(params["user"], "new_password")
        })

      body = json_response(retry, 200)
      assert body["user"]["status"] == "active"

      assert Starter.Repo.get!(Starter.Schema.Organizations.InviteToken, invite.id).uses == 1
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp gated_routes do
    StarterWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.map(fn route -> {route.verb |> to_string() |> String.upcase(), concrete(route.path)} end)
    |> Enum.uniq()
    |> Enum.filter(fn {verb, path} ->
      case Phoenix.Router.route_info(StarterWeb.Router, verb, path, "www.example.com") do
        %{pipe_through: pipes} -> :authenticated in pipes
        _ -> false
      end
    end)
    |> Enum.reject(fn {verb, path} -> RequireInvite.exempt?(verb, path) end)
  end

  defp concrete(path) do
    path
    |> String.split("/")
    |> Enum.map(fn
      ":" <> _ -> Ecto.UUID.generate()
      "*" <> _ -> "file.txt"
      seg -> seg
    end)
    |> Enum.join("/")
  end

  defp user_with_status(status, opts \\ []) do
    %{user: user} = ctx = setup_user_and_token()

    {:ok, user} =
      user
      |> Ecto.Changeset.change(status: status, admin: Keyword.get(opts, :admin, false))
      |> Starter.Repo.update()

    %{ctx | user: user}
  end

  defp invite(attrs) do
    defaults = %{
      starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      role: "viewer"
    }

    Starter.Organizations.create_invite_token(Map.merge(defaults, Map.new(attrs)))
  end

  defp reg(email) do
    %{
      email: email,
      password: "password123",
      user_name: "u#{uniq()}",
      first_name: "Ada",
      last_name: "Lovelace",
      mobile_phone: "+15555550123"
    }
  end

  defp socket_stub, do: %Phoenix.Socket{assigns: %{}}

  defp uniq, do: System.unique_integer([:positive])
end
