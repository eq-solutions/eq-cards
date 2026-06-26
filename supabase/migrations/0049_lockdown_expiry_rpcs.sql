-- 0049 — Lock down expiry-notification RPCs to service_role only.
--
-- SECURITY FIX (applied to live eq-canonical 2026-06-26).
--
-- eq_get_licences_expiring_on / _within and eq_get_org_admins are SECURITY DEFINER,
-- return cross-tenant roster PII (names, emails, phones, licence numbers), and accept an
-- arbitrary p_org_id with NO internal authorization check. Their grants previously included
-- PUBLIC + anon + authenticated, so anyone holding the public anon key could harvest any
-- org's roster by passing a (trivially guessable, e.g. 00000000-...-000000000002) org_id.
--
-- They are only ever called by the eq-shell licence-expiry-scheduler cron via the service
-- role (netlify/functions/licence-expiry-scheduler.ts), so this revoke is non-breaking.

REVOKE ALL ON FUNCTION public.eq_get_licences_expiring_on(uuid, date)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.eq_get_licences_expiring_within(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.eq_get_org_admins(uuid)                        FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.eq_get_licences_expiring_on(uuid, date)        TO service_role;
GRANT EXECUTE ON FUNCTION public.eq_get_licences_expiring_within(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.eq_get_org_admins(uuid)                        TO service_role;

-- Pin search_path on the two SECURITY DEFINER functions that lacked it (the third, _within,
-- already had it via migration 0047). Defense-in-depth against search-path injection.
ALTER FUNCTION public.eq_get_licences_expiring_on(uuid, date) SET search_path = public;
ALTER FUNCTION public.eq_get_org_admins(uuid)                 SET search_path = public;
