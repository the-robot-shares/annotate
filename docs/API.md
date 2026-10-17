# Annotate HTTP API (Phase 1)

Multi-tenant comments API. Base URL (prod): `https://annotate-srv.therobotlives.com`.
All `/api/v1` routes are tenant-scoped by **site slug**; CORS is per-site via the
site's `allowed_origins` (exact match, no wildcards, no credentials — tokens ride
`Authorization`).

Conventions:

- JSON bodies and responses; errors are `{"error": "<machine_reason>"}`.
- Auth: `Authorization: Bearer <access-jwt>` (HS256, `typ: "annotate_access"`,
  claims `sub` (commenter id), `site` (site id), `origin`, `exp`, 15 min TTL).
- **Preflights:** browsers cannot send `Authorization` on `OPTIONS`. Token-bound
  routes therefore take the site as a `?site=<slug>` query parameter (the CORS
  plug resolves the site from the path or that query param). Real requests may
  use either the query param or the path segment.
- Anonymous (guest) thread creation is **off by default** — see below. Writes
  are rate-limited per (ip, site); reads are not counted.

## Site provisioning

```
mix annotate.site.create --slug acme --name "Acme" --origins https://acme.com,https://www.acme.com
```

Prints the **service key once** (32-byte url64). Store it host-side; annotate
keeps a hash (verification) and an AES-256-GCM sealed copy (host-assert
commenter upserts).

**Primary path (2026-10-17): the owner dashboard** at
`https://annotate.therobotlives.com/dashboard`. Sign in with GitHub (the only
dashboard sign-in), **Add site** (name, site code = slug, exact origins), and
the site page shows the embed snippet, settings (display: admin+; origins and
`comment_policy`: owner; key rotation: owner), members (owner adds verified
users by email) and the comments inbox. Dashboard actions are Hologram
commands, not a REST API. Ops escape hatches: `mix annotate.site.create`,
`mix annotate.site.grant --slug S --email E` /
`Annotate.Release.grant_site_owner/2` (owner grant to a verified user).

## Site config (widget bootstrap)

`GET /api/v1/sites/:site/config` (token optional, `public_read` gated like
other reads) → `{"site", "default_visibility", "public_read",
"allow_anonymous", "max_upload_mb", "page_key_strategy", "team"}`. No PII.
`team` is true when the presented token's commenter is on the site's team
**right now** (re-derived per request, not read off the claim).
The response also carries the viewer's permission keys (below).

## Read visibility (`comment_policy.read_visibility`)

Owner-only security setting (dashboard → Security settings → "Who can read
comments"; `Sites.update_site_security/2`):

| Value | Who sees what |
|---|---|
| `public` (default) | every reader sees every thread (still gated by `public_read`) |
| `staff_only` | **staff** see every thread; any other signed-in commenter sees only the threads **they started**, with every comment in them (staff replies included); anonymous readers see **none** |

**Staff** = a live team role on the site, re-derived on every request and
every realtime event: `owner`, `admin` **or `member`** in `site_members`
(Authentik bridge), the legacy `sites.owner_commenter_id`, or a host-asserted
`team_role` while `comment_policy.trust_host_roles` is on (see EMBED-AUTH.md).
There is no "moderators only" split yet — `member` counts as staff.

Anonymous guests: guest commenter rows are shared by display name (T-11) and
hold no credential, so a guest cannot be recognised later — under
`staff_only` a guest sees their thread in the create response only.

Enforced server-side on every read path (`Annotate.Embed.Visibility`):

- `GET /sites/:site/threads` — filtered in SQL; foreign threads are never
  loaded, so they are not rendered, counted, presigned or deep-linkable.
- `/threads/:id/{comments,resolve,reopen,anchor}` and `/comments/:id`
  (PATCH/DELETE) on a thread the viewer may not read → `404 not_found`
  (identical to a foreign-site id; never `403`).
- Attachment presigned GET urls are minted only inside rendered comments of
  readable threads.
- Realtime: events are filtered per subscriber (see Realtime → Events).
- There is no search or count endpoint; deep links resolve client-side
  against the filtered list.

## Viewer permissions (`GET /api/v1/sites/:site/me`)

Token optional (same `public_read` gate as other reads). Computed live; no
PII (no ids, names or emails). The same keys are merged into `/config`.

```json
{
  "authenticated": true,          // a valid token was presented
  "role": "member",               // "owner" | "admin" | "member" | null (live)
  "staff": true,                  // role != null
  "can_read_all": true,           // public site, or staff on a staff_only site
  "can_moderate": false,          // owner/admin: may delete others' comments
  "can_post": true,               // authenticated, or anonymous on an allow_anonymous site
  "read_visibility": "staff_only" // "public" | "staff_only"
}
```

Browser: `fetch(`${api}/api/v1/sites/acme/me?site=acme`, {headers: {Authorization: `Bearer ${token}`}})`.
Host backend (server-to-server): call the same route with the viewer's
annotate access token and **no** `Origin` header (origin-less reads are
tolerated); the answer reflects current membership and site policy. A
service-key `POST /permissions/check` (no user token) is not provided — see
EMBED-AUTH.md "Learning the viewer's permissions".

## Threads

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/sites/:site/threads?page_key=/p/1[&query=a=1&b=2][&url=…][&ignore_params=utm_x]` | optional (see below) | list w/ comments; `query`/`url` narrow to matching query params (see `ANCHORS.md`) |
| POST | `/api/v1/sites/:site/threads` | token, or guest opt-in (see below) | create thread + root comment |

`GET` honors site setting `public_read` (default true): when false, a valid
token is required.

**Posting:** thread creation requires a token like every other write. A site
may opt in to anonymous threads via `comment_policy.allow_anonymous` (default
**false**); when true, a token-less create must carry a non-empty
`guest_name` (trimmed, ≤ 80 chars) and the comment is attributed to a
site-scoped **guest commenter row** — never a NULL author. Guest rows hold no
credentials and can never authenticate. Reads are unaffected and a missing
`Origin` header is tolerated on reads only.

Create body:

```json
{
  "page_key": "/products/42",
  "url": "https://acme.com/products/42",   // optional, refreshes page record
  "title": "Product 42",                    // optional
  "anchor": {"css": "#reviews", "x": 0.5},  // required, opaque jsonb
  "body_md": "first comment (markdown)",
  "guest_name": "Gary (guest)",             // required for token-less creates on allow_anonymous sites
  "attachment_ids": ["<uuid>"]              // optional, author's own + ready + unbound + same-site only
}
```

`201 {"thread": {...}}` (thread includes `comments[]` with authors +
attachments, each attachment carrying a presigned download `url`).
Errors: `400 invalid_anchor | invalid_page_key | invalid_body |
guest_name_required`, `401 invalid_token (token-less create without the
opt-in) | origin_required (token-bound write without an Origin header)`,
`404 site_not_found`, `422 attachment_mismatch`.

## Comment + thread management — token required

Site carried via `?site=<slug>`.

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/threads/:id/comments` | reply; `parent_id` optional |
| POST | `/api/v1/threads/:id/resolve` | `{"", …}` → status resolved |
| POST | `/api/v1/threads/:id/reopen` | status open, clears resolved_* |
| PATCH | `/api/v1/threads/:id/anchor` | `{"anchor": {...}}` repair; clears `orphaned_at` |
| PATCH | `/api/v1/comments/:id` | `{"body_md": …}`; author (or site owner) only; sets `edited_at` |
| DELETE | `/api/v1/comments/:id` | soft delete; author or site owner |

Edit/delete authorization: comment author, else site owner
(`sites.owner_commenter_id`). Guests (anonymous authors) can only be moderated
by the site owner. Foreign-site resources are 404 (not 403) — no existence
leak; token bound to another site is `403 site_mismatch`.

## Attachments — token required

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/attachments/presign` | `{"filename", "content_type", "bytes", "kind"?}` → `201 {attachment, upload_url}` (presigned S3 PUT) |
| POST | `/api/v1/attachments/:id/complete` | pending → ready (optional `width/height/annotation`); completer must be the uploader, else `403 forbidden`; repeat → `409 not_pending` |

Constraints: content-type allowlist (png/jpeg/webp/gif/pdf/txt), `bytes > 0`
and ≤ `max_upload_mb` (default 20) → `413 too_large`. `kind` ∈ file | image |
screenshot (default file). Pending uploads never completed are swept after 24h
(`Annotate.Workers.AttachmentSweeper`, hourly at :30). Binding
`attachment_ids` onto a comment accepts only the author's **own**, **ready**
(uncompleted uploads are rejected), still-unbound attachments on the same site
→ `422 attachment_mismatch` otherwise.

## Tokens

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/token/refresh` | `{"refresh_token"}` → `{"access_token", "refresh_token", "commenter"}`; rotation is single-use — reuse of a rotated token → `401 invalid_refresh_token`; the site's **current** `comment_policy` is re-checked against the identity captured at issuance and a failure revokes the presented token → `403 policy_violation` |
| POST | `/api/v1/sites/:site/token/assert` | host-assert identity, see EMBED-AUTH.md |

Host-assert body: `{"token": "<HS256 JWT signed with the site service key>"}`,
claims `sub` (external user id, required), `exp` (required, ≤ 300s in the
future), `name/email/avatar/groups` optional, `team_role`
(`owner|admin|member`) honoured only when the site's
`comment_policy.trust_host_roles` is true.

Access tokens of team members carry `team_role` + `team_src`
(`bridge`|`host`); see EMBED-AUTH.md "Team roles". Comment author objects
carry `"team": true` for replies written from the owner dashboard. The site's `comment_policy` is
enforced at assert time (`allowed_email_domains` against the asserted email,
`required_groups` against the optional `groups` claim) →
`403 group_not_allowed | email_domain_not_allowed`. Upserts the commenter by
`(site, external_id)` and issues a fresh access/refresh pair → `201`.
Errors: `401 invalid_assertion | expired_assertion`, `422 exp_window_exceeded |
sub_required | service_key_not_configured`, `404 site_not_found`.

### Rate limiting

Annotate write routes (thread create/reply/resolve/reopen/anchor, comment
edit/delete, attachment presign/complete, `/token/refresh`, `/token/assert`)
share a **60 requests/minute** budget keyed per `(client ip, site)`. Reads are
not counted. Exceeding it → `429` with a `Retry-After` header.

## CORS behavior

Endpoint-level plug (`AnnotateWeb.Plugs.AnnotateCORS`), scoped to `/api/v1*`:

- Origin in the addressed site's `allowed_origins` → `Access-Control-Allow-Origin: <origin>` (exact echo), methods `GET, POST, PUT, PATCH, DELETE, OPTIONS`, headers `authorization, content-type, x-annotate-site`, `Vary: Origin`.
- Origin present but not allowed → `403 {"error": "origin_not_allowed"}`, **no** ACAO header (fails in the browser).
- No Origin header (curl/native) → passes through untouched.
- Preflight (`OPTIONS` + `Access-Control-Request-Method`) → `204` when allowed.
- No `Allow-Credentials` — the API is token-bearer, not cookie-based (except the `/embed/*` popup, same-origin to annotate itself).

## Realtime

WebSocket-only Phoenix socket at **`/socket/annotate`** (no longpoll). The
widget connects after REST bootstrap and keeps a channel open per page;
everything stays read-only — writes still go through the REST API, and
committed changes fan out as broadcasts.

### Connect

```js
new Socket("/socket/annotate", { params: { site: "<site_slug>", token: "<access-jwt (optional)>" } })
```

Origin checking is two-layered (Phoenix's transport `check_origin` hook only
sees the raw `Origin` header, not the connect params):

1. **Transport gate** (CSWSH protection): a well-formed `http(s)` `Origin`
   registered in *some* annotate site's `allowed_origins` is required
   (registry-wide check, ports significant, default ports normalized away).
   No `Origin` header → allowed through (native clients), same tolerance the
   REST API has for origin-less reads.
2. **Per-site binding at `connect`**: the validated handshake origin must be
   in the *connecting site's* `allowed_origins` — an origin registered to a
   different site cannot ride along. Unknown site slug →
   `{"error": "site_not_found"}`; presented-but-invalid token →
   `{"error": "invalid_token"}` (never falls back to anonymous — same rule as
   the REST plug).

### Join

Topic per page: **`page:<site_slug>:<sha256_hex_lower(page_key)>`** — the
client hashes its `page_key` with sha256 (lowercase hex, 64 chars). The topic's
site must equal the connected site (`site_mismatch` otherwise).

Join authorization mirrors the REST thread listing:

- anonymous join (no token) only when `site.settings.public_read` is true;
- otherwise the token must verify with `site` claim == the connected site
  (`site_mismatch`) and `origin` claim in that site's `allowed_origins`
  (`origin_mismatch`).

Denied joins are rejected before the channel comes up (`{"error": "<reason>"}`).

### Events

Broadcast after the REST commit lands; payloads are rendered by the same JSON
renderer the REST API uses, so shapes are identical (attachment presigned GET
urls included):

| Event | Payload | Fires after |
|---|---|---|
| `thread_created` | `{"thread": <thread>}` | `POST /api/v1/sites/:site/threads` |
| `comment_created` | `{"comment": <comment>}` | reply / thread create |
| `comment_updated` | `{"comment": <comment>}` | comment body edit |
| `comment_deleted` | `{"comment": <comment>}` | soft delete (key removal off `id`) |
| `thread_resolved` | `{"thread": <thread>}` | resolve |
| `thread_reopened` | `{"thread": <thread>}` | reopen |
| `thread_anchor_updated` | `{"thread": <thread>}` | anchor move |

**Per-viewer filtering.** Broadcasts carry an internal `__vis` key (site,
thread creator, `read_visibility` at send time) that `PageChannel` always
strips. On a `staff_only` site each subscriber's viewer is re-derived live
(current policy + membership) and events for threads it may not read are
dropped, so a non-staff or anonymous socket never receives another user's
thread, comment, attachment url or count change.

The channel is **broadcast-only**: any client `push` is answered with
`{"error": "read_only"}` — there are no write handlers over the socket.
