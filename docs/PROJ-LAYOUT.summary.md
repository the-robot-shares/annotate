# Project Layout Summary — hologram-start-app

```
hologram-start-app/
├── backend/                        # Phoenix 1.8 + Hologram app (:starter) — see backend/docs/PROJ-LAYOUT.md
│   ├── lib/                        #   Starter + StarterWeb (entities, schema, auth, authz, hologram, style_guide)
│   ├── config/                     #   Mix config (dev/test/prod/runtime)
│   ├── themes/                     #   Live theme YAML (runtime-discovered)
│   ├── db/                         #   Liquibase changelogs 000–025 + migration runner image
│   ├── priv/                       #   gettext, Ecto migrations, seeds, static assets
│   ├── test/                       #   ExUnit suites + support cases
│   ├── docs/                       #   Backend layout/arch docs
│   ├── Dockerfile · Dockerfile.dev
│   └── mix.exs
├── assets/                         # Design-system source
│   ├── theme-style-guide/          #   Canonical theme YAML
│   └── scripts/generate-css.ts     #   CSS generator (make regen)
├── design/                         # Design artifacts (themes/starter seed)
├── nginx/                          # Reverse proxy (nginx.conf, Dockerfile)
├── helm/hologram-start-app/        # Helm chart (templates + values.yaml, values-sandbox.yaml)
├── sandbox/                        # Sandbox container config (supervisord, smb.conf, entrypoint)
├── scripts/
│   └── gen-env.sh                  # Env file generator (make init)
├── docs/                           # PROJ-LAYOUT*, PROJ-ARCH*, PROJ-SCHEMA*, SCAFFOLDING.md, feature notes
├── merge-notes.md                  # start-app → hologram port notes
├── CLAUDE.md · AGENTS.md · AGENT.md # Agent instructions (worktree + PR policy)
├── .env.example                    # Env template
├── .tool-versions                  # asdf/mise runtime versions
├── .dockerignore · .gitignore
├── .base-hydration.yaml            # Scaffold hydration manifest
├── docker-compose.yaml             # Base services (nginx, backend)
├── docker-compose.dev.yaml         # Dev overrides (hot reload)
├── docker-compose.sandbox.yaml     # Sandbox overrides
├── docker-compose.ci.yml           # CI overrides
├── Dockerfile.sandbox              # Sandbox build
├── Makefile                        # Build + lifecycle
└── README.md                       # Start here
```
