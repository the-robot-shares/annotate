# annotate.therobotlives.com

**Repo:** https://github.com/the-robot-lives/annotate.therobotlives.com

Embeddable comments service: multi-tenant comments API (`annotate-srv.therobotlives.com`)
plus a minimal Hologram marketing placeholder (`annotate.therobotlives.com`).
Hydrated from the [`hologram-start-app`](https://github.com/the-robot-lives/hologram-start-app)
scaffold (see `.base-hydration.yaml` for provenance; scaffold references in
comments/docs are intentional).

## What Phase 1 (this branch) delivers

- **Tenancy** — `sites` (slug, `allowed_origins`, `comment_policy`, `settings`),
  provisioned via `mix annotate.site.create --slug <s> --name <n> --origins <a,b>`
  (service key printed once; stored hashed + AES-256-GCM sealed).
- **Comments core** — pages / threads / comments / attachments / refresh_tokens
  (Liquibase `db/changelog/028-…`, `029-…`). Guest (anonymous) comments allowed;
  authors edit/soft-delete their own; site owners moderate everything.
- **Auth** — HS256 access tokens (15 min, bound to commenter + site + origin),
  single-use rotating refresh tokens (30 d), popup OIDC broker
  (`/embed/login` → `/embed/callback`, Authentik) and host-assert identity
  (`POST /api/v1/sites/:site/token/assert`, service-key JWT, exp ≤ 300 s).
- **CORS** — per-site exact-origin echo (`AnnotateWeb.Plugs.AnnotateCORS`);
  preflights resolve the site from the path or `?site=`.
- **Uploads** — presigned S3/MinIO PUT, pending → ready completion, content-type
  allowlist, per-site size cap, 24 h pending sweeper (Oban cron).

Docs: [`docs/API.md`](docs/API.md) · [`docs/EMBED-AUTH.md`](docs/EMBED-AUTH.md).

## Stack

| Layer | Choice |
|-------|--------|
| Backend | Phoenix JSON API at `/api/v1/*` (scaffold domain: auth/orgs/PBAC/media/SSO retained) |
| UI | Hologram 0.10 marketing placeholder (same scaffold design system) |
| Proxy | Nginx → single backend; host-based routing (Phase 1b wiring) |
| Data | Postgres (pgvector image), Redis, Oban queues |

## Local devbox

`scripts/devbox up` runs Phoenix + Hologram on the host (code reload, log `/tmp/annotate-devbox.log`)
and serves **both hosts** from one process: `http://annotate.localhost:4100/` (landing) and
`http://annotate-srv.localhost:4100/` (API + `/socket/annotate`). Run it from the main checkout.

```bash
scripts/devbox up [--local|--cluster]   # default data source: cluster (see warning)
scripts/devbox status | logs [-f|N|infra] | shell | restart | down
scripts/devbox reset                    # wipe LOCAL volumes + site keys, back to --local
scripts/devbox test [args]              # mix test, always against the local docker Postgres
```

- **`--local`**: docker compose project `annotate-devbox` (pgvector Postgres :54391, Redis :56379,
  MinIO :59000/:59001, bucket `annotate`). Liquibase 000-030 + Ecto migrate are applied and dev sites
  `annotate-landing` and `devsite` are seeded (service keys under `~/.local/state/annotate-devbox/`).
- **`--cluster` (default): PROD DATA.** `kubectl port-forward` (context `noizu` only, auto-reconnecting) to
  the real `annotate` Postgres (app-timescaledb), Valkey db 16 and MinIO. Credentials are read from the
  `annotate-secrets` Secret into the process environment only. Guardrails: the Repo session is
  read-only (`DEVBOX_CLUSTER_WRITES=1` to lift), Oban queues/cron/pruner are off, and no migration, Liquibase,
  seed or test ever runs against it. Browser use against cluster data additionally needs the page origin in the
  site's `allowed_origins` (per-site exact-origin CORS).
- **Login without Authentik (dev only):** `http://annotate-srv.localhost:4100/embed/dev-login?site=<slug>&origin=<origin>` shows a name/email form and mints the same token pair as `/embed/callback` (postMessage to the opener). The route and controller are compiled in only when `MIX_ENV=dev` (pinned by `dev_login_test.exs`). It writes a commenter + refresh-token row, so on cluster data use the dedicated `devbox` site and `DEVBOX_CLUSTER_WRITES=1`.
- `scripts/devbox cluster-site SLUG NAME ORIGINS` is the one sanctioned additive cluster write (refuses an existing slug); the key goes to `~/.local/state/annotate-devbox/site-SLUG.key`.
- The landing widget loads from the CDN (`ANNOTATE_PUBLIC_WIDGET_SRC` overrides); its `api-base` points at the local API host.
- Generated dev secrets live in `~/.local/state/annotate-devbox/env` (outside the repo, mode 600).

## Development

```bash
cd backend
mix deps.get
mix ecto.create && mix liquibase.update   # canonical schema (Liquibase owns it)
mix test                                  # needs Postgres + Redis (see docker-compose.dev.yml)
```

Branches: `develop` (default) ← feature PRs; releases `develop → stage → main`.
