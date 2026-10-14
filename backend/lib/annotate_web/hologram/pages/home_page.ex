defmodule AnnotateWeb.Hologram.Pages.HomePage do
  @moduledoc "Landing page — style-guide cards + CTAs (start-app home)."
  use Hologram.Page

  alias Hologram.UI.Link
  alias AnnotateWeb.Hologram.Components.ButtonRow
  alias AnnotateWeb.Hologram.Components.Card
  alias AnnotateWeb.Hologram.Components.CardGrid
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Pages.LoginPage
  alias AnnotateWeb.Hologram.Pages.SignupPage
  alias AnnotateWeb.Hologram.Pages.SitemapPage
  alias AnnotateWeb.Hologram.Pages.StyleGuidePage

  route "/"
  layout MainLayout, page_title: "Start-App: Tagline"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server) do
    put_state(component, :ready, true)
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Start-App: Tagline</h1>
      <p class="sg-page-intro">
        Edit this page to build your project. Auth, registration, consent, and the
        <strong>login → app home → org dashboard</strong> flow are ready — Hologram UI
        on the style-guide design system.
      </p>
      <ButtonRow class="sg-page-cta">
        <Link to={LoginPage} class="btn btn-outline">Log In</Link>
        <Link to={SignupPage} class="btn btn-black">Get Started</Link>
        <Link to={StyleGuidePage} class="btn btn-outline">Style Guide</Link>
        <Link to={SitemapPage} class="btn btn-outline">Site Map</Link>
      </ButtonRow>
      <CardGrid>
        <Card
          title="Accounts"
          body="Email/password, SSO, invites, magic links, and approval states."
        />
        <Card
          title="App shell"
          body="After login: /app home, profile, and /app/:org_id dashboard with sidebar chrome."
        />
        <Card
          title="Design system"
          body="YAML themes + Hologram components live in this app at /styleguide and /styleguide/tailwind-plus."
        />
      </CardGrid>
    </div>
    """
  end
end
