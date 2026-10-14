defmodule StarterWeb.Hologram.Components.Navbar do
  @moduledoc """
  Sticky auth-aware navbar using style-guide `sg-navbar*` classes
  (ported from start-app `frontend/src/components/navbar.tsx`).
  """
  use Hologram.Component

  alias Hologram.UI.Link
  alias StarterWeb.Hologram.Components.FloatingAuth
  alias StarterWeb.Hologram.Pages.AppHomePage
  alias StarterWeb.Hologram.Pages.HomePage
  alias StarterWeb.Hologram.Pages.StyleGuidePage

  prop :user, :map, default: nil
  prop :brand, :string, default: "Start-App: Tagline"
  prop :loading, :boolean, default: false

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <nav class="sg-navbar" aria-label="Primary">
      <div class="sg-navbar__inner">
        <Link to={HomePage} class="sg-navbar__brand">{@brand}</Link>
        <div class="sg-navbar__links">
          <Link to={StyleGuidePage} class="btn btn-outline btn-sm">Style Guide</Link>
          {%if @loading}
          {%else}
            {%if @user}
              <Link to={AppHomePage} class="btn btn-outline btn-sm">Dashboard</Link>
              <Link to={AppHomePage} class="sg-navbar__user">{@user.email}</Link>
              <button type="button" class="btn btn-outline btn-sm" $click={action: :logout, target: "layout"}>
                Log Out
              </button>
            {%else}
              <FloatingAuth />
            {/if}
          {/if}
        </div>
      </div>
    </nav>
    """
  end
end
