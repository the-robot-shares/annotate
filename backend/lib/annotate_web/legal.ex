defmodule AnnotateWeb.Legal do
  @moduledoc """
  annotate's configuration for the shared `legal_forms` component
  (`Components/legal-forms`). The text of the Privacy Policy and Terms of
  Service lives in that component's Markdown templates; this module only says
  which data-collection modules apply to annotate and fills the placeholders.

  Evaluated at compile time by `LegalForms.Hologram.template/3`, so the pages
  keep rendering as plain Hologram markup.

  When the product's data handling changes, update the toggles here AND bump
  `@last_updated` (and `AnnotateWeb.SEO` sitemap lastmod).
  """

  @last_updated "2026-10-17"

  @common %{
    product_name: "annotate",
    site_url: "https://annotate.therobotlives.com",
    contact_email: "keith.brings@noizu.com",
    operator_legal_name: "Noizu Labs, Inc.",
    last_updated: @last_updated,
    widget_commenting: true,
    github_oauth: true,
    google_oauth: true
  }

  @privacy %{
    product_summary: "It adds a comment rail to web pages and gives site owners a dashboard.",
    oidc_commenters: true,
    sso_name: "Authentik",
    uploads_storage: true,
    rate_limit_ip: true,
    cookies_session: true,
    analytics: :ga4,
    ga4_detail:
      "The marketing pages (home, sign-in, privacy and terms) use Google Analytics 4 (Google LLC) to count visits, pages viewed and referrers in aggregate. It sets first-party analytics cookies and sends page-view data to Google; GA4 does not store IP addresses. Advertising features (ad storage, ad personalisation, Google signals) are switched off. Analytics runs on those pages by default; the comment widget embedded on customer sites and the annotate API host do not load it, and we do not run advertising scripts or sell your data. If you would rather not be counted, block googletagmanager.com / google-analytics.com or use a tracking-protection extension, or ask us to delete data linked to you.",
    waitlist_email: true,
    waitlist_detail:
      "If you join the waitlist we store your email address and the features you ticked (for example MCP tools or a ticket integration) and use them only to tell you when those ship. Ask us to remove it at any time.",
    service_purpose_detail:
      "show comments to the right people, authenticate you, store attachments, and send realtime updates",
    ip_detail:
      "Your IP address, as passed by Cloudflare (CF-Connecting-IP / X-Forwarded-For), used to rate-limit abuse. The limiter keeps counters in server memory, not in the database, but ordinary infrastructure and access logs can also contain IP addresses.",
    cookies_detail:
      "a session cookie and CSRF protection for the dashboard, a short-lived (15 minute) sign-in handshake cookie for the widget's SSO popup, and your cookie preference",
    telemetry_detail:
      "Operational telemetry (logs, metrics and traces) from our own servers, kept in self-hosted tooling so we can run and debug the service.",
    description:
      "What annotate collects when you comment on a page or manage a site, who processes it, how long we keep it, and how to ask for deletion.",
    processors: [
      %{
        name: "Cloudflare",
        description:
          "proxies our traffic (DNS, TLS, caching, DDoS protection) and sees request metadata such as IP addresses."
      },
      %{
        name: "GitHub",
        description:
          "authenticates site owners. We receive the profile fields listed above; GitHub's own privacy statement governs what it does."
      },
      %{
        name: "Google (sign-in)",
        description:
          "authenticates site owners who choose Google sign-in. We receive the profile fields listed above; Google's own privacy policy governs what it does."
      },
      %{
        name: "Google (Google Analytics 4)",
        description:
          "receives page-view and device data from the marketing pages for aggregate usage statistics; Google's own privacy policy governs its processing."
      },
      %{
        name: "Our own infrastructure",
        punct: ":",
        description:
          "the application, PostgreSQL database, S3-compatible object storage (MinIO, bucket \"annotate\") and SSO run on infrastructure operated by Noizu Labs. Static assets for the widget are served from cdn.derobot.is."
      }
    ]
  }

  @terms %{
    service_description: "the comment widget, the dashboard and the API",
    data_examples: "comments, attachments, screenshots, sites, settings, keys or accounts",
    description:
      "annotate is provided as is, with no SLA and no guarantee of data. Read the terms for using the comment widget and dashboard."
    # No governing-law clause: no jurisdiction has been specified.
  }

  @spec config(:privacy | :terms) :: map
  def config(:privacy), do: Map.merge(@common, @privacy)
  def config(:terms), do: Map.merge(@common, @terms)

  @doc "`%{page_title:, description:}` for the LegalLayout props."
  def meta(doc), do: LegalForms.meta(doc, config(doc))
end
