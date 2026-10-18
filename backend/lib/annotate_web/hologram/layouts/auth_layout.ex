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

  alias AnnotateWeb.Hologram.Components.AnalyticsConsent

  prop :page_title, :string, default: "annotate"

  def init(_props, component, server) do
    ga_id = AnnotateWeb.Analytics.for_server(server)

    # Sign-in is a marketing surface (AnnotateWeb.Analytics): gtag + consent
    # banner render here exactly as on the landing/legal layouts, and only
    # when the request host is the marketing host (`ga_id` is nil otherwise).
    put_state(component,
      auth_css: AnnotateWeb.Assets.versioned("/css/auth.css"),
      ga_css: AnnotateWeb.Assets.versioned("/css/ga-consent.css"),
      ga_js: AnnotateWeb.Assets.versioned("/js/ga-init.js"),
      ga_id: ga_id
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
        <link rel="stylesheet" href={@auth_css} />
        {%if @ga_id}
          <link rel="stylesheet" href={@ga_css} />
          <script src={@ga_js} data-ga-id={@ga_id}></script>
        {/if}
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="nd-skip" href="#main">Skip to content</a>
        <main id="main" class="nd-auth-page">
          <slot />
        </main>
        {%if @ga_id}
          <AnalyticsConsent />
        {/if}
      </body>
    </html>
    """
  end
end
