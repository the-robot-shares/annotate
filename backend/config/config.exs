import Config

config :seed_helper,
  repo: Starter.Repo

config :smart_token,
  repo: Starter.Repo

config :starter, Starter.Repo,
  types: Starter.PostgrexTypes,
  migration_primary_key: [name: :id, type: :uuid]

config :starter,
  ecto_repos: [Starter.Repo],
  generators: [timestamp_type: :utc_datetime]

config :starter, StarterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: StarterWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Starter.PubSub

config :noizu_sendgrid,
  api_key: System.get_env("SENDGRID_API_KEY") || "SG.dev-placeholder"

config :starter, :mail_from, {"Starter", "noreply@starter.local"}

# Trace correlation: StarterWeb.Plugs.OtelLoggerMetadata (endpoint) reads the
# active span and sets :trace_id/:span_id logger metadata; the allowlist below
# renders them. Mirrors start-app.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

config :phoenix, :json_library, Jason

# Plug options in endpoint.ex are evaluated at compile time, so plugs that
# need boot-time values read them inside init/1; runtime init mode makes that
# init run when the endpoint serves instead of when it compiles. This is what
# lets StarterWeb.Plugs.Session pick up the per-boot session signing salt
# from runtime.exs instead of a literal committed here.
config :phoenix, :plug_init_mode, :runtime

config :starter, :redis, uri: "redis://localhost:6379/0", key_prefix: "starter:"

config :starter, Starter.Guardian,
  issuer: "starter",
  secret_key: "dev-secret-key-change-in-production"

# SSO feature flags (all disabled by default, enabled via runtime env vars)
config :ueberauth, Ueberauth, providers: []

config :starter, :oidc_enabled, false
config :starter, :saml_enabled, false
config :starter, :google_enabled, false
config :starter, :facebook_enabled, false
config :starter, :github_enabled, false
config :starter, :linkedin_enabled, false
# Retired as an access control (register open, app gated): signup never needs
# an invite and Starter.Auth.InviteGate holds gated accounts regardless of this
# value. Still parsed from SSO_REQUIRE_INVITE for zero env churn; unused.
config :starter, :sso_require_invite, false
config :starter, :sso_domains, %{}
config :starter, :sso_auto_approve_domains, []
config :starter, :sso_domain_policies, %{}

config :junit_formatter,
  report_file: "results.xml"

# Rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Background jobs
config :starter, Oban,
  repo: Starter.Repo,
  queues: [mailer: 10, default: 10, cleanup: 5, fleet_push: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */6 * * *", Starter.Workers.CleanupWorker},
       # Fleet dashboard (fleet.noizu.com) daily metrics push. No-ops at
       # runtime when FLEET_INGEST_KEY is unset.
       {"5 9 * * *", Starter.FleetPush}
     ]}
  ]

# Fleet metrics push — see Starter.FleetPush. runtime.exs overlays url/key
# from FLEET_INGEST_URL / FLEET_INGEST_KEY. A fresh scaffold ships the
# MetricsProvider.Nil provider (all metrics nil => "not reporting" on the
# dashboard); sites implement a real provider and point metrics_provider at it.
config :starter, Starter.FleetPush,
  url: "https://fleet.noizu.com/api/v1/ingest/metrics",
  source: "starter",
  metrics_provider: Starter.FleetPush.MetricsProvider.Nil,
  http_client: Starter.FleetPush.ReqClient

# Feature flags
config :starter, :feature_flags, %{
  email_verification: true,
  webhooks: false,
  file_uploads: false,
  # Past invite-only: when true, Starter.Auth.InviteGate stops holding
  # :pending/:waitlist/:unverified accounts at /auth/invite-required.
  general_release: false
}

# i18n
config :starter, StarterWeb.Gettext, default_locale: "en"

import_config "#{config_env()}.exs"
