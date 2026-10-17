defmodule AnnotateWeb.Hologram.Components.SiteFooter do
  @moduledoc """
  The one footer for annotate's Night Desk surfaces (landing, legal pages,
  owner dashboard): Privacy / Terms links plus the tobor-kit
  `<noizu-footer-brand>` attribution ("A The Robot Lives Joint"), loaded from
  the CDN at the same pinned sha as the rest of the kit and themed through its
  `--noizu-footer-brand-*` custom properties (`.nd-site-footer` in
  landing.css / dashboard.css).

  Self-contained on purpose: copy rewrites of the landing body never touch it.
  """

  use Hologram.Component

  alias AnnotateWeb.Hologram.Components.GithubAuth

  def template do
    ~HOLO"""
    <footer class="nd-site-footer" data-cy="site-footer">
      <div class="nd-site-footer__inner">
        <nav class="nd-site-footer__links" aria-label="Footer">
          <a href="/privacy" data-cy="footer-privacy">Privacy</a>
          <a href="/terms" data-cy="footer-terms">Terms</a>
        </nav>
        <noizu-footer-brand class="nd-site-footer__brand" align="end"></noizu-footer-brand>
      </div>
      <script type="module" src={footer_src()}></script>
    </footer>
    """
  end

  @doc "The kit's `noizu-footer-brand` bundle, pinned to the same CDN sha as the widget."
  def footer_src do
    String.replace(
      GithubAuth.kit_src(),
      "components/auth/noizu-auth.js",
      "components/footer-brand/noizu-footer-brand.js"
    )
  end
end
