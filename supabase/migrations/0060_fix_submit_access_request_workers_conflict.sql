-- 0060_fix_submit_access_request_workers_conflict.sql
--
-- Mirrors the 0059 fix (eq_cards_claim_invite) for eq_cards_submit_access_request.
--
-- Scenario: self-signup user has a workers row (user_id = auth.uid()) already.
-- When they press "Apply" on a discoverable org, the tail of the RPC runs:
--   UPDATE workers SET user_id = auth.uid() WHERE user_id IS NULL AND phone = v_phone
-- If an admin-pre-populated shell row exists with the same phone, that UPDATE
-- tries to write a duplicate user_id → ERROR 23505 workers_user_id_key.
--
-- Fix: skip the phone-linkage UPDATE if the caller already owns a workers row.

CREATE OR REPLACE FUNCTION public.eq_cards_submit_access_request(
  p_org_id       uuid,
  p_sharing_scope text DEFAULT 'full'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_phone      text;
  v_request_id uuid;
BEGIN
  IF p_sharing_scope NOT IN ('basic', 'full') THEN
    RAISE EXCEPTION 'invalid_sharing_scope' USING ERRCODE = 'P0020';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organisations
    WHERE id = p_org_id AND accepts_applications = true
  ) THEN
    RAISE EXCEPTION 'org_not_discoverable' USING ERRCODE = 'P0021';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_access_requests
    WHERE org_id         = p_org_id
      AND worker_user_id = auth.uid()
      AND requested_by   = auth.uid()
      AND status         = 'pending'
  ) THEN
    RAISE EXCEPTION 'duplicate_request' USING ERRCODE = 'P0022';
  END IF;

  SELECT regexp_replace(regexp_replace(COALESCE(phone, ''), '\s', '', 'g'), '^(\+61|61|0)', '')
    INTO v_phone FROM auth.users WHERE id = auth.uid();

  INSERT INTO public.org_access_requests
    (org_id, worker_phone, worker_user_id, status, requested_by, sharing_scope)
  VALUES
    (p_org_id, NULLIF(v_phone, ''), auth.uid(), 'pending', auth.uid(), p_sharing_scope)
  RETURNING id INTO v_request_id;

  -- Link any unlinked phone-matched workers shell row to this user,
  -- but only if they don't already own a workers row (prevents 23505 on
  -- workers_user_id_key when self-signup + admin-pre-populated row both exist).
  IF v_phone IS NOT NULL AND v_phone <> ''
     AND NOT EXISTS (SELECT 1 FROM public.workers WHERE user_id = auth.uid())
  THEN
    UPDATE public.workers
    SET user_id = auth.uid()
    WHERE user_id IS NULL
      AND regexp_replace(regexp_replace(COALESCE(phone, ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_phone;
  END IF;

  RETURN v_request_id;
END;
$function$;
