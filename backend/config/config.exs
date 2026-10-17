import Config

config :seed_helper,
  repo: Annotate.Repo

config :smart_token,
  repo: Annotate.Repo

config :annotate, Annotate.Repo,
  types: Annotate.PostgrexTypes,
  migration_primary_key: [name: :id, type: :uuid]

config :annotate,
  ecto_repos: [Annotate.Repo],
  generators: [timestamp_type: :utc_datetime]

config :annotate, AnnotateWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AnnotateWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Annotate.PubSub

config :noizu_sendgrid,
  api_key: System.get_env("SENDGRID_API_KEY") || "SG.dev-placeholder"

config :annotate, :mail_from, {"Annotate", "noreply@annotate.local"}

# Trace correlation: AnnotateWeb.Plugs.OtelLoggerMetadata (endpoint) reads the
# active span and sets :trace_id/:span_id logger metadata; the allowlist below
# renders them. Mirrors start-app.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

config :phoenix, :json_library, Jason

# Plug options in endpoint.ex are evaluated at compile time, so plugs that
# need boot-time values read them inside init/1; runtime init mode makes that
# init run when the endpoint serves instead of when it compiles. This is what
# lets AnnotateWeb.Plugs.Session pick up the per-boot session signing salt
# from runtime.exs instead of a literal committed here.
config :phoenix, :plug_init_mode, :runtime

config :annotate, :redis, uri: "redis://localhost:6379/0", key_prefix: "annotate:"

config :annotate, Annotate.Guardian,
  issuer: "annotate",
  secret_key: "dev-secret-key-change-in-production"

# SSO feature flags (all disabled by default, enabled via runtime env vars)
config :ueberauth, Ueberauth, providers: []

# annotate dashboard sign-in is GitHub-only (Annotate.Auth.LoginMethods):
# the scaffold's password/magic-link/OTP, OIDC and SAML sign-in routes 404.
config :annotate, :login_methods, ["github"]
config :annotate, :post_auth_path, "/dashboard"

config :annotate, :oidc_enabled, false
config :annotate, :saml_enabled, false
config :annotate, :google_enabled, false
config :annotate, :facebook_enabled, false
config :annotate, :github_enabled, false
config :annotate, :linkedin_enabled, false
# Retired as an access control (register open, app gated): signup never needs
# an invite and Annotate.Auth.InviteGate holds gated accounts regardless of this
# value. Still parsed from SSO_REQUIRE_INVITE for zero env churn; unused.
config :annotate, :sso_require_invite, false
config :annotate, :sso_domains, %{}
config :annotate, :sso_auto_approve_domains, []
config :annotate, :sso_domain_policies, %{}

config :junit_formatter,
  report_file: "results.xml"

# Rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Background jobs
config :annotate, Oban,
  repo: Annotate.Repo,
  queues: [mailer: 10, default: 10, cleanup: 5, fleet_push: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */6 * * *", Annotate.Workers.CleanupWorker},
       # Annotate: drop pending uploads that never completed (24h TTL).
       {"30 * * * *", Annotate.Workers.AttachmentSweeper},
       # Fleet dashboard (fleet.noizu.com) daily metrics push. No-ops at
       # runtime when FLEET_INGEST_KEY is unset.
       {"5 9 * * *", Annotate.FleetPush}
     ]}
  ]

# Fleet metrics push — see Annotate.FleetPush. runtime.exs overlays url/key
# from FLEET_INGEST_URL / FLEET_INGEST_KEY. A fresh scaffold ships the
# MetricsProvider.Nil provider (all metrics nil => "not reporting" on the
# dashboard); sites implement a real provider and point metrics_provider at it.
config :annotate, Annotate.FleetPush,
  url: "https://fleet.noizu.com/api/v1/ingest/metrics",
  source: "annotate",
  metrics_provider: Annotate.FleetPush.MetricsProvider.Nil,
  http_client: Annotate.FleetPush.ReqClient

# Feature flags
config :annotate, :feature_flags, %{
  email_verification: true,
  webhooks: false,
  file_uploads: false,
  # Past invite-only: when true, Annotate.Auth.InviteGate stops holding
  # :pending/:waitlist/:unverified accounts at /auth/invite-required.
  general_release: false
}

# ── Annotate embeddable-comments API ────────────────────────────
# Dev fallbacks; runtime.exs overlays ANNOTATE_JWT_SECRET /
# ANNOTATE_KEY_ENC_SECRET, prod requires them explicitly.
config :annotate, Annotate.Auth.ApiToken,
  secret: "dev-annotate-jwt-secret-change-in-production-0123456789abcdef"

config :annotate, Annotate.Auth.ServiceKey,
  enc_secret: "dev-annotate-key-enc-secret-change-in-production-0123456789"

config :annotate, :embed, redirect_uri: nil
config :annotate, :oidc_impl, OpenIDConnect

# ── Marketing landing host split ────────────────────────────────
# annotate.therobotlives.com serves the Night Desk landing (LandingPage /
# LandingLayout); annotate-srv.therobotlives.com is the API host and must not
# serve "/" (MarketingHostGate 302s it). runtime.exs overlays MARKETING_HOST /
# MARKETING_API_HOST / ANNOTATE_PUBLIC_API_BASE / ANNOTATE_PUBLIC_WIDGET_SRC /
# ANNOTATE_DOGFOOD_SITE. Widget src: tobor-kit page-comments on cdn.derobot.is.
config :annotate, :marketing,
  host: "annotate.therobotlives.com",
  api_host: "annotate-srv.therobotlives.com",
  api_base: "https://annotate-srv.therobotlives.com",
  widget_src:
    "https://cdn.derobot.is/tobor-kit/sha-0e5a20e04fefcb400f9f395795c438a7312f27ec/components/page-comments/page-comments.js",
  dogfood_site: "annotate-landing"

# i18n
config :annotate, AnnotateWeb.Gettext, default_locale: "en"

# ExAws defaults to hackney, which is not a dependency here (req is): without
# this every server-side S3 call (delete_object, media fetch/variants) raised
# UndefinedFunctionError ExAws.Request.Hackney.request/5. Presigned urls are
# signed locally and were unaffected.
config :ex_aws, http_client: ExAws.Request.Req

import_config "#{config_env()}.exs"
