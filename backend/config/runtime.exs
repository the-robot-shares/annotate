import Config

if System.get_env("PHX_SERVER") do
  config :annotate, AnnotateWeb.Endpoint, server: true
end

# Secret material for dev/test: prefer an injected value (.env) and otherwise
# generate a strong one per boot. No literal secret_key_base or signing salt
# may be committed in this scaffold — see README/.env.example. Sessions do not
# survive a restart when the fallback fires; that is intentional, do not "fix"
# it with a literal.
#
# In :prod both variables are REQUIRED and fail fast — see the prod block
# below. A per-boot key in prod would rotate sessions on every restart and
# diverge between replicas; a missing variable must fail the boot loudly.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    :crypto.strong_rand_bytes(48) |> Base.encode64() |> binary_part(0, 64)

# Plug options are evaluated at compile time, so the session salt is read at
# runtime by AnnotateWeb.Plugs.Session.init/1 from app env (see config.exs:
# :plug_init_mode, :runtime).
session_signing_salt =
  System.get_env("SESSION_SIGNING_SALT") ||
    :crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower) |> binary_part(0, 48)

config :annotate, AnnotateWeb.Endpoint,
  secret_key_base: secret_key_base,
  session_signing_salt: session_signing_salt

config :annotate, :redis,
  uri: System.get_env("REDIS_URL") || "redis://localhost:6379/0",
  key_prefix: System.get_env("REDIS_KEY_PREFIX", "annotate:")

# Marketing landing host split — env overrides for per-env domains (staging,
# previews). Defaults live in config.exs.
config :annotate, :marketing,
  host: System.get_env("MARKETING_HOST", "annotate.therobotlives.com"),
  api_host: System.get_env("MARKETING_API_HOST", "annotate-srv.therobotlives.com"),
  api_base: System.get_env("ANNOTATE_PUBLIC_API_BASE", "https://annotate-srv.therobotlives.com"),
  widget_src:
    System.get_env(
      "ANNOTATE_PUBLIC_WIDGET_SRC",
      # Exact tobor-kit release; keep in step with AnnotateWeb.WidgetCdn.
      "https://cdn.derobot.is/tobor-kit/v1.0.1/annotate.js"
    ),
  dogfood_site: System.get_env("ANNOTATE_DOGFOOD_SITE", "annotate-landing")

# GA4 measurement id (public, G-…): marketing-host pages only, prod only, and
# only when set (chart analytics.ga.measurementId -> GA_MEASUREMENT_ID).
# AnnotateWeb.Analytics re-validates the shape before it reaches a template.
ga_measurement_id = String.trim(System.get_env("GA_MEASUREMENT_ID", ""))

config :annotate,
       :ga_measurement_id,
       if(config_env() == :prod and ga_measurement_id != "", do: ga_measurement_id, else: nil)

parse_sso_domains = fn
  nil ->
    %{}

  "" ->
    %{}

  value ->
    value
    |> String.split(~r/[;\s]+/, trim: true)
    |> Enum.reduce(%{}, fn entry, acc ->
      case String.split(entry, ["=", ":"], parts: 2) do
        [domain, providers] ->
          provider_list =
            providers
            |> String.split(",", trim: true)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          Map.put(acc, domain |> String.trim() |> String.downcase(), provider_list)

        _ ->
          acc
      end
    end)
end

parse_domain_list = fn
  nil ->
    []

  "" ->
    []

  value ->
    value
    |> String.split(~r/[,\s;]+/, trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
end

build_sso_domain_policies = fn domains, auto_approve_domains ->
  auto_approve = MapSet.new(auto_approve_domains)

  domains
  |> Enum.into(%{}, fn {domain, providers} ->
    {domain,
     %{
       providers: providers,
       auto_approve: MapSet.member?(auto_approve, "*") || MapSet.member?(auto_approve, domain)
     }}
  end)
end

# ── OpenTelemetry ────────────────────────────────────────────────
# House conventions: trl-infra monorepo docs/observability/OTEL-CONVENTIONS.md.
# Everything below is keyed off OTEL_EXPORTER_OTLP_ENDPOINT: unset (dev,
# test, chart with observability.enabled=false) ⇒ the SDK starts disabled
# (no tracer provider, no processors, no exporter, zero connection
# attempts). Otherwise the default batch processor would export to
# http://localhost:4318 and retry forever, spamming deploy logs with
# failed_connect errors.
if otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry_exporter,
    otlp_protocol: Annotate.Observability.protocol(System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL")),
    otlp_endpoint: otel_endpoint

  otel_resource =
    Annotate.Observability.resource_env_keys()
    |> Map.new(fn key ->
      {key, System.get_env(key)}
    end)
    |> Annotate.Observability.resource_attributes()
    |> Map.put_new(
      "service.version",
      Application.spec(:annotate, :vsn) |> to_string()
    )

  config :opentelemetry,
    span_processor: :batch,
    sampler:
      Annotate.Observability.sampler_spec(
        System.get_env("OTEL_TRACES_SAMPLER", "parentbased_traceidratio"),
        System.get_env("OTEL_TRACES_SAMPLER_ARG", "1.0")
      ),
    resource: otel_resource

  # Metrics leg (Annotate.Observability.Metrics): one periodic reader exporting
  # over OTLP. The exporter reads OTEL_EXPORTER_OTLP_ENDPOINT itself and appends
  # v1/metrics; the resource (service.name/namespace/version) comes from the
  # same env the traces resource uses, so metrics land on the same service.
  config :opentelemetry_experimental,
    readers: [
      %{
        module: :otel_metric_reader,
        config: %{
          export_interval_ms: 30_000,
          exporter: {:otel_exporter_metrics_otlp, %{}}
        }
      }
    ]
else
  # OTel disabled (no OTLP endpoint): start the SDK with sdk_disabled so no
  # tracer provider / span processors start — and keep the metrics app
  # disabled too, so no meter provider/reader ever comes up.
  config :opentelemetry, sdk_disabled: true
  config :opentelemetry_experimental, sdk_disabled: true
end

# ── Devbox cluster-data guardrails (scripts/devbox, DEVBOX_DATA=cluster) ──
# The dev server is pointed (via kubectl port-forward) at the REAL annotate DB.
# Keep it safe: no Oban queues/plugins (no cron sweepers/pruner against prod) and a
# read-only Repo session unless DEVBOX_CLUSTER_WRITES=1 is set explicitly.
if config_env() == :dev and System.get_env("DEVBOX_DATA") == "cluster" do
  config :annotate, Oban, queues: false, plugins: false

  if System.get_env("DEVBOX_CLUSTER_WRITES") != "1" do
    config :annotate, Annotate.Repo, parameters: [default_transaction_read_only: "on"]
  end
end

# ── Local devbox storage (scripts/devbox) ───────────────────────
# Dev has no Annotate.Storage config by default; the devbox points it at its
# local MinIO via S3_* env. Unset S3_BUCKET ⇒ dev behaves as before.
if config_env() == :dev and System.get_env("S3_BUCKET") do
  config :annotate, Annotate.Storage,
    bucket: System.fetch_env!("S3_BUCKET"),
    region: System.get_env("S3_REGION", "us-east-1"),
    host: System.get_env("S3_ENDPOINT"),
    scheme: System.get_env("S3_SCHEME", "http://"),
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("S3_REGION", "us-east-1"),
    s3: [
      scheme: System.get_env("S3_SCHEME", "http://"),
      host: System.get_env("S3_ENDPOINT"),
      region: System.get_env("S3_REGION", "us-east-1")
    ]
end

# Dev-only GitHub sign-in stub (Annotate.Auth.GithubStub): lets the dashboard
# flow run locally without a GitHub OAuth app. Never in prod — the strategy
# itself also refuses to run unless :github_stub_allowed is set, which only
# dev/test config does.
if config_env() == :dev and System.get_env("ANNOTATE_GITHUB_STUB") == "1" and
     is_nil(System.get_env("GITHUB_CLIENT_ID")) do
  config :annotate, :github_stub_allowed, true
  config :annotate, :github_enabled, true
  config :annotate, :google_enabled, true

  config :ueberauth, Ueberauth,
    providers: [github: {Annotate.Auth.GithubStub, []}, google: {Annotate.Auth.GoogleStub, []}]
end

if config_env() == :prod do
  # Dashboard + SSO flow cookies are Secure behind the TLS ingress.
  config :annotate, :secure_cookies, true

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://user:pass@host/database
      """

  config :annotate, Annotate.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  session_signing_salt =
    System.get_env("SESSION_SIGNING_SALT") ||
      raise """
      environment variable SESSION_SIGNING_SALT is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :annotate, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  guardian_secret =
    System.get_env("GUARDIAN_SECRET_KEY") ||
      raise """
      environment variable GUARDIAN_SECRET_KEY is missing.
      You can generate one by calling: mix guardian.gen.secret
      """

  config :annotate, Annotate.Guardian,
    issuer: "annotate",
    secret_key: guardian_secret

  config :annotate, :frontend_url, System.get_env("FRONTEND_URL")

  if sendgrid_key = System.get_env("SENDGRID_API_KEY") do
    config :noizu_sendgrid, api_key: sendgrid_key
  end

  config :annotate,
         :mail_from,
         {System.get_env("MAIL_FROM_NAME", "Annotate"),
          System.get_env("MAIL_FROM_ADDRESS", "noreply@annotate.local")}

  # ── Storage (S3/MinIO) ──────────────────────────────────────────
  # S3_ENDPOINT may be a bare host[:port] or a full URL
  # ("http://minio-service.infra.svc.cluster.local:9000"); ExAws wants scheme,
  # host and port as separate keys, so split it here. Passing the URL straight
  # through as :host produced "http://http:%3A//minio…" presigned URLs.
  #
  # S3_PUBLIC_ENDPOINT is the browser-reachable endpoint (e.g.
  # "https://annotate-files.therobotlives.com"). Presigned PUT/GET urls are handed to the
  # browser, so they must be signed for that host — the in-cluster service
  # name never resolves outside the cluster. Server-side calls keep using
  # S3_ENDPOINT.
  # Parsing lives in Annotate.Storage.Endpoint (unit-tested).
  if s3_bucket = System.get_env("S3_BUCKET") do
    internal =
      Annotate.Storage.Endpoint.parse(
        System.get_env("S3_ENDPOINT"),
        System.get_env("S3_SCHEME", "https://")
      )

    public = Annotate.Storage.Endpoint.parse(System.get_env("S3_PUBLIC_ENDPOINT"), "https://")

    config :annotate,
           Annotate.Storage,
           [
             bucket: s3_bucket,
             region: System.get_env("S3_REGION", "us-east-1"),
             scheme: System.get_env("S3_SCHEME", "https://"),
             access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
             secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
             public: public
           ]
           |> Keyword.merge(internal)

    config :ex_aws,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("S3_REGION", "us-east-1"),
      s3:
        [
          scheme: System.get_env("S3_SCHEME", "https://"),
          region: System.get_env("S3_REGION", "us-east-1")
        ]
        |> Keyword.merge(internal)
  end

  # ── SSO: OIDC ──────────────────────────────────────────────────
  if oidc_client_id = System.get_env("OIDC_CLIENT_ID") do
    config :openid_connect, :providers,
      default: [
        discovery_document_uri:
          System.get_env("OIDC_ISSUER") <> "/.well-known/openid-configuration",
        client_id: oidc_client_id,
        client_secret: System.get_env("OIDC_CLIENT_SECRET"),
        redirect_uri: System.get_env("OIDC_REDIRECT_URI") || "https://#{host}/auth/oidc/callback",
        response_type: "code",
        scope: "openid email profile"
      ]

    config :annotate, :oidc_enabled, true
  end

  # Trusted reverse-proxy hops in front of the app for rate-limit client-IP
  # derivation (rightmost-Nth X-Forwarded-For entry). 1 = ingress-nginx, which
  # overwrites/appends the peer address. 0 = ignore XFF, use the socket peer.
  config :annotate,
         :rate_limit_trusted_hops,
         String.to_integer(System.get_env("RATE_LIMIT_TRUSTED_HOPS") || "1")

  # Opt-in: take the client IP from this request header (e.g. cf-connecting-ip)
  # when it holds a valid IP. ONLY set when every request reaching the pod has
  # passed a proxy that overwrites the header (chart gates it on the
  # Cloudflare-only ingress whitelist); otherwise clients can forge it.
  rate_limit_client_ip_header =
    case System.get_env("RATE_LIMIT_CLIENT_IP_HEADER") do
      h when is_binary(h) and h != "" -> String.downcase(h)
      _ -> nil
    end

  config :annotate, :rate_limit_client_ip_header, rate_limit_client_ip_header

  # ── Annotate embeddable-comments API ────────────────────────────
  config :annotate, Annotate.Auth.ApiToken,
    secret:
      System.get_env("ANNOTATE_JWT_SECRET") ||
        "dev-annotate-jwt-secret-change-in-production-0123456789abcdef"

  config :annotate, Annotate.Auth.ServiceKey,
    enc_secret:
      System.get_env("ANNOTATE_KEY_ENC_SECRET") ||
        "dev-annotate-key-enc-secret-change-in-production-0123456789"

  # Popup broker redirect: the Authentik client's registered callback.
  config :annotate, :embed,
    redirect_uri: System.get_env("EMBED_OIDC_REDIRECT_URI") || "https://#{host}/embed/callback"

  if config_env() == :prod do
    # Fail closed: tokens/keys minted with a known dev fallback would be a
    # trivial forgery vector. Phase 1b wires these via Infisical.
    System.fetch_env!("ANNOTATE_JWT_SECRET")
    System.fetch_env!("ANNOTATE_KEY_ENC_SECRET")
  end

  # ── SSO: SAML ──────────────────────────────────────────────────
  saml_metadata =
    cond do
      value = System.get_env("SAML_IDP_METADATA") -> [metadata: value]
      value = System.get_env("SAML_IDP_METADATA_FILE") -> [metadata_file: value]
      true -> []
    end

  if saml_metadata != [] do
    sp_cert = System.get_env("SAML_SP_CERT", "") |> String.replace("\\n", "\n")
    sp_key = System.get_env("SAML_SP_KEY", "") |> String.replace("\\n", "\n")

    config :samly, Samly.Provider,
      service_providers: [
        %{
          id: "default",
          entity_id: System.get_env("SAML_SP_ENTITY_ID") || "https://#{host}",
          certfile_data: sp_cert,
          keyfile_data: sp_key
        }
      ],
      identity_providers: [
        %{
          id: "default",
          sp_id: "default",
          base_url: "https://#{host}/sso/saml",
          pre_session_create_pipeline: AnnotateWeb.SAMLHandler
        }
        |> Map.merge(Map.new(saml_metadata))
      ]

    config :annotate, :saml_enabled, true
  end

  # ── SSO: Social OAuth (each enabled when *_CLIENT_ID is set) ──
  # Retired: no longer an access control (see config.exs). Parsed for zero env
  # churn only — signup status comes from Annotate.Auth.InviteGate.signup_status/3.
  config :annotate, :sso_require_invite, System.get_env("SSO_REQUIRE_INVITE", "true") == "true"
  sso_domains = parse_sso_domains.(System.get_env("SSO_DOMAINS"))
  sso_auto_approve_domains = parse_domain_list.(System.get_env("SSO_AUTO_APPROVE_DOMAINS"))
  config :annotate, :sso_domains, sso_domains
  config :annotate, :sso_auto_approve_domains, sso_auto_approve_domains

  config :annotate,
         :sso_domain_policies,
         build_sso_domain_policies.(sso_domains, sso_auto_approve_domains)

  oauth_providers = []

  # Both halves non-blank (optional chart secretKeyRefs) or Google stays
  # "not configured". Same shape as the GitHub block below. (Bind the ids
  # BEFORE `oauth_providers =` — see the GitHub block's root-cause note.)
  google_id = System.get_env("GOOGLE_CLIENT_ID", "") |> String.trim()
  google_secret = System.get_env("GOOGLE_CLIENT_SECRET", "") |> String.trim()

  oauth_providers =
    if google_id != "" and google_secret != "" do
      config :ueberauth, Ueberauth.Strategy.Google.OAuth,
        client_id: google_id,
        client_secret: google_secret

      config :annotate, :google_enabled, true

      [
        {:google, {Ueberauth.Strategy.Google, [default_scope: "openid email profile"]}}
        | oauth_providers
      ]
    else
      oauth_providers
    end

  oauth_providers =
    if fb_id = System.get_env("FACEBOOK_CLIENT_ID") do
      config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
        client_id: fb_id,
        client_secret: System.get_env("FACEBOOK_CLIENT_SECRET")

      config :annotate, :facebook_enabled, true

      [
        {:facebook, {Ueberauth.Strategy.Facebook, [default_scope: "email,public_profile"]}}
        | oauth_providers
      ]
    else
      oauth_providers
    end

  # Both halves must be present and non-blank (the chart's secretKeyRefs are
  # optional, so an unpopulated Secret yields unset vars): otherwise GitHub
  # sign-in stays "not configured" rather than failing at github.com.
  gh_id = System.get_env("GITHUB_CLIENT_ID", "") |> String.trim()
  gh_secret = System.get_env("GITHUB_CLIENT_SECRET", "") |> String.trim()

  # (Root cause of the 2026-10-17 prod /auth/github 500: an earlier edit left
  # `oauth_providers = gh_id = ...` here, binding the provider list to the
  # client-id STRING — "" when unset — and discarding this `if`.)
  oauth_providers =
    if gh_id != "" and gh_secret != "" do
      config :ueberauth, Ueberauth.Strategy.Github.OAuth,
        client_id: gh_id,
        client_secret: gh_secret

      config :annotate, :github_enabled, true
      [{:github, {Ueberauth.Strategy.Github, [default_scope: "user:email"]}} | oauth_providers]
    else
      oauth_providers
    end

  # LinkedIn SSO disabled — ueberauth_linkedin has incompatible oauth2 dep
  # oauth_providers =
  #   if li_id = System.get_env("LINKEDIN_CLIENT_ID") do
  #     config :ueberauth, Ueberauth.Strategy.LinkedIn.OAuth,
  #       client_id: li_id,
  #       client_secret: System.get_env("LINKEDIN_CLIENT_SECRET")
  #     config :annotate, :linkedin_enabled, true
  #     [{:linkedin, {Ueberauth.Strategy.LinkedIn, [default_scope: "r_liteprofile r_emailaddress"]}} | oauth_providers]
  #   else
  #     oauth_providers
  #   end

  # Always set (even []): the release's build-time value arrived as "" in prod
  # (observed 2026-10-17 via rpc: `[providers: ""]`), which made Ueberauth's
  # plug init crash (`Enum.flat_map("")`) → every /auth/:provider request 500'd
  # instead of the "github_not_configured" redirect. Runtime config is applied
  # in memory, so [] stays a list here.
  config :ueberauth, Ueberauth, providers: oauth_providers

  # Fleet dashboard (fleet.noizu.com) daily metrics push. Unset/blank
  # FLEET_INGEST_KEY ⇒ the worker logs once and no-ops; nothing is pushed.
  config :annotate, Annotate.FleetPush,
    url: System.get_env("FLEET_INGEST_URL", "https://fleet.noizu.com/api/v1/ingest/metrics"),
    key: System.get_env("FLEET_INGEST_KEY")

  config :annotate, AnnotateWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    session_signing_salt: session_signing_salt
end
