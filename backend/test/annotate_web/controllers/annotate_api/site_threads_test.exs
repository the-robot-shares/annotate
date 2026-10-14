defmodule AnnotateWeb.AnnotateAPI.SiteThreadsTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  describe "POST /api/v1/sites/:site/threads" do
    test "creates page, thread and root comment; anonymous guest allowed", %{conn: conn} do
      {site, _key} = create_site()

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/1",
          "url" => "https://good.example/p/1",
          "title" => "Page 1",
          "anchor" => %{"css" => "#hero"},
          "body_md" => "hello thread"
        })

      assert %{"thread" => thread} = json_response(conn, 201)
      assert thread["status"] == "open"
      assert thread["anchor"] == %{"css" => "#hero"}
      assert [%{"body_md" => "hello thread", "author" => nil}] = thread["comments"]

      # page upserted
      assert Annotate.Repo.get_by!(Annotate.Schema.Annotate.Page,
               site_id: site.id,
               page_key: "/p/1"
             ).title == "Page 1"
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

      create_thread!(site, uploader, %{"attachment_ids" => [attachment.id]})

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/threads", %{
          "page_key" => "/p/3",
          "anchor" => %{"css" => "h1"},
          "body_md" => "x",
          "attachment_ids" => [attachment.id]
        })

      assert %{"error" => "attachment_mismatch"} = json_response(conn, 422)
    end

    test "400 on missing anchor", %{conn: conn} do
      {site, _key} = create_site()

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/threads", %{"page_key" => "/p", "body_md" => "x"})

      assert %{"error" => "invalid_anchor"} = json_response(conn, 400)
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

    test "deleted comments are excluded", %{conn: conn} do
      {site, _key} = create_site()
      commenter = create_commenter()
      thread = create_thread!(site, commenter)
      root = hd(Annotate.Repo.preload(thread, [:comments]).comments)

      {:ok, _} = Annotate.Comments.soft_delete_comment(root)

      conn =
        conn
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")

      assert %{"threads" => [%{"comments" => []}]} = json_response(conn, 200)
    end

    test "unknown site → 404", %{conn: conn} do
      conn = get(conn, "/api/v1/sites/nope-nope/threads?page_key=/x")
      assert %{"error" => "site_not_found"} = json_response(conn, 404)
    end
  end
end
