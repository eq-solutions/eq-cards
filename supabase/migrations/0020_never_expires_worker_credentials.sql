-- Sprint 1: Add never_expires flag to worker_credentials.
-- When true, the credential is treated as permanently valid regardless of
-- any expiryDate value that may be stored.
ALTER TABLE public.worker_credentials
  ADD COLUMN IF NOT EXISTS never_expires boolean NOT NULL DEFAULT false;
