# Annotate embed authentication (Phase 1)

Two ways a host site proves a visitor's identity to annotate:

1. **Popup broker (recommended)** — OAuth-style flow via Authentik OIDC.
2. **Host-assert** — server-to-server JWT for sites that already know who the
   user is (signed with the site service key).

## 0. Embed snippet (widget source)

The widget is tobor-kit's `<noizu-page-comments>`, served from
`cdn.derobot.is`. Each tobor-kit release ships an `annotate.js` loader that
registers the widget from that same release. Two forms:

```html
<!-- Latest (dashboard default): picks up widget fixes automatically -->
<script type="module" src="https://cdn.derobot.is/tobor-kit/latest/annotate.js"></script>
<noizu-page-comments site="<slug>" api-base="https://annotate-srv.therobotlives.com"></noizu-page-comments>

<!-- Pinned: never changes until you edit the version -->
<script type="module" src="https://cdn.derobot.is/tobor-kit/v1.0.0/annotate.js"></script>
<noizu-page-comments site="<slug>" api-base="https://annotate-srv.therobotlives.com"></noizu-page-comments>
```

| Path | Changes | Cache |
|---|---|---|
| `tobor-kit/v<X.Y.Z>/annotate.js` | never | 1 year, immutable |
| `tobor-kit/v<X>/annotate.js` | newest `X.*` release | ~5 min at the edge |
| `tobor-kit/latest/annotate.js` | newest release | ~5 min at the edge (browsers may hold it up to 4 h) |

The widget loads **collapsed**: a small pill with the page's open-comment
count. Visitors expand it with the pill or Alt+C, and the choice is
remembered per site. `#annotate=<id>` deep links always expand it. Add
`default-open` to start expanded on a first visit, or `enabled` to force it
open. annotate's own pages pin the exact version
(`AnnotateWeb.WidgetCdn.pinned_src/0`, overridable with
`ANNOTATE_PUBLIC_WIDGET_SRC`); bump `@version` there, and the `config.exs` /
`runtime.exs` defaults, to move to a new tobor-kit release. Never point a page
at a `v<X.Y.Z>/` URL before that release is published: the CDN caches 404s
on those paths for a day.

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

## Team roles (`team_role` claim)

A commenter is on a site's **team** (owner / admin / member, table
`site_members`, managed in the owner dashboard) through one of two sources,
recorded on the access token as `team_src`:

- **`bridge`**: Authentik popup sign-in only. The id_token's `email_verified`
  must be true, and that email must belong to a **verified** dashboard user
  who is a member of the site. Host-asserted and guest commenters never
  bridge, whatever their claims say.
- **`host`**: host-assert with a `team_role` claim, honoured only while the
  site's `comment_policy.trust_host_roles` is on (owner-only setting, default
  off). Turning it on means anyone holding the service key can mint team
  roles.

Refresh tokens persist the **source** (never a derived role); every rotation
re-derives the role (bridge: current membership; host: only while
`trust_host_roles` is still on) and keeps the issuing-origin binding.
Authorization never trusts the claim alone: moderation (owner/admin may
delete others' comments) and `GET /config` `team` re-check membership and
site policy on every request, so removal takes effect immediately.

### Team roles and read visibility

On a `comment_policy.read_visibility = "staff_only"` site every team role
(owner, admin, **member**) counts as **staff** and reads every thread;
everyone else reads only their own threads (API.md "Read visibility").

- **IN (host → annotate).** A host that wants its own admins treated as
  staff turns on `trust_host_roles` and adds `team_role` to the assertion:

  ```js
  // host backend, Node — never ship the service key to the browser
  const jwt = await new SignJWT({ sub: user.id, name: user.name, team_role: user.isAdmin ? "member" : undefined })
    .setProtectedHeader({ alg: "HS256" })
    .setExpirationTime("120s")
    .sign(createHash("sha256").update(SERVICE_KEY).digest());
  // POST https://annotate-srv.therobotlives.com/api/v1/sites/acme/token/assert {"token": jwt}
  ```

  The source is persisted on the refresh token (`team_src=host`,
  `host_team_role`) and re-honoured at every rotation with the T-01 origin
  binding kept; turning `trust_host_roles` off revokes staff on the very next
  request, even with a still-valid access token. Host-asserted staff is only
  as trustworthy as the holder of the service key (T-17, T-25).

- **OUT (annotate → host).** See below.

## Learning the viewer's permissions

`GET /api/v1/sites/:site/me` (and the same keys on `/config`) returns
`{authenticated, role, staff, can_read_all, can_moderate, can_post,
read_visibility}`, computed live (API.md). Three ways to consume it:

1. **Widget JS API** (tobor-kit `<page-comments>`):

   ```js
   const el = document.querySelector("page-comments");
   el.addEventListener("page-comments-permissions", (e) => {
     const p = e.detail;          // same shape as GET /me
     adminTools.hidden = !p.can_moderate;
     banner.hidden = p.can_read_all;
   });
   console.log(el.permissions);   // last known value (null before bootstrap)
   ```

   The event bubbles (composed) and fires after bootstrap and on every auth
   change (sign-in, sign-out, token refresh that changes the role).

2. **Browser fetch** with the widget's access token (`Authorization:
   Bearer`, `?site=<slug>` for the CORS preflight).

3. **Host backend**: call `/me` server-to-server with the viewer's annotate
   access token and no `Origin` header. UI hints only — annotate enforces
   visibility itself; never treat the host's copy as the gate.

Not provided: a service-key-authenticated `POST
/api/v1/sites/:site/permissions/check` taking only an external user id. It
would let any service-key holder probe membership without a user token and
adds a second authenticated read surface for no capability `/me` lacks
(follow-up if a host needs offline checks).

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
- `connect-src https://annotate-srv.therobotlives.com wss://annotate-srv.therobotlives.com https://annotate-files.therobotlives.com` (API + polling/WS, and attachment uploads: the widget PUTs files straight to a presigned URL on annotate's dedicated MinIO)
- `img-src https://annotate-files.therobotlives.com` (attachment previews/downloads are presigned URLs on annotate's dedicated MinIO)
- `frame-src` / popup: none needed — the broker is `window.open`, allowed by default unless `popup` sandboxing is in play.

`https://annotate-files.therobotlives.com` is the chart's `storage.publicEndpoint` (`S3_PUBLIC_ENDPOINT`); if that changes, the host CSP must follow. Without it in `connect-src`, attachments fail with "Upload failed".

## Environment variables (backend)

| Var | Purpose |
|---|---|
| `ANNOTATE_JWT_SECRET` | HS256 secret for access tokens (prod: required) |
| `ANNOTATE_KEY_ENC_SECRET` | AES-256-GCM key-encryption secret for service keys (prod: required) |
| `OIDC_ISSUER` | Authentik issuer, e.g. `https://auth.derobot.is/application/o/annotate/` (Phase 1b provisioning) |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | Authentik confidential client |
| `EMBED_OIDC_REDIRECT_URI` | defaults to `https://<host>/embed/callback` |
