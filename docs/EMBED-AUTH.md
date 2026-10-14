# Annotate embed authentication (Phase 1)

Two ways a host site proves a visitor's identity to annotate:

1. **Popup broker (recommended)** — OAuth-style flow via Authentik OIDC.
2. **Host-assert** — server-to-server JWT for sites that already know who the
   user is (signed with the site service key).

## 1. Popup broker (`/embed/login` → `/embed/callback`)

Widget-side flow:

1. `window.open("https://annotate-srv.therobotlives.com/embed/login?site=<slug>&origin=<encodeURIComponent(location.origin)>", "annotate-auth", "width=480,height=640")`
2. The popup validates `origin` against `sites.allowed_origins`, stashes
   `{site_id, origin, state, nonce}` in a **signed session cookie** (max_age
   900s), and 302s to the Authentik authorize endpoint (OIDC provider from
   `OIDC_ISSUER` / `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET`; redirect URI from
   `EMBED_OIDC_REDIRECT_URI`, default `https://annotate-srv.therobotlives.com/embed/callback`).
3. Authentik redirects back; the callback exchanges the code server-side,
   verifies `state` (constant-time) and `nonce` — **failing closed**: both the
   session nonce and the id-token `nonce` claim must be present and equal, a
   missing claim on either side is a `nonce_mismatch` — enforces the site's
   `comment_policy` (any-of `required_groups`, `allowed_email_domains`),
   upserts the commenter by Authentik `sub`, and mints an access + refresh
   pair (the policy-relevant identity — `email`/`groups` — is stored on the
   refresh token for the rotation-time policy re-check described below).
4. The popup renders a tiny page that `postMessage`s to the **exact** opener
   origin:

```js
{type: "annotate-auth", access, refresh, commenter, display_name}
// failures: {type: "annotate-auth-error", reason: "state_mismatch" | "nonce_mismatch"
//  | "group_not_allowed" | "email_domain_not_allowed" | "unknown_session" | "auth_failed"}
```

Widget listens for the message and keeps the tokens in memory (access 15 min;
refresh 30 days, single-use rotation via `POST /api/v1/token/refresh`).

## 2. Host-assert (`POST /api/v1/sites/:site/token/assert`)

For hosts that authenticate users server-side and just want annotate tokens.
The host backend signs a short-lived JWT with its **service key** (shown once by
`mix annotate.site.create`; annotate stores sha256 hash + AES-256-GCM sealed
copy):

```json
{"token": "<HS256 JWT>"}
```

Claims: `sub` (required — external user id, upsert key per site), `exp`
(required — must be within **300 s**), `name` / `email` / `avatar` / `groups`
optional profile fields. The site's `comment_policy` is enforced at assert
time: `allowed_email_domains` applies to the asserted `email`,
`required_groups` to the optional `groups` claim → failures are
`403 {"error": "group_not_allowed" | "email_domain_not_allowed"}` (no
commenter is created). → `201 {"access_token", "refresh_token", "commenter"}`.

## Comment policy re-check (`/token/refresh`)

The site's `comment_policy` is enforced **at issuance** (popup callback and
host-assert) **and again on every refresh rotation**: the refresh token stores
the policy-relevant identity captured at issuance (`email`, `groups`), and
`POST /api/v1/token/refresh` re-checks it against the site's **current**
policy. A failure revokes the presented (rotated) token →
`403 {"error": "policy_violation"}` — tightening a policy kills non-conforming
sessions at their next refresh. Tokens issued before claims were stored fall
back to the commenter's stored email; for them a `required_groups` policy
fails closed (re-authentication required once, after which claims are
persisted).

## Anonymous posting (opt-in)

Guest thread creation is disabled by default. A site may opt in via
`comment_policy.allow_anonymous: true`; token-less `POST
/api/v1/sites/:site/threads` must then carry a non-empty `guest_name`, and the
comment is attributed to a site-scoped guest commenter row (never a NULL
author). Guest rows hold no credentials and can never obtain tokens.

Why the service key is *sealed*, not just hashed: host-assert needs to mint
response tokens with the exact key the host holds, so annotate must recover the
raw key material (AES-256-GCM with `ANNOTATE_KEY_ENC_SECRET` as AAD-backed
key). The hash exists for cheap presentation-time verification. Both the JWT
secret and key-encryption secret are **required in prod** (`ANNOTATE_JWT_SECRET`,
`ANNOTATE_KEY_ENC_SECRET` — boot fails closed without them).

## Host page CSP (widget embedding)

If the host site ships a strict CSP, it must allow:

- `script-src https://cdn.derobot.is` (widget bundle)
- `connect-src https://annotate-srv.therobotlives.com wss://annotate-srv.therobotlives.com` (API + polling/WS)
- `img-src https://<minio-host>` (attachment downloads are presigned MinIO URLs)
- `frame-src` / popup: none needed — the broker is `window.open`, allowed by default unless `popup` sandboxing is in play.

## Environment variables (backend)

| Var | Purpose |
|---|---|
| `ANNOTATE_JWT_SECRET` | HS256 secret for access tokens (prod: required) |
| `ANNOTATE_KEY_ENC_SECRET` | AES-256-GCM key-encryption secret for service keys (prod: required) |
| `OIDC_ISSUER` | Authentik issuer, e.g. `https://auth.derobot.is/application/o/annotate/` (Phase 1b provisioning) |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | Authentik confidential client |
| `EMBED_OIDC_REDIRECT_URI` | defaults to `https://<host>/embed/callback` |
