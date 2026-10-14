# Schema — Organizations & PBAC

Organizations plus the policy-based access control (PBAC) family (changesets 013–021): groups, group hierarchy, scoped memberships, JSONB policies, custom org roles, and the stored-procedure permission engine.

## organizations

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| slug | CITEXT | No | — |
| name | VARCHAR(255) | No | — |
| settings | JSONB | Yes | '{}' |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

**Constraints**: UNIQUE(slug)

## memberships (legacy)

Original flat role table. Changeset 021 migrated its rows into `scoped_memberships` and renamed the table to `memberships_legacy` (kept for rollback safety). Do not write to it; `Annotate.Schema.Organizations.Membership` retains a read-side schema.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| organization_id | UUID | No | FK organizations |
| user_id | UUID | No | FK users |
| role | VARCHAR(50) | No | 'viewer' |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

## groups

System role-template groups; `groups.name` is the `role_name_enum` (owner/admin/member/viewer). `updated_at` maintained by trigger.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| name | role_name_enum | No | UNIQUE |
| display_name | VARCHAR(200) | No | — |
| description | TEXT | Yes | — |
| is_system | BOOLEAN | No | true |
| created_at | TIMESTAMPTZ | Yes | now() |
| updated_at | TIMESTAMPTZ | Yes | now() |

**Triggers**: update_groups_updated_at (BEFORE UPDATE); add_group_self_hierarchy (AFTER INSERT)

## group_hierarchy

Transitive-closure table for group nesting (depth ≤ 10). Self-row (depth 0) inserted by trigger.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ancestor_id | UUID | No | FK groups, ON DELETE CASCADE |
| descendant_id | UUID | No | FK groups, ON DELETE CASCADE |
| depth | INTEGER | No | CHECK (0..10) |

**Constraints**: PK (ancestor_id, descendant_id)
**Indexes**: idx_group_hierarchy_ancestor, idx_group_hierarchy_descendant

## scoped_memberships

Grants a member (user or group) a group on a resource (organization or project). Expiring grants supported.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| group_id | UUID | No | FK groups, ON DELETE CASCADE |
| resource_type | resource_type_enum | No | — |
| resource_id | UUID | No | — |
| member_type | member_type_enum | No | — |
| member_id | UUID | No | — |
| expires_at | TIMESTAMPTZ | Yes | — |
| added_by | UUID | Yes | FK users, ON DELETE SET NULL |
| created_at | TIMESTAMPTZ | No | now() |

**Constraints**: uq_scoped_memberships_resource_member (resource_type, resource_id, member_type, member_id)
**Indexes**: idx_scoped_memberships_resource_covering (covering), idx_scoped_memberships_user_resource (partial, member_type='user'), idx_scoped_memberships_expires_at, idx_scoped_memberships_group_id
**Trigger**: cascade_org_removal — deleting a user's org membership also deletes their project-level memberships under that org

## policies

JSONB policy documents (AWS-IAM-style statements: effect/actions/resources with `*`, `type:*`, `*`, and `${resource_type}`/`${resource_id}` templates). GIN-indexed. `updated_at` maintained by trigger.

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| name | VARCHAR(100) | No | UNIQUE |
| description | TEXT | Yes | — |
| policy_document | JSONB | No | — |
| is_system | BOOLEAN | No | false |
| is_active | BOOLEAN | No | true |
| created_by | UUID | Yes | FK users, ON DELETE SET NULL |
| created_at | TIMESTAMPTZ | Yes | now() |
| updated_at | TIMESTAMPTZ | Yes | now() |

**Indexes**: idx_policies_name_active (partial, is_active), idx_policies_document_gin (GIN)

## group_policies / user_policies

Policy attachments. group_policies: UNIQUE(group_id, policy_id), covering index on group_id. user_policies: UNIQUE(user_id, policy_id, resource_type, resource_id) — nullable resource columns allow platform-wide direct grants; covering index on (user_id, resource_type, resource_id).

Common columns: id UUID PK, created_at TIMESTAMPTZ DEFAULT now(); group_policies adds group_id FK, policy_id FK, priority INTEGER DEFAULT 0; user_policies adds user_id FK, policy_id FK, resource_type resource_type_enum, resource_id UUID, priority.

## custom_roles / custom_role_permissions

Per-organization custom roles (018).

custom_roles: id UUID PK, organization_id UUID NOT NULL FK (CASCADE), name VARCHAR(100) NOT NULL, display_name VARCHAR(200) NOT NULL, description TEXT, is_active BOOLEAN DEFAULT true, inserted_at/updated_at TIMESTAMPTZ NOT NULL. UNIQUE(organization_id, name).

custom_role_permissions: id UUID PK, role_id UUID NOT NULL FK custom_roles (CASCADE), permission VARCHAR(200) NOT NULL, inserted_at/updated_at. UNIQUE(role_id, permission).

## Stored procedures (019)

Permission evaluation runs in-database via PL/pgSQL functions:

| Function | Purpose |
|----------|---------|
| `check_user_permission(user, resource_type, resource_id, action)` | Evaluates policies from user+group scoped memberships (deny-overrides-allow, wildcard action/resource matching, expiry-aware) → BOOLEAN |
| `add_scoped_member` | Validated membership insertion |
| `update_scoped_member_role` | Swap a member's group on a resource |
| `remove_scoped_member_safe` | Removal with org→project cascade semantics |
| `get_user_role_in_resource` | Resolve a user's effective role/group |
| `list_user_accessible_projects` | Projects a user can see |

## Seed data (020)

- **Groups**: fixed UUID5 system groups — owner, admin, member, viewer (`is_system = true`, ON CONFLICT DO NOTHING).
- **Policies**: system policies incl. `system:super-admin` (`*`/`*` allow) and `system:owner` (`${resource_type}:${resource_id}` + `/*` allow) — attached via group_policies to the seeded groups.
