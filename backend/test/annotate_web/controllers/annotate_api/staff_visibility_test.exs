defmodule AnnotateWeb.AnnotateAPI.StaffVisibilityTest do
  @moduledoc """
  `comment_policy.read_visibility = "staff_only"` leak tests (T-25) and the
  permission endpoints `GET /me` + `/config` (T-26).

  User A starts a thread; user B (non-staff) must not learn it exists through
  list, get-by-id (reply / resolve / reopen / re-anchor), comment by id
  (edit / delete), counts, attachment urls or deep links (all derived from the
  list), or realtime. Search: no search endpoint exists. Staff (bridge
  member, legacy owner, host-asserted role under trust_host_roles) see all.
  """
  use AnnotateWeb.AnnotateAPICase, async: true

  alias Annotate.Auth.ApiToken
  alias Annotate.Comments
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.{Attachment, Commenter, SiteMember}
  alias Annotate.Schema.Users.User
  alias Annotate.SiteMembers
  alias Annotate.Sites

  @now System.system_time(:second)
  @page "/vis/page"

  # ── helpers ───────────────────────────────────────────────────

  defp staff_only_site(policy \\ %{}),
    do: create_site(comment_policy: Map.merge(%{"read_visibility" => "staff_only"}, policy))

  defp api(conn, token),
    do:
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{token}")

  defp list(conn, site, token \\ nil) do
    conn = put_req_header(conn, "origin", @good_origin)
    conn = if token, do: put_req_header(conn, "authorization", "Bearer #{token}"), else: conn
    conn |> get("/api/v1/sites/#{site.slug}/threads?page_key=#{@page}") |> json_response(200)
  end

  defp ids(%{"threads" => threads}), do: threads |> Enum.map(& &1["id"]) |> Enum.sort()

  defp thread!(site, commenter, body \\ "secret from A"),
    do: create_thread!(site, commenter, %{"page_key" => @page, "body_md" => body})

  defp member_commenter!(site, role) do
    email = "staff-#{System.unique_integer([:positive])}@corp.example"

    u =
      Repo.insert!(%User{id: Ecto.UUID.generate(), email: email, status: :active, verified: true})

    Repo.insert!(%SiteMember{site_id: site.id, user_id: u.id, role: role})

    c =
      Repo.insert!(%Commenter{
        authentik_sub: "ak-#{System.unique_integer([:positive])}",
        email: email,
        email_verified: true,
        display_name: "Staff #{role}"
      })

    {u, c, ApiToken.issue_access(c, site, @good_origin, :bridge)}
  end

  defp host_jwt(service_key, claims) do
    jwk = %{
      "kty" => "oct",
      "k" => Base.url_encode64(:crypto.hash(:sha256, service_key), padding: false)
    }

    jwk |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims) |> JOSE.JWS.compact() |> elem(1)
  end

  defp assert_host(conn, site, key, claims) do
    conn
    |> put_req_header("origin", @good_origin)
    |> post("/api/v1/sites/#{site.slug}/token/assert", %{
      "token" => host_jwt(key, Map.merge(%{"exp" => @now + 60}, claims))
    })
    |> json_response(201)
  end

  defp setup_ab(policy \\ %{}) do
    {site, key} = staff_only_site(policy)
    a = create_commenter()
    b = create_commenter()
    ta = thread!(site, a)
    tb = thread!(site, b, "B's own")
    %{site: site, key: key, a: a, b: b, ta: ta, tb: tb}
  end

  # ── setting ───────────────────────────────────────────────────

  describe "setting" do
    test "defaults to public; owner security update accepts only known values" do
      {site, _} = create_site()
      assert Sites.read_visibility(site) == :public

      {:ok, site} =
        Sites.update_site_security(site, %{
          "comment_policy" => %{"read_visibility" => "staff_only"}
        })

      assert Sites.read_visibility(site) == :staff_only

      assert {:error, :invalid_policy} =
               Sites.update_site_security(site, %{
                 "comment_policy" => %{"read_visibility" => "everyone"}
               })

      # display (admin) settings can never flip it
      {:ok, site} =
        Sites.update_site_display(site, %{"settings" => %{"read_visibility" => "public"}})

      assert Sites.read_visibility(site) == :staff_only
    end

    test "public sites are unchanged: everyone sees every thread", %{conn: conn} do
      {site, _} = create_site()
      a = create_commenter()
      b = create_commenter()
      ta = thread!(site, a)
      assert ids(list(conn, site, issue_access(b, site))) == [ta.id]
      assert ids(list(build_conn(), site)) == [ta.id]
    end
  end

  # ── leak tests: user B vs user A's thread ─────────────────────

  describe "list" do
    test "non-staff see only their own threads (with every reply, staff replies included)",
         %{conn: conn} do
      %{site: site, b: b, tb: tb, ta: ta} = setup_ab()
      {_u, staff, _} = member_commenter!(site, :member)
      {:ok, _} = Comments.add_comment(tb, staff, %{"body_md" => "staff reply to B"})
      {:ok, _} = Comments.add_comment(ta, staff, %{"body_md" => "staff reply to A"})

      body = list(conn, site, issue_access(b, site))
      assert ids(body) == [tb.id]
      [t] = body["threads"]

      assert Enum.map(t["comments"], & &1["body_md"]) |> Enum.sort() ==
               ["B's own", "staff reply to B"]

      encoded = Jason.encode!(body)
      refute encoded =~ "secret from A"
      refute encoded =~ "staff reply to A"
      refute encoded =~ ta.id
    end

    test "anonymous readers see nothing under staff_only", %{conn: conn} do
      %{site: site} = setup_ab()
      assert list(conn, site) == %{"threads" => []}
    end

    test "page-level count leaks nothing: B's list length counts only B's threads",
         %{conn: conn} do
      %{site: site, b: b, a: a} = setup_ab()
      thread!(site, a, "A again")
      assert length(list(conn, site, issue_access(b, site))["threads"]) == 1
    end
  end

  describe "staff see everything" do
    test "bridge member, admin and owner; legacy owner_commenter_id", %{conn: conn} do
      %{site: site, ta: ta, tb: tb} = setup_ab()
      all = Enum.sort([ta.id, tb.id])

      for role <- [:member, :admin, :owner] do
        {_u, _c, token} = member_commenter!(site, role)
        assert ids(list(build_conn(), site, token)) == all
      end

      legacy = create_commenter()
      site = set_owner!(site, legacy)
      assert ids(list(conn, site, issue_access(legacy, site))) == all
    end

    test "membership removal takes effect on the next request (token still valid)",
         %{conn: conn} do
      %{site: site, ta: ta, tb: tb} = setup_ab()
      {u, _c, token} = member_commenter!(site, :member)
      assert ids(list(conn, site, token)) == Enum.sort([ta.id, tb.id])

      {:ok, _} = SiteMembers.remove_member(site, u.id)
      assert ids(list(build_conn(), site, token)) == []
    end
  end

  describe "host-asserted staff (IN direction)" do
    test "honoured only while trust_host_roles is on; carried across refresh with origin binding",
         %{conn: conn} do
      %{site: site, key: key, ta: ta, tb: tb} = setup_ab(%{"trust_host_roles" => true})
      all = Enum.sort([ta.id, tb.id])

      %{"access_token" => a, "refresh_token" => r} =
        assert_host(conn, site, key, %{"sub" => "host-admin", "team_role" => "member"})

      assert ids(list(build_conn(), site, a)) == all

      %{"access_token" => a2} =
        build_conn()
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => r})
        |> json_response(200)

      {:ok, claims} = ApiToken.verify(a2)
      assert claims["origin"] == @good_origin
      assert ids(list(build_conn(), site, a2)) == all

      {:ok, _} =
        Sites.update_site_security(site, %{"comment_policy" => %{"trust_host_roles" => false}})

      # same, still-valid access token: no longer staff on the very next read
      assert ids(list(build_conn(), site, a2)) == []
    end

    test "team_role claim ignored when trust_host_roles is off", %{conn: conn} do
      %{site: site, key: key} = setup_ab()

      %{"access_token" => a} =
        assert_host(conn, site, key, %{"sub" => "pretender", "team_role" => "owner"})

      assert ids(list(build_conn(), site, a)) == []
    end
  end

  describe "get-by-id / deep-link targets → 404" do
    test "reply, resolve, reopen, re-anchor on A's thread are 404 for B; B's own work",
         %{conn: conn} do
      %{site: site, b: b, ta: ta, tb: tb} = setup_ab()
      tok = issue_access(b, site)
      q = "?site=#{site.slug}"

      for {method, path, body} <- [
            {:post, "/api/v1/threads/#{ta.id}/comments#{q}", %{"body_md" => "hi"}},
            {:post, "/api/v1/threads/#{ta.id}/resolve#{q}", %{}},
            {:post, "/api/v1/threads/#{ta.id}/reopen#{q}", %{}},
            {:patch, "/api/v1/threads/#{ta.id}/anchor#{q}", %{"anchor" => %{"css" => "p"}}}
          ] do
        resp = build_conn() |> api(tok) |> dispatch(@endpoint, method, path, body)
        assert json_response(resp, 404) == %{"error" => "not_found"}
        refute resp.resp_body =~ "secret from A"
      end

      assert conn
             |> api(tok)
             |> post("/api/v1/threads/#{tb.id}/comments#{q}", %{"body_md" => "more"})
             |> json_response(201)
    end

    test "edit / delete A's comment are 404 for B (not 403)", %{conn: conn} do
      %{site: site, b: b, ta: ta} = setup_ab()
      [c] = Repo.preload(ta, :comments).comments
      tok = issue_access(b, site)

      assert conn
             |> api(tok)
             |> patch("/api/v1/comments/#{c.id}?site=#{site.slug}", %{"body_md" => "x"})
             |> json_response(404) == %{"error" => "not_found"}

      assert build_conn()
             |> api(tok)
             |> delete("/api/v1/comments/#{c.id}?site=#{site.slug}")
             |> json_response(404) == %{"error" => "not_found"}
    end

    test "deep_link of A's thread never appears in B's (or anonymous) reads", %{conn: conn} do
      %{site: site, b: b, ta: ta} = setup_ab()

      [rendered] =
        AnnotateWeb.AnnotateAPI.Renderer.thread_list([Repo.preload(ta, [:creator, :comments])])

      link = rendered["deep_link"]

      for body <- [list(conn, site, issue_access(b, site)), list(build_conn(), site)] do
        refute Jason.encode!(body) =~ ta.id
        if link, do: refute(Jason.encode!(body) =~ link)
      end
    end
  end

  describe "attachments" do
    test "presigned GET urls of A's attachment are never minted for B", %{conn: conn} do
      {site, _} = staff_only_site()
      a = create_commenter()
      b = create_commenter()

      att =
        Repo.insert!(%Attachment{
          uploader_id: a.id,
          site_id: site.id,
          kind: :image,
          storage_key: "annotate/#{site.id}/#{Ecto.UUID.generate()}/a-secret.png",
          content_type: "image/png",
          bytes: 10,
          status: :ready
        })

      create_thread!(site, a, %{"page_key" => @page, "attachment_ids" => [att.id]})

      refute Jason.encode!(list(conn, site, issue_access(b, site))) =~ "a-secret.png"

      {_u, _c, staff} = member_commenter!(site, :admin)
      assert Jason.encode!(list(build_conn(), site, staff)) =~ "a-secret.png"
    end
  end

  # ── permission endpoints (OUT direction) ──────────────────────

  describe "GET /me and /config permissions" do
    test "anonymous", %{conn: conn} do
      {site, _} = staff_only_site(%{"allow_anonymous" => true})

      assert conn |> get("/api/v1/sites/#{site.slug}/me") |> json_response(200) == %{
               "authenticated" => false,
               "role" => nil,
               "staff" => false,
               "can_read_all" => false,
               "can_moderate" => false,
               "can_post" => true,
               "read_visibility" => "staff_only"
             }
    end

    test "non-staff commenter vs member vs admin", %{conn: conn} do
      {site, _} = staff_only_site()
      b = create_commenter()

      assert %{
               "authenticated" => true,
               "role" => nil,
               "staff" => false,
               "can_read_all" => false,
               "can_moderate" => false,
               "can_post" => true
             } =
               conn
               |> api(issue_access(b, site))
               |> get("/api/v1/sites/#{site.slug}/me")
               |> json_response(200)

      {_u, _c, member} = member_commenter!(site, :member)

      assert %{
               "role" => "member",
               "staff" => true,
               "can_read_all" => true,
               "can_moderate" => false
             } =
               build_conn()
               |> api(member)
               |> get("/api/v1/sites/#{site.slug}/me")
               |> json_response(200)

      {_u, _c, admin} = member_commenter!(site, :admin)

      cfg =
        build_conn()
        |> api(admin)
        |> get("/api/v1/sites/#{site.slug}/config")
        |> json_response(200)

      assert %{
               "role" => "admin",
               "staff" => true,
               "can_moderate" => true,
               "team" => true,
               "read_visibility" => "staff_only"
             } = cfg
    end

    test "public site: everyone can_read_all; server-to-server (no Origin) works with a token",
         %{conn: conn} do
      {site, _} = create_site()
      b = create_commenter()

      assert %{"can_read_all" => true, "read_visibility" => "public", "staff" => false} =
               conn
               |> put_req_header("authorization", "Bearer #{issue_access(b, site)}")
               |> get("/api/v1/sites/#{site.slug}/me")
               |> json_response(200)
    end

    test "no PII in the permission payload", %{conn: conn} do
      {site, _} = staff_only_site()
      b = create_commenter(email: "pii@corp.example", display_name: "Private Name")

      body =
        conn
        |> api(issue_access(b, site))
        |> get("/api/v1/sites/#{site.slug}/me")
        |> json_response(200)

      encoded = Jason.encode!(body)
      refute encoded =~ "pii@corp.example"
      refute encoded =~ "Private Name"
      refute encoded =~ b.id
    end
  end
end
