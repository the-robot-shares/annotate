defmodule AnnotateWeb.LandingWaitlistTest do
  use AnnotateWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.WaitlistSignup

  @marketing_host "annotate.therobotlives.com"

  defp rows(email),
    do: Repo.all(from w in WaitlistSignup, where: w.email == ^email, order_by: w.interest)

  defp post_json(conn, params) do
    conn
    |> put_req_header("accept", "application/json")
    |> post("/waitlist", params)
  end

  describe "landing page copy" do
    setup %{conn: conn} do
      html = conn |> Map.put(:host, @marketing_host) |> get("/") |> html_response(200)
      {:ok, html: html}
    end

    test "renders the key strings", %{html: html} do
      for s <- [
            "From a comment on the page to a fix in the repo.",
            "over MCP, an agent",
            "Comment. Triage. Ticket. Patch. Resolve.",
            "Your agents read the feedback too.",
            "claude mcp add",
            "Where the work goes next.",
            "Get one email when these ship.",
            "Planned",
            "Available today",
            "Jira",
            "Notion",
            "ClickUp",
            "Asana",
            "The Robot Plans",
            "hero-loop-1600"
          ] do
        assert html =~ s, "missing #{inspect(s)}"
      end

      # footer is the shared SiteFooter, untouched
      assert html =~ "<noizu-footer-brand"
    end

    test "has no AI-generated disclosure, no prices, no old hero", %{html: html} do
      refute html =~ ~r/AI-generated/i
      refute html =~ "$12"
      refute html =~ "per seat"
      # (Hologram's asset manifest may list stale files from an old build priv;
      # only the markup that references images matters.)
      refute html =~ ~r/(src|srcset)="[^"]*hero-1600/
      assert html =~ ~s(src="/images/landing/hero-loop-1600.png")
      # shipped features are not softened to roadmap
      refute html =~ "export or delete it at any time"
    end

    test "waitlist form is wired with a honeypot and a no-JS action", %{html: html} do
      assert html =~ ~s(action="/waitlist")
      assert html =~ ~s(name="website")
      assert html =~ ~s(name="interests")
    end

    test "meta carries the new title and OG image", %{html: html} do
      assert html =~ "<title>annotate — site feedback that points at the thing</title>"
      assert html =~ "with an AI agent over MCP"
      assert html =~ "/images/landing/og.png"
    end
  end

  test "privacy policy discloses the waitlist data", %{conn: conn} do
    html = conn |> Map.put(:host, @marketing_host) |> get("/privacy") |> html_response(200)
    assert html =~ "join the waitlist we store your email address"
  end

  describe "POST /waitlist" do
    test "stores one row per interest and normalizes the email", %{conn: conn} do
      conn =
        post_json(conn, %{
          "email" => "  Dev@Example.COM ",
          "interests" => ["mcp", "jira", "mcp", "bogus"]
        })

      assert %{"ok" => true} = json_response(conn, 200)
      assert [%{interest: "jira"}, %{interest: "mcp"}] = rows("dev@example.com")
    end

    test "a browser same-origin POST (Origin header) is not CORS-denied", %{conn: conn} do
      c =
        conn
        |> put_req_header("origin", "https://annotate.therobotlives.com")
        |> post_json(%{"email" => "origin@example.com", "interests" => ["mcp"]})

      assert %{"ok" => true} = json_response(c, 200)
    end

    test "re-submitting is idempotent", %{conn: conn} do
      p = %{"email" => "again@example.com", "interests" => ["asana"]}
      assert %{"ok" => true} = conn |> post_json(p) |> json_response(200)
      assert %{"ok" => true} = conn |> recycle() |> post_json(p) |> json_response(200)
      assert [_] = rows("again@example.com")
    end

    test "rejects an invalid email", %{conn: conn} do
      for bad <- ["", "nope", "a@b", "a b@c.com", "@x.com"] do
        c = conn |> recycle() |> post_json(%{"email" => bad, "interests" => ["mcp"]})
        assert %{"ok" => false, "error" => "invalid_email"} = json_response(c, 422)
      end
    end

    test "rejects when no known interest is picked", %{conn: conn} do
      c = post_json(conn, %{"email" => "x@example.com", "interests" => ["bogus"]})
      assert %{"error" => "no_interest"} = json_response(c, 422)
      assert rows("x@example.com") == []
    end

    test "honeypot: looks like success, stores nothing", %{conn: conn} do
      c =
        post_json(conn, %{
          "email" => "bot@example.com",
          "interests" => ["mcp"],
          "website" => "http://spam.example"
        })

      assert %{"ok" => true} = json_response(c, 200)
      assert rows("bot@example.com") == []
    end

    test "no-JS form post returns an HTML thank-you page", %{conn: conn} do
      c =
        post(conn, "/waitlist", %{"email" => "nojs@example.com", "interests" => ["notion"]})

      assert html_response(c, 200) =~ "You&#39;re on the list" or
               html_response(c, 200) =~ "You're on the list"

      assert [_] = rows("nojs@example.com")
    end

    test "is rate limited per IP", %{conn: conn} do
      codes =
        for _ <- 1..7 do
          conn
          |> recycle()
          |> post_json(%{"email" => "nope", "interests" => ["mcp"]})
          |> Map.get(:status)
        end

      assert 429 in codes
    end
  end
end
