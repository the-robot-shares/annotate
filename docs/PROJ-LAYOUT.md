# Project Layout — hologram-start-app

Hologram sibling of `components/start-app`. Two-container Docker stack: **Phoenix 1.8 + Hologram backend** (single app `:annotate` serving both `~HOLO` pages and the `/api/v1/*` JSON API) and **nginx reverse proxy** — orchestrated by Make and docker-compose, connecting to shared Postgres/Redis on a shared Docker network. No separate frontend; UI is Elixir (Hologram 0.10).

Design system: **@noizu/styleguide** YAML themes → CSS. This app owns the design-system Hologram components and the interactive style-guide viewer (`/styleguide`).

```
hologram-start-app/
├── backend/                        # Phoenix + Hologram app (:annotate) → [backend/docs/PROJ-LAYOUT.md](../backend/docs/PROJ-LAYOUT.md)
│   ├── lib/                        #   Annotate + AnnotateWeb (entities, schema, auth, authz, hologram pages/components, style_guide)
│   ├── config/                     #   Mix config per environment (+ runtime.exs)
│   ├── themes/                     #   Live theme YAML (theme-style-guide, theme-swiss, theme-sumi-e, theme-cyberpunk) — discovered at runtime
│   ├── db/                         #   Liquibase schema management → [PROJ-SCHEMA.md](PROJ-SCHEMA.md)
│   │   ├── changelog/              #     Versioned YAML changesets (000–025) + db.changelog-master.yaml
│   │   ├── liquibase.properties    #     Liquibase connection config
│   │   └── Dockerfile              #     Liquibase migration runner image
│   ├── priv/                       #   gettext, Ecto migrations (smart_token, Oban), seeds, static/ (prebuilt theme CSS, tobor-kit CSS, twp demos)
│   ├── test/                       #   ExUnit suites (auth, controllers) + support cases
│   ├── docs/                       #   Backend PROJ-LAYOUT* / PROJ-ARCH*
│   ├── Dockerfile · Dockerfile.dev #   Production / hot-reload dev builds
│   └── mix.exs                     #   Deps + aliases (`mix liquibase.update`, `mix test`)
├── assets/                         # Design-system source of truth
│   ├── theme-style-guide/          #   Canonical theme YAML (vars, palettes, typography, glyphs, snippets, …)
│   └── scripts/generate-css.ts     #   CSS generator (Node side of @noizu/styleguide; `make regen`)
├── design/                         # Design artifacts → [design/README.md](../design/README.md)
│   └── themes/annotate/             #   Annotate theme seed (branding, meta, vars)
├── nginx/                          # Reverse proxy
│   ├── nginx.conf                  #   Routes: /socket → backend (WS), /otel/ → collector, / → backend (Hologram pages + API)
│   └── Dockerfile                  #   Nginx container build
├── helm/hologram-start-app/        # Helm chart (deployment, service, ingress, migrate-job, HPA, PDB, configmap, secrets, TLS)
│   ├── Chart.yaml · values.yaml    #   Chart metadata + defaults (values-sandbox.yaml for sandbox lane)
│   └── templates/                  #   K8s manifests incl. sandbox-* (sandbox deployment/service/PVC)
├── sandbox/                        # Sandbox container config (supervisord, smb.conf, entrypoint)
├── scripts/
│   └── gen-env.sh                  # Generates .env files with secrets for all services (`make init`)
├── docs/                           # Root documentation
│   ├── PROJ-LAYOUT.md              #   This file
│   ├── PROJ-LAYOUT.summary.md      #   Tree-only quick reference
│   ├── PROJ-ARCH.md                #   Architecture documentation
│   ├── PROJ-ARCH.summary.md        #   Architecture quick reference
│   ├── PROJ-SCHEMA.md              #   Persistence + config artifact documentation
│   ├── SCAFFOLDING.md              #   How this template hydrates into a new project
│   ├── COOKIE-CONSENT.md           #   Consent feature notes
│   ├── cypress-attributes.md       #   data-* test hooks reference
│   └── frontend-reference/         #   Porting notes from the React start-app (auth, design-system)
├── merge-notes.md                  # Notes from the start-app → hologram-start-app port
├── CLAUDE.md · AGENTS.md · AGENT.md # Agent instructions (Claude / Codex / Grok — worktree + PR policy)
├── .env.example                    # Environment template — copy and configure (`make init` automates)
├── .tool-versions                  # asdf/mise versions (Elixir, Erlang, Java for Liquibase)
├── .dockerignore · .gitignore      # Build/git hygiene
├── .base-hydration.yaml            # Scaffold hydration manifest (scaffold-time variable mapping)
├── docker-compose.yaml             # Base service definitions (nginx, backend)
├── docker-compose.dev.yaml         # Dev overrides (hot reload, volume mounts)
├── docker-compose.sandbox.yaml     # Sandbox lane overrides
├── docker-compose.ci.yml           # CI overrides
├── Dockerfile.sandbox              # Sandbox container build
├── Makefile                        # Build + lifecycle commands
└── README.md                       # Start here (stack, pages, quick start)
```

## Key Files Requiring Setup

| File | Action |
|------|--------|
| `.env` | Run `make init` to generate from `.env.example` with real secrets |
| `.tool-versions` | Run `mise install` or `asdf install` (Elixir 1.19, Erlang 28, Java for Liquibase) |
| `backend/themes/*` | Duplicate a theme dir to add a theme (auto-discovered at runtime) |

## Make Targets

| Command | Purpose |
|---------|---------|
| `make init` | Generate `.env` + `backend/.env` with secrets |
| `make build` | Build Docker images (backend, nginx) |
| `make run` | Start all containers via docker-compose |
| `make run-dev` / `run-dev-d` | Dev mode (hot reload; `mix holo` sets `HOLOGRAM_START=1`) |
| `make regen` | Regenerate design-system CSS from theme YAML |
| `make migrate` | Apply Liquibase changelog |
| `make clean` | Remove containers, volumes, and local images |

## Network Architecture

Backend and nginx join a shared external Docker network where shared Postgres and Redis run. Nginx listens on `$PORT` (default 8080): `/socket` (WebSocket upgrade) and `/` (Hologram pages + `/api/v1/*` JSON) proxy to the single Phoenix backend on :4000; `/otel/` proxies to the OTLP collector. Deployment parity exists via the Helm chart (ArgoCD-managed) with a dedicated sandbox lane.
