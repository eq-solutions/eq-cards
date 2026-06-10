-- 0024_hussain_dedup.sql
-- Nabeel Hussain and Mohammed Hussain are the same person (same phone 0474284352).
-- Mohammed's invite (worker_id=10dc5bd0, expires 2026-06-15) is the active one.
-- Keep it; rename the worker record and invite profile_data to "Nabeel Hussain".
-- Expire the orphan Nabeel invite (no worker_id, already expired 2026-06-06).

-- 1. Rename the worker record
UPDATE public.workers
SET    first_name = 'Nabeel',
       last_name  = 'Hussain',
       updated_at = now()
WHERE  id = '10dc5bd0-e16b-4d44-8ec3-a4d0eeae9825'::uuid
  AND  first_name = 'Mohammed';

-- 2. Update the active invite's profile_data to match
UPDATE public.worker_invites
SET    profile_data = profile_data
         || '{"first_name":"Nabeel","last_name":"Hussain","full_name":"Nabeel Hussain"}'::jsonb
WHERE  id = '76da709b-3571-4f9b-bdcd-3959d28c4287'::uuid;

-- 3. Mark the expired orphan Nabeel invite as superseded (set expires_at to now
--    so it's unambiguously dead; it was already past expiry so this is cosmetic).
UPDATE public.worker_invites
SET    expires_at = now()
WHERE  id = 'c5eb52d3-2636-4cc2-a07e-d1ecd73f51c3'::uuid;
