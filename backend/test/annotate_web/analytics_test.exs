defmodule AnnotateWeb.AnalyticsTest do
  use AnnotateWeb.ConnCase, async: false

  @marketing_host "annotate.therobotlives.com"
  @api_host "annotate-srv.therobotlives.com"
  @id "G-TEST123456"

  setup do
    orig_ga = Application.get_env(:annotate, :ga_measurement_id)
    orig_m = Application.get_env(:annotate, :marketing)

    Application.put_env(:annotate, :marketing,
      host: @marketing_host,
      api_host: @api_host,
      api_base: "https://#{@api_host}",
      widget_src: "https://cdn.derobot.is/x.js",
      dogfood_site: "annotate-landing"
    )

    on_exit(fn ->
      Application.put_env(:annotate, :ga_measurement_id, orig_ga)
      Application.put_env(:annotate, :marketing, orig_m)
    end)

    :ok
  end

  defp fetch(conn, host, path) do
    conn
    |> Map.put(:host, host)
    |> get(path)
  end

  test "landing renders the opt-in banner + loader, but never gtag.js itself", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)
    body = html_response(fetch(conn, @marketing_host, "/"), 200)
    assert body =~ ~s(data-ga-id="#{@id}")
    assert body =~ "/js/ga-init.js"
    assert body =~ ~s(id="ga-consent")
    assert body =~ ~s(data-ga-consent="accept")
    assert body =~ ~s(data-ga-consent="decline")
    # Not loaded before accept: the server HTML never references gtag.js.
    refute body =~ "gtag/js?id="
    refute body =~ "googletagmanager.com/gtag"
  end

  test "landing has no gtag when unset", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, nil)
    body = html_response(fetch(conn, @marketing_host, "/"), 200)
    refute body =~ "gtag/js?id="
    refute body =~ ~s(data-ga-id=")
    refute body =~ ~s(id="ga-consent")
  end

  test "a malformed id is never rendered", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, ~S[G-X"></script><script>alert(1)])
    body = html_response(fetch(conn, @marketing_host, "/"), 200)
    refute body =~ ~s(data-ga-id=")
  end

  test "privacy and terms render gtag on the marketing host, not on the API host", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)

    for path <- ["/privacy", "/terms"] do
      assert html_response(fetch(conn, @marketing_host, path), 200) =~ ~s(data-ga-id="#{@id}")
      refute html_response(fetch(conn, @api_host, path), 200) =~ ~s(data-ga-id=")
    end
  end

  test "the sign-in page renders gtag on the marketing host only", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)
    m = html_response(fetch(conn, @marketing_host, "/sign-in"), 200)
    assert m =~ ~s(data-ga-id="#{@id}")
    assert m =~ ~s(id="ga-consent")
    refute html_response(fetch(conn, @api_host, "/sign-in"), 200) =~ ~s(data-ga-id=")
  end

  test "CSP allows the GA hosts on landing and legal pages", %{conn: conn} do
    for path <- ["/", "/privacy"] do
      csp =
        fetch(conn, @marketing_host, path)
        |> get_resp_header("content-security-policy")
        |> List.first()

      [script] = Regex.run(~r/script-src [^;]+/, csp)
      [connect] = Regex.run(~r/connect-src [^;]+/, csp)
      [img] = Regex.run(~r/img-src [^;]+/, csp)
      assert script =~ "https://www.googletagmanager.com"

      for src <- [connect, img] do
        assert src =~ "https://www.googletagmanager.com"
        assert src =~ "https://*.google-analytics.com"
        assert src =~ "https://*.analytics.google.com"
      end
    end
  end

  test "privacy policy discloses Google Analytics", %{conn: conn} do
    body = html_response(fetch(conn, @marketing_host, "/privacy"), 200)
    assert body =~ "Google Analytics"
  end

  test "ga-init.js: consent defaults denied, gtag.js only injected on accept, choice persisted" do
    js = File.read!("priv/static/js/ga-init.js")
    assert js =~ ~s(analytics_storage: "denied")
    assert js =~ "localStorage.setItem"
    assert js =~ ~s("consent", "update", { analytics_storage: "granted" })
    # the only place gtag.js is requested is load(), which only apply("granted") calls
    assert length(String.split(js, "googletagmanager.com/gtag/js")) == 2
    assert js =~ ~r/function load\(\)[\s\S]*googletagmanager\.com\/gtag\/js/
  end

  test "ga-init.js behaviour (node --test, stub DOM): banner, accept loads, decline/persist" do
    case System.find_executable("node") do
      nil ->
        :ok

      node ->
        {out, status} =
          System.cmd(node, ["--test", "test/js/ga-init.test.mjs"], stderr_to_stdout: true)

        assert status == 0, out
    end
  end

  test "the embed/widget assets never carry GA" do
    refute File.read!("priv/static/js/annotate-auth.js") =~ "gtag/js?id="
  end
end

defmodule AnnotateWeb.LandingLoopListTest do
  use AnnotateWeb.ConnCase, async: false

  test "loop list: native markers removed, one custom 01-05 counter, versioned css" do
    css = File.read!("priv/static/css/landing.css")
    [loop] = Regex.run(~r/\.nd-loop \{[^}]*\}/, css)
    assert loop =~ "list-style: none"
    assert loop =~ "counter-reset: nd-step"

    assert css =~
             ~r/\.nd-step::before \{[^}]*counter-increment: nd-step;[^}]*decimal-leading-zero/

    assert css =~ ".nd-loop > li { list-style: none; }"

    body = html_response(get(conn_for_landing(), "/"), 200)
    # five steps, no hand-typed numerals in the markup (numbers come from CSS only)
    [ol] = Regex.run(~r/<ol class="nd-loop">.*?<\/ol>/s, body)
    assert length(Regex.scan(~r/<li class="nd-step">/, ol)) == 5
    refute ol =~ ~r/>\s*0?[1-5]\s*</
    assert body =~ ~r"/css/landing\.css\?v=[0-9a-f]{8}"
  end

  defp conn_for_landing,
    do: Phoenix.ConnTest.build_conn() |> Map.put(:host, "annotate.therobotlives.com")
end
