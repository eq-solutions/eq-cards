-- 0063_onboarding_dedup_cleanup.sql
--
-- ONE-TIME, reversible cleanup of the duplicate worker orphans that the
-- pre-0062 approval path created. An "orphan" here is a `user_id IS NULL`
-- worker whose normalised phone matches a sibling that DOES have a login —
-- the login sibling is the canonical record we keep, so a whole person can
-- never be removed.
--
-- Verified live 2026-06-30: 7 such orphans, ALL empty (0 credentials /
-- assignments / inductions / agent-tokens); 1 dead worker_invite hangs off
-- one of them. `public.workers` has no soft-delete column, so each removed
-- row is copied into a durable archive table first → fully reversible.
--
-- SELF-VERIFYING: aborts (rolls back) if the data has drifted since the audit
-- — wrong orphan count, or any value-bearing row attached — so it can never
-- silently delete a real record.
--
-- NOTE (cross-plane): one ehow straggler remains — Yura Konakov's canonical
-- staff row `b41c73d4…` (app_data.staff) is still active=true with no login /
-- 0 licences. That archive is a coordinated one-liner on ehow (eq-shell /
-- canonical owner): `UPDATE app_data.staff SET active=false WHERE staff_id=…`.
-- It is NOT done here because app_data.staff lives on a different project.

-- 1. Identify orphans — only where a login sibling exists to keep.
CREATE TEMP TABLE _dedup_orphans ON COMMIT DROP AS
WITH norm AS (
  SELECT id, user_id,
    regexp_replace(regexp_replace(coalesce(phone,''), '\s', '', 'g'), '^(\+61|61|0)', '') AS np
  FROM public.workers
),
grp AS (
  SELECT np,
         count(*)                               AS total,
         count(*) FILTER (WHERE user_id IS NOT NULL) AS logins
  FROM norm
  WHERE np <> ''
  GROUP BY np
)
SELECT n.id
FROM norm n
JOIN grp g ON g.np = n.np
WHERE n.user_id IS NULL
  AND g.total  > 1
  AND g.logins >= 1;

-- 2. Safety gate — refuse to run if reality has moved since the audit.
DO $$
DECLARE n_orphans int; n_value int;
BEGIN
  SELECT count(*) INTO n_orphans FROM _dedup_orphans;

  SELECT (SELECT count(*) FROM public.worker_credentials   WHERE worker_id IN (SELECT id FROM _dedup_orphans))
       + (SELECT count(*) FROM public.worker_assignments   WHERE worker_id IN (SELECT id FROM _dedup_orphans))
       + (SELECT count(*) FROM public.worker_inductions    WHERE worker_id IN (SELECT id FROM _dedup_orphans))
       + (SELECT count(*) FROM public.revoked_agent_tokens WHERE worker_id IN (SELECT id FROM _dedup_orphans))
    INTO n_value;

  IF n_orphans <> 7 THEN
    RAISE EXCEPTION 'dedup cleanup aborted: expected 7 orphans, found % — re-run the audit first', n_orphans;
  END IF;
  IF n_value <> 0 THEN
    RAISE EXCEPTION 'dedup cleanup aborted: % value-bearing row(s) attached to orphans — would lose data', n_value;
  END IF;
END $$;

-- 3. Durable archive (rollback source).
CREATE TABLE IF NOT EXISTS public.worker_dedup_archive_20260630 (
  archived_at timestamptz NOT NULL DEFAULT now(),
  reason      text        NOT NULL,
  row_data    jsonb       NOT NULL
);

-- 4. Archive + remove the dead invite(s) on orphans.
INSERT INTO public.worker_dedup_archive_20260630 (reason, row_data)
SELECT 'worker_invite_on_orphan', to_jsonb(wi)
FROM public.worker_invites wi
WHERE wi.worker_id IN (SELECT id FROM _dedup_orphans);

DELETE FROM public.worker_invites
WHERE worker_id IN (SELECT id FROM _dedup_orphans);

-- 5. Archive + remove the orphan workers.
INSERT INTO public.worker_dedup_archive_20260630 (reason, row_data)
SELECT 'worker_orphan', to_jsonb(w)
FROM public.workers w
WHERE w.id IN (SELECT id FROM _dedup_orphans);

DELETE FROM public.workers
WHERE id IN (SELECT id FROM _dedup_orphans);

-- ROLLBACK (manual): re-INSERT from public.worker_dedup_archive_20260630 —
-- 'worker_orphan' rows back into public.workers, 'worker_invite_on_orphan'
-- rows back into public.worker_invites (row_data is the full original row).
