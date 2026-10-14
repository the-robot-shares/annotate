# Observability (OpenTelemetry → SigNoz)

This scaffold ships a complete OpenTelemetry wiring: Phoenix/Bandit request
spans, Ecto query spans, Oban job spans, and trace-id log correlation.
Everything reports to the portfolio SigNoz instance (`https://apm.noizu.com`).

**Naming and attribute conventions (REQUIRED reading):**
[trl-infra monorepo `docs/observability/OTEL-CONVENTIONS.md`](https://github.com/the-robot-lives/trl-infra/blob/main/docs/observability/OTEL-CONVENTIONS.md)
— `service.name` must be the fleet site key **exactly**; the SigNoz
deep-links and the fleet dashboards key off it.

## What a site must set

| thing | value |
|---|---|
| `observability.fleetSiteKey` (chart value) | the site's fleet site key — canonical list in the fleet repo `app/priv/sites.yml`, generated from `docs/site-fleet/REGISTRY.md` (lowercase domain-minus-TLD: `therobotplans`, `tracktimo`, `therobot.is`) |
| `observability.enabled` | `true` (default) in cluster deploys; `false` only for fully-local/no-op builds |
| `observability.deploymentEnvironment` | `prod` \| `stage` \| `dev`; empty falls back to the release namespace |

That's the whole per-site surface. Everything else (endpoint, sampler,
protocol, resource attributes) has house defaults.

## Environment variables (runtime)

| var | meaning | default / set by |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | **master switch.** Set ⇒ OTel on; unset ⇒ whole stack no-ops (SDK `sdk_disabled: true`, no exporters, no connection attempts — hard requirement, pinned by `OtelDisabledTest`) | chart `observability.collectorEndpoint` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` (default) or `grpc` | chart `observability.protocol` |
| `OTEL_SERVICE_NAME` | `service.name` — must equal the fleet site key | chart `observability.fleetSiteKey` |
| `OTEL_RESOURCE_ATTRIBUTES` | `k=v,k=v` resource attrs: `service.namespace=portfolio`, `deployment.environment`, `service.version` (image tag) | chart builds it; app never sets `k8s.*` (collector owns those) |
| `OTEL_TRACES_SAMPLER` | sampler name — default `parentbased_traceidratio`; also `always_on`, `always_off`, `traceidratio`, `parentbased_always_on/off` | chart `observability.sampler` |
| `OTEL_TRACES_SAMPLER_ARG` | ratio for ratio samplers (`"1.0"` default) | chart `observability.samplerArg` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` = `http://signoz-otel-collector.infra.svc:4318` | in-cluster OTLP (HTTP/protobuf) | chart default; `:4317`+`grpc` is the alternative |

Pure helper: `Annotate.Observability` (unit-tested) builds resource attrs and
maps sampler/protocol values. Log correlation: the endpoint plug
`AnnotateWeb.Plugs.OtelLoggerMetadata` lifts the active span's ids into
`Logger.metadata`, and the default formatter's metadata allowlist
(`[:request_id, :trace_id, :span_id]`) renders them; with no span the plug
is a no-op. (Per-request/per-job processes keep the ids scoped; the Erlang
SDK additionally maintains `:otel_trace_id` process metadata alongside.)

## Metrics (BEAM VM + Oban)

Traces alone were phase 1; the fleet dashboard also reads metric gauges, so
the same endpoint gate also arms a metrics reader
(`opentelemetry_experimental` SDK, OTLP metrics exporter, 30s export
interval, `v1/metrics` appended to the same collector endpoint). Metrics ride
the identical `service.name` resource as traces — no separate identity.

`Annotate.Observability.Metrics.setup()` runs at boot next to the four trace
setups and, when the endpoint is set:

1. registers observable gauges for the telemetry_poller-canonical BEAM
   instruments the dashboard panels query (dotted names, `.total/.cpu/.io`
   and `.process_count` variants),

2. creates the Oban instruments (counter `oban.job.count`, histogram
   `oban.job.duration` in seconds) and attaches a `:telemetry` handler for
   `[:oban, :job, :stop]` / `[:oban, :job, :exception]`.

Attribute map per Oban sample: `queue`, `worker` (module string), `status`
(`success`/`error`). Job args, ids and error bodies never enter attributes
(PII rule; unit-tested). The handler is rescue-wrapped — a metrics failure
can never fail a job execution — and handler attach is idempotent across
test re-boots.

When the endpoint is unset the reader never starts and the handler is never
attached; the app is byte-identical to the traces-only disabled contract
(`OtelDisabledTest` + `MetricsTest` pin both halves).

Quick check that metrics are flowing (ClickHouse, counts only):

```sql
SELECT count() FROM signoz_metrics.number_time_series
WHERE service_name = '<fleetSiteKey>' AND created_at > now() - INTERVAL 15 MINUTE;
```

## Verifying in SigNoz

1. **Service exists:** `https://apm.noizu.com/services/<fleetSiteKey>` — if
   this 404s after a deploy, the key doesn't match the convention (exactness
   matters; a mismatch doesn't degrade, the link just lands nowhere).
2. **Metrics:** Metrics Explorer / the dashboard panels — gauges `vm.memory.total` and `vm.total_run_queue_lengths.*` should be non-stale within two export intervals (30s each); zero samples for a live pod means the metrics reader did not arm.
3. **Traces:** Traces Explorer filtered by `service.name = <fleetSiteKey>`;
   request traces should chain `GET /route/template` server span → Ecto
   client spans; Oban jobs appear as their own traces (worker-module-named).
4. **Dashboard:** the per-service dashboard
   `https://apm.noizu.com/dashboard/<uuid>` (dashboards are Terraform-managed
   in `terraform/monitoring/`; ask before hand-editing).
5. **Logs:** `trace_id=…` appears in log lines while a span is active —
   paste it into the SigNoz log search for the exact request's logs.

## Dev / test behaviour

No-op by design: without `OTEL_EXPORTER_OTLP_ENDPOINT` (local `mix phx.server`,
`mix test`, fresh scaffolds) the SDK starts disabled and emits nothing —
`OtelDisabledTest` pins this. `OTEL_TRACES_SAMPLER=always_off` is the
in-cluster kill switch if a site ever needs tracing off.

## Relation to FleetPush

The FleetPush worker (PR #31, `Annotate.FleetPush`) pushes **fleet activity
metrics** to fleet.noizu.com daily — a separate concern from OTel tracing.
Both may run at once; they use different env keys
(`FLEET_INGEST_URL`/`FLEET_INGEST_KEY` vs `OTEL_*`) and different
destinations.

## Frontend note

This annotate has **no Node/Next.js frontend** — the UI is Hologram
(isomorphic Elixir) served by the same BEAM process, so there is no
separate frontend service to instrument. For the Elixir + Next.js annotate
(with a browser-side OTel setup), see **start-app**.
