# Project Layout — hologram-start-app/backend

Phoenix 1.8 + Hologram app — OTP app **`:starter`** (`Starter` / `StarterWeb`). start-app platform scaffold (users, orgs, PBAC, media, SSO, workers, consent) with Hologram UI served by the same Phoenix host (no separate frontend).

Plain tree: [`PROJ-LAYOUT.summary.md`](PROJ-LAYOUT.summary.md). Arch: [`PROJ-ARCH.md`](PROJ-ARCH.md).

```
backend/
├── lib/
│   ├── starter.ex
│   ├── starter/
│   │   ├── application.ex · repo.ex · entity_repo.ex · redis.ex · release.ex
│   │   ├── guardian.ex · mailer.ex · feature_flags.ex · storage.ex
│   │   ├── auth/                       # smart_token, SSO, token_store
│   │   ├── authz/                      # policy_evaluator, uuids
│   │   ├── entities/                   # users, orgs, media, projects, authz, versioned, providers
│   │   ├── schema/                     # Ecto schemas (mirror entities) + cookie_consent
│   │   ├── media/ · events/ · protocols/
│   │   ├── hologram/                 # Hologram runtime helpers (auth, etc.)
│   │   └── style_guide/              # design-system components
│   │   └── workers/                    # cleanup, email (Oban)
│   ├── starter_web.ex
│   ├── starter_web/
│   │   ├── endpoint.ex · router.ex · telemetry.ex · gettext.ex
│   │   ├── controllers/                # auth, sso, org, media, admin, consent, pbac, …
│   │   ├── plugs/                      # auth pipeline, RBAC, rate_limit, cors, otel
│   │   └── channels/                   # user_socket, org_channel
│   ├── mix/tasks/liquibase.update.ex   # `mix liquibase.update`
│   └── supports/                       # ecto, event, migration, jason encoder, types
├── config/                             # config/dev/test/prod/runtime.exs
├── themes/                            # theme CSS sources
├── db/
│   ├── changelog/                      # 000–025 + db.changelog-master.yaml
│   ├── liquibase.properties
│   └── Dockerfile                      # Migration runner image
├── priv/
│   ├── gettext/
│   └── repo/
│       ├── migrations/                 # smart_token, Oban
│       └── seeds.exs · seeds/          # env seeds + auth_providers/
├── test/
│   ├── starter/ · starter_web/         # auth + controller tests
│   └── support/                        # conn_case, data_case
├── docs/                               # PROJ-LAYOUT* · PROJ-ARCH*
├── Dockerfile · Dockerfile.dev
├── mix.exs · mix.lock                  # app: :starter
└── .tool-versions
```

## Key Files Requiring Setup

| File | Action |
|------|--------|
| `.env` | DB URL, Guardian secret, SSO (via root `make init`) |
| `.tool-versions` | `asdf install` / `mise install` |

## Mix Aliases

| Command | Purpose |
|---------|---------|
| `mix setup` | deps → ecto create/migrate → seeds |
| `mix ecto.reset` | Drop → create → migrate → seeds |
| `mix test` | Quiet DB create → `liquibase.update` → tests |
| `mix liquibase.update` | Apply canonical Liquibase changelog to Repo DB |

## Notable Dependencies

- **Phoenix 1.8** + **Bandit**
- **Guardian** + **bcrypt_elixir** · **smart_token** · **openid_connect** / **samly** / Ueberauth
- **noizu_labs_entities** · **GenAI** · **Syn** · **Redix** · **Hammer**
- **PostGIS / pgvector / geo** · **Oban** · **ex_aws** / **vix** (media)
- **OpenTelemetry** stack · **logger_json**
