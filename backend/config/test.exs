import Config

# Enable the Hologram runtime in :test. Config runs before the application
# supervision tree boots, so `Hologram.enabled?/0` (HOLOGRAM_START=1) makes the
# Hologram children (page-module resolver, asset registries) start and
# `Hologram.Router` resolve page paths — without it every Hologram page request
# (e.g. the marketing landing at "/") passes through to the Phoenix router and
# 404s. test_helper.exs is too late: `mix test` starts the app before helpers.
System.put_env("HOLOGRAM_START", "1")

config :annotate, Annotate.Repo,
  username: System.get_env("DB_USER", "annotate"),
  password: System.get_env("DB_PASS", "annotate_dev"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database:
    "#{System.get_env("DB_NAME", "annotate")}_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :annotate, AnnotateWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :noizu_sendgrid,
  sandbox_enable: true

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :annotate, Oban, testing: :inline

# Minimum bcrypt cost in test: every login/invite path hashes, and the default
# cost (12) dominates the suite. Never copy this into dev/prod config.
config :bcrypt_elixir, log_rounds: 4

# Hermetic tests: strip live-provider credentials from the OS env BEFORE
# config/runtime.exs reads them (mix test evaluates this file first, in the
# same VM), so a developer's shell key can never make a test call a real
# provider. CI never sets these; this keeps local runs equal to CI.
for key <-
      ~w(SENDGRID_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY MISTRAL_API_KEY
         GROQ_API_KEY ZAI_API_KEY DASHSCOPE_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
         OIDC_CLIENT_SECRET GOOGLE_CLIENT_SECRET FACEBOOK_CLIENT_SECRET GITHUB_CLIENT_SECRET
         DATABASE_URL) do
  System.delete_env(key)
end

# config.exs already captured SENDGRID_API_KEY at load time; pin a dummy.
config :noizu_sendgrid, api_key: "SG.test-placeholder"

# ── Annotate API test config ─────────────────────────────────────
config :annotate, Annotate.Auth.ApiToken,
  secret: "test-annotate-jwt-secret-0123456789abcdef0123456789abcdef"

config :annotate, Annotate.Auth.ServiceKey,
  enc_secret: "test-annotate-key-enc-secret-0123456789abcdef0123456789abcdef"

config :annotate, :embed, redirect_uri: "http://localhost:4002/embed/callback"

# Offline S3: ExAws signs URLs locally, no network. test_helper strips live
# AWS_* env above, so these explicit keys are what ExAws uses.
config :annotate, Annotate.Storage,
  bucket: "annotate-test-bucket",
  region: "us-east-1",
  access_key_id: "test-access-key",
  secret_access_key: "test-secret-key",
  scheme: "http://",
  host: "localhost:9000"
