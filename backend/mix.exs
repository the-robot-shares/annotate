defmodule Starter.MixProject do
  use Mix.Project

  def project do
    [
      app: :starter,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:hologram],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      # Ratchet: CI runs `mix test --cover`, which fails below this line %.
      # Set to floor(measured acceptance coverage) - 5; raise as tests land.
      # (Hologram 0.10.1 survives --cover here; if a future page test crashes
      # in Hologram.Reflection.beam_defs/1, drop --cover in CI and log debt.)
      test_coverage: [summary: [threshold: 11]]
    ]
  end

  def application do
    [
      mod: {Starter.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Resolve the monorepo's Portfolio/Libs/tobor-kit/hologram by walking up
  # from this mix.exs (works from both the main checkout and any
  # .claude/worktrees/<name>/backend worktree). Env override first so CI or
  # non-monorepo checkouts can pin an explicit location.
  defp kit_hologram_path do
    System.get_env("TOBOR_KIT_HOLOGRAM_PATH") ||
      (
        dir = __DIR__

        0..10
        |> Enum.find_value(fn depth ->
          candidate = Enum.reduce(1..depth//1, dir, fn _, acc -> Path.join(acc, "..") end)
          kit = Path.expand("Portfolio/Libs/tobor-kit/hologram", candidate)

          if File.exists?(Path.join(kit, "mix.exs")), do: kit
        end) ||
          raise """
          tobor_kit_hologram not found: walked up from #{dir} without finding
          Portfolio/Libs/tobor-kit/hologram. Set TOBOR_KIT_HOLOGRAM_PATH to the
          kit checkout's absolute path.
          """
      )
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      # Isomorphic UI (replaces the Next.js frontend from start-app)
      {:hologram, "~> 0.10.0"},
      # tobor-kit Hologram mirrors (Lit → native Hologram component kit).
      # Path dep resolved by walking up from this file: the scaffold sits at
      # components/hologram-start-app/backend in the monorepo, but worktrees
      # (.claude/worktrees/<name>/backend) are three levels deeper, so a fixed
      # ../ count is wrong in one of the two. TOBOR_KIT_HOLOGRAM_PATH overrides
      # for non-monorepo checkouts. Productize as a git dep once the mirror
      # ships from its own repo.
      {:tobor_kit_hologram, path: kit_hologram_path()},
      # hologram requires gproc ~> 1.0; grpcbox 0.18.0 pins gproc ~> 1.2.0
      {:gproc, "~> 1.0", override: true},
      # hologram depends on hex package `uuid` (OTP app :uuid) while our noizu
      # libs (genai, genai_core, seed_helper, smart_token, noizu_labs_entities)
      # depend on the renamed hex package `elixir_uuid` (OTP app :elixir_uuid).
      # They are the same library under two names and BOTH define the module
      # `Elixir.UUID` — `mix compile` tolerates the collision but `mix release`
      # aborts with:
      #   ** (Mix) Duplicated modules: 'Elixir.UUID' specified in elixir_uuid and uuid
      # and hex: remapping fails with "Conflicting OTP application names").
      # Instead we override :uuid with a local, module-free shim app that just
      # pulls in :elixir_uuid. See vendor/uuid_shim/mix.exs.
      {:uuid, path: "vendor/uuid_shim", override: true},
      {:noizu_sendgrid, "~> 2.1.0"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:guardian, "~> 2.3"},
      {:bcrypt_elixir, "~> 3.0"},
      # Explicit (not just transitive-optional) so Mint/Finch/Redix HTTPS
      # clients (OIDC discovery, outbound Redis TLS, etc.) always have a CA
      # trust store — without this, HTTPS requests raise
      # "default CA trust store not available".
      {:castore, "~> 1.0"},

      # SSO / OAuth
      {:openid_connect, "~> 1.0"},
      {:samly, "~> 1.4"},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_facebook, "~> 0.10"},
      {:ueberauth_github, "~> 0.8"},
      # {:ueberauth_linkedin, "~> 0.3"}, # incompatible oauth2 dep — needs replacement

      # Noizu
      {:noizu_labs_entities, "~> 0.3.0"},
      {:semaphore, "~> 1.0"},
      {:seed_helper, "~> 0.1.1"},
      {:smart_token, "~> 0.1.3"},

      # GenAI
      {:genai, "~> 0.4.0"},
      # {:ex_llama, "~> 0.2.0"},

      # Routing
      {:syn, "~> 3.3"},

      # Ecto / Schema
      {:redix, "~> 1.1"},
      {:geo_postgis, "~> 3.7"},
      {:geo, "~> 3.6"},
      {:ecto_psql_extras, "~> 0.8.1"},
      {:pgvector, "~> 0.3.0"},

      # Rate Limiting
      {:hammer, "~> 6.2"},

      # Storage
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},

      # Image Processing
      {:vix, "~> 0.31"},

      # Background Jobs
      {:oban, "~> 2.18"},

      # Observability
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.7"},
      {:opentelemetry_api_experimental, "~> 0.6"},
      {:opentelemetry_experimental, "~> 0.6"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_bandit, "~> 0.2"},
      # Oban job spans (telemetry-handler bridge; setup() in Starter.Application)
      {:opentelemetry_oban, "~> 1.2"},
      {:logger_json, "~> 6.0"},

      # Test
      {:junit_formatter, "~> 3.4", only: [:test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "liquibase.update --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
