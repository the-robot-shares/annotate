defmodule AnnotateWeb.AnnotateAPI.CommentsTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  setup %{conn: conn} do
    {site, _key} = create_site()
    author = create_commenter()
    other = create_commenter()
    thread = create_thread!(site, author)
    root = hd(Annotate.Repo.preload(thread, [:comments]).comments)

    author_token = issue_access(author, site)
    other_token = issue_access(other, site)

    conn =
      conn
      |> put_req_header("origin", @good_origin)

    {:ok,
     conn: conn,
     site: site,
     author: author,
     other: other,
     thread: thread,
     root: root,
     author_token: author_token,
     other_token: other_token}
  end

  describe "POST /api/v1/threads/:id/comments" do
    test "reply with parent_id", %{
      conn: conn,
      site: site,
      thread: thread,
      root: root,
      author_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/threads/#{thread.id}/comments?site=#{site.slug}", %{
          "body_md" => "a reply",
          "parent_id" => root.id
        })

      assert %{"comment" => comment} = json_response(conn, 201)
      assert comment["parent_id"] == root.id
      assert comment["author"]["id"]
    end

    test "invalid parent → 400", %{conn: conn, site: site, thread: thread, author_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/threads/#{thread.id}/comments?site=#{site.slug}", %{
          "body_md" => "x",
          "parent_id" => Ecto.UUID.generate()
        })

      assert %{"error" => "invalid_parent"} = json_response(conn, 400)
    end

    test "thread of another site is invisible → 404", %{
      conn: conn,
      thread: thread,
      author: author
    } do
      {other_site, _} = create_site()
      other_token = issue_access(author, other_site)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{other_token}")
        |> post("/api/v1/threads/#{thread.id}/comments?site=#{other_site.slug}", %{
          "body_md" => "x"
        })

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "PATCH /api/v1/comments/:id (author only)" do
    test "author edits → 200, edited_at set", %{
      conn: conn,
      site: site,
      root: root,
      author_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/comments/#{root.id}?site=#{site.slug}", %{"body_md" => "edited"})

      assert %{"comment" => %{"body_md" => "edited", "edited_at" => edited}} =
               json_response(conn, 200)

      assert edited
    end

    test "another commenter → 403", %{conn: conn, site: site, root: root, other_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/comments/#{root.id}?site=#{site.slug}", %{"body_md" => "hijack"})

      assert %{"error" => "forbidden"} = json_response(conn, 403)
    end

    test "site owner may edit someone else's comment", %{conn: conn, site: site, root: root} do
      owner = create_commenter()
      set_owner!(site, owner)
      token = issue_access(owner, site)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/comments/#{root.id}?site=#{site.slug}", %{"body_md" => "owner edit"})

      assert %{"comment" => %{"body_md" => "owner edit"}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/v1/comments/:id (soft)" do
    test "author soft-deletes; comment disappears from reads but row remains", %{
      conn: conn,
      site: site,
      root: root,
      author_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/comments/#{root.id}?site=#{site.slug}")

      assert conn.status == 204

      assert %{"threads" => []} =
               build_conn()
               |> Map.put(:host, @site_host)
               |> get("/api/v1/sites/#{site.slug}/threads?page_key=/some/page")
               |> json_response(200)

      db_comment = Annotate.Repo.get!(Annotate.Schema.Annotate.Comment, root.id)
      refute is_nil(db_comment.deleted_at)
    end

    test "non-author commenter → 403", %{conn: conn, site: site, root: root, other_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/comments/#{root.id}?site=#{site.slug}")

      assert %{"error" => "forbidden"} = json_response(conn, 403)
    end

    test "site owner may soft-delete a guest comment", %{conn: conn, site: site, thread: thread} do
      # guest (anonymous) comment — authored via a site-scoped guest row
      {:ok, guest} = Annotate.Sites.upsert_guest_commenter(site, "Guest Greta")
      {:ok, _} = Annotate.Comments.add_comment(thread, guest, %{"body_md" => "guest"})
      thread = Annotate.Repo.preload(thread, [comments: []], force: true)
      guest_comment = thread.comments |> Enum.find(&(&1.author_id == guest.id))

      owner = create_commenter()
      set_owner!(site, owner)
      token = issue_access(owner, site)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/comments/#{guest_comment.id}?site=#{site.slug}")

      assert conn.status == 204
    end

    test "library refuses a NULL author (guests must resolve to a commenter row)", %{
      thread: thread
    } do
      assert {:error, :invalid_author} =
               Annotate.Comments.add_comment(thread, nil, %{"body_md" => "guest"})
    end
  end

  describe "resolve / reopen / anchor repair" do
    test "resolve sets status/resolved_by/at; reopen clears them", %{
      conn: conn,
      site: site,
      thread: thread,
      author_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/threads/#{thread.id}/resolve?site=#{site.slug}", %{})

      assert %{"thread" => %{"status" => "resolved", "resolved_at" => resolved_at}} =
               json_response(conn, 200)

      assert resolved_at

      conn =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/threads/#{thread.id}/reopen?site=#{site.slug}", %{})

      assert %{"thread" => %{"status" => "open", "resolved_at" => nil}} = json_response(conn, 200)
    end

    test "PATCH anchor clears orphaned_at", %{
      conn: conn,
      site: site,
      thread: thread,
      author_token: token
    } do
      {:ok, _} = Annotate.Comments.mark_thread_orphaned(thread)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/threads/#{thread.id}/anchor?site=#{site.slug}", %{
          "anchor" => %{"css" => "#new-anchor"}
        })

      assert %{"thread" => %{"anchor" => %{"css" => "#new-anchor"}, "orphaned_at" => nil}} =
               json_response(conn, 200)
    end

    test "token bound to site A rejected on site B → 403 site_mismatch", %{
      conn: conn,
      thread: _thread,
      author: author
    } do
      {site_a, _} = create_site()
      {site_b, _} = create_site()
      token_a = issue_access(author, site_a)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> post("/api/v1/threads/#{Ecto.UUID.generate()}/comments?site=#{site_b.slug}", %{
          "body_md" => "x"
        })

      assert %{"error" => "site_mismatch"} = json_response(conn, 403)
    end
  end
end
