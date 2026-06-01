-- 0012_workers_email_nullable.sql
--
-- Training matrix entries have no email — admin creates profiles first,
-- workers fill in their own contact details after claiming their account.

ALTER TABLE public.workers ALTER COLUMN email DROP NOT NULL;
