-- 0033_revoke_sync_trigger_grants.sql
--
-- Defense-in-depth. public.sync_worker_to_canonical() and
-- public.sync_credential_to_canonical() are SECURITY DEFINER *trigger*
-- functions with `vault` in their search_path -- they read the
-- WORKERS_WEBHOOK_SECRET from vault.decrypted_secrets and POST to the
-- canonical-sync edge functions.
--
-- The default function grant left EXECUTE open to PUBLIC/anon/authenticated.
-- A direct client call cannot exfiltrate the secret (the secret is only held
-- in a local var and the function raises on its NEW/OLD reference before any
-- output), but a vault-reading definer function should never be directly
-- invokable by client roles. Trigger execution does NOT consult EXECUTE
-- grants, so the workers/worker_credentials sync triggers keep firing normally.
--
-- Reversible: re-GRANT EXECUTE ... TO authenticated if ever needed.

revoke all on function public.sync_worker_to_canonical()     from public, anon, authenticated;
revoke all on function public.sync_credential_to_canonical() from public, anon, authenticated;
