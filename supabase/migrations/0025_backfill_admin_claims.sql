-- 0025_backfill_admin_claims.sql
-- Royce, Simon, and Luke are already active in shell_control but their
-- worker_invites rows have incomplete claim audit fields. Backfill so the
-- invite table reflects reality.

-- Royce Milmlow (shell_user_id = 85e30693, invite = 03c87e8b)
UPDATE public.worker_invites
SET    claimed_at = now(),
       claimed_by = '85e30693-b467-407a-88e8-539e345b88cd'::uuid
WHERE  id         = '03c87e8b-1840-4b44-997a-3d439b99f780'::uuid
  AND  claimed_at IS NULL;

-- Simon Bramall (shell_user_id = ac4244e3, invite = c2e4c3b3)
UPDATE public.worker_invites
SET    claimed_at = now(),
       claimed_by = 'ac4244e3-5196-4551-a57f-711d315b7a46'::uuid
WHERE  id         = 'c2e4c3b3-42cf-4029-8668-d720df8116f8'::uuid
  AND  claimed_at IS NULL;

-- Luke Wheeler — claimed_at already set 2026-06-09, claimed_by was NULL (bug in
-- the flow at the time). Backfill claimed_by only.
UPDATE public.worker_invites
SET    claimed_by = '155ac75c-bcd8-41c2-834c-cf119cce0ec0'::uuid
WHERE  id         = '1529c1d9-02d5-4ab5-9e0c-470675e73b39'::uuid
  AND  claimed_by IS NULL;
