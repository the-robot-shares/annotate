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
    assert body =~ "From a comment on the page to a fix in the repo."
    assert body =~ "noizu-page-comments"
    assert body =~ "cdn.derobot.is"
    # The landing runs the exact tobor-kit release; the copyable snippet
    # offers the always-newest loader. Neither forces the widget open.
    assert body =~ ~s(src="#{AnnotateWeb.WidgetCdn.pinned_src()}")
    assert body =~ AnnotateWeb.WidgetCdn.latest_src()
    [mount] = Regex.run(~r{<noizu-page-comments\b[^>]*>}s, body)
    refute mount =~ ~r/\benabled\b/

    csp = get_resp_header(conn, "content-security-policy") |> List.first()
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "script-src 'self' 'unsafe-inline' https://cdn.derobot.is"
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]

    # The widget PUTs attachments to the presigned storage url: the storage
    # origin must be allowed for XHR, not just for <img>.
    storage = Annotate.Storage.public_origin()
    assert is_binary(storage)
    [connect_src] = Regex.run(~r/connect-src [^;]+/, csp)
    assert connect_src =~ storage
  end

  test "GET / on the API host redirects to the marketing host", %{conn: conn} do
    Application.put_env(:annotate, :marketing,
      host: @marketing_host,
      api_host: @api_host,
      api_base: "https://#{@api_host}",
      widget_src: "https://cdn.derobot.is/tobor-kit/v1.0.8/annotate.js",
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
    assert html_response(conn, 200) =~ "From a comment on the page to a fix in the repo."
  end

  test "landing stylesheet is served", %{conn: conn} do
    conn = get(conn, "/css/landing.css")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/css"
  end

  test "keep-location.js loads before the Hologram runtime and is served", %{conn: conn} do
    body =
      conn |> Map.put(:host, @marketing_host) |> get("/") |> html_response(200)

    {kl, _} = :binary.match(body, "/js/keep-location.js")
    {rt, _} = :binary.match(body, "/hologram/")
    assert kl < rt

    js = get(build_conn(), "/js/keep-location.js")
    assert js.status == 200
  end

  @tag :node
  test "keep-location.js re-appends search+hash to Hologram's boot replaceState once" do
    script = Path.expand("../../priv/static/js/keep-location.js", __DIR__)

    harness = """
    const fs = require("fs");
    const calls = [];
    global.location = {pathname: "/", search: "?tab=anchors&utm_source=x", hash: "#annotate=abc"};
    global.history = {replaceState(s, t, u) { calls.push(u); }};
    eval(fs.readFileSync(process.argv[1], "utf8"));
    history.replaceState("id", null, location.pathname);   // Hologram boot
    history.replaceState("id2", null, "/other");           // later call untouched
    console.log(JSON.stringify(calls));
    """

    case System.find_executable("node") do
      nil ->
        :ok

      node ->
        {out, 0} = System.cmd(node, ["-e", harness, script])

        assert Jason.decode!(String.trim(out)) == [
                 "/?tab=anchors&utm_source=x#annotate=abc",
                 "/other"
               ]
    end
  end
end
