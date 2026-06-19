-- 0039_find_pending_invite.sql
--
-- Auth-context RPC: find any pending invite for the currently signed-in user,
-- matched by their phone number across all orgs.
--
-- Purpose: after phone OTP, _resolveAndLand() calls this before falling back
-- to the not-provisioned screen. If a pending invite exists, the worker is
-- routed directly to /claim?token=... and the "Welcome / enter company code"
-- intermediary screen is never shown.
--
-- Phone matching reuses the 9-digit AU suffix normalisation from 0022 so the
-- same fuzzy match (E.164, local, no-prefix) applies across all stored formats.
--
-- Auth: SECURITY DEFINER; granted only to `authenticated`. Anon callers cannot
-- reach this — the user must have already proved identity via phone OTP.

CREATE OR REPLACE FUNCTION public.eq_cards_find_pending_invite()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone  text;
  v_suffix text;
  v_token  uuid;
BEGIN
  -- Authenticated user's phone from GoTrue. May be E.164 (+61...) or bare digits.
  SELECT phone INTO v_phone
  FROM auth.users
  WHERE id = auth.uid();

  IF v_phone IS NULL OR trim(v_phone) = '' THEN
    RETURN NULL;
  END IF;

  -- Normalise to 9-digit AU mobile suffix (strips +61 / 61 / leading 0).
  v_suffix := regexp_replace(trim(v_phone), '^(\+61|61|0)', '');

  IF length(v_suffix) < 8 THEN
    RETURN NULL; -- not a valid AU mobile
  END IF;

  -- Most-recent unclaimed, non-expired invite for this phone (any org).
  -- Phone stored on the linked workers row OR in profile_data JSON keys.
  SELECT wi.token INTO v_token
  FROM   public.worker_invites wi
  LEFT JOIN public.workers w ON w.id = wi.worker_id
  WHERE  wi.claimed_at IS NULL
    AND  wi.expires_at > now()
    AND (
      regexp_replace(coalesce(w.phone,                        ''), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(coalesce(wi.profile_data->>'mobile',     ''), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(coalesce(wi.profile_data->>'phone',      ''), '^(\+61|61|0)', '') = v_suffix
    )
  ORDER  BY wi.created_at DESC
  LIMIT  1;

  RETURN v_token; -- NULL if no unclaimed invite found
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_find_pending_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.eq_cards_find_pending_invite() TO authenticated;
