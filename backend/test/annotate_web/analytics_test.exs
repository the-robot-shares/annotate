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

  test "landing renders gtag with the id on the marketing host when configured", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)
    conn = fetch(conn, @marketing_host, "/")
    body = html_response(conn, 200)
    assert body =~ "https://www.googletagmanager.com/gtag/js?id=#{@id}"
    assert body =~ ~s(data-ga-id="#{@id}")
    assert body =~ "/js/ga-init.js"
  end

  test "landing has no gtag when unset", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, nil)
    body = html_response(fetch(conn, @marketing_host, "/"), 200)
    refute body =~ "gtag/js?id="
    refute body =~ ~s(data-ga-id=")
  end

  test "a malformed id is never rendered", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, ~S[G-X"></script><script>alert(1)])
    body = html_response(fetch(conn, @marketing_host, "/"), 200)
    refute body =~ "gtag/js?id="
  end

  test "privacy and terms render gtag on the marketing host, not on the API host", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)

    for path <- ["/privacy", "/terms"] do
      assert html_response(fetch(conn, @marketing_host, path), 200) =~ "gtag/js?id=#{@id}"
      refute html_response(fetch(conn, @api_host, path), 200) =~ "gtag/js?id="
    end
  end

  test "the sign-in page renders gtag on the marketing host only", %{conn: conn} do
    Application.put_env(:annotate, :ga_measurement_id, @id)
    assert html_response(fetch(conn, @marketing_host, "/sign-in"), 200) =~ "gtag/js?id=#{@id}"
    refute html_response(fetch(conn, @api_host, "/sign-in"), 200) =~ "gtag/js?id="
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

  test "the embed/widget assets never carry GA" do
    refute File.read!("priv/static/js/annotate-auth.js") =~ "gtag/js?id="
  end
end
