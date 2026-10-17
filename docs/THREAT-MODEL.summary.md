# Threat Model Summary — annotate.therobotlives.com

Embeddable multi-tenant comments service: REST `/api/v1`, popup auth broker `/embed/*`, host-assert, websocket `/socket/annotate`, MinIO presigned attachments. Code-read review of `develop` @ `2b5819d` (2026-10-17); no dynamic testing. Crown jewels: `ANNOTATE_JWT_SECRET`, `ANNOTATE_KEY_ENC_SECRET`, per-site service keys, refresh tokens.

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

Full doc: [THREAT-MODEL.md](THREAT-MODEL.md).
