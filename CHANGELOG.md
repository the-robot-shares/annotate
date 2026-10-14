# Changelog

## 2026-10-13
- feat(observability): OTLP traces via the SigNoz collector (PR #32) — opentelemetry_oban instrumentation (worker spans), chart `observability.*` env block (enabled=true default: collector endpoint http/protobuf, fleetSiteKey service.name, parentbased_traceidratio, namespace/env/version resource attrs) rendered only when enabled; request log correlation via the existing endpoint plug (metadata allowlist gains :trace_id/:span_id); no-op in dev/test without OTEL_EXPORTER_OTLP_ENDPOINT (OtelDisabledTest) + live-span correlation test
- feat(fleet): vendor FleetPush daily fleet-dashboard metrics worker + MetricsProvider behaviour (PR pending) — Oban cron 09:05 UTC, no-ops without FLEET_INGEST_KEY; nil metric = "no source" ("not reporting"), real 0 is sent as 0; default Nil provider ships all-null so fresh scaffolds are born instrumented; chart exposes FLEET_INGEST_URL/FLEET_INGEST_KEY (optional secretKeyRef); suite drives the REAL default HTTP client against an unreachable port (asanisima.si lesson)
- chore(auth): replace retired auth.noizu.com references with auth.derobot.is (#30)
## 2026-10-12

- Release of the scaffold secret/salt hardening (PR #29, 9cdfadc):
  - Removed the literal session signing salt baked into endpoint.ex; prod now RAISES on a missing SECRET_KEY_BASE / SESSION_SIGNING_SALT (dev/test still generate per boot).
  - Removed placeholder secrets from dev/test config.
  - Added `*.js.map` ignore globs, a Dockerfile source-map strip, and a CI guard against shipping source maps.
  - Chart now pins MIX_ENV / HOLOGRAM_ENV at chart level.
