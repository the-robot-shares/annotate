defmodule AnnotateWeb.AnnotateAPI.CORSTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  setup %{conn: conn} do
    {site, _key} = create_site()
    commenter = create_commenter()
    {:ok, conn: conn, site: site, commenter: commenter}
  end

  test "allowed origin echoed verbatim on the thread list", %{conn: conn, site: site} do
    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == [@good_origin]
  end

  test "foreign origin → 403, no ACAO header", %{conn: conn, site: site} do
    conn =
      conn
      |> put_req_header("origin", @evil_origin)
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert conn.status == 403
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "no origin header (non-browser) → passes through without ACAO", %{conn: conn, site: site} do
    conn = get(conn, "/api/v1/sites/#{site.slug}/threads?page_key=/p")
    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "preflight allowed: 204 + methods/headers, no credentials", %{conn: conn, site: site} do
    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "authorization, content-type")
      |> options("/api/v1/sites/#{site.slug}/threads")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == [@good_origin]

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET, POST, PUT, PATCH, DELETE, OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-headers") == [
             "authorization, content-type, x-annotate-site"
           ]

    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "preflight foreign origin → 403", %{conn: conn, site: site} do
    conn =
      conn
      |> put_req_header("origin", @evil_origin)
      |> put_req_header("access-control-request-method", "POST")
      |> options("/api/v1/sites/#{site.slug}/threads")

    assert conn.status == 403
  end

  test "token-bound route preflight resolves site via ?site= query", %{conn: conn, site: site} do
    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("access-control-request-method", "POST")
      |> options(
        "/api/v1/threads/00000000-0000-0000-0000-000000000000/comments?site=#{site.slug}"
      )

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == [@good_origin]
  end

  test "unresolvable site with origin → 403", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> get("/api/v1/sites/does-not-exist/threads?page_key=/p")

    assert conn.status == 403
    assert json_response(conn, 403)["error"] == "origin_not_allowed"
  end

  test "second registered origin works; origin not listed fails", %{conn: conn} do
    {site, _} =
      create_site(origins: ["https://a.example", "https://b.example"])

    ok =
      conn
      |> put_req_header("origin", "https://b.example")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert ok.status == 200

    bad =
      build_conn()
      |> Map.put(:host, @site_host)
      |> put_req_header("origin", "https://c.example")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert bad.status == 403
  end
end
