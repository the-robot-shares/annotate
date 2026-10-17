defmodule AnnotateWeb.Hologram.Components.AnalyticsConsent do
  @moduledoc """
  Opt-in banner for Google Analytics (Night Desk styling, `/css/ga-consent.css`).

  Static markup, hidden by default; `/js/ga-init.js` reveals it until the
  visitor chooses, persists the choice, and only then loads gtag.js. No
  Hologram state/actions: nothing here re-renders, so the JS-driven `hidden`
  toggle is never clobbered.
  """
  use Hologram.Component

  def template do
    ~HOLO"""
    <div id="ga-consent" class="ga-consent" role="dialog" aria-live="polite" aria-label="Analytics cookies" data-cy="ga-consent" hidden>
      <div class="ga-consent__inner">
        <p class="ga-consent__text">
          <strong>Analytics cookies.</strong>
          May we use Google Analytics to count visits to this site? Nothing is sent to Google unless you accept.
          <a href="/privacy">Privacy</a>
        </p>
        <div class="ga-consent__actions">
          <button type="button" class="ga-consent__btn ga-consent__btn--ghost" data-ga-consent="decline" data-cy="ga-decline">Decline</button>
          <button type="button" class="ga-consent__btn ga-consent__btn--primary" data-ga-consent="accept" data-cy="ga-accept">Accept</button>
        </div>
      </div>
    </div>
    """
  end
end
