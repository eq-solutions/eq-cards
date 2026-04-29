# EQ Cards — Database Schema

**Status:** Phase 0.5 contract
**Owner:** Royce Milmlow
**Last updated:** 2026-04-27

This document defines the Supabase schema for EQ Cards v1. Every column, type, index, and RLS predicate listed here is locked. Schema changes require an explicit migration file AND a doc update in the same PR.

Migration files live in `supabase/migrations/`:
- `0001_initial_schema.sql` — tables, indexes, RLS policies, triggers
- `0002_seed_licence_types.sql` — pre-seeded `licence_types` for common Aus tradie licences
- `0003_storage_setup.sql` — `licence-photos` bucket + 4 RLS policies on `storage.objects`

---

## Tables

### 1. `profiles`

One row per authenticated user. Created on first profile-edit submit (not on signup), so unfinished users don't pollute the table.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK, FK → `auth.users(id)` ON DELETE CASCADE |
| `full_name` | text | Required for inductions |
| `date_of_birth` | date | Required for inductions |
| `mobile` | text | E.164 format, e.g. `+61412345678` |
| `email` | text | |
| `address_street` | text | |
| `address_suburb` | text | |
| `address_state` | text | NSW, VIC, QLD, etc. |
| `address_postcode` | text | |
| `emergency_contact_name` | text | |
| `emergency_contact_relationship` | text | |
| `emergency_contact_mobile` | text | E.164 |
| `created_at` | timestamptz | default `now()` |
| `updated_at` | timestamptz | default `now()`, updated by trigger |
| `deleted_at` | timestamptz | nullable, soft-delete marker |

**Indexes:** PK on `id` only. Single-row-per-user means lookups are by id.

**RLS:** users `SELECT` / `INSERT` / `UPDATE` only where `id = auth.uid()`. No `DELETE` policy — soft-delete via `deleted_at`.

---

### 2. `licence_types`

Reference table. Pre-seeded with common Australian tradie licences. Users can extend with custom types (`is_custom = true`, scoped by `user_id`).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK, default `gen_random_uuid()` |
| `code` | text | Unique slug, e.g. `white_card`, `driver_licence` |
| `label` | text | Display name, e.g. "White Card (Construction Induction)" |
| `requires_state` | boolean | True for state-specific (driver licence, electrical) |
| `default_validity_months` | int | Suggested auto-fill for expiry, e.g. 36 for First Aid |
| `is_custom` | boolean | False for seeded, true for user-added |
| `user_id` | uuid | NULL for seeded; FK → `auth.users(id)` for custom |
| `created_at` | timestamptz | default `now()` |

**Constraints:** `is_custom = false` ⇒ `user_id IS NULL`; `is_custom = true` ⇒ `user_id IS NOT NULL`.

**Indexes:**
- PK on `id`
- Unique on `code` where `is_custom = false` (seeded codes are global identifiers)
- Index on `user_id` where `is_custom = true`

**RLS:** anyone reads where `is_custom = false OR user_id = auth.uid()`. `INSERT` / `UPDATE` only own custom rows.

**Seed data:** see `0002_seed_licence_types.sql`.

---

### 3. `licences`

The user's actual licence records. One row per physical card.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK, default `gen_random_uuid()` |
| `user_id` | uuid | FK → `auth.users(id)` ON DELETE CASCADE |
| `licence_type` | text | References `licence_types.code` (logical FK; not enforced because custom types are user-scoped) |
| `licence_number` | text | The number printed on the card |
| `issue_date` | date | |
| `expiry_date` | date | Drives expiry alerts |
| `issuing_authority` | text | nullable, e.g. "Service NSW", "RTO 12345" |
| `state` | text | nullable; required when `licence_types.requires_state = true` |
| `photo_front_url` | text | Supabase Storage path; signed URL on read |
| `photo_back_url` | text | nullable |
| `notes` | text | nullable, free text |
| `metadata` | jsonb | Type-specific extras: Medicare IRN, driver class, forklift class (LF/LO/LR), HRWL ticket number. Default `'{}'::jsonb`. |
| `created_at` | timestamptz | default `now()` |
| `updated_at` | timestamptz | default `now()`, updated by trigger |
| `deleted_at` | timestamptz | nullable, soft-delete marker |

**Why `metadata jsonb`:** added in Phase 0.5 so Medicare cards live in this table (Medicare IRN goes in metadata) without bloating the schema with type-specific columns. Driver licence class, forklift class (LF/LO/LR), HRWL ticket numbers, etc. all use the same pattern.

**Conventions for `metadata` keys:**
- Medicare: `{"irn": "1"}`
- Driver licence: `{"class": "C"}`
- Forklift HRWL: `{"class": "LF", "ticket_number": "..."}`

Document new keys here before shipping a licence type that uses them.

**Indexes:**
- PK on `id`
- `(user_id, expiry_date)` for the list-by-expiry query in `LicenceRepository.getAllForCurrentUser()`
- `(user_id, licence_type)` for filtered views

**RLS:** users `SELECT` / `INSERT` / `UPDATE` only where `user_id = auth.uid()`. No `DELETE` policy — soft-delete via `deleted_at`.

---

### 4. `audit_log`

Immutable trail of mutations. Used for support diagnostics and security forensics. Read-only from clients.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK, default `gen_random_uuid()` |
| `user_id` | uuid | FK → `auth.users(id)` |
| `action` | text | e.g. `licence.created`, `profile.updated`, `licence.deleted` |
| `entity_type` | text | e.g. `licence`, `profile` |
| `entity_id` | uuid | nullable |
| `metadata` | jsonb | Action-specific context, default `'{}'::jsonb`. **Never** store PII or licence numbers here. |
| `created_at` | timestamptz | default `now()` |

**Write path:** populated by Postgres triggers (`SECURITY DEFINER`) on `licences` and `profiles`. Clients have no write access.

**Indexes:**
- PK on `id`
- `(user_id, created_at desc)` for "your recent activity" views

**RLS:** `SELECT` only where `user_id = auth.uid()`. No `INSERT` / `UPDATE` / `DELETE` policy for clients.

---

## Storage buckets

### `licence-photos` (private)

- One bucket for all licence and profile photos.
- Path pattern: `{user_id}/{licence_id}/front.jpg`, `.../back.jpg`.
- Access via signed URLs only, expiry 1 hour.
- Upload helper in `lib/core/utils/photo_upload.dart` strips EXIF + compresses before upload.

**Created via `0003_storage_setup.sql`** — the migration creates the bucket and applies the 4 RLS policies on `storage.objects` (SELECT / INSERT / UPDATE / DELETE) in one step.

**RLS predicate:**
```sql
bucket_id = 'licence-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
```

The first segment of the path must equal the authenticated user's id, which prevents lateral access.

---

## Triggers

### `set_updated_at` — generic

Applied to `profiles` and `licences`. Sets `updated_at = now()` on every UPDATE.

### `audit_log_*` — per table

Triggers on `INSERT` / `UPDATE` / `DELETE` of `profiles` and `licences`. Insert a row into `audit_log` with the action, entity_id, and a sanitized metadata payload (op type and licence_type only — no licence numbers, no PII).

---

## Out of scope for v1

Tables explicitly **not** in this schema:

- `tenants`, `memberships` — multi-org deferred (architecture §15)
- `shares` — QR-sharing tokens for single-licence public display (Phase 1.5)
- `share_destinations`, `share_grants`, `share_tokens` — **cross-module data sharing reserved per ARCHITECTURE.md §18** (independent products + share API + explicit user consent). Distinct from QR sharing above: this is app-to-app data import (e.g. EQ Field connecting to EQ Cards), not public link sharing. Phase 2+.
- Encrypted columns / vault for TFN, bank, super — deferred to v1.1 with vault UX
- `notifications` table — local notification scheduling lives client-side via `flutter_local_notifications`; no server-side schedule table in v1

---

**End of document.** Schema changes require an explicit migration file AND an update here in the same PR.
