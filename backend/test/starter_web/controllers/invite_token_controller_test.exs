defmodule StarterWeb.InviteTokenControllerTest do
  @moduledoc """
  Invite REST surface: the raw token is a one-time mint response, lookup is a
  no-detail 404 oracle, redeem joins an existing user, and only org admins
  may manage invites.
  """
  use StarterWeb.ConnCase

  setup do
    %{user: user, access_token: token} = setup_user_and_token()

    {:ok, org} =
      Starter.Organizations.create_organization_with_owner(
        %{
          slug: "invite-org-#{System.unique_integer([:positive])}",
          name: "Invite Test Org"
        },
        user.id
      )

    %{user: user, token: token, org: org}
  end

  describe "GET /api/v1/invites/lookup (public)" do
    test "returns org + role for a valid token", %{conn: conn, org: org} do
      {:ok, _invite, raw} = mint_invite(org.id, role: "member")

      conn = get(conn, "/api/v1/invites/lookup", %{"token" => raw})

      assert %{
               "organization_name" => "Invite Test Org",
               "role" => "member",
               "email_required" => false
             } = json_response(conn, 200)
    end

    test "404s identically for unknown, revoked, and exhausted tokens", %{conn: conn, org: org} do
      {:ok, invite, raw_revoked} = mint_invite(org.id, [])
      revoke(invite)

      {:ok, _invite2, raw_dead} = mint_invite(org.id, max_uses: 1)
      # burn the single use via the redeem path
      %{access_token: other_token} = setup_user_and_token()
      conn_other = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{other_token}")
      post(conn_other, "/api/v1/invites/redeem", %{"token" => raw_dead})

      for token <- ["garbage-token", raw_revoked, raw_dead] do
        resp = get(conn, "/api/v1/invites/lookup", %{"token" => token})
        assert %{"error" => "Invalid or expired invite token"} = json_response(resp, 404)
      end
    end

    test "missing token param is 404, not 500", %{conn: conn} do
      assert %{"error" => _} = json_response(get(conn, "/api/v1/invites/lookup"), 404)
    end
  end

  describe "POST /api/v1/invites/redeem (authenticated)" do
    test "joins an existing user to the inviting org at the invited role", %{
      conn: conn,
      org: org
    } do
      {:ok, _invite, raw} = mint_invite(org.id, role: "member")
      %{user: joiner, access_token: joiner_token} = setup_user_and_token()

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{joiner_token}")
        |> post("/api/v1/invites/redeem", %{"token" => raw})

      body = json_response(conn, 200)
      assert body["organization_id"] == org.id
      assert body["role"] == "member"

      assert {:ok, %{role: "member"}} =
               Starter.Authz.authorize(joiner.id, "organization", org.id, "member")
    end

    test "redeem with an invalid token is 404", %{conn: conn} do
      %{access_token: token} = setup_user_and_token()

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/invites/redeem", %{"token" => "nope"})

      assert %{"error" => _} = json_response(conn, 404)
    end

    test "unauthenticated redeem is rejected", %{conn: conn} do
      conn = post(conn, "/api/v1/invites/redeem", %{"token" => "nope"})
      assert conn.status in [401, 403]
    end

    test "re-posting the same token is idempotent per user (no use consumed)", %{
      conn: conn,
      org: org
    } do
      {:ok, invite, raw} = mint_invite(org.id, role: "member", max_uses: 2)
      %{access_token: token} = setup_user_and_token()
      auth = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

      assert json_response(post(auth, "/api/v1/invites/redeem", %{"token" => raw}), 200)
      assert json_response(post(auth, "/api/v1/invites/redeem", %{"token" => raw}), 200)

      # The repeat was a no-op: one use burned, not two.
      assert Starter.Repo.get!(Starter.Schema.Organizations.InviteToken, invite.id).uses == 1
    end
  end

  describe "admin CRUD /api/v1/organizations/:org_id/invites" do
    test "owner mints (raw token shown once), lists without hash, revokes", %{
      conn: conn,
      org: org,
      token: token
    } do
      auth = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

      conn1 = post(auth, "/api/v1/organizations/#{org.id}/invites", %{"role" => "member", "max_uses" => 3})
      body = json_response(conn1, 201)

      raw = body["token"]
      assert is_binary(raw) and raw != ""
      assert String.starts_with?(raw, body["invite"]["key_prefix"])
      assert body["link"] == "/join/" <> raw
      refute Map.has_key?(body["invite"], "token_hash")

      conn2 = get(auth, "/api/v1/organizations/#{org.id}/invites")
      invites = json_response(conn2, 200)["invites"]
      assert length(invites) == 1
      refute Enum.any?(invites, &Map.has_key?(&1, "token_hash"))
      refute Enum.any?(invites, &Map.has_key?(&1, "token"))

      conn3 = delete(auth, "/api/v1/organizations/#{org.id}/invites/#{body["invite"]["id"]}")
      assert json_response(conn3, 200)

      conn4 = get(conn, "/api/v1/invites/lookup", %{"token" => raw})
      assert json_response(conn4, 404)
    end

    test "invalid role is 400 with the allowed roles", %{conn: conn, org: org, token: token} do
      auth = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

      conn1 = post(auth, "/api/v1/organizations/#{org.id}/invites", %{"role" => "owner"})

      body = json_response(conn1, 400)
      assert body["roles"] == ["admin", "member", "viewer"]
    end

    test "malformed max_uses / expires_in_days are 400, not silently coerced", %{
      conn: conn,
      org: org,
      token: token
    } do
      auth = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

      for bad <- ["0", "-1", "many", "3-or-so"] do
        assert %{"error" => _} =
                 json_response(
                   post(auth, "/api/v1/organizations/#{org.id}/invites", %{
                     "role" => "member",
                     "max_uses" => bad
                   }),
                   400
                 )
      end

      assert %{"error" => _} =
               json_response(
                 post(auth, "/api/v1/organizations/#{org.id}/invites", %{
                   "role" => "member",
                   "expires_in_days" => "forever"
                 }),
                 400
               )
    end

    test "a non-member cannot mint", %{conn: conn, org: org} do
      %{access_token: outsider} = setup_user_and_token()
      auth = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{outsider}")

      conn1 = post(auth, "/api/v1/organizations/#{org.id}/invites", %{"role" => "member"})

      assert conn1.status in [401, 403, 404]
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp mint_invite(org_id, opts) do
    Starter.Organizations.create_invite_token(%{
      organization_id: org_id,
      email: Keyword.get(opts, :email),
      role: Keyword.get(opts, :role, "viewer"),
      max_uses: Keyword.get(opts, :max_uses),
      starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
  end

  defp revoke(invite) do
    :ok = Starter.Organizations.revoke_invite(invite.organization_id, invite.id)
  end
end
