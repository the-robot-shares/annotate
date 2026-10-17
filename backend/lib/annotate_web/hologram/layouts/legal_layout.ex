defmodule AnnotateWeb.Hologram.Layouts.LegalLayout do
  @moduledoc """
  Night Desk layout for the legal pages (`/privacy`, `/terms`).

  Same visual language as `LandingLayout` (shared `/css/landing.css`) but with
  no dogfood widget: the nav/footer chrome is rendered here so each page only
  supplies its article. Per-page SEO comes in as props (`page_title`,
  `description`, `path`).
  """

  use Hologram.Component

  alias AnnotateWeb.Hologram.Components.SiteFooter

  prop :page_title, :string, default: "annotate"
  prop :description, :string, default: ""
  prop :path, :string, default: "/"

  def init(_props, component, _server) do
    put_state(component,
      host: marketing_host(),
      theme_color: AnnotateWeb.SEO.theme_color(),
      og_image: AnnotateWeb.SEO.landing_meta().og_image
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
        <meta name="robots" content="index, follow" />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="icon" href="/favicon.ico" sizes="48x48" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <title>{@page_title}</title>
        <meta name="description" content={@description} />
        <link rel="canonical" href={"https://" <> @host <> @path} />
        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="annotate" />
        <meta property="og:title" content={@page_title} />
        <meta property="og:description" content={@description} />
        <meta property="og:url" content={"https://" <> @host <> @path} />
        <meta property="og:locale" content="en_US" />
        <meta property="og:image" content={@og_image} />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta property="og:image:alt" content="annotate" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:image" content={@og_image} />
        <meta name="twitter:title" content={@page_title} />
        <meta name="twitter:description" content={@description} />
        <link rel="preload" href="/fonts/geist-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="stylesheet" href="/css/landing.css" />
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="nd-skip" href="#main">Skip to content</a>
        <header class="nd-nav">
          <div class="nd-nav__inner">
            <a class="nd-nav__brand" href="/"><span class="nd-nav__dot" aria-hidden="true"></span>annotate</a>
            <nav class="nd-nav__links" aria-label="Legal">
              <a class="nd-nav__link" href="/privacy">Privacy</a>
              <a class="nd-nav__link" href="/terms">Terms</a>
            </nav>
            <a class="nd-btn nd-btn--secondary nd-btn--sm nd-nav__cta" href="/">Home</a>
          </div>
        </header>
        <main id="main" class="nd-legal">
          <slot />
        </main>
        <SiteFooter />
      </body>
    </html>
    """
  end

  defp marketing_host do
    case Application.get_env(:annotate, :marketing) do
      kw when is_list(kw) -> Keyword.get(kw, :host) || "annotate.therobotlives.com"
      _ -> "annotate.therobotlives.com"
    end
  end
end
