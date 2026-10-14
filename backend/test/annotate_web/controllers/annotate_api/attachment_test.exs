defmodule AnnotateWeb.AnnotateAPI.AttachmentTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  setup %{conn: conn} do
    {site, _key} = create_site()
    uploader = create_commenter()
    token = issue_access(uploader, site)

    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn, site: site, uploader: uploader}
  end

  describe "POST /api/v1/attachments/presign" do
    test "creates pending attachment + presigned PUT url", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/presign?site=#{site.slug}", %{
          "filename" => "screenshot 2026.png",
          "content_type" => "image/png",
          "bytes" => 2048,
          "kind" => "screenshot"
        })

      assert %{"attachment" => a, "upload_url" => url} = json_response(conn, 201)
      assert a["status"] == "pending"
      assert a["kind"] == "screenshot"
      assert url =~ "annotate-test-bucket"
      assert url =~ "X-Amz-Signature"
      # sanitized key path
      refute url =~ " "
    end

    test "kind defaults to file", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/presign?site=#{site.slug}", %{
          "filename" => "notes.txt",
          "content_type" => "text/plain",
          "bytes" => 12
        })

      assert %{"attachment" => %{"kind" => "file"}} = json_response(conn, 201)
    end

    test "disallowed content type → 400", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/presign?site=#{site.slug}", %{
          "filename" => "evil.exe",
          "content_type" => "application/x-msdownload",
          "bytes" => 12
        })

      assert %{"error" => "unsupported_content_type"} = json_response(conn, 400)
    end

    test "oversized upload → 413", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/presign?site=#{site.slug}", %{
          "filename" => "big.png",
          "content_type" => "image/png",
          "bytes" => 21 * 1024 * 1024
        })

      assert %{"error" => "too_large"} = json_response(conn, 413)
    end

    test "missing filename → 400", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/presign?site=#{site.slug}", %{
          "content_type" => "image/png",
          "bytes" => 12
        })

      assert %{"error" => "invalid_request"} = json_response(conn, 400)
    end
  end

  describe "POST /api/v1/attachments/:id/complete" do
    test "pending → ready; second complete → 409", %{conn: conn, site: site, uploader: uploader} do
      {:ok, attachment, _url} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "a.png",
          content_type: "image/png",
          bytes: 10,
          kind: :image
        })

      conn =
        conn
        |> post("/api/v1/attachments/#{attachment.id}/complete?site=#{site.slug}", %{
          "width" => 100,
          "height" => 50
        })

      assert %{"attachment" => %{"status" => "ready", "width" => 100}} = json_response(conn, 200)

      again =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{issue_access(uploader, site)}")
        |> post("/api/v1/attachments/#{attachment.id}/complete?site=#{site.slug}", %{})

      assert %{"error" => "not_pending"} = json_response(again, 409)
    end

    test "non-uploader cannot complete someone else's attachment → 403", %{
      conn: conn,
      site: site,
      uploader: uploader
    } do
      {:ok, attachment, _url} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "theirs.png",
          content_type: "image/png",
          bytes: 10,
          kind: :image
        })

      other = create_commenter()

      hijack =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{issue_access(other, site)}")
        |> post("/api/v1/attachments/#{attachment.id}/complete?site=#{site.slug}", %{
          "width" => 1
        })

      assert %{"error" => "forbidden"} = json_response(hijack, 403)

      # still pending — the hijack did not mutate it
      assert Annotate.Repo.reload!(attachment).status == :pending

      # the real uploader can still complete it
      ok =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{issue_access(uploader, site)}")
        |> post("/api/v1/attachments/#{attachment.id}/complete?site=#{site.slug}", %{})

      assert %{"attachment" => %{"status" => "ready"}} = json_response(ok, 200)
    end

    test "unknown attachment id → 404", %{conn: conn, site: site} do
      conn =
        conn
        |> post("/api/v1/attachments/#{Ecto.UUID.generate()}/complete?site=#{site.slug}", %{})

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "stale pending sweep" do
    test "sweep_stale_pending deletes old pending only", %{site: site, uploader: uploader} do
      {:ok, old, _} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "old.png",
          content_type: "image/png",
          bytes: 1,
          kind: :image
        })

      {:ok, fresh, _} =
        Annotate.Comments.create_pending_attachment(site, uploader, %{
          filename: "fresh.png",
          content_type: "image/png",
          bytes: 1,
          kind: :image
        })

      cutoff = DateTime.add(DateTime.utc_now(), -25 * 60 * 60)

      Annotate.Repo.query!("UPDATE attachments SET inserted_at = $1 WHERE id = $2", [
        cutoff,
        Ecto.UUID.dump!(old.id)
      ])

      {:ok, worker} =
        Annotate.Workers.AttachmentSweeper.new(%{}) |> Oban.insert()

      assert :ok =
               Annotate.Workers.AttachmentSweeper.perform(%Oban.Job{
                 args: %{},
                 id: worker.id
               })

      refute Annotate.Repo.get(Annotate.Schema.Annotate.Attachment, old.id)
      assert Annotate.Repo.get(Annotate.Schema.Annotate.Attachment, fresh.id)
    end
  end
end
