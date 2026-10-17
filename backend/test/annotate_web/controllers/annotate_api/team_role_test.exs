defmodule AnnotateWeb.AnnotateAPI.TeamRoleTest do
  @moduledoc """
  team_role claim: issuance per source, refresh carry-over (origin binding
  kept), S1 regression (host-assert can never light the email bridge),
  per-request membership re-check for moderation (Q1-b), and GET /config.
  """
  use AnnotateWeb.AnnotateAPICase, async: true

  alias Annotate.Auth.ApiToken
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.{Commenter, SiteMember}
  alias Annotate.Schema.Users.User
  alias Annotate.SiteMembers
  alias Annotate.Sites

  @now System.system_time(:second)

  defp host_jwt(service_key, claims) do
    jwk = %{
      "kty" => "oct",
      "k" => Base.url_encode64(:crypto.hash(:sha256, service_key), padding: false)
    }

    jwk |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims) |> JOSE.JWS.compact() |> elem(1)
  end

  defp claims!(token) do
    {:ok, claims} = ApiToken.verify(token)
    claims
  end

  defp member_user!(site, email, role) do
    u =
      Repo.insert!(%User{id: Ecto.UUID.generate(), email: email, status: :active, verified: true})

    Repo.insert!(%SiteMember{site_id: site.id, user_id: u.id, role: role})
    u
  end

  defp sso_commenter!(email, verified \\ true) do
    Repo.insert!(%Commenter{
      authentik_sub: "ak-#{System.unique_integer([:positive])}",
      email: email,
      email_verified: verified,
      display_name: "SSO #{email}"
    })
  end

  defp api(conn, token),
    do:
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{token}")

  defp refresh(conn, site, raw) do
    conn
    |> put_req_header("origin", @good_origin)
    |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => raw})
  end

  describe "bridge (Authentik commenter)" do
    test "verified member gets team_role; refresh re-derives from current membership", %{
      conn: conn
    } do
      {site, _} = create_site()
      u = member_user!(site, "admin@corp.example", :admin)
      c = sso_commenter!("admin@corp.example")

      {:ok, %{access_token: a, refresh_token: r}} =
        ApiToken.issue_pair(c, site, @good_origin, nil, :bridge)

      assert %{"team_role" => "admin", "team_src" => "bridge"} = claims!(a)

      {:ok, _} = SiteMembers.remove_member(site, u.id)

      %{"access_token" => a2, "refresh_token" => _} =
        conn |> refresh(site, r) |> json_response(200)

      refute Map.has_key?(claims!(a2), "team_role")
    end

    test "unverified IdP email → no claim", %{conn: _conn} do
      {site, _} = create_site()
      member_user!(site, "m@corp.example", :member)
      c = sso_commenter!("m@corp.example", false)

      refute Map.has_key?(
               claims!(ApiToken.issue_access(c, site, @good_origin, :bridge)),
               "team_role"
             )
    end
  end

  describe "host-assert" do
    test "team_role honoured only with trust_host_roles; survives refresh only while trust is on",
         %{conn: conn} do
      {site, key} = create_site(comment_policy: %{"trust_host_roles" => true})

      token =
        host_jwt(key, %{
          "sub" => "qa-1",
          "name" => "QA",
          "team_role" => "admin",
          "exp" => @now + 60
        })

      %{"access_token" => a, "refresh_token" => r} =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{"token" => token})
        |> json_response(201)

      assert %{"team_role" => "admin", "team_src" => "host"} = claims!(a)

      %{"access_token" => a2, "refresh_token" => r2} =
        build_conn() |> refresh(site, r) |> json_response(200)

      assert %{"team_role" => "admin"} = claims!(a2)
      # origin binding preserved on the carried-over token
      assert claims!(a2)["origin"] == @good_origin

      {:ok, _} =
        Sites.update_site_security(site, %{"comment_policy" => %{"trust_host_roles" => false}})

      %{"access_token" => a3} = build_conn() |> refresh(site, r2) |> json_response(200)
      refute Map.has_key?(claims!(a3), "team_role")
    end

    test "team_role ignored without trust_host_roles; invalid role ignored", %{conn: conn} do
      {site, key} = create_site()

      %{"access_token" => a} =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(key, %{"sub" => "x", "team_role" => "owner", "exp" => @now + 60})
        })
        |> json_response(201)

      refute Map.has_key?(claims!(a), "team_role")

      {site2, key2} = create_site(comment_policy: %{"trust_host_roles" => true})

      %{"access_token" => b} =
        build_conn()
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site2.slug}/token/assert", %{
          "token" =>
            host_jwt(key2, %{"sub" => "y", "team_role" => "superuser", "exp" => @now + 60})
        })
        |> json_response(201)

      refute Map.has_key?(claims!(b), "team_role")
    end

    test "S1: a host asserting email_verified + a member's email never inherits the team role", %{
      conn: conn
    } do
      {site, key} = create_site()
      member_user!(site, "owner@corp.example", :owner)

      assert_fn = fn c ->
        c
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" =>
            host_jwt(key, %{
              "sub" => "attacker",
              "email" => "owner@corp.example",
              "email_verified" => true,
              "exp" => @now + 60
            })
        })
        |> json_response(201)
      end

      _ = assert_fn.(conn)
      %{"refresh_token" => r} = assert_fn.(build_conn())

      stored = Repo.get_by!(Commenter, site_id: site.id, external_id: "attacker")
      assert stored.email_verified == nil

      %{"access_token" => a} = build_conn() |> refresh(site, r) |> json_response(200)
      refute Map.has_key?(claims!(a), "team_role")
    end
  end

  describe "moderation re-checks membership per request (Q1-b)" do
    setup do
      {site, _} = create_site()
      author = create_commenter(authentik_sub: "ak-author")

      {:ok, thread} =
        Annotate.Comments.create_thread(site, author, %{
          "page_key" => "/p",
          "body_md" => "hi",
          "anchor" => %{"css" => "#x"}
        })

      [comment] = thread.comments
      %{site: site, comment: comment}
    end

    test "admin deletes another's comment; after removal the same token is refused", %{
      conn: conn,
      site: site,
      comment: comment
    } do
      u = member_user!(site, "mod@corp.example", :admin)
      mod = sso_commenter!("mod@corp.example")
      token = ApiToken.issue_access(mod, site, @good_origin, :bridge)
      assert %{"team_role" => "admin"} = claims!(token)

      {:ok, _} = SiteMembers.remove_member(site, u.id)

      assert conn
             |> api(token)
             |> delete("/api/v1/comments/#{comment.id}?site=#{site.slug}")
             |> Map.get(:status) == 403

      Repo.insert!(%SiteMember{site_id: site.id, user_id: u.id, role: :admin})

      assert build_conn()
             |> api(token)
             |> delete("/api/v1/comments/#{comment.id}?site=#{site.slug}")
             |> Map.get(:status) == 204
    end

    test "a plain member cannot moderate", %{conn: conn, site: site, comment: comment} do
      member_user!(site, "mem@corp.example", :member)
      c = sso_commenter!("mem@corp.example")
      token = ApiToken.issue_access(c, site, @good_origin, :bridge)

      assert conn
             |> api(token)
             |> delete("/api/v1/comments/#{comment.id}?site=#{site.slug}")
             |> Map.get(:status) == 403
    end
  end

  describe "GET /api/v1/sites/:site/config" do
    test "public, no PII, team flag from live membership", %{conn: conn} do
      {site, _} = create_site()

      body =
        conn
        |> put_req_header("origin", @good_origin)
        |> get("/api/v1/sites/#{site.slug}/config")
        |> json_response(200)

      assert Map.keys(body) |> Enum.sort() ==
               ~w(allow_anonymous authenticated can_moderate can_post can_read_all default_visibility
                  max_upload_mb page_key_strategy public_read read_visibility role site staff team)

      assert body["team"] == false and body["default_visibility"] == "public"

      member_user!(site, "t@corp.example", :member)
      c = sso_commenter!("t@corp.example")
      token = ApiToken.issue_access(c, site, @good_origin, :bridge)

      assert %{"team" => true} =
               build_conn()
               |> api(token)
               |> get("/api/v1/sites/#{site.slug}/config")
               |> json_response(200)
    end

    test "token for another site is rejected", %{conn: conn} do
      {site, _} = create_site()
      {other, _} = create_site()
      token = issue_access(create_commenter(), other)

      assert conn |> api(token) |> get("/api/v1/sites/#{site.slug}/config") |> Map.get(:status) ==
               403
    end
  end
end
