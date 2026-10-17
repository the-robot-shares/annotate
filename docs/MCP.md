# annotate MCP server

Remote [Model Context Protocol](https://modelcontextprotocol.io) server so AI
agents (Claude Code, Claude.ai / Claude Desktop connectors, VS Code, Codex…)
can read and triage a site's comments **as the signed-in dashboard user**.

| | |
|---|---|
| Endpoint (Streamable HTTP) | `https://annotate.therobotlives.com/mcp` |
| Authorization server (issuer) | `https://annotate.therobotlives.com` (annotate itself — never Authentik) |
| AS metadata (RFC 8414) | `/.well-known/oauth-authorization-server` (also `/.well-known/openid-configuration`) |
| Protected-resource metadata (RFC 9728) | `/.well-known/oauth-protected-resource/mcp` (and the bare path) |
| OAuth endpoints | `/oauth/authorize`, `/oauth/consent`, `/oauth/token`, `/oauth/register` (DCR, RFC 7591), `/oauth/revoke` |
| Library | [`noizu_mcp`](https://hex.pm/packages/noizu_mcp) 0.6.x (`Noizu.MCP.Auth.Server`, `Store.Ecto`) |
| Dashboard | `/dashboard/agents` — connect snippets, connected clients (+ granted scopes, revoke), activity log |

## Connect

```bash
claude mcp add --transport http annotate https://annotate.therobotlives.com/mcp
# then /mcp → annotate → Authenticate
```

Claude.ai / Claude Desktop: *Settings → Connectors → Add custom connector*, URL
above. VS Code: `.vscode/mcp.json` `{"servers":{"annotate":{"type":"http","url":"…/mcp"}}}`.
Codex: `codex mcp add annotate --url …/mcp` then `codex mcp login annotate`.
**Cursor is not supported yet**: its OAuth callback is a `cursor://` URI and
noizu_mcp's DCR accepts only https or loopback redirect URIs.

## Sign-in flow

1. Client discovers the AS from the 401 `WWW-Authenticate: Bearer resource_metadata=…`,
   registers itself (DCR; or CIMD), opens `/oauth/authorize` (PKCE S256 only).
2. Signed out → `/sign-in?return_to=/oauth/authorize?login_state=…` → GitHub /
   Google → `/auth/sso-callback` → back to authorize. `return_to` is validated
   same-origin on every hop (`AnnotateWeb.ReturnTo`).
3. The upstream identity is the **dashboard session** (`Annotate.MCP.Bridge`):
   only an active, non-deleted user through the invite gate
   (`Dashboard.Access.allowed?/1`) becomes a subject; a gated account gets an
   error page, never consent.
4. **Consent** (`AnnotateWeb.MCP.Consent`) for every dynamically registered
   client: `comments:read` pre-checked and required; `comments:write` and
   `comments:moderate` unchecked, opt-in. The grant, its tokens and the
   recorded consent carry only what was ticked
   (`AnnotateWeb.MCP.OAuthPlug.narrow_consent/2`).
5. Code → token: access token ≤ 15 min, HS256 with the MCP-only key
   `ANNOTATE_MCP_SIGNING_SECRET`, `aud` = `…/mcp`; rotating refresh tokens
   with family revocation on replay.

## Scopes

| Scope | Grants | Tools |
|---|---|---|
| `comments:read` | always | `list_sites`, `get_site_config`, `list_threads`, `get_thread`, resources, prompts |
| `comments:write` | opt-in | `reply_to_thread`, `resolve_thread`, `reopen_thread` |
| `comments:moderate` | opt-in | `delete_comment` |

A `tools/call` of a tool whose scope was not granted is answered **HTTP 403**
`WWW-Authenticate: Bearer error="insufficient_scope", scope="…"` (step-up): the
client can send the user back through consent to grant more. Tools re-check
the scope themselves as well.

## Tools

All take a site **slug** (never a site id); thread/comment tools also accept
a bare id and resolve its site, then authorize it.

| Tool | Notes |
|---|---|
| `list_sites` | member sites, your role, open/resolved counts |
| `get_site_config` | allowed origins + read/comment policy; never keys |
| `list_threads` | `status` (open/resolved/all), `page_path` (exact or `prefix*`), `origin`, `since` (ISO-8601), `text`, `author`, `orphaned`, `cursor`, `limit` ≤ 100 |
| `get_thread` | live comments, anchor, page context, attachments (download URLs valid 5 min) |
| `reply_to_thread` | posts as the **site team** (dashboard parity, realtime) |
| `resolve_thread` / `reopen_thread` | member+, audited |
| `delete_comment` | soft delete, `destructiveHint`; own team replies, or anyone's for admin/owner |

Resources: `annotate://sites`, `annotate://site/{slug}/threads`,
`annotate://site/{slug}/threads/{status}`, `annotate://thread/{id}`.
Prompts: `triage_open_threads(site)`, `investigate_thread(thread_id)`.

### Untrusted content

Comment bodies, author names, page titles, anchors, URLs and site names are
written by visitors or other users. They are returned **only** under an
`untrusted` key; tool descriptions and the server `instructions` tell the
agent to treat them as data. `deep_link` is present only when the thread URL's
origin is one of the site's `allowed_origins` (the stored URL is otherwise
unvalidated). Nothing auto-resolves.

## Authorization (every call)

`Annotate.MCP.Authz`: claims of *this* request → scope → rate limit →
user re-read (active, invite gate) → site by slug → `SiteMembers.member_role/2`
from the DB. Non-member, missing site, unknown/malformed id and site mismatch
are the same `not_found`. A removed member, demoted admin or gated account
loses access on the next call — same token, same MCP session.

`Annotate.MCP.Verifier` (every HTTP request): JWT signature/alg/iss/aud/exp,
`jti` not revoked, and the `(user, client)` consent still present — revoking
in `/dashboard/agents` kills a live access token on its next request and
revokes its refresh tokens.

## Audit and limits

`mcp_audit_events` (Liquibase `037`, `annotate-0055`): every write (`ok` /
`error`) and every denial (`denied` + reason) with user, client_id, site,
tool, SHA-256 of the canonical arguments, ip. Never comment bodies. Reads are
not logged.

Rate limits (Hammer, per `(user, client_id)`): 120 reads/min, 30 writes/min.
OAuth endpoints per IP: register 20/h, authorize/consent 30/min, token 60/min.

## Operations

- Tables: `mcp_oauth_{clients,login_states,authorization_codes,refresh_tokens,consents,access_tokens}`
  (`annotate-0049..0054`, library template), purged every 15 min by
  `Annotate.Workers.MCPOAuthPurge`.
- Sessions are node-local (one replica, `strategy: Recreate`); a deploy drops
  them and clients re-initialize.
- `/mcp` has its own Ingress (no proxy buffering, 3600 s timeouts).
- Secret: Infisical `/apps/annotate` `ANNOTATE_MCP_SIGNING_SECRET` (dc
  `services apps.annotate_mcp_signing_secret`); prod refuses to boot without
  it (≥ 32 bytes). Rotating it invalidates every MCP access token (refresh
  tokens keep working).

Live checks:

```bash
curl -si https://annotate.therobotlives.com/.well-known/oauth-protected-resource/mcp   # resource == …/mcp
curl -si -X POST https://annotate.therobotlives.com/mcp                               # 401 + WWW-Authenticate
curl -s  https://annotate.therobotlives.com/.well-known/oauth-authorization-server | jq \
  '{code_challenge_methods_supported, token_endpoint_auth_methods_supported, client_id_metadata_document_supported, registration_endpoint}'
```

Threat model: T-30..T-35 in `THREAT-MODEL.md`. Not yet: personal access
tokens (PAT → short-lived `/mcp` token exchange, planned phase 5).
