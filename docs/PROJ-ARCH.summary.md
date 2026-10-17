# Architecture Summary — annotate.therobotlives.com

Embeddable multi-tenant comments service (sites, pages, threads, comments, attachments). Two hosts on one Phoenix release: `annotate-srv.therobotlives.com` (API `/api/v1`, popup auth broker `/embed/*`, websocket `/socket/annotate`) and `annotate.therobotlives.com` (Hologram "Night Desk" landing dogfooding the widget).

- **Tenancy**: `sites` (slug, `allowed_origins`, `comment_policy`, `settings`, service key). CLI-provisioned (`mix annotate.site.create`). All lookups scoped by site id.
- **Auth**: 15-min HS256 access JWT bound to commenter+site+origin (`Annotate.Auth.ApiToken`); 30-day single-use rotating refresh token, sha256 at rest (`RefreshTokens`); Authentik popup login via `/embed/callback` (state+nonce in signed cookie, postMessage to registered origin); host-assert via service-key-signed JWT (`TokenController`).
- **Edge controls**: per-site exact-match CORS (`AnnotateCORS`), Hammer ETS rate limits (60 writes/min per ip+site), websocket origin gate (`AnnotateSocket`), read-only `PageChannel`.
- **Storage**: Postgres (Liquibase owns schema; Helm migrate Job is Ecto-only), MinIO presigned PUT/GET for attachments, Valkey, Oban sweeper.
- **Also shipped**: inherited scaffold surface (PBAC, orgs, invites, password auth, SSO, webhooks, media) on the same hosts.

Full doc: [PROJ-ARCH.md](PROJ-ARCH.md).
