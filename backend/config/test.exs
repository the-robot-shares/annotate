import Config

config :starter, Starter.Repo,
  username: System.get_env("DB_USER", "starter"),
  password: System.get_env("DB_PASS", "starter_dev"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "#{System.get_env("DB_NAME", "starter")}_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :starter, StarterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :noizu_sendgrid,
  sandbox_enable: true

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :starter, Oban, testing: :inline

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
