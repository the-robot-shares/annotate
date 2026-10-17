defmodule AnnotateWeb.Hologram.Layouts.AuthLayout do
  @moduledoc """
  Auth-surface layout (Night Desk, dark) — the sign-in / sign-up / join /
  invite-gate family. Replaces the old scaffold "Start-App" style-guide shell
  those pages still rendered (landing feedback 178de5bc: the sign-in
  interstitial showed the stub theme).

  Standalone by design, same posture as `LandingLayout`/`DashboardLayout`: no
  StyleGuide.Catalog, no theme YAML. Styles live in `/css/auth.css` (nd-auth
  classes, tokens in lockstep with the landing sheet). Always noindex.
  """

  use Hologram.Component

  prop :page_title, :string, default: "annotate"

  def init(_props, component, _server) do
    put_state(component, auth_css: AnnotateWeb.Assets.versioned("/css/auth.css"))
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
        <link rel="stylesheet" href={@auth_css} />
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="nd-skip" href="#main">Skip to content</a>
        <main id="main" class="nd-auth-page">
          <slot />
        </main>
      </body>
    </html>
    """
  end
end
