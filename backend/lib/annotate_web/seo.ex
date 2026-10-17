defmodule AnnotateWeb.SEO do
  @moduledoc """
  Single source of truth for annotate's search / AI-answer-engine plumbing.

  Everything crawlers see that is not page markup is generated from here:
  `robots.txt`, `sitemap.xml`, `llms.txt`, `llms-full.txt`, the per-page
  `<head>` metadata the layouts render, and the JSON-LD on `/`.

  Copy owners: swap the strings in the `@landing` / `@legal` blocks and the
  `llms_*` functions; nothing else needs to change. Served by
  `AnnotateWeb.Plugs.SEO`.

  Honesty rules (mirror the product): only describe what ships. MCP hooks and
  ticket push are *planned*; there is no pricing, so no `offers`.
  """

  @default_host "annotate.therobotlives.com"
  @default_api_host "annotate-srv.therobotlives.com"

  # ── Copy: landing (swap strings here when the copy overhaul lands) ──────
  # og.png is a 1200x630 crop of the loop hero (hero-loop-1600).
  @landing %{
    title: "annotate — site feedback that points at the thing",
    description:
      "One script tag pins threaded comments to the exact element on any page. Triage in the dashboard or read it over the REST API; agent tools are in development.",
    og_title: "annotate — site feedback that points at the thing",
    og_description:
      "One script tag pins threaded comments to the exact element on any page. Triage in the dashboard or read it over the REST API; agent tools are in development.",
    og_image: "/images/landing/og.png",
    og_image_width: 1200,
    og_image_height: 630,
    og_image_alt:
      "A comment pinned to a page's Export button becomes a ticket, then an agent reports a patch ready."
  }

  @org %{
    name: "The Robot Lives",
    url: "https://therobotlives.com",
    # Only links that already exist on the site/footer; no invented profiles.
    same_as: ["https://tobor.dev"]
  }

  @theme_color "#0B0B10"

  # Compile date: "/" ships with every deploy, so this is its lastmod.
  @built_on Date.utc_today() |> Date.to_iso8601()

  # ── Indexable marketing routes (the sitemap is generated from these) ────
  # `lastmod` nil => build date. Legal pages carry their own "Last updated".
  @pages [
    %{path: "/", changefreq: "weekly", priority: "1.0", lastmod: nil},
    %{path: "/privacy", changefreq: "yearly", priority: "0.3", lastmod: "2026-10-17"},
    %{path: "/terms", changefreq: "yearly", priority: "0.3", lastmod: "2026-10-17"}
  ]

  # Never indexed: robots.txt Disallow (the ones that are safe to disallow),
  # plus X-Robots-Tag: noindex on every prefix here. `/sign-in`, `/login` and
  # `/signup` are deliberately NOT in robots.txt so crawlers can fetch them
  # and see the noindex.
  @noindex_prefixes ~w(/dashboard /app /auth /api /embed /sign-in /login /signup /join
                       /forgot-password /complete-registration /pending-approval
                       /styleguide /tk-smoke /sitemap /dev /media /socket /health /sso)

  @robots_disallow ~w(/dashboard /app /auth /api /embed /join /styleguide /tk-smoke
                      /sitemap /dev /media /socket /health /sso)

  @ai_bots ~w(GPTBot ChatGPT-User OAI-SearchBot ClaudeBot Claude-User Claude-SearchBot
              Anthropic-ai PerplexityBot Perplexity-User Google-Extended CCBot
              Applebot-Extended Bytespider)

  # ── Config ──────────────────────────────────────────────────────────────

  def host, do: marketing(:host, @default_host)
  def api_host, do: marketing(:api_host, @default_api_host)
  def origin, do: "https://" <> host()
  def api_origin, do: "https://" <> api_host()

  defp marketing(key, default) do
    case Application.get_env(:annotate, :marketing) do
      kw when is_list(kw) -> Keyword.get(kw, key) || default
      _ -> default
    end
  end

  def pages, do: @pages
  def noindex_prefixes, do: @noindex_prefixes
  def robots_disallow, do: @robots_disallow
  def ai_bots, do: @ai_bots
  def theme_color, do: @theme_color

  @doc "True when `path_info` (a list of segments) sits under a noindex prefix."
  def noindex_path?(path_info) do
    path = "/" <> Enum.join(path_info, "/")

    Enum.any?(@noindex_prefixes, fn p -> path == p or String.starts_with?(path, p <> "/") end)
  end

  @doc "True when the connection host is the API host (never indexed)."
  def api_host?(host), do: host == api_host()

  # ── Per-page head metadata (used by layouts) ────────────────────────────

  @doc "Flat map of head metadata for the landing page; absolute URLs resolved."
  def landing_meta do
    Map.merge(@landing, %{
      canonical: origin() <> "/",
      og_image: origin() <> @landing.og_image
    })
  end

  # ── robots.txt ──────────────────────────────────────────────────────────

  def robots_txt(:api), do: "User-agent: *\nDisallow: /\n"

  def robots_txt(:marketing) do
    disallow = Enum.map_join(@robots_disallow, "\n", &"Disallow: #{&1}")
    group = fn ua -> "User-agent: #{ua}\nAllow: /\n#{disallow}\n" end

    # Each named group repeats the Disallow list: a crawler that matches a
    # specific group ignores the `*` group entirely.
    [group.("*") | Enum.map(@ai_bots, group)]
    |> Enum.join("\n")
    |> Kernel.<>("\nSitemap: #{origin()}/sitemap.xml\n")
  end

  # ── sitemap.xml ─────────────────────────────────────────────────────────

  def sitemap_xml do
    urls =
      Enum.map_join(@pages, "\n", fn p ->
        """
          <url>
            <loc>#{xml(origin() <> p.path)}</loc>
            <lastmod>#{p.lastmod || @built_on}</lastmod>
            <changefreq>#{p.changefreq}</changefreq>
            <priority>#{p.priority}</priority>
          </url>\
        """
      end)

    ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <>
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n) <>
      urls <> "\n</urlset>\n"
  end

  defp xml(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # ── llms.txt / llms-full.txt (llmstxt.org) ──────────────────────────────

  def llms_txt do
    """
    # annotate

    > annotate adds a comment layer to any webpage. A site owner pastes one script tag; visitors then select an element or some text on the page and leave a comment thread attached to that spot. The aim is a loop from a comment on the page to a fix in the repo: comments land in a dashboard inbox and a REST API today; ticket integrations are planned and agent (MCP) tools are in development. It is early software built by The Robot Lives.

    What works today: element- and text-anchored comment threads, replies, resolve and reopen, file and image attachments, screenshots with box/arrow/pen/text/blur markup, live updates, per-site origin allow-lists, and sign-in through GitHub (dashboard) or through your own identity provider or your own site (embedded widget). Comments are publicly readable by default; this can be changed per site.

    Not shipped yet: ticket push to Jira, Notion, ClickUp, Asana or The Robot Plans (planned); MCP tools for coding agents (in development). A waitlist on the home page takes an email for each.

    ## Key pages

    - [Home](#{origin()}/): what annotate does, the embed snippet, and the FAQ
    - [Privacy Policy](#{origin()}/privacy): what is collected, who processes it, retention, deletion
    - [Terms of Service](#{origin()}/terms): as-is service terms, acceptable use, data loss

    ## Embed and API

    - [Full plain-text description](#{origin()}/llms-full.txt): how it works, the embed snippet, the API surface, limits
    - API host (JSON over HTTPS, not a website): #{api_origin()}
    - The embed is the `noizu-page-comments` web component from tobor-kit: https://tobor.dev
    - There are no public API or embed documentation pages yet. The API, embed-auth and anchor docs are in a private repository and are given to site owners on request.

    ## How agents can interact

    - Reading: every page above is server-rendered HTML; no JavaScript is needed to read it.
    - Site owners sign in with GitHub at #{origin()}/sign-in to create a site and get its embed snippet. This is a human sign-in; there is no agent token flow.
    - There is no MCP server yet; MCP tools are in development. The JSON REST API (threads, comments, anchors, resolve state) is the programmatic surface today.

    ## Optional

    - [The Robot Lives](#{@org.url}): the publisher
    """
  end

  def llms_full_txt do
    """
    # annotate (full description)

    annotate adds a comment layer to any webpage. This file is the long form of #{origin()}/llms.txt. Last built: #{@built_on}. Where this file and the website disagree, the website is right.

    ## What it is

    The pitch: from a comment on the page to a fix in the repo. Shipped today: the comment widget, the owner dashboard with an inbox, and a JSON REST API with live events. Planned: ticket creation in Jira, Notion, ClickUp, Asana and The Robot Plans. In development: MCP tools so coding agents can triage and patch. A waitlist on the home page takes an email for each.

    A site owner adds one script tag and one `noizu-page-comments` element to a page. Visitors select an element or some text, and the comment thread attaches to exactly that spot. The thread is shown in a comment rail beside the element, and opening a comment rings the element it refers to on the page.

    ## How to add it to a site

    1. Sign in at #{origin()}/sign-in with GitHub. The first sign-in creates your account.
    2. In the dashboard, add a site: choose a slug and list the exact origins (scheme and host) that may use it.
    3. Paste the embed snippet shown for the site before the closing body tag: a module script that loads the widget, and a `noizu-page-comments` element with your `site` slug and `api-base="#{api_origin()}"`.
    4. Choose who can post: sign-in through an identity provider, your own site vouching for its logged-in users, or (off by default) anonymous guests.

    ## What the widget does

    - Anchors a thread to an element or a text selection, and re-finds it on later visits.
    - Replies, resolve, reopen, edit and delete of your own comments.
    - File and image attachments on any comment, uploaded straight to object storage with short-lived signed URLs.
    - Screenshots of the page, cropped, with boxes, arrows, freehand pen, text and blur drawn on top.
    - Live updates: new comments and replies appear without a refresh.
    - Pages are keyed by path and, optionally, by query parameters; tracking parameters can be ignored per site.

    ## API surface (summary)

    The API lives at #{api_origin()} under `/api/v1`. It is JSON over HTTPS and is tenant-scoped by site slug. This is a summary, not the full contract.

    - List and create threads on a page of a site (`/api/v1/sites/:site/threads`).
    - Add comments to a thread, resolve and reopen a thread, edit and delete a comment, change a thread's anchor.
    - Request an upload URL for an attachment and mark the upload complete.
    - Refresh a short-lived access token; a site's own backend can assert a logged-in user to obtain one.
    - A websocket carries live updates for a page.

    Access model:

    - Access tokens are short-lived (15 minutes) and bound to a site and an origin. Requests from an origin that is not on the site's allow-list are rejected.
    - Reads are public by default and can be restricted per site. Writes need a token. Anonymous threads are off unless the site opts in.
    - Writes are rate limited per IP and site.

    ## Privacy and data

    No third-party cookies. The widget keeps only what it needs to keep a visitor signed in and does no analytics; the marketing site itself uses Google Analytics 4. Details, processors and deletion requests are on #{origin()}/privacy.

    ## Status and roadmap

    - Shipped: everything under "What the widget does", the dashboard for site owners, per-site origin rules, GitHub sign-in for owners.
    - Planned, not shipped: ticket push (Jira, Notion, ClickUp, Asana, The Robot Plans); per-thread internal-only or public-only visibility. In development: MCP tools for coding agents.
    - Pricing: none published. annotate is free to try while it is early software, with no uptime guarantee; see #{origin()}/terms.

    ## Publisher

    #{@org.name}, #{@org.url}. Contact details are on the privacy page.
    """
  end

  # ── JSON-LD (rendered into the response, never into Hologram page state) ─

  @doc """
  JSON-LD graph for `/`. `faq` is a list of `{question, answer}` pairs read
  from the rendered page, so the markup can never drift from visible copy.
  """
  def landing_json_ld(faq) do
    org_id = @org.url <> "/#organization"
    site_id = origin() <> "/#website"
    app_id = origin() <> "/#software"
    meta = landing_meta()

    graph = [
      %{
        "@type" => "Organization",
        "@id" => org_id,
        "name" => @org.name,
        "url" => @org.url,
        "sameAs" => @org.same_as
      },
      %{
        "@type" => "WebSite",
        "@id" => site_id,
        "url" => origin() <> "/",
        "name" => "annotate",
        "description" => meta.description,
        "inLanguage" => "en",
        "publisher" => %{"@id" => org_id}
      },
      %{
        "@type" => "SoftwareApplication",
        "@id" => app_id,
        "name" => "annotate",
        "url" => origin() <> "/",
        "description" => meta.description,
        "applicationCategory" => "DeveloperApplication",
        "operatingSystem" => "Web",
        "image" => meta.og_image,
        "publisher" => %{"@id" => org_id},
        "isPartOf" => %{"@id" => site_id}
      }
    ]

    graph =
      case faq do
        [] ->
          graph

        pairs ->
          graph ++
            [
              %{
                "@type" => "FAQPage",
                "@id" => origin() <> "/#faq",
                "url" => origin() <> "/",
                "mainEntity" =>
                  Enum.map(pairs, fn {q, a} ->
                    %{
                      "@type" => "Question",
                      "name" => q,
                      "acceptedAnswer" => %{"@type" => "Answer", "text" => a}
                    }
                  end)
              }
            ]
      end

    %{"@context" => "https://schema.org", "@graph" => graph}
  end

  @doc "Extracts `{question, answer}` pairs from the landing HTML's FAQ section."
  def faq_from_html(html) when is_binary(html) do
    with {:ok, doc} <- Floki.parse_document(html) do
      doc
      |> Floki.find(".nd-faq details")
      |> Enum.map(fn d ->
        {squash(d |> Floki.find("summary") |> Floki.text()),
         squash(d |> Floki.find("p") |> Floki.text())}
      end)
      |> Enum.reject(fn {q, a} -> q == "" or a == "" end)
    else
      _ -> []
    end
  end

  defp squash(s), do: s |> String.replace(~r/\s+/u, " ") |> String.trim()

  @doc "`<script type=\"application/ld+json\">` tag; the JSON cannot close the script element."
  def json_ld_script(data) do
    # :html_safe escapes `</`, `<!--` openers and U+2028/9 so no value can break out of the tag.
    json = Jason.encode!(data, escape: :html_safe)
    ~s(<script type="application/ld+json">#{json}</script>)
  end
end
