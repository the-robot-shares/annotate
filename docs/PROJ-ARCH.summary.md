# Architecture Summary — hologram-start-app

Two-container Docker stack: Phoenix 1.8 + Hologram backend (single `:starter` app serving `~HOLO` pages and the `/api/v1/*` JSON API) and nginx reverse proxy; Postgres/Redis on a shared external Docker network. Hologram sibling of `components/start-app` (Next.js); shares backend domain model, Liquibase schema, SSO, and style-guide YAML themes. Deployable via Docker Compose (local) or Helm chart (Kubernetes/ArgoCD).

## Components

- **nginx** — reverse proxy: `/socket` and `/` → backend, `/otel/` → OTLP collector
- **backend** — Phoenix 1.8 JSON API + Hologram pages/commands; Guardian JWT (API), Hologram session (UI)
- **Hologram UI** — pages (auth, org dashboards, admin, style guide), components, auth middleware
- **PBAC engine** — groups + scoped memberships + JSONB policies, evaluated in-database (PL/pgSQL)
- **Workers/events** — Oban (cleanup, email) + outbound webhooks
- **Media pipeline** — upload/transform, variants cache, short-id + visibility
- **Style-guide CSS** — YAML themes → generated CSS; app owns the Hologram design-system components
- **Makefile** — build orchestration, project identity derivation
- **helm/hologram-start-app/** — K8s chart: deployment, migrate-job, HPA/PDB, sandbox lane

## Request Routing

nginx forwards `/socket` (WebSocket) and `/` to the backend on :4000. Phoenix splits traffic between `StarterWeb.Router` (`/api/v1/*`, `/health`, `/auth/*`, `/sso/*`), static (`/themes/*`, `/twp/*`), and `Hologram.Router` (all pages). Plugs: auth pipeline, CORS, Hammer rate limiting, OTel metadata.

## Auth & SSO

JWT (Guardian) for API clients; the Hologram UI keeps tokens in the Phoenix session. Email/password, magic-link/smart tokens, and SSO via OIDC (Authentik default). `SSO_DOMAINS` maps email domains to providers; `SSO_AUTO_APPROVE_DOMAINS` bypasses manual approval. New registrations can require admin approval (`pending` status).

## Schema Management

Dual-track: Liquibase YAML changelogs (000–025) are canonical — auth/users/orgs/PBAC/media/webhooks/projects/consent — applied via `make migrate`/`mix liquibase.update`; Ecto migrations cover smart_token and Oban tables. PBAC permission checks run in Postgres stored procedures (deny-overrides-allow, wildcard/template matching).

## Design System

`assets/theme-style-guide/` canonical YAML + `backend/themes/theme-*/` runtime themes → `@noizu/styleguide` → generated CSS in `backend/priv/static/themes/`. Hologram components map 1:1 to styleguide React primitives using semantic classes. Interactive viewer at `/styleguide` and `/styleguide/tailwind-plus`. Path dep `:tobor_kit_hologram` (Lit → Hologram component-kit mirror) with a browser smoke page at `/tk-smoke`.

## Deployment

Local: `make init` → `make build` → `make run`; dev mode `make run-dev` (`mix holo` sets `HOLOGRAM_START=1` — pages 404 without it). Kubernetes: Helm chart via ArgoCD auto-sync with pre-deploy migrate Job, Infisical-sourced secrets/TLS, and a dedicated sandbox lane (`Dockerfile.sandbox`, `values-sandbox.yaml`). Releases are git-driven: push to product `main` → CI builds `sha-*` images → Argo syncs.

## Scaffold Flow

Same hydration pattern as start-app: `init-proj-scaffold` builds/caches the tarball, extracts to the target project, and hydrates (rename `Starter` → module, `:starter` → otp_app, per `.base-hydration.yaml` placeholders). See `docs/SCAFFOLDING.md`.

## Technology Stack

UI: Hologram ~> 0.10 | API: Elixir 1.19, Phoenix 1.8, Bandit | DB: PostgreSQL (PostGIS, pgvector) + Liquibase | Cache: Redis | Jobs: Oban | Auth: Guardian JWT + smart_token + OIDC/SAML SSO | Design: @noizu/styleguide | Observability: OpenTelemetry + logger_json | Proxy: Nginx | Orchestration: Docker Compose + Helm (ArgoCD) | Registry: ops.noizu.com | Secrets: Infisical | Build: Make + shell

## Key Decisions

- Two-container split — UI is Elixir in the same OTP app; no separate frontend
- External shared network — projects share infra, isolated by DB/Redis credentials
- Parent-directory-driven identity — Makefile resolves slug/DB/Redis from project layout
- In-database PBAC — policy evaluation in PL/pgSQL for consistent enforcement across API and UI
- Dual-track schema — Liquibase canonical, Ecto app-level
- Runtime config injection — one image, all environments (env files / Helm ConfigMap+Secrets)
- Pluggable SSO — env-var-driven provider + approval policy
- HOLOGRAM_START gate — dev router disables pages unless explicitly enabled (test suite unaffected via `Hologram.Test.setup()`)
