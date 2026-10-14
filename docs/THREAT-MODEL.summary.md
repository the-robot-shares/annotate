# Threat Model Summary — hologram-start-app

Two-container stack (Phoenix + Hologram backend, nginx proxy) behind k8s ingress TLS. Trust boundaries: internet→edge (TLS at ingress, nginx :80 internal), edge→backend (nginx adds no auth), backend→stores (credential-isolated Postgres/Redis on shared Docker network), cluster→sandbox (Samba/supervisord lane), process→third parties (Authentik OIDC, SMTP, webhook egress). Crown jewels: Postgres data, session/JWT/webhook signing secrets. Scaffold template — hydrated products must re-review.

## Register (10 entries: 5 mitigated · 4 partial · 1 open)

| ID | Sev | STRIDE | Component | Status |
|----|-----|--------|-----------|--------|
| T-001 | High | Spoofing | SSO domain trust + auto-approve | Mitigated (allowlist + pending approval default) |
| T-002 | High | Elevation | PBAC wildcard policies | Partial (deny-overrides; broad wildcard honored) |
| T-003 | Med | Spoofing | Auth brute force | Mitigated (Hammer rate limits) |
| T-004 | Med | Tampering | Webhooks unsigned when secret nil | Partial (HMAC when secret set) |
| T-005 | Med | DoS/Info | Unauthenticated /otel/ proxy | Open |
| T-006 | Med | Tampering | Media upload/transform | Partial |
| T-007 | High | Elevation | Sandbox Samba share | Mitigated (cluster-internal, SMB2, valid users) |
| T-008 | Low | Info | PII in JSON/OTel logs | Partial |
| T-009 | Med | DoS | Single backend, WS churn | Partial (HPA/PDB) |
| T-010 | Low | Tampering | tobor_kit_hologram path dep | Mitigated (monorepo-local) |

Session cross-cutting: signed SameSite=Lax SSO flow cookie, fails closed on state mismatch; Guardian JWT secrets from runtime/Infisical.

## Residual Risk

Shared Docker network isolation is credential-based (dev); /otel/ openness accepted for zero-config browser RUM; scaffold drift in hydrated products cannot be enforced by the template.
