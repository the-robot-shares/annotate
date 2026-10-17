defmodule AnnotateWeb.LegalPagesTest do
  use AnnotateWeb.ConnCase, async: false

  @marketing_host "annotate.therobotlives.com"

  defp page(conn, path) do
    conn |> Map.put(:host, @marketing_host) |> get(path)
  end

  test "GET /privacy renders the privacy policy on the marketing host", %{conn: conn} do
    conn = page(conn, "/privacy")
    body = html_response(conn, 200)

    assert body =~ "Privacy Policy"
    assert body =~ "Last updated: 2026-10-17"
    assert body =~ "CF-Connecting-IP"
    assert body =~ "Cloudflare"
    assert body =~ "GitHub"
    assert body =~ "keith.brings@noizu.com"
    assert body =~ ~s(rel="canonical" href="https://annotate.therobotlives.com/privacy")
    assert body =~ ~s(name="description")
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "GET /terms renders the terms with the as-is / no-SLA / data-loss clauses", %{conn: conn} do
    conn = page(conn, "/terms")
    body = html_response(conn, 200)

    assert body =~ "AS IS and AS AVAILABLE"
    assert body =~ "No SLA"
    assert body =~ "no uptime guarantee"
    assert body =~ "Data loss"
    assert body =~ "Limitation of liability"
    assert body =~ "Indemnity"
    assert body =~ "Acceptable use"
    assert body =~ "Last updated: 2026-10-17"
    assert body =~ ~s(rel="canonical" href="https://annotate.therobotlives.com/terms")
  end

  test "no TODO placeholders are visible on the legal pages", %{conn: conn} do
    for path <- ["/terms", "/privacy"] do
      refute conn |> get(path) |> html_response(200) =~ "TODO"
    end
  end

  test "legal pages are served on localhost too", %{conn: conn} do
    assert conn |> get("/privacy") |> html_response(200) =~ "Privacy Policy"
    assert build_conn() |> get("/terms") |> html_response(200) =~ "Terms of Service"
  end

  test "landing links to both legal pages", %{conn: conn} do
    body = conn |> get("/") |> html_response(200)
    assert body =~ ~s(href="/privacy")
    assert body =~ ~s(href="/terms")
  end

  test "sign-in page carries the agreement notice", %{conn: conn} do
    body = conn |> get("/sign-in") |> html_response(200)
    assert body =~ "By continuing you agree to the"
    assert body =~ ~s(href="/terms")
    assert body =~ ~s(href="/privacy")
  end
end

defmodule AnnotateWeb.SiteFooterTest do
  use AnnotateWeb.ConnCase, async: false

  for path <- ["/", "/privacy", "/terms"] do
    test "#{path} carries the shared tobor-kit footer, no sitemap link, no AI disclosure", %{
      conn: conn
    } do
      body = conn |> get(unquote(path)) |> html_response(200)

      assert body =~ "<noizu-footer-brand"
      assert body =~ "components/footer-brand/noizu-footer-brand.js"
      assert body =~ ~s(data-cy="footer-privacy")
      assert body =~ ~s(data-cy="footer-terms")
      # self-styled: cache-busted own stylesheet, so no host sheet has to carry the rules
      assert body =~ ~r/<link rel="stylesheet" href="\/css\/site-footer\.css\?v=[0-9a-f]{8}"/
      refute body =~ ~s(href="/sitemap")
      refute body =~ ~r/AI[- ]generated/i
    end
  end
end

defmodule AnnotateWeb.SiteFooterCssTest do
  use ExUnit.Case, async: true

  @css Path.expand("../../priv/static/css/site-footer.css", __DIR__)

  test "footer sheet exists and styles the row, links and brand" do
    css = File.read!(@css)
    assert css =~ ".nd-site-footer__inner"
    assert css =~ "justify-content: space-between"
    assert css =~ "flex-wrap: wrap"
    assert css =~ "text-decoration: none"
    assert css =~ ".nd-site-footer__links a:hover"
    assert css =~ "@media (max-width: 560px)"
  end

  test "host sheets no longer duplicate the footer rules" do
    for sheet <- ["landing.css", "dashboard.css"] do
      css = File.read!(Path.expand("../../priv/static/css/" <> sheet, __DIR__))
      refute css =~ ".nd-site-footer__links a {"
    end
  end
end
