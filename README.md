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

## Development

```bash
cd backend
mix deps.get
mix ecto.create && mix liquibase.update   # canonical schema (Liquibase owns it)
mix test                                  # needs Postgres + Redis (see docker-compose.dev.yml)
```

Branches: `develop` (default) ← feature PRs; releases `develop → stage → main`.
