# Schema — Webhooks, Projects & Cookie Consent

## webhooks

Org-scoped outbound webhook endpoints (011). Delivery handled by `Starter.Events.WebhookHandler`.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| organization_id | UUID | Yes | FK organizations |
| url | VARCHAR(2048) | No | — |
| secret | VARCHAR(255) | Yes | — |
| events | TEXT[] | Yes | '{}' |
| active | BOOLEAN | Yes | true |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

**Indexes**: idx_webhooks_org_active (organization_id, active)

## projects

Org-scoped projects (017); also the second `resource_type` in the PBAC model.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | UUID | No | gen_random_uuid() | |
| organization_id | UUID | No | FK organizations, ON DELETE CASCADE | |
| name | VARCHAR(255) | No | — | |
| slug | CITEXT | No | — | UNIQUE per org |
| description | TEXT | Yes | — | |
| settings | JSONB | Yes | '{}' | |
| status | VARCHAR(20) | No | 'active' | CHECK ('active','archived','deleted') |
| created_by | UUID | Yes | FK users, ON DELETE SET NULL | |
| inserted_at | TIMESTAMPTZ | No | — | |
| updated_at | TIMESTAMPTZ | No | — | |
| archived_at | TIMESTAMPTZ | Yes | — | |

**Constraints**: uq_projects_org_slug (organization_id, slug)
**Indexes**: idx_projects_org_active_covering (organization_id, inserted_at DESC) WHERE status = 'active'

## cookie_consents

Cookie consent records per user or anonymous browser session (025). Mirrors `Starter.Schema.CookieConsent`; feature notes in `docs/COOKIE-CONSENT.md`.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | UUID | No | gen_random_uuid() | |
| user_id | UUID | Yes | FK users, ON DELETE CASCADE | |
| browser_session_id | UUID | Yes | — | anonymous sessions |
| version | INTEGER | No | — | consent policy version |
| categories | JSONB | No | '{}' | per-category choices |
| required_session_allowed | BOOLEAN | No | true | |
| accepted_at | TIMESTAMPTZ | Yes | — | |
| updated_choice_at | TIMESTAMPTZ | No | now() | |
| inserted_at | TIMESTAMPTZ | No | now() | |
| updated_at | TIMESTAMPTZ | No | now() | |

**Constraints**: cookie_consents_identity_check — CHECK (user_id IS NOT NULL OR browser_session_id IS NOT NULL)
**Indexes**: idx_cookie_consents_user_id (UNIQUE WHERE user_id IS NOT NULL), idx_cookie_consents_browser_session_id (UNIQUE WHERE user_id IS NULL AND browser_session_id IS NOT NULL)
