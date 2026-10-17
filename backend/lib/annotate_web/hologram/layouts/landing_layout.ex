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
      "https://cdn.derobot.is/tobor-kit/sha-5239abef2237bb118cdd75f67eb8b38023ae6620/components/page-comments/page-comments.js",
    dogfood_site: "annotate-landing"
  }

  prop :page_title, :string, default: "annotate — site feedback that points at the thing"

  def init(_props, component, _server) do
    cfg = marketing_cfg()
    m = AnnotateWeb.SEO.landing_meta()

    # All <head> metadata comes from AnnotateWeb.SEO (copy lives there). The
    # `page_title` prop is kept for the page declaration but SEO owns <title>.
    put_state(component,
      meta_title: m.title,
      meta_description: m.description,
      canonical: m.canonical,
      og_title: m.og_title,
      og_description: m.og_description,
      og_image: m.og_image,
      og_image_width: m.og_image_width,
      og_image_height: m.og_image_height,
      og_image_alt: m.og_image_alt,
      theme_color: AnnotateWeb.SEO.theme_color(),
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
        <meta name="theme-color" content={@theme_color} />
        <meta name="robots" content="index, follow, max-image-preview:large" />
        <title>{@meta_title}</title>
        <meta name="description" content={@meta_description} />
        <link rel="canonical" href={@canonical} />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="icon" href="/favicon.ico" sizes="48x48" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="annotate" />
        <meta property="og:locale" content="en_US" />
        <meta property="og:title" content={@og_title} />
        <meta property="og:description" content={@og_description} />
        <meta property="og:url" content={@canonical} />
        <meta property="og:image" content={@og_image} />
        <meta property="og:image:width" content={@og_image_width} />
        <meta property="og:image:height" content={@og_image_height} />
        <meta property="og:image:alt" content={@og_image_alt} />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={@og_title} />
        <meta name="twitter:description" content={@og_description} />
        <meta name="twitter:image" content={@og_image} />
        <meta name="twitter:image:alt" content={@og_image_alt} />
        <link rel="preload" href="/fonts/geist-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="stylesheet" href="/css/landing.css" />
        <script src="/js/keep-location.js"></script>
        <script src="/js/waitlist.js" defer></script>
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
