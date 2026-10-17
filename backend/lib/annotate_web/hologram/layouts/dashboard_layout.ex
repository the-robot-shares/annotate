defmodule AnnotateWeb.Hologram.Layouts.DashboardLayout do
  @moduledoc """
  Owner-dashboard layout — Night Desk / Nocturne, dark-native, standalone by
  design (same posture as `LandingLayout`: no StyleGuide.Catalog, no theme
  YAML, so release builds never trip compile-time asset paths).

  Tokens are defined once in `/css/dashboard.css` (kept in lockstep with the
  landing sheet's `nd-*` values). Self-hosted Geist/Inter/JetBrains Mono.
  """

  use Hologram.Component

  prop :page_title, :string, default: "annotate — dashboard"

  # Dogfood widget (feedback 2026-10-18: annotate should run on the dashboard
  # too, not just the landing page). Same origin as the landing page, so the
  # annotate-landing site's allowed origin already covers it.
  @widget_default %{
    api_base: "https://annotate-srv.therobotlives.com",
    widget_src: AnnotateWeb.WidgetCdn.pinned_src(),
    dogfood_site: "annotate-landing"
  }

  def init(_props, component, _server) do
    cfg = widget_cfg()

    component =
      put_state(component, dashboard_css: AnnotateWeb.Assets.versioned("/css/dashboard.css"))

    put_state(
      component,
      lightbox_js: AnnotateWeb.Assets.versioned("/js/dashboard-lightbox.js"),
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
        <meta name="robots" content="noindex, nofollow" />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="icon" href="/favicon.ico" sizes="48x48" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <title>{@page_title}</title>
        <link rel="preload" href="/fonts/geist-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="stylesheet" href={@dashboard_css} />
        <script src={@lightbox_js} defer></script>
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="dsh-skip" href="#main">Skip to content</a>
        <slot />
        <noizu-page-comments
          site={@dogfood_site}
          api-base={@api_base}
          rail-mode="overlay"
        ></noizu-page-comments>
        <script type="module" src={@widget_src}></script>
      </body>
    </html>
    """
  end

  defp widget_cfg do
    case Application.get_env(:annotate, :marketing) do
      kw when is_list(kw) ->
        %{
          api_base: Keyword.get(kw, :api_base, @widget_default.api_base),
          widget_src: Keyword.get(kw, :widget_src, @widget_default.widget_src),
          dogfood_site: Keyword.get(kw, :dogfood_site, @widget_default.dogfood_site)
        }

      _ ->
        @widget_default
    end
  end
end
