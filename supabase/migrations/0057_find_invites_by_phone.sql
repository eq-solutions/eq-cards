-- Authenticated RPC that returns all unclaimed invites for the signed-in
-- user's phone number, across every active tenant.
--
-- Used by the "Find my company account" button on the not-provisioned screen.
-- Because the user is already authenticated (phone known from auth.uid()),
-- there is no enumeration risk and no need to go through the Shell gateway.
-- Rate limiting is handled by GoTrue session gating.
--
-- Returns one row per org (DISTINCT ON tenant) — if an org sent multiple
-- invites to the same phone, only the most recent unclaimed one is returned.

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

GRANT EXECUTE ON FUNCTION public.eq_cards_find_invites_by_phone() TO authenticated;
