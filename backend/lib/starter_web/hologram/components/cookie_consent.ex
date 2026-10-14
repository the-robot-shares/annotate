defmodule StarterWeb.Hologram.Components.CookieConsent do
  @moduledoc """
  Category-level cookie consent banner (start-app cookie-consent port).

  Stores a versioned consent record in the Hologram session via layout commands.
  """
  use Hologram.Component

  prop :visible, :boolean, default: false

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    {%if @visible}
      <div class="cookie-banner" role="dialog" aria-label="Cookie preferences">
        <div class="cookie-banner__inner">
          <div>
            <strong>Cookies</strong>
            <p>
              We use necessary cookies to run the app. Optional analytics cookies
              help us improve the product — choose what you allow.
            </p>
          </div>
          <div class="cookie-banner__actions">
            <button type="button" class="btn btn-outline btn-sm" $click={action: :reject_optional_cookies, target: "layout"}>
              Necessary only
            </button>
            <button type="button" class="btn btn-black btn-sm" $click={action: :accept_all_cookies, target: "layout"}>
              Accept all
            </button>
          </div>
        </div>
      </div>
    {/if}
    """
  end
end
