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
commenter upserts). No site CRUD over HTTP in Phase 1.

## Threads

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/sites/:site/threads?page_key=/p/1` | optional (see below) | list w/ comments |
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
future), `name/email/avatar/groups` optional. The site's `comment_policy` is
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
