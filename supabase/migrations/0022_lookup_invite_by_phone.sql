-- 0022_lookup_invite_by_phone.sql
-- Public RPC: given a phone number and org slug, returns the token UUID of
-- the first unclaimed, non-expired worker invite for that worker + org.
-- Used by the QR claim flow: worker scans QR → enters phone → gets their token.

CREATE OR REPLACE FUNCTION eq_cards_lookup_invite_by_phone(
  p_phone  text,   -- E.164 (+61...) or Australian local (04...)
  p_slug   text    -- tenant slug, e.g. 'sks'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id  uuid;
  v_token   uuid;
  -- Normalise to 9-digit AU mobile suffix for fuzzy matching
  v_suffix  text := regexp_replace(p_phone, '^(\+61|61|0)', '');
BEGIN
  -- Resolve org by tenant slug
  SELECT id INTO v_org_id
  FROM   public.tenants
  WHERE  slug   = lower(trim(p_slug))
    AND  status = 'active'
  LIMIT  1;

  IF v_org_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Find the most recent unclaimed, non-expired invite for this phone + org.
  -- Check workers.phone (pre-assigned worker record) AND profile_data keys
  -- ('mobile' is Shell's key, 'phone' is a legacy key). Both may be stored
  -- in different formats so compare the 9-digit AU suffix after stripping prefix.
  SELECT wi.token INTO v_token
  FROM   public.worker_invites wi
  LEFT JOIN public.workers w ON w.id = wi.worker_id
  WHERE  wi.org_id    = v_org_id
    AND  wi.claimed_at IS NULL
    AND  wi.expires_at > now()
    AND (
      regexp_replace(coalesce(w.phone,                          ''), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(coalesce(wi.profile_data->>'mobile',       ''), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(coalesce(wi.profile_data->>'phone',        ''), '^(\+61|61|0)', '') = v_suffix
    )
  ORDER  BY wi.created_at DESC
  LIMIT  1;

  RETURN v_token; -- NULL if no unclaimed invite found
END;
$$;

-- Callable without auth — worker hasn't signed in yet when scanning the QR.
REVOKE ALL  ON FUNCTION eq_cards_lookup_invite_by_phone(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eq_cards_lookup_invite_by_phone(text, text) TO anon, authenticated;
