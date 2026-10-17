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

  def init(_props, component, _server) do
    put_state(component, [])
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
        <link rel="stylesheet" href="/css/dashboard.css" />
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="dsh-skip" href="#main">Skip to content</a>
        <slot />
      </body>
    </html>
    """
  end
end
