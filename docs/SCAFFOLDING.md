# Hologram Start-App Scaffolding

Hydrate a portfolio app from this scaffold with `init-proj-scaffold`, pointing
it at this directory via `--from` (default source is `components/start-app`,
the Next.js sibling — the flag is what selects the Hologram scaffold):

```bash
init-proj-scaffold <project_dir> <slug> <elixir_module> \
  --from components/hologram-start-app \
  --target <absolute/target/app> \
  --no-helm
```

Example (this is how `pos_app` was hydrated):

```bash
init-proj-scaffold pos-app.noizu.com pos_app Pos \
  --from components/hologram-start-app \
  --target "$PWD/Portfolio/WebApps/Product/pos-app.noizu.com/app" \
  --no-helm
```

## What hydration does

- Builds a tarball of this directory (excluding `.git`, deps/build artifacts,
  and generated `backend/priv/static/hologram/` bundles) and extracts it to
  the target.
- Rewrites `Annotate` / `AnnotateWeb` / `:annotate` to the given module/OTP app
  across `backend/**/*.{ex,exs}`, and renames `lib/annotate*` and
  `test/annotate*` directories to match.
- Substitutes the `__TOKEN__` placeholders in `.base-hydration.yaml`
  (source template path, tarball md5, hydration args and derived names).
- Emits a `docker-compose.override.yaml` port overlay (default host port 8080).

The scaffold ships un-hydrated: `Annotate` naming in code, placeholder tokens
in `.base-hydration.yaml` with `applied: false`. Do not tokenize scaffold
files beyond `.base-hydration.yaml` — the hydration tool performs the rename.

## Post-hydration steps this scaffold does NOT automate

The higher-level `start-app-scaffold` wrapper (which provisions `.env`
values, Helm values, Postgres/Valkey ACLs) targets the Next.js start-app
layout and does not read `--from`. After hydrating from this scaffold, do
the equivalent by hand or extend the wrapper:

- `.env` values for backend, nginx, SSO, app domain, cookie domain
  (`make init` in the generated app covers the local `.env` files).
- Helm wrapper chart (hence `--no-helm` above; the scaffold ships its own
  `helm/hologram-start-app` chart to adapt).
- Postgres database/user + Valkey ACL user provisioning.
- Theme CSS: the YAML→CSS pipeline is NOT wired — hand-author
  `backend/priv/static/css/app.css` with app-specific `--*` variables
  (the shipped `themes/*` and style-guide classes are the base).

## Frontend

There is none — Hologram renders the UI from the Phoenix backend
(`lib/starter_web/hologram/` pages/components). The Cypress suite from the
Next.js sibling does not apply; E2E coverage is backend tests plus the
Hologram pages themselves.
