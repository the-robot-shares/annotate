defmodule AnnotateWeb.Hologram.Layouts.LandingLayout do
  @moduledoc """
  Marketing landing layout (Night Desk / Nocturne direction).

  Standalone by design: it does NOT touch `Annotate.StyleGuide.Catalog` or the
  theme YAML machinery (see #20 — compile-time `__DIR__` theme paths broke
  release builds). Dark-native head: SEO meta, Open Graph / Twitter cards with
  absolute og:image computed from the marketing host config, self-hosted font
  preloads, `/css/landing.css`, skip link, and the dogfood widget embed at the
  end of body (module script — deferred by default, never blocks render).
  """

  use Hologram.Component

  @default %{
    host: "annotate.therobotlives.com",
    api_base: "https://annotate-srv.therobotlives.com",
    widget_src:
      "https://cdn.derobot.is/tobor-kit/sha-69056864dcf3fba0adfa4eea995dde4fa381c8eb/components/page-comments/page-comments.js",
    dogfood_site: "annotate-landing"
  }

  prop :page_title, :string, default: "annotate — Feedback that points at the thing"

  def init(_props, component, _server) do
    cfg = marketing_cfg()
    host = cfg.host

    put_state(component,
      page_url: "https://#{host}/",
      og_image: "https://#{host}/images/landing/og.png",
      api_base: cfg.api_base,
      widget_src: cfg.widget_src,
      dogfood_site: cfg.dogfood_site
    )
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0B0B10" />
        <title>{@page_title}</title>
        <meta
          name="description"
          content="annotate adds a comment rail to any webpage. Visitors select an element or some text, and the thread attaches to exactly that spot."
        />
        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="annotate" />
        <meta property="og:title" content="annotate — Feedback that points at the thing" />
        <meta
          property="og:description"
          content="One script tag adds element-level comment threads, screenshots, and replies to any webpage."
        />
        <meta property="og:url" content={@page_url} />
        <meta property="og:image" content={@og_image} />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta property="og:image:alt" content="A webpage with a glowing ring around a commented element and a floating comment rail" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content="annotate — Feedback that points at the thing" />
        <meta
          name="twitter:description"
          content="One script tag adds element-level comment threads, screenshots, and replies to any webpage."
        />
        <meta name="twitter:image" content={@og_image} />
        <link rel="preload" href="/fonts/geist-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="stylesheet" href="/css/landing.css" />
        <script src="/js/keep-location.js"></script>
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="nd-skip" href="#main">Skip to content</a>
        <slot />
        <noizu-page-comments
          site={@dogfood_site}
          api-base={@api_base}
          enabled
          rail-mode="overlay"
        ></noizu-page-comments>
        <script type="module" src={@widget_src}></script>
      </body>
    </html>
    """
  end

  defp marketing_cfg do
    case Application.get_env(:annotate, :marketing) do
      kw when is_list(kw) ->
        %{
          host: Keyword.get(kw, :host, @default.host),
          api_base: Keyword.get(kw, :api_base, @default.api_base),
          widget_src: Keyword.get(kw, :widget_src, @default.widget_src),
          dogfood_site: Keyword.get(kw, :dogfood_site, @default.dogfood_site)
        }

      _ ->
        @default
    end
  end
end
