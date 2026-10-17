defmodule AnnotateWeb.AnnotateAPI.SiteThreadsTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  describe "POST /api/v1/sites/:site/threads" do
    test "token-less create rejected by default (allow_anonymous not opted in)", %{conn: conn} do
      {site, _key} = create_site()

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/0",
          "anchor" => %{"css" => "#x"},
          "body_md" => "nope"
        })

      assert %{"error" => "invalid_token"} = json_response(conn, 401)
    end

    test "allow_anonymous opt-in: guest_name creates thread attributed to a site-scoped guest row",
         %{conn: conn} do
      {site, _key} = create_site(comment_policy: %{"allow_anonymous" => true})

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/1",
          "url" => "https://good.example/p/1",
          "title" => "Page 1",
          "anchor" => %{"css" => "#hero"},
          "body_md" => "hello thread",
          "guest_name" => "  Guest Gary  "
        })

      assert %{"thread" => thread} = json_response(conn, 201)
      assert thread["status"] == "open"
      assert [%{"body_md" => "hello thread", "author" => author}] = thread["comments"]
      assert author["display_name"] == "Guest Gary"

      # guest row: site-scoped, no credentials, display_name = trimmed name
      guest = Annotate.Repo.get!(Annotate.Schema.Annotate.Commenter, author["id"])
      assert guest.site_id == site.id
      assert guest.display_name == "Guest Gary"
      assert guest.external_id == "guest:Guest Gary"
      assert is_nil(guest.authentik_sub)

      # page upserted
      assert Annotate.Repo.get_by!(Annotate.Schema.Annotate.Page,
               site_id: site.id,
               page_key: "/p/1"
             ).title == "Page 1"
    end

    test "allow_anonymous opt-in: missing/blank guest_name → 400", %{conn: conn} do
      {site, _key} = create_site(comment_policy: %{"allow_anonymous" => true})

      missing =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/1a",
          "anchor" => %{"css" => "#x"},
          "body_md" => "anon"
        })

      assert %{"error" => "guest_name_required"} = json_response(missing, 400)

      blank =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/1b",
          "anchor" => %{"css" => "#x"},
          "body_md" => "anon",
          "guest_name" => "   "
        })

      assert %{"error" => "guest_name_required"} = json_response(blank, 400)
    end

    test "attributed to token commenter when Authorization present", %{conn: conn} do
      {site, _key} = create_site()
      commenter = create_commenter()
      token = issue_access(commenter, site)

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/2",
          "anchor" => %{"css" => "h2"},
          "body_md" => "attributed"
        })

      assert %{"thread" => %{"comments" => [%{"author" => author}]}} = json_response(conn, 201)
      assert author["id"] == commenter.id
    end

    test "422 on attachment mismatch (foreign or already-bound attachment)", %{conn: conn} do
      {site, _key} = create_site()
      uploader = create_commenter()

      {:ok, attachment, _url} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "a.png",
          content_type: "image/png",
          bytes: 10,
          kind: :image
        })

      {:ok, _} = Annotate.Comments.complete_attachment(attachment, %{})

      create_thread!(site, uploader, %{"attachment_ids" => [attachment.id]})

      # already-bound attachment (and, per the same check, foreign/pending
      # uploads) is refused with 422 even with a valid token
      other = create_commenter()

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{issue_access(other, site)}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/3",
          "anchor" => %{"css" => "h1"},
          "body_md" => "x",
          "attachment_ids" => [attachment.id]
        })

      assert %{"error" => "attachment_mismatch"} = json_response(conn, 422)
    end

    test "422 binding someone else's ready attachment (not the author's own)", %{conn: conn} do
      {site, _key} = create_site()
      owner = create_commenter()
      attacker = create_commenter()

      {:ok, attachment, _url} =
        Annotate.Comments.create_pending_attachment(site, owner, %{
          filename: "mine.png",
          content_type: "image/png",
          bytes: 10,
          kind: :image
        })

      {:ok, _} = Annotate.Comments.complete_attachment(attachment, %{})

      token = issue_access(attacker, site)

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/4",
          "anchor" => %{"css" => "h1"},
          "body_md" => "sticker theft",
          "attachment_ids" => [attachment.id]
        })

      assert %{"error" => "attachment_mismatch"} = json_response(conn, 422)
    end

    test "422 binding a still-pending attachment (not ready)", %{conn: conn} do
      {site, _key} = create_site()
      uploader = create_commenter()
      token = issue_access(uploader, site)

      {:ok, attachment, _url} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "notyet.png",
          content_type: "image/png",
          bytes: 10,
          kind: :image
        })

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/5",
          "anchor" => %{"css" => "h1"},
          "body_md" => "premature",
          "attachment_ids" => [attachment.id]
        })

      assert %{"error" => "attachment_mismatch"} = json_response(conn, 422)
    end

    test "400 on missing anchor", %{conn: conn} do
      {site, _key} = create_site()
      token = issue_access(create_commenter(), site)

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{"page_key" => "/p", "body_md" => "x"})

      assert %{"error" => "invalid_anchor"} = json_response(conn, 400)
    end

    test "token-bound create without Origin header → 401 origin_required", %{conn: conn} do
      {site, _key} = create_site()
      token = issue_access(create_commenter(), site)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/6",
          "anchor" => %{"css" => "#x"},
          "body_md" => "originless"
        })

      assert %{"error" => "origin_required"} = json_response(conn, 401)
    end

    test "token-less read without Origin header still allowed (reads unchanged)", %{conn: conn} do
      {site, _key} = create_site()
      create_thread!(site, create_commenter())

      conn = get(conn, "/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => [_]} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/sites/:site/threads" do
    test "lists threads with comments and presigned attachment urls", %{conn: conn} do
      {site, _key} = create_site()
      commenter = create_commenter()
      thread = create_thread!(site, commenter)

      {:ok, attachment, _put_url} =
        Annotate.Comments.create_pending_attachment(site, commenter, %{
          filename: "shot.png",
          content_type: "image/png",
          bytes: 100,
          kind: :screenshot
        })

      root_comment = hd(Annotate.Repo.preload(thread, [:comments]).comments)

      {:ok, _} =
        Annotate.Comments.complete_attachment(attachment, %{"width" => 800, "height" => 600})

      {:ok, _} =
        Annotate.Comments.add_comment(thread, commenter, %{
          "body_md" => "reply",
          "parent_id" => root_comment.id,
          "attachment_ids" => [attachment.id]
        })

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => [listed]} = json_response(conn, 200)
      assert listed["id"] == thread.id
      assert [root, reply] = listed["comments"]
      assert reply["parent_id"] == root["id"]
      assert [%{"status" => "ready", "url" => url}] = reply["attachments"]
      assert url =~ "annotate-test-bucket"
      assert url =~ "X-Amz-Signature"
    end

    test "public_read=false requires a valid token", %{conn: conn} do
      {site, _key} =
        create_site(settings: %{"public_read" => false, "max_upload_mb" => 20})

      create_thread!(site, create_commenter())

      anon =
        conn
        |> put_req_header("origin", @good_origin)
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"error" => "invalid_token"} = json_response(anon, 401)

      commenter = create_commenter()
      token = issue_access(commenter, site)

      authed =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => [_]} = json_response(authed, 200)
    end

    test "a thread whose comments are all deleted is hidden (no empty shell)", %{conn: conn} do
      {site, _key} = create_site()
      commenter = create_commenter()
      thread = create_thread!(site, commenter)
      root = hd(Annotate.Repo.preload(thread, [:comments]).comments)

      {:ok, _} = Annotate.Comments.soft_delete_comment(root)

      conn =
        conn
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => []} = json_response(conn, 200)
    end

    test "deleted root with replies stays as a redacted [deleted] placeholder", %{conn: conn} do
      {site, _key} = create_site()
      commenter = create_commenter()
      thread = create_thread!(site, commenter)
      root = hd(Annotate.Repo.preload(thread, [:comments]).comments)
      {:ok, _} = Annotate.Comments.add_comment(thread, commenter, %{"body_md" => "a reply"})
      {:ok, _} = Annotate.Comments.soft_delete_comment(root)

      conn = get(conn, "/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => [%{"comments" => [placeholder, %{"body_md" => "a reply"}]}]} =
               json_response(conn, 200)

      assert placeholder["body_md"] == "[deleted]"
      assert placeholder["deleted"] == true
      assert placeholder["author"] == nil
      assert placeholder["attachments"] == []
    end

    test "unknown site → 404", %{conn: conn} do
      conn = get(conn, "/api/v1/sites/nope-nope/threads?page_key=/x")
      assert %{"error" => "site_not_found"} = json_response(conn, 404)
    end
  end
end
