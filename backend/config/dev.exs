import Config

config :annotate, Annotate.Repo,
  username: System.get_env("DB_USER", "annotate"),
  password: System.get_env("DB_PASS", "starter_dev"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "starter_dev"),
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :annotate, AnnotateWeb.Endpoint,
  http: [
    ip:
      case System.get_env("PHX_IP") do
        nil -> {127, 0, 0, 1}
        ip_str -> ip_str |> String.to_charlist() |> :inet.parse_address() |> elem(1)
      end,
    port: String.to_integer(System.get_env("PORT") || "5585")
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true

config :annotate, dev_routes: true

# Public app URL — Hologram UI is served by this Phoenix app (same host/port).
config :annotate, :frontend_url, System.get_env("FRONTEND_URL", "http://localhost:5585")

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :noizu_sendgrid,
  sandbox_enable: true
