defmodule AnnotateWeb.Hologram.Layouts.MainLayout do
  @moduledoc """
  Root Hologram layout: multi-theme style-guide CSS, runtime, navbar, cookie consent.

  Theme YAML lives under `backend/themes/theme-*/`; CSS under `priv/static/themes/`.
  Cookie `sg-theme` selects the active theme; `color-mode` selects light/dark.
  """
  use Hologram.Component

  alias AnnotateWeb.Hologram.Components.AnalyticsConsent

  alias Hologram.UI.Link
  alias Annotate.Hologram.Auth
  alias Annotate.StyleGuide.Catalog
  alias AnnotateWeb.Hologram.Components.CookieConsent
  alias AnnotateWeb.Hologram.Components.Navbar
  alias AnnotateWeb.Hologram.Pages.AppHomePage
  alias AnnotateWeb.Hologram.Pages.StyleGuidePage
  alias AnnotateWeb.Hologram.Pages.TailwindPlusPage

  prop :page_title, :string, default: "Start-App"
  prop :brand, :string, default: "Start-App"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_props, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)
    ga_id = AnnotateWeb.Analytics.for_server(server)
    consent = Hologram.Server.get_session(server, :cookie_consent)
    color_mode = Hologram.Server.get_cookie(server, "color-mode", "system")
    theme_slug = Hologram.Server.get_cookie(server, "sg-theme", "style-guide")
    theme = Catalog.get_theme(theme_slug)
    brand = Catalog.brand()

    component =
      put_state(component,
        user: user,
        ga_css: AnnotateWeb.Assets.versioned("/css/ga-consent.css"),
        ga_js: AnnotateWeb.Assets.versioned("/js/ga-init.js"),
        ga_id: ga_id,
        organizations: organizations || [],
        show_cookie_banner: is_nil(consent) and is_nil(ga_id),
        color_mode: color_mode,
        theme_slug: theme.slug,
        theme_css: theme.css,
        themes: Catalog.themes(),
        brand_meta: brand,
        brand: brand.logo_text || "Start-App",
        font_url:
          brand.font_url ||
            "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=IBM+Plex+Mono:ital,wght@0,300;0,400;0,500;0,600;1,400&display=swap"
      )

    {component, server}
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en" data-design-theme={@theme_slug} class={html_class(@color_mode)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>{@page_title}</title>
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="icon" href="/favicon.ico" sizes="48x48" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link rel="stylesheet" href={@font_url} />
        <link rel="stylesheet" href={@theme_css} />
        <link rel="stylesheet" href="/css/app.css" />
        <link rel="stylesheet" href="/css/tobor-kit.css" />
        <link rel="stylesheet" href="/css/viewer.css" />
        {%if @ga_id}
          <link rel="stylesheet" href={@ga_css} />
          <script src={@ga_js} data-ga-id={@ga_id}></script>
        {/if}
        <Hologram.UI.Runtime />
      </head>
      <body>
        <a class="skip-link" href="#main">Skip to content</a>
        <Navbar user={@user} brand={@brand} />
        <div class="sg-viewer-bar sg-viewer-bar--compact" aria-label="Design system">
          <div class="sg-viewer-bar__left">
            <nav class="sg-site-nav" aria-label="Style guide">
              <Link to={StyleGuidePage} class="sg-site-nav__link">Style guide</Link>
              <Link to={TailwindPlusPage} class="sg-site-nav__link">Tailwind Plus</Link>
              {%if @user}
                <Link to={AppHomePage} class="sg-site-nav__link">App</Link>
              {/if}
            </nav>
          </div>
          <div class="sg-viewer-bar__controls">
            <label for="theme-select" style="font-size: var(--font-size-xs); opacity: 0.7">Theme</label>
            <select id="theme-select" $change={action: :set_theme, target: "layout"}>
              {%for t <- @themes}
                <option value={t.slug} selected={t.slug == @theme_slug}>{t.name}</option>
              {/for}
            </select>
            <button type="button" class="btn btn-outline btn-sm" $click={action: :toggle_dark, target: "layout"}>
              {%if @color_mode == "dark"}Light{%else}Dark{/if}
            </button>
          </div>
        </div>
        <main id="main">
          <slot />
        </main>
        <CookieConsent cid="cookie_consent" visible={@show_cookie_banner} />
        {%if @ga_id}
          <AnalyticsConsent />
        {/if}
      </body>
    </html>
    """
  end

  # <REMOVED UUID HERE> html_class :: auto-generated pointer for public function html_class
  def html_class("dark"), do: "dark"
  def html_class(_), do: ""

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_theme, params, component) do
    slug = params.event.value
    theme = Catalog.get_theme(slug)

    component
    |> put_state(theme_slug: theme.slug, theme_css: theme.css)
    |> put_command(:persist_theme, slug: theme.slug)
  end

  def action(:toggle_dark, _params, component) do
    next = if component.state.color_mode == "dark", do: "light", else: "dark"

    component
    |> put_state(:color_mode, next)
    |> put_command(:persist_color_mode, mode: next)
  end

  def action(:accept_all_cookies, _params, component) do
    component
    |> put_state(:show_cookie_banner, false)
    |> put_command(:save_cookie_consent, analytics: true, marketing: true, preferences: true)
  end

  def action(:reject_optional_cookies, _params, component) do
    component
    |> put_state(:show_cookie_banner, false)
    |> put_command(:save_cookie_consent, analytics: false, marketing: false, preferences: false)
  end

  def action(:logout, _params, component) do
    component
    |> put_state(user: nil, organizations: [])
    |> put_command(:logout)
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:persist_theme, params, server) do
    Hologram.Server.put_cookie(server, "sg-theme", params.slug,
      http_only: false,
      max_age: 60 * 60 * 24 * 365,
      secure: false
    )
  end

  def command(:persist_color_mode, params, server) do
    Hologram.Server.put_cookie(server, "color-mode", params.mode,
      http_only: false,
      max_age: 60 * 60 * 24 * 365,
      secure: false
    )
  end

  def command(:save_cookie_consent, params, server) do
    consent = %{
      version: 1,
      necessary: true,
      analytics: Map.get(params, :analytics, false),
      marketing: Map.get(params, :marketing, false),
      preferences: Map.get(params, :preferences, false),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Hologram.Server.put_session(server, :cookie_consent, consent)
  end

  def command(:logout, _params, server) do
    server
    |> Auth.logout()
    |> Hologram.Server.put_redirect(AnnotateWeb.Hologram.Pages.LandingPage)
  end
end
