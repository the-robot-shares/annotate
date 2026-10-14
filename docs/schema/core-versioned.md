# Schema — Core & Versioned Entities

Infrastructure and versioned profile records. Soft-deletable via `deleted_at`.

## seed_helper_records

Tracks idempotent seed execution by key + content hash.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| id | UUID | No | — | Primary key |
| key | VARCHAR(255) | No | — | Unique seed identifier |
| hash | VARCHAR(255) | Yes | — | Content hash for change detection |
| inserted_at | TIMESTAMP | Yes | — | Created timestamp |
| updated_at | TIMESTAMP | Yes | — | Modified timestamp |

**Constraints**: UNIQUE(key)

## versioned_strings

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| content | TEXT | Yes | — |
| deleted_at | TIMESTAMPTZ | Yes | — |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

## versioned_names

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| first | VARCHAR(255) | Yes | — |
| middle | TEXT[] | Yes | '{}' |
| last | VARCHAR(255) | Yes | — |
| deleted_at | TIMESTAMPTZ | Yes | — |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

## versioned_descriptions

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | UUID | No | gen_random_uuid() |
| title | VARCHAR(255) | Yes | — |
| body | TEXT | Yes | — |
| deleted_at | TIMESTAMPTZ | Yes | — |
| inserted_at | TIMESTAMPTZ | No | now() |
| updated_at | TIMESTAMPTZ | No | now() |

**Referenced by**: users.name_id → versioned_names, users.description_id → versioned_descriptions, user_credentials.description_id, user_media.description_id (all nullable).
