defmodule AnnotateWeb.Hologram.Pages.PrivacyPage do
  @moduledoc """
  `/privacy` — Privacy Policy. Grounded in what annotate actually stores
  (docs/PROJ-ARCH.md, docs/ANCHORS.md, docs/THREAT-MODEL.md). Operator and
  contact follow house prior art (Noizu Labs, Inc.; keith.brings@noizu.com).
  """

  use Hologram.Page

  alias AnnotateWeb.Hologram.Layouts.LegalLayout

  route "/privacy"

  layout LegalLayout,
    page_title: "Privacy Policy — annotate",
    description:
      "What annotate collects when you comment on a page or manage a site, who processes it, how long we keep it, and how to ask for deletion.",
    path: "/privacy"

  def init(_params, component, _server), do: component

  def template do
    ~HOLO"""
    <article class="nd-legal__inner" data-cy="privacy-page">
      <p class="nd-section__label">Legal</p>
      <h1>Privacy Policy</h1>
      <p class="nd-legal__meta">Last updated: 2026-10-17</p>

      <p>
        annotate ("annotate", "we", "us") is operated by Noizu Labs, Inc. It adds a
        comment rail to web pages and gives site owners a dashboard. This policy explains
        what we collect, why, and what you can ask us to do about it. Questions:
        <a href="mailto:keith.brings@noizu.com">keith.brings@noizu.com</a>.
      </p>

      <h2>Who is who</h2>
      <ul>
        <li><strong>Site owners</strong> sign in to the dashboard, add a site, and put our script tag on it.</li>
        <li><strong>Commenters</strong> are the visitors of a site owner's website who leave comments with the widget.</li>
      </ul>
      <p>
        For site owners' own account data we are the controller. For comments left by a site
        owner's visitors, the site owner decides to collect them and we act as their processor.
        Site owners are responsible for telling their visitors that the widget is on their site
        and for having a legal basis to collect their comments.
      </p>

      <h2>What we collect</h2>
      <h3>Site owners (dashboard)</h3>
      <ul>
        <li>Your GitHub account id, login, name, avatar and verified email, received when you sign in with GitHub.</li>
        <li>The sites you create: name, slug, allowed origins, comment policy and settings, and API keys (stored as hashes or encrypted).</li>
      </ul>
      <h3>Commenters (widget)</h3>
      <ul>
        <li>
          Identity, depending on how the site lets visitors sign in: a display name and email
          from our SSO (Authentik), a name, email, avatar and group list that the site's own
          backend vouches for, or just a name for guests.
        </li>
        <li>The comments you write, and any files, images or screenshots you attach.</li>
        <li>
          Where the comment points: the page URL, path and query string, the CSS selector and
          XPath of the element you picked, a short quote of the selected text with the words
          around it, and the element's position and your viewport size and scroll position.
          That page context can contain whatever is on the page you annotated, including text
          or personal data shown on it.
        </li>
        <li>Short-lived access and refresh tokens that keep you signed in to the widget.</li>
      </ul>
      <h3>Everyone</h3>
      <ul>
        <li>
          Your IP address, as passed by Cloudflare (CF-Connecting-IP / X-Forwarded-For), used
          to rate-limit abuse. The limiter keeps counters in server memory, not in the database,
          but ordinary infrastructure and access logs can also contain IP addresses.
        </li>
        <li>
          Cookies: a session cookie and CSRF protection for the dashboard, a short-lived
          (15 minute) sign-in handshake cookie for the widget's SSO popup, and your cookie
          preference. These are strictly necessary and always on. Optional analytics,
          marketing and preference storage is off until you opt in.
        </li>
        <li>
          Operational telemetry (logs, metrics and traces) from our own servers, kept in
          self-hosted tooling so we can run and debug the service.
        </li>
      </ul>
      <p>
        We do not run third-party advertising or tracking scripts, and we do not sell your data.
      </p>

      <h2>Why we use it</h2>
      <ul>
        <li>To run the service: show comments to the right people, authenticate you, store attachments, and send realtime updates.</li>
        <li>To keep it safe: rate limiting, abuse prevention, and security debugging.</li>
        <li>To contact you about your account or a request you made.</li>
      </ul>

      <h2>Who processes it</h2>
      <ul>
        <li><strong>Cloudflare</strong> proxies our traffic (DNS, TLS, caching, DDoS protection) and sees request metadata such as IP addresses.</li>
        <li><strong>GitHub</strong> authenticates site owners. We receive the profile fields listed above; GitHub's own privacy statement governs what it does.</li>
        <li>
          <strong>Our own infrastructure</strong>: the application, PostgreSQL database, S3-compatible
          object storage (MinIO, bucket "annotate") and SSO run on infrastructure operated by Noizu Labs.
          Static assets for the widget are served from cdn.derobot.is.
        </li>
      </ul>
      <p>We do not share personal data with other third parties, except if the law requires it.</p>

      <h2>Who can see comments</h2>
      <p>
        That is up to the site owner. By default a site's comments are publicly readable by anyone
        on the page and only signed-in visitors can post; owners can restrict reading. Attachments
        are served through time-limited links that anyone holding the link can open, so do not attach
        anything you would not want shared.
      </p>

      <h2>How long we keep it</h2>
      <ul>
        <li>Account and site data: until the account or site is deleted.</li>
        <li>Comments and attachments: until deleted by their author or the site owner. A deleted comment is hidden right away; backups, copies and stored files may linger for a while before they are purged.</li>
        <li>Refresh tokens: 30 days, then expire. Unfinished upload records are cleaned up after 24 hours.</li>
        <li>Logs and telemetry: kept only as long as we need them for operations and security.</li>
      </ul>
      <p>
        There is no guarantee we keep data for any period; see the Terms. Keep your own copies
        of anything important.
      </p>

      <h2>Your choices</h2>
      <p>
        Depending on where you live you may have the right to access, correct, export or delete
        your personal data, or to object to how we use it. Site owners can delete comments and sites
        from the dashboard. To make a request, or to ask us to delete data you left on someone's
        site, email <a href="mailto:keith.brings@noizu.com">keith.brings@noizu.com</a> from the address on the account if you can.
        If your comment sits on a site owned by someone else, we may refer you to that site owner
        as well. We respond within a reasonable time.
      </p>

      <h2>Children</h2>
      <p>annotate is not directed to children under 13 and we do not knowingly collect their data.</p>

      <h2>Security and transfers</h2>
      <p>
        We use HTTPS, origin-bound tokens, hashed secrets and per-site isolation, but no system
        is perfectly secure and we cannot promise it. Data may be processed in countries other than yours.
      </p>

      <h2>Changes</h2>
      <p>
        We may update this policy. The date at the top shows the latest version, and continued use
        means you accept it.
      </p>

      <h2>Contact</h2>
      <p>
        Noizu Labs, Inc. &middot; <a href="mailto:keith.brings@noizu.com">keith.brings@noizu.com</a> &middot;
        See also the <a href="/terms">Terms of Service</a>.
      </p>
    </article>
    """
  end
end
