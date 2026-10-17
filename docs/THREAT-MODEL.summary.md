# Threat Model Summary — annotate.therobotlives.com

Embeddable multi-tenant comments service: REST `/api/v1`, popup auth broker `/embed/*`, host-assert, websocket `/socket/annotate`, MinIO presigned attachments, and the invite-only owner dashboard (GitHub or Google sign-in) (sites, members, inbox). Code-read review of `develop` @ `2b5819d` (2026-10-17); no dynamic testing. Crown jewels: `ANNOTATE_JWT_SECRET`, `ANNOTATE_KEY_ENC_SECRET`, per-site service keys, refresh tokens.

| ID | Sev | Finding | Status |
|----|-----|---------|--------|
| T-01 | High | Refresh token not origin-bound; new token's `origin` copied from request header, no allowlist check | Fixed 2026-10-17 |
| T-02 | Med | No refresh reuse detection; rotate not atomic | Partial |
| T-03 | High | Rate limit trusts first `X-Forwarded-For`; per-pod ETS | Fixed 2026-10-17 (spoofing); per-pod ETS remains |
| T-04 | Med | Upload size/type unverified at storage; `complete` never checks object | Open |
| T-05 | Med | One global JWT secret for all tenants, no `kid` | Partial |
| T-06 | Med | Resolve/reopen/re-anchor lack authorship check; default policy admits any Authentik user | Open |
| T-07 | Low | `display_name` in inline script on `/embed/callback` not `</script>`-safe | Open |
| T-08 | Low | Sweeper leaves orphan objects; no quotas | Open |
| T-09 | Med | Websocket outlives 15-min token | Open |
| T-10 | Med | Host-assert JWT replayable up to 5 min (no `jti`) | Open |
| T-11 | Low | Guest names spoofable / share rows | Partial |
| T-12 | Info | Per-site exact-match CORS works | Mitigated |
| T-13 | Med | Stored XSS safety depends on widget renderer (outside repo) | Unknown |
| T-14 | Info | Popup postMessage targets registered origin | Mitigated |
| T-15 | High | Host-assert could set `email_verified` and bridge into a team role | Fixed 2026-10-17 |
| T-16 | High | Unverified accounts / GitHub unverified primary email could inherit memberships | Fixed 2026-10-17 |
| T-17 | Med | `trust_host_roles` lets service-key holders mint team roles | Mitigated (opt-in, owner-only) |
| T-18 | Med | Stale `team_role` claim after membership change | Mitigated (per-request DB re-check) |
| T-19 | Med | Dashboard role escalation / cross-tenant via commands | Mitigated |
| T-20 | Med | Dashboard origin edits weaken exact-match CORS | Mitigated |
| T-21 | Low | Show-once service key in command response / logs | Partial / Unknown |
| T-22 | Low | Self-serve site creation abuse; commands not rate-limited | Partial |
| T-23 | Info | Untrusted strings in Hologram hydration state | Mitigated (inbox) |
| T-24 | Med | OAuth login CSRF / cookie scope | Mitigated |
| T-25 | High | staff_only read visibility on every path incl. realtime | Mitigated (residual: host-asserted staff = host trust) |
| T-26 | Low | `/me` permission endpoint (no PII, live) | Mitigated |
| T-27 | Med | Self-serve dashboard sign-up | Fixed 2026-10-17 (invite-only; exact verified @noizu.com exempt) |
| T-28 | Med | Invite token theft/guessing/replay | Mitigated (256-bit, bcrypt at rest, single-use, expiry, revoke, email bind, atomic) |
| T-29 | Low | GitHub+Google account linking | Mitigated (verified-email exact match only) |
| T-30 | High | MCP cross-tenant / stale membership | Mitigated (per-call DB re-authorization; uniform not_found) |
| T-31 | Med | Unvalidated thread URL deep links | Mitigated for dashboard + MCP (allowed-origin check); embed renderer residual |
| T-32 | High | Prompt injection via comment text | Mitigated by design (`untrusted` fields, opt-in write scopes, audit); inherent residual |
| T-33 | High | MCP OAuth AS (confused deputy, redirects, replay, consent CSRF) | Mitigated (noizu_mcp AS, mandatory subset consent, same-origin return_to) |
| T-34 | Med | MCP token lifetime / revocation | Mitigated (MCP-only key, per-request jti + consent check) |
| T-35 | Low | MCP abuse / audit trail | Mitigated (rate limits, `mcp_audit_events`, purge) |

Full doc: [THREAT-MODEL.md](THREAT-MODEL.md).
