# Data Retention & PII-Access Audit Logging — Spec

**Status:** Spec for build (2026-06-26). Not yet implemented.
**Why:** The Privacy Policy makes retention/deletion promises the system does not currently keep
(APP 11.2), and PII *access* is not logged (APP 1.2 accountability + breach investigation).
**Scope:** eq-canonical (`jvknxcmbtrfnxfrwfimn`). Pairs with the [NDB runbook](notifiable-data-breach-runbook.md).

---

## Part A — Data retention / destruction

### A.1 What the policy promises (Privacy Policy §8 / §9)

| Promise | Current reality | Gap |
|---|---|---|
| Soft-deleted licences permanently deleted **30 days** after deletion | `licences.deleted_at` is set; nothing ever purges them. Rows + storage objects persist forever. | **No purge job** |
| Account on request to delete → **hard-deleted within 30 days** | `eq_cards_delete_account` (migration 0014) soft-deletes/anonymises only; hard-delete of `auth.users` is a manual "Sprint K" step | **Not automated** |
| Licence photos kept "while the licence exists … plus 30 days" | Storage objects are never removed when a licence is deleted | **Orphaned objects accumulate** |

There is no `pg_cron` purge in the repo (grep: none) — the only scheduled job is eq-shell's
licence-expiry-scheduler.

### A.2 Proposed implementation

Two viable hosts — pick one and be consistent:

- **Option 1 (recommended): eq-shell Netlify scheduled function**, mirroring
  `netlify/functions/licence-expiry-scheduler.ts` (service-role client, daily cron). Keeps all
  scheduled jobs in one place; can delete both DB rows and storage objects via the Storage API.
- **Option 2: `pg_cron` in eq-canonical** — DB-native, but cannot delete storage objects directly
  (would need an edge-function call or a storage-purge companion).

**Daily `retention-purge` job should:**

1. **Hard-delete soft-deleted licences > 30 days:**
   ```sql
   delete from public.licences
   where deleted_at is not null
     and deleted_at < now() - interval '30 days';
   ```
   …after first collecting their `photo` storage paths and removing those objects from the
   `licence-photos` bucket (and any `certificates`/`worker_credentials` photo paths similarly).

2. **Finalise account deletions > 30 days:** for accounts soft-deleted/anonymised by
   `eq_cards_delete_account`, hard-delete the `auth.users` row (and cascade) via the Auth admin API,
   plus remove their storage objects. Gate behind an explicit `deletion_requested_at` marker so only
   genuinely requested deletions are finalised.

3. **Sweep orphaned storage objects:** licence-photo/certificate objects with no matching live row
   (e.g. the known orphan `7dee117c/…/1244f14a-…`). List bucket → left-join to live rows → delete misses
   older than a grace window.

4. **Log每 run** to `audit_log` (see Part B): counts purged, by type.

**Acceptance:** after a licence is deleted and 30 days pass, neither the row nor its storage
objects exist; a deleted account leaves no `auth.users` row or storage objects after 30 days.

### A.3 If not built before go-live
Soften Privacy Policy §8/§9 to describe what actually happens (manual deletion on request),
so the policy is not making commitments the system can't keep (ACL misleading-conduct risk).

---

## Part B — PII-access audit logging

### B.1 Current state
`audit_log` (migration 0001) is populated by triggers on **INSERT/UPDATE/DELETE** of `profiles`,
`licences`, and `org_memberships` — i.e. **writes only**. There is no record of who **read,
viewed, exported, or shared** a worker's data. For WWCC/police-check-class data this is the gap
that bites hardest during a breach investigation: you can't answer "whose data was accessed, by whom?"

### B.2 What to log (access events)

| Event | Where to emit | Actor | Subject |
|---|---|---|---|
| Admin views a worker's HR record | `eq_cards_get_worker_hr_record` RPC | `auth.uid()` (admin) | worker user_id |
| Admin views/reads a member's licence photo | storage read path / admin screen | admin | worker user_id |
| Worker exports their data | `Settings → Export my data` (client → RPC) | self | self |
| Public share-link access | `share-licence` edge function | anon (IP) | licence/holder |
| Compliance-pack / wallet-pass export | export path | actor | worker |
| Retention purge run | `retention-purge` job | system | counts |

### B.3 Proposed shape

Either extend `audit_log` with an `action` taxonomy that includes read/export/share verbs, or add a
dedicated append-only table:

```sql
create table if not exists public.pii_access_log (
  id            bigint generated always as identity primary key,
  occurred_at   timestamptz not null default now(),
  actor_user_id uuid,                 -- null for anon (share links)
  actor_ip      inet,                 -- for share-licence / anon access
  action        text not null,        -- 'view_hr_record' | 'export_self' | 'share_access' | ...
  subject_user_id uuid,               -- whose PII
  object_ref    text,                 -- e.g. licence_id, storage path, request_id
  detail        jsonb
);
-- Append-only: grant INSERT to the relevant roles, no UPDATE/DELETE to anon/authenticated.
-- RLS: readable only by service_role / platform admin.
```

- **`share-licence`** (edge fn): insert a `share_access` row on every successful fetch
  (licence_id, requester IP, timestamp) — this also gives the C3 share endpoint the accountability
  trail it currently lacks.
- **Admin HR-record reads**: emit `view_hr_record` inside the SECURITY DEFINER RPC so it can't be bypassed.
- **Data export**: emit `export_self` when the export RPC runs.

### B.4 Retention of the log itself
Keep access logs at least 12 months (breach-investigation horizon), then prune. Don't let the
access log itself become an unbounded PII store — store references (IDs/paths), not copied PII.

---

## Build order (suggested)
1. `share-licence` access logging (smallest, closes the C3 accountability gap).
2. `retention-purge` daily job (Part A) — the policy is actively over-promising today.
3. Admin-read + export logging (Part B) — accountability for sensitive-doc access.
