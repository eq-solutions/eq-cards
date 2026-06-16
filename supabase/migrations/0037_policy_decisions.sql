-- Migration 0037: Policy decisions — decline cooldown
--
-- Outcome of 2026-06-17 policy review:
--   P1 (tenant_id personal home): deferred — auth-touching, own session.
--   P2 (licence visibility disclosure): banner copy only, no DB change.
--   P3 (decline cooldown): block re-request within 30 days of a decline.
--
-- This migration implements P3 only.
--
-- Behaviour:
--   * Worker declines → status = 'declined', responded_at = now()
--   * Same org re-requests within 30 days → 'recently_declined' exception
--   * After 30 days → new request permitted (fresh INSERT, old row stays)
--
-- The cooldown is checked against the most-recent declined row for the
-- (org_id, worker_phone) pair so it survives multiple re-request cycles.

CREATE OR REPLACE FUNCTION public.eq_cards_request_worker_access(
  p_org_id uuid, p_phone text, p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_norm        text := regexp_replace(regexp_replace(COALESCE(p_phone,''),'\s','','g'),'^(\+61|61|0)','');
  v_worker_user uuid;
  v_request_id  uuid;
  v_rl          jsonb;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  -- Enumeration throttle: cap how fast one admin can probe phone numbers.
  -- 30/hour/admin — from migration 0036.
  v_rl := public.check_and_increment_rate_limit('connect_req:' || auth.uid()::text, 3600, 30, 3600);
  IF (v_rl->>'blocked')::boolean THEN
    RAISE EXCEPTION 'Too many connection requests. Try again in % second(s).',
      (v_rl->>'retry_after_seconds')
      USING ERRCODE = 'P0001', HINT = 'rate_limited', DETAIL = (v_rl->>'retry_after_seconds');
  END IF;

  IF v_norm = '' THEN
    RAISE EXCEPTION 'invalid_phone' USING ERRCODE = 'P0006';
  END IF;

  SELECT id INTO v_worker_user FROM auth.users
  WHERE regexp_replace(regexp_replace(COALESCE(phone,''),'\s','','g'),'^(\+61|61|0)','') = v_norm
  LIMIT 1;

  IF v_worker_user IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.org_memberships
    WHERE org_id = p_org_id AND user_id = v_worker_user AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'already_member' USING ERRCODE = 'P0007';
  END IF;

  -- Decline cooldown: worker privacy protection.
  -- If the worker declined a request from this org within the last 30 days,
  -- block the org from sending another. After 30 days they may try once more.
  -- Checked on the most-recent declined row so multiple cycles work correctly.
  IF EXISTS (
    SELECT 1 FROM public.org_access_requests
    WHERE org_id       = p_org_id
      AND worker_phone = v_norm
      AND status       = 'declined'
      AND responded_at > now() - interval '30 days'
  ) THEN
    RAISE EXCEPTION 'recently_declined' USING ERRCODE = 'P0013';
  END IF;

  INSERT INTO public.org_access_requests (org_id, worker_phone, worker_user_id, note, requested_by)
  VALUES (p_org_id, v_norm, v_worker_user, NULLIF(TRIM(COALESCE(p_note,'')),''), auth.uid())
  ON CONFLICT (org_id, worker_phone) WHERE status = 'pending'
  DO UPDATE SET note          = COALESCE(EXCLUDED.note, public.org_access_requests.note),
               worker_user_id = COALESCE(public.org_access_requests.worker_user_id, EXCLUDED.worker_user_id)
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_request_worker_access(uuid, text, text) TO authenticated;
