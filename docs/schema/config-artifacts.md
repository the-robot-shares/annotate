# Data & Config Artifacts (non-SQL)

This project's persistence is not limited to Postgres. These are the file-based config/data formats it defines and consumes.

## Scaffold hydration manifest — `.base-hydration.yaml`

Written by `init-proj-scaffold` when this template is hydrated into a project. Schema id `noizu.start_app.base_hydration.v1`. Placeholders (`__SLUG__`, `__ELIXIR_MODULE__`, `__WEB_MODULE__`, `__OTP_APP__`, `__DB_NAME__`, `__HOST_PORT__`, etc.) are substituted at scaffold time; `start_app_scaffold.applied` tracks whether the project-specific scaffold pass ran. Keep the placeholder names in sync with `SCAFFOLDING.md`.

## Environment structure — `.env.example` → `.env`, `backend/.env`

`scripts/gen-env.sh` (via `make init`) generates env files from this template. Groups:

| Group | Keys |
|-------|------|
| Project identity | PROJECT_SLUG, REGISTRY |
| Postgres | DATABASE_URL (`ecto://user:pass@db:5433/db_name`) |
| Redis | REDIS_URL, REDIS_KEY_PREFIX (`{slug}:`) |
| Secrets | SECRET_KEY_BASE, GUARDIAN_SECRET_KEY (generated) |
| App | PHX_HOST, FRONTEND_URL, PORT, NEXT_PUBLIC_* (legacy start-app keys) |
| SSO (Authentik OIDC) | OIDC_ISSUER, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_REDIRECT_URI — flow activates only when client id is set |
| SSO policy | SSO_DOMAINS (`example.com=oidc;…`), SSO_AUTO_APPROVE_DOMAINS (`example.com;…` or `*`), SSO_REQUIRE_INVITE (deprecated) |

Runtime config injection happens in `backend/config/runtime.exs` from these env vars; Helm supplies the same keys via `configmap.yaml` + `app-secrets.yaml`.

## Theme YAML format — `assets/theme-style-guide/*` + `backend/themes/theme-*/`

The design-system data format. One directory per theme (`theme-{slug}/`); the canonical base lives in `assets/theme-style-guide/`, runtime-discovered themes in `backend/themes/`. File family:

| File | Contents |
|------|----------|
| `branding.yaml` | Logo, tone, audience, intro section |
| `style-guide.meta.yaml` | Theme identity: name, slug (drives `data-design-theme`), title, description |
| `style-guide.vars.yaml` | Design tokens — CSS custom properties; engine auto-generates extended scales from seeds |
| `style-guide.scoped-vars.yaml` | Component-scoped token overrides |
| `style-guide.color-palette.yaml` / `.color-modes.yaml` | Palette + light/dark mode definitions |
| `style-guide.typography.yaml`, `.spacing.yaml`, `.glyphs.yaml` | Type/spacing/icon scales |
| `style-guide.semantic-classes.yaml`, `.semantic-groups.yaml` | Semantic class definitions (`btn`, `card`, `sg-*`) |
| `style-guide.page-layouts.yaml`, `.page-sections.yaml`, `.shell-layouts.yaml`, `.design-sections.yaml`, `.globals.yaml` | Layout/section definitions for the style-guide viewer |
| `style-guide.css-snippets.yaml` | Per-component CSS snippets |
| `style-guide.jsx-snippets.yaml`, `.overrides.yaml`, `*.user.yaml` | Node-side generator extras (theme-style-guide only) |

To add a theme: duplicate a `backend/themes/theme-*` directory and edit. `make regen` (Node `assets/scripts/generate-css.ts` + `@noizu/styleguide`) regenerates CSS into `backend/priv/static/themes/`. `.bak`/`.user.yaml` variants in `theme-style-guide` are generator working files, not canonical.

## Generated/static artifacts — `backend/priv/static/`

- `themes/` — prebuilt CSS per theme (output of `make regen`; committed).
- `twp/` — Tailwind Plus demo HTML snippets + `registry.json` (consumed by `TailwindPlusPage` / `twp_catalog.ex`).

## Helm values — `helm/hologram-start-app/values.yaml`

Chart config shape (also `values-sandbox.yaml`): `domain`, `appDomain`, `cookieDomain`, `backend`/`frontend`/`migrate` images, `database`/`redis`/`secrets`/`mail`/`sso`, `extraEnv`, `configMap`, `ingress`/`tls`/`otel`/`storage`, `autoscaling`/`podDisruptionBudget`, and a `sandbox:` lane block. Secrets here map to the env keys above via templates.

## Docker/Compose config

- `docker-compose.yaml` base services (backend, nginx) + `.dev.yaml` (hot reload), `.sandbox.yaml` (sandbox lane), `.ci.yml` (CI) overrides; `Dockerfile.sandbox` + `sandbox/supervisord.conf`, `sandbox/smb.conf`, `sandbox/sandbox-entrypoint.sh` define the sandbox image.
- `backend/db/liquibase.properties` — Liquibase connection/defaults for the migration runner (values from env).

## Mix config — `backend/config/{config,dev,test,prod,runtime}.exs`

Compile-time config per environment; `runtime.exs` resolves env vars (DB URL, Guardian secret, SSO, Redis, OTel) at boot. `backend/mix.exs` aliases encode the migration order (`mix test` runs Liquibase before tests).
