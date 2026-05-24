# Cards migration scripts

## migrate-to-canonical.ts

One-time migration of Cards Supabase data → eq-canonical (Cards Unit 3).

See `eq-context/eq/cards/canonical-migration/plan.md` §Unit 3 for context.

### Prerequisites

- Node.js + `pnpm tsx` available
- Service-role keys for **both** Supabases (Cards source + canonical destination)
- The canonical tenant UUID for the tenant receiving the migrated data

### Steps

1. Copy `.env.example` → `.env` and fill in the four required env vars (see below)
2. Dry-run first:
   ```
   pnpm tsx scripts/migrate-to-canonical.ts --tenant-id <canonical_tenant_uuid> --dry-run
   ```
3. Inspect the output. Confirm row counts match what you expect.
4. Live apply:
   ```
   pnpm tsx scripts/migrate-to-canonical.ts --tenant-id <canonical_tenant_uuid> --apply
   ```
5. Verify on canonical:
   ```sql
   select count(*) from app_data.staff where imported_from = 'eq_cards_supabase_2026_05_20';
   select count(*) from app_data.licences where imported_from = 'eq_cards_supabase_2026_05_20';
   ```
6. If anything looks wrong, roll back with the `eq_intake_rollback` intake IDs printed at end of script.
7. Set Cards Supabase to read-only via Supabase Dashboard (RLS policy or just lock the project).

### Required env vars

| Var | Source |
|---|---|
| `CARDS_SUPABASE_URL` | Legacy Cards project URL (`https://hshvnjzczdytfiklhojz.supabase.co`) — project decommissioned 2026-05-24; script is historical |
| `CARDS_SUPABASE_SERVICE_KEY` | Cards project service-role key (Dashboard → API → service_role) |
| `CANONICAL_SUPABASE_URL` | Canonical project URL (`https://jvknxcmbtrfnxfrwfimn.supabase.co`) |
| `CANONICAL_SUPABASE_SERVICE_KEY` | Canonical project service-role key |

### Safety properties

- **Dry-run is default.** Must explicitly pass `--apply` to write anything.
- **Idempotent.** `imported_from = 'eq_cards_supabase_2026_05_20'` is the dedup key. Re-running for already-migrated rows is a no-op (intake's commit path handles dedup).
- **Per-intake rollback.** Two intake events created (staff + licences). Either can be rolled back via `eq_intake_rollback(intake_id, reason)`.
- **Photos: best-effort.** Photo migration failures don't block the migration. Re-run to retry failures.
- **No source mutation.** Cards Supabase is read-only from this script's perspective. Service-role key is needed only for reading.
