-- Security hardening: eq_cards_find_invites_by_phone must not be callable
-- by the anon role. PostgreSQL grants EXECUTE to PUBLIC by default for new
-- functions; 0057 granted to authenticated but never revoked from PUBLIC,
-- leaving anon able to call it.
--
-- Fix:
--   1. REVOKE from PUBLIC (removes the PostgreSQL default, covers anon).
--   2. KEEP the existing authenticated grant (callers are OTP-authed users).
--   3. Replace the function body with an explicit auth.uid() guard (defence
--      in depth — even if the REVOKE were somehow bypassed, a NULL uid()
--      raises 'insufficient_privilege' before touching any data).

-- Supabase creates explicit anon + PUBLIC grants for new functions by default;
-- both must be revoked to close the exposure.
REVOKE EXECUTE ON FUNCTION public.eq_cards_find_invites_by_phone() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.eq_cards_find_invites_by_phone() FROM anon;

GRANT EXECUTE ON FUNCTION public.eq_cards_find_invites_by_phone() TO authenticated;

CREATE OR REPLACE FUNCTION public.eq_cards_find_invites_by_phone()
RETURNS TABLE(org_name text, token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_phone text;
  v_suffix     text;
BEGIN
  -- Require an authenticated session. anon role has no EXECUTE grant after
  -- 0058, but a SECURITY DEFINER function can be called by any role that
  -- has EXECUTE — this guard makes the auth requirement explicit in the body.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();

  IF v_auth_phone IS NULL OR v_auth_phone = '' THEN
    RETURN;
  END IF;

  -- Normalise to 9-digit suffix (same logic as eq_cards_lookup_invite_by_phone).
  v_suffix := regexp_replace(
                regexp_replace(v_auth_phone, '\s', '', 'g'),
                '^(\+61|61|0)', ''
              );

  RETURN QUERY
  SELECT DISTINCT ON (t.id)
    t.name  AS org_name,
    wi.token
  FROM   public.worker_invites wi
  JOIN   public.tenants        t  ON t.id  = wi.org_id
  LEFT   JOIN public.workers   w  ON w.id  = wi.worker_id
  WHERE  wi.claimed_at IS NULL
    AND  wi.expires_at  > now()
    AND  t.status        = 'active'
    AND (
      regexp_replace(regexp_replace(COALESCE(w.phone,                    ''), '\s','','g'), '^(\+61|61|0)','') = v_suffix
      OR
      regexp_replace(regexp_replace(COALESCE(wi.profile_data->>'mobile', ''), '\s','','g'), '^(\+61|61|0)','') = v_suffix
      OR
      regexp_replace(regexp_replace(COALESCE(wi.profile_data->>'phone',  ''), '\s','','g'), '^(\+61|61|0)','') = v_suffix
    )
  ORDER BY t.id, wi.created_at DESC;
END;
$$;
