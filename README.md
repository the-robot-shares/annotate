# hologram-start-app

**Repo:** https://github.com/the-robot-lives/hologram-start-app

Phoenix API + **Hologram** isomorphic UI scaffold — two-container stack (backend, nginx) with Postgres/Redis on a shared Docker network.

## What

The Hologram sibling of [`components/start-app`](../start-app) (Next.js frontend). It reuses the same backend domain model (auth, orgs, PBAC, media, SSO) and the **@noizu/styleguide** design system (YAML themes → CSS), but renders the UI with Hologram pages/components instead of React.

| Layer | Choice |
|-------|--------|
| UI | Hologram 0.10 (`~HOLO`, client actions, server commands) |
| Design system | Style-guide CSS tokens + semantic classes (`btn`, `card`, `sg-*`) |
| API | Phoenix JSON at `/api/v1/*` (same as start-app) |
| Auth UI | Session-backed Hologram commands + Guardian JWT for the API |
| Proxy | Nginx → single backend |

```
Browser ──► nginx ──► Phoenix
                       ├── Hologram.Router  (pages, commands)
                       └── AnnotateWeb.Router (JSON API, SSO)
```

## Why

Noizu's default app stack is Elixir Hologram (see monorepo `CLAUDE.md`); start-app covers teams that need Next.js. This scaffold gives new Elixir-native apps the same batteries-included starting point — auth, orgs, admin, SSO, style guide — without leaving the Elixir/Hologram world or maintaining a separate React frontend.

## Getting Started

```bash
make init          # Generate .env files with secrets
make build         # Build backend + nginx images
make run           # Start containers (nginx on :8080)
```

Dev (hot reload) — `mix holo` sets `HOLOGRAM_START=1` so the Hologram compiler and client runtime are enabled:

```bash
make run-dev       # Foreground: mix holo + nginx
make run-dev-d     # Detached
make logs-dev
make stop-dev
```

Local backend only:

```bash
cd backend
mix deps.get
export HOLOGRAM_START=1
mix holo
```

Migrations & tests:

```bash
make migrate
cd backend && mix test
```

## How It Works

- Hologram pages/components handle UI; the Phoenix JSON API under `/api/v1/*` is identical to start-app, so backends stay interchangeable.
- **Style guide ownership**: this app owns the design-system Hologram components and interactive viewer (`/styleguide`, `/styleguide/tailwind-plus`) — not `components/styleguide/hologram` (retired; `styleguide/app` remains the optional Node CSS generator). Themes are live YAML discovered at runtime under `backend/themes/`, with prebuilt CSS in `backend/priv/static/themes/` and Tailwind Plus demos in `backend/priv/static/twp/`. Regenerate CSS with `make regen` after theme changes.
- Pages mirror start-app parity: `/`, `/login`, `/signup`, `/forgot-password`, `/app` (+ profile, org dashboard, members, admin users/orgs), `/complete-registration`, `/pending-approval`, `/auth/verify*`, `/auth/sso-callback`, `/sitemap`. JSON API routes remain under `/api/v1/*`.
- **Still not ported** vs the React start-app: projects list/detail UI, media upload UI, browser analytics / OTEL providers, i18n, Cypress e2e suite, and magic-link/OTP *request* buttons on login (verify routes exist).

## Scaffolding into a project

Same hydration pattern as start-app: rename `Annotate` → your module. Prefer the existing `start-app-scaffold` flow once this component is registered, or copy/rsync and sed-rename as with start-app.

## Comparison with start-app

| | start-app | hologram-start-app |
|--|-----------|--------------------|
| Frontend | Next.js 15 | Hologram 0.10 |
| Containers | nginx + backend + frontend | nginx + backend |
| UI language | TypeScript/React | Elixir (`~HOLO`) |
| Design system | `@noizu/styleguide` React + CSS | Style-guide CSS + Hologram components |
| Auth UI state | localStorage JWT | Hologram session + Guardian |
| API | `/api/v1/*` | same |

## CI

`.github/workflows/ci.yml` runs the backend suite (`mix test --cover`, coverage
gate in `backend/mix.exs`) and a backend docker smoke build in parallel on every
PR and `develop` push; on `main` the release image is built **only after the
suite passes**, then CI bumps the chart tag. `nightly.yml` keeps the release
docker cache warm. PR runs restore caches only (develop/main/nightly save).
Template defaults and current numbers: `docs/TEST-HEALTH.md`.

Entity repo overrides must call `super`, not themselves: the template's
`create`/`update`/`delete` overrides self-dispatched (sign-up's
`Credentials.register/4` raised) until 2026-10-07. Apps hydrated before that
need the same fix — see "Entity repo overrides call `super`" in
`docs/TEST-HEALTH.md`.

Entity handler warm-up: `Annotate.Application.start/2` calls
`Annotate.EntityRepo.warm_sref_handlers()` (noizu_labs_entities ≥ 0.3.4) once the
supervision tree is up, so the first requests after boot don't hit a cold
sref → handler table (Guardian `ref.user-session.*` lookups would 401); failures
only log. `backend/test/test_helper.exs` does the same before ExUnit starts and
asserts the `user-session` handler exists. Keep both in hydrated apps.

**After hydration** (`init-proj-scaffold` extracts this template into `app/`):
move `app/.github/workflows/*.yml` to the repo root `.github/workflows/`, set
`APP_DIR: app` and `CHART_VALUES` in both files, and make sure the repo has the
`TRR_GITHUB_APP_ID`/`TRR_GITHUB_APP_PRIVATE_KEY` (tobor-kit checkout) and
`REGISTRY_USER`/`REGISTRY_PASSWORD` secrets. Keep `.tool-versions`, the CI
toolchain and `backend/Dockerfile` `BASE_IMAGE` on the same Elixir/OTP.
