-- Sweep identified orphan worker rows:
-- 1. John Angangan: orphan 89286549 (phone +61447444250, no data) vs live linked row
--    cba4aaad (phone +61439842416, email john.angangan@sks.com.au, user_id already set).
--    Different phones — the orphan was a batch-imported shell with his personal number;
--    the linked row is his live profile. Orphan has zero dependents, delete it.
DELETE FROM public.workers WHERE id = '89286549-eefc-438d-8215-ea22d42e0a57';

-- 2-4. Cicero, Zemi, Marcus: single orphan each with no competing linked row.
--      Proactively link them to their auth user so profile-save goes straight to UPDATE.
UPDATE public.workers
SET user_id = '93b24e16-058b-4d0f-a84a-81a7692f7e29', updated_at = now()
WHERE id = '33149c1a-810a-41be-a08a-a172a5c7261e' AND user_id IS NULL;

UPDATE public.workers
SET user_id = 'fb20ce14-eb6a-44c6-a072-4d64040a0875', updated_at = now()
WHERE id = '5e9d6e83-13ef-427f-abae-61393c6529e1' AND user_id IS NULL;

UPDATE public.workers
SET user_id = 'db4cf37c-28ca-4b47-97c5-e70eb4c7dd4a', updated_at = now()
WHERE id = 'dc0cca46-041d-410a-83b3-fdc11aca336b' AND user_id IS NULL;
