defmodule AnnotateWeb.MarketingLandingTest do
  use AnnotateWeb.ConnCase, async: false

  @marketing_host "annotate.therobotlives.com"
  @api_host "annotate-srv.therobotlives.com"

  setup do
    original = Application.get_env(:annotate, :marketing)
    on_exit(fn -> Application.put_env(:annotate, :marketing, original) end)
    :ok
  end

  test "GET / on the marketing host renders the landing page", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, @marketing_host)
      |> get("/")

    assert conn.status == 200
    body = html_response(conn, 200)
    assert body =~ "Feedback that points at the thing."
    assert body =~ "noizu-page-comments"
    assert body =~ "cdn.derobot.is"

    csp = get_resp_header(conn, "content-security-policy") |> List.first()
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "script-src 'self' 'unsafe-inline' https://cdn.derobot.is"
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "GET / on the API host redirects to the marketing host", %{conn: conn} do
    Application.put_env(:annotate, :marketing,
      host: @marketing_host,
      api_host: @api_host,
      api_base: "https://#{@api_host}",
      widget_src:
        "https://cdn.derobot.is/tobor-kit/sha-eb1ebf97b6f0a058f15aea55b50e29cfd4c34e09/components/page-comments/page-comments.js",
      dogfood_site: "annotate-landing"
    )

    conn =
      conn
      |> Map.put(:host, @api_host)
      |> get("/")

    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["https://#{@marketing_host}/"]
  end

  test "GET / on localhost renders without redirect", %{conn: conn} do
    conn = get(conn, "/")

    assert conn.status == 200
    assert html_response(conn, 200) =~ "Feedback that points at the thing."
  end

  test "landing stylesheet is served", %{conn: conn} do
    conn = get(conn, "/css/landing.css")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/css"
  end
end
