-- Sprint 1: Add never_expires flag to licences (worker-entered wallet cards).
-- Mirrors the same column added to worker_credentials in 0020.
ALTER TABLE public.licences
  ADD COLUMN IF NOT EXISTS never_expires boolean NOT NULL DEFAULT false;
