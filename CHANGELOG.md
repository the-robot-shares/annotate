# Changelog

All notable changes to `annotate.therobotlives.com`.

## 2026-10-14

- Phase 1b infra stand-up: chart wired for the annotate hosts — DB `annotate` on app-timescaledb, valkey db 16, secrets renamed `START_APP_*` → `ANNOTATE_*` in `annotate-secrets`, OIDC issuer `auth.derobot.is/application/o/annotate` with embed-broker redirect on annotate-srv, MinIO storage (bucket `annotate`), TLS pinned to the `therobotlives.com` wildcard secret. PR #2.
- Scaffold hydrated from `the-robot-lives/hologram-start-app` (Starter → Annotate module/app/chart rename, provenance in `.base-hydration.yaml`). PR #1.
- Phase 1 multi-tenant comments API: sites/commenters/pages/threads/comments/attachments/refresh_tokens schema (Liquibase 028–029), thread + comment + attachment controllers, HS256 access tokens w/ single-use refresh rotation, per-site CORS plug, guest comments, site-owner moderation, presigned S3 uploads + 24h pending sweeper. PR #1.
- Embed auth broker (`/embed/login` + `/embed/callback`, Authentik OIDC via `OpenIDConnect`) and host-assert identity endpoint (`POST /api/v1/sites/:site/token/assert`, service-key JWT ≤300s exp window). PR #1.
- Docs: `docs/API.md`, `docs/EMBED-AUTH.md`. PR #1.
