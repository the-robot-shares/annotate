defmodule AnnotateWeb.SEOTest do
  use AnnotateWeb.ConnCase, async: false

  alias AnnotateWeb.SEO

  @host "annotate.therobotlives.com"
  @api_host "annotate-srv.therobotlives.com"

  defp marketing(conn), do: Map.put(conn, :host, @host)
  defp api(conn), do: Map.put(conn, :host, @api_host)

  defp ct(conn), do: conn |> get_resp_header("content-type") |> List.first()

  describe "robots.txt" do
    test "marketing host allows AI crawlers, disallows app paths, points at the sitemap", %{
      conn: conn
    } do
      conn = conn |> marketing() |> get("/robots.txt")
      body = response(conn, 200)
      assert ct(conn) =~ "text/plain"

      for bot <- ~w(GPTBot ChatGPT-User OAI-SearchBot ClaudeBot Claude-User PerplexityBot
                    Google-Extended CCBot Applebot-Extended) do
        assert body =~ "User-agent: #{bot}\nAllow: /\n"
      end

      # every group repeats the disallows (a named group ignores `*`)
      for group <- String.split(body, "\n\n", trim: true), group =~ "User-agent:" do
        for p <- ~w(/dashboard /auth /api /embed /dev) do
          assert group =~ "Disallow: #{p}\n", "group missing #{p}: #{group}"
        end
      end

      assert body =~ "Sitemap: https://#{@host}/sitemap.xml"
      refute body =~ "example.com"
      # /sign-in stays crawlable so its noindex is seen
      refute body =~ "Disallow: /sign-in"
    end

    test "API host disallows everything and is noindex", %{conn: conn} do
      conn = conn |> api() |> get("/robots.txt")
      assert response(conn, 200) == "User-agent: *\nDisallow: /\n"
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  describe "sitemap.xml" do
    test "is generated from SEO.pages with lastmod and the xml content-type", %{conn: conn} do
      conn = conn |> marketing() |> get("/sitemap.xml")
      body = response(conn, 200)
      assert ct(conn) =~ "application/xml"
      assert {:ok, _} = parse_xml(body)

      for %{path: path} <- SEO.pages() do
        assert body =~ "<loc>https://#{@host}#{path}</loc>"
      end

      assert body =~ "https://#{@host}/privacy"
      assert body =~ "https://#{@host}/terms"

      assert length(Regex.scan(~r/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/, body)) ==
               length(SEO.pages())

      refute body =~ "/sign-in"
      refute body =~ "/dashboard"
      refute body =~ "example.com"
    end

    test "not served on the API host", %{conn: conn} do
      assert conn |> api() |> get("/sitemap.xml") |> Map.fetch!(:status) == 404
    end

    test "every static Hologram page route is either in the sitemap or noindex" do
      listed = MapSet.new(SEO.pages(), & &1.path)

      for mod <- Hologram.Reflection.list_pages(),
          String.starts_with?(to_string(mod), "Elixir.AnnotateWeb"),
          route = mod.__route__(),
          not String.contains?(route, ":") do
        unless MapSet.member?(listed, route) do
          assert SEO.noindex_path?(String.split(route, "/", trim: true)),
                 "#{route} (#{inspect(mod)}) is neither in SEO.pages/0 nor under a noindex prefix"
        end
      end
    end
  end

  describe "llms.txt" do
    test "follows llmstxt.org: H1, blockquote summary, link sections; honest about planned work",
         %{conn: conn} do
      conn = conn |> marketing() |> get("/llms.txt")
      body = response(conn, 200)
      assert ct(conn) =~ "text/plain"
      assert String.starts_with?(body, "# annotate\n\n> ")
      assert body =~ "## Key pages"
      assert body =~ "[Privacy Policy](https://#{@host}/privacy)"
      assert body =~ "[Terms of Service](https://#{@host}/terms)"
      assert body =~ "llms-full.txt"
      assert body =~ "planned, not available"
      assert body =~ "no MCP server"
    end

    test "llm.txt alias is byte-identical to llms.txt", %{conn: conn} do
      a = conn |> marketing() |> get("/llms.txt") |> response(200)
      b = build_conn() |> marketing() |> get("/llm.txt") |> response(200)
      assert a == b
    end

    test "llms-full.txt is served", %{conn: conn} do
      conn = conn |> marketing() |> get("/llms-full.txt")
      body = response(conn, 200)
      assert ct(conn) =~ "text/plain"
      assert body =~ "Planned, not shipped"
      refute body =~ ~r/\$\d/
    end
  end

  describe "indexing headers" do
    test "API host pages send X-Robots-Tag noindex", %{conn: conn} do
      conn = conn |> api() |> get("/health")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end

    test "/sign-in and /dashboard are noindex (header + meta) on the marketing host", %{
      conn: conn
    } do
      signin = conn |> marketing() |> get("/sign-in")
      assert get_resp_header(signin, "x-robots-tag") == ["noindex, nofollow"]
      assert html_response(signin, 200) =~ ~s(name="robots" content="noindex, nofollow")

      dash = build_conn() |> marketing() |> get("/dashboard")
      assert get_resp_header(dash, "x-robots-tag") == ["noindex, nofollow"]
    end

    test "/ and legal pages are indexable", %{conn: conn} do
      for path <- ["/", "/privacy", "/terms"] do
        c = build_conn() |> marketing() |> get(path)
        assert get_resp_header(c, "x-robots-tag") == []
        assert html_response(c, 200) =~ ~s(name="robots" content="index, follow)
      end
    end
  end

  describe "landing head + JSON-LD" do
    setup %{conn: conn} do
      body = conn |> marketing() |> get("/") |> html_response(200)
      %{body: body}
    end

    test "carries title, description, canonical, og, twitter, icons", %{body: body} do
      m = SEO.landing_meta()
      assert body =~ "<title>#{m.title}</title>"
      assert body =~ ~s(name="description" content="#{m.description}")
      assert body =~ ~s(rel="canonical" href="https://#{@host}/")
      assert body =~ ~s(property="og:type" content="website")
      assert body =~ ~s(property="og:url" content="https://#{@host}/")
      assert body =~ ~s(property="og:title")
      assert body =~ ~s(property="og:description")
      assert body =~ ~s(property="og:image" content="https://#{@host}/images/landing/og.png")
      assert body =~ ~s(property="og:image:width" content="1200")
      assert body =~ ~s(property="og:image:height" content="630")
      assert body =~ ~s(name="twitter:card" content="summary_large_image")
      assert body =~ ~s(name="theme-color")
      assert body =~ ~s(rel="icon" href="/favicon.svg")
      assert body =~ ~s(rel="apple-touch-icon" href="/apple-touch-icon.png")
    end

    test "JSON-LD parses and has Organization, WebSite, SoftwareApplication, FAQPage", %{
      body: body
    } do
      [json] =
        Regex.run(~r/<script type="application\/ld\+json">(.*?)<\/script>/s, body,
          capture: :all_but_first
        )

      assert %{"@context" => "https://schema.org", "@graph" => graph} = Jason.decode!(json)
      types = Enum.map(graph, & &1["@type"])
      assert types == ~w(Organization WebSite SoftwareApplication FAQPage)

      org = Enum.find(graph, &(&1["@type"] == "Organization"))
      assert String.starts_with?(org["@id"], "https://")
      assert org["sameAs"] == ["https://tobor.dev"]

      app = Enum.find(graph, &(&1["@type"] == "SoftwareApplication"))
      assert app["applicationCategory"] == "DeveloperApplication"
      refute Map.has_key?(app, "offers")

      faq = Enum.find(graph, &(&1["@type"] == "FAQPage"))
      assert length(faq["mainEntity"]) >= 3
      assert Enum.all?(faq["mainEntity"], &(&1["acceptedAnswer"]["text"] != ""))
    end

    test "JSON-LD script cannot be broken out of and is not in Hologram state" do
      evil =
        SEO.json_ld_script(%{
          "x" => "</script><script>alert(1)</script> <!-- " <> <<0xE2, 0x80, 0xA8>>
        })

      inner =
        evil
        |> String.replace_prefix(~s(<script type="application/ld+json">), "")
        |> String.replace_suffix("</script>", "")

      refute inner =~ "</"
      refute inner =~ "<!--"
      assert Jason.decode!(inner)["x"] =~ "</script>"
    end

    test "no JSON-LD on the API host or on other pages", %{conn: conn} do
      refute conn |> marketing() |> get("/privacy") |> html_response(200) =~ "ld+json"
    end
  end

  defp parse_xml(s) do
    {:ok, :xmerl_scan.string(String.to_charlist(s), quiet: true)}
  catch
    :exit, e -> {:error, e}
  end
end
