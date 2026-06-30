-- 0062_onboarding_dedup_prevention.sql
--
-- ROOT CAUSE (verified live): eq_cards_respond_to_access_request (the approve
-- step) minted a worker with `INSERT ... ON CONFLICT (user_id) DO NOTHING`.
-- It only dedups on user_id — it never ADOPTS a pre-existing unlinked worker
-- (admin-pre-populated shell, user_id IS NULL, matchable only by phone/email).
-- So every roster member who was bulk-imported and then self-signed-up got a
-- SECOND worker row (6/6 cases as of 2026-06-30; propagates to ehow.app_data.staff).
--
-- FIX: a single adopt-or-create helper used by the signup/approval path. It
-- (1) is idempotent on user_id, (2) adopts an existing unlinked shell by
-- normalised phone OR lower(email) before creating, (3) advisory-locks to avoid
-- the 23505 race that 0060 patched. Then re-point the approve RPC at it.
--
-- This is the PREVENTION half only. The reversible duplicate CLEANUP and the
-- invite-path retirement ship separately (see eq-context cards dedup sprint).
-- handle_phone_dedup (identity-plane, shell_control.users) is a follow-up.

-- ── 1. Single source of truth for worker identity ──────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_link_or_create_worker(
  p_user_id uuid,
  p_phone   text,
  p_email   text,
  p_first   text,
  p_last    text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_norm  text := regexp_replace(regexp_replace(COALESCE(p_phone,''), '\s', '', 'g'), '^(\+61|61|0)', '');
  v_email text := lower(NULLIF(TRIM(COALESCE(p_email,'')), ''));
  v_id    uuid;
BEGIN
  -- (1) idempotent: caller already owns a worker row
  SELECT id INTO v_id FROM public.workers WHERE user_id = p_user_id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- serialise concurrent signups for the same identity (prevents 23505)
  PERFORM pg_advisory_xact_lock(
    hashtextextended(COALESCE(NULLIF(v_norm,''), v_email, p_user_id::text), 0)
  );

  -- re-check under lock
  SELECT id INTO v_id FROM public.workers WHERE user_id = p_user_id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- (2) ADOPT an existing unlinked shell by normalised phone OR email.
  -- Prefer the row carrying the most credentials, then the oldest (the real
  -- admin-pre-populated record over an empty stub).
  SELECT w.id INTO v_id
  FROM public.workers w
  WHERE w.user_id IS NULL
    AND (
      (v_norm <> '' AND regexp_replace(regexp_replace(COALESCE(w.phone,''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_norm)
      OR (v_email IS NOT NULL AND lower(w.email) = v_email)
    )
  ORDER BY (SELECT count(*) FROM public.worker_credentials wc WHERE wc.worker_id = w.id) DESC,
           w.created_at ASC
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.workers SET user_id = p_user_id WHERE id = v_id;
    RETURN v_id;
  END IF;

  -- (3) nothing to adopt: create
  INSERT INTO public.workers (user_id, first_name, last_name, phone, email)
  VALUES (p_user_id,
          COALESCE(NULLIF(p_first,''), 'Unknown'),
          COALESCE(p_last,''),
          p_phone,
          p_email)
  ON CONFLICT (user_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.workers WHERE user_id = p_user_id LIMIT 1;
  END IF;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_link_or_create_worker(uuid, text, text, text, text) FROM public, anon;

-- ── 2. Re-point the approve RPC at the helper ──────────────────────────────
-- Body is verbatim from the live definition; the ONLY change is the worker
-- creation block (previously INSERT ... ON CONFLICT (user_id) DO NOTHING) now
-- calls eq_cards_link_or_create_worker so a pre-existing shell is adopted.
CREATE OR REPLACE FUNCTION public.eq_cards_respond_to_access_request(p_request_id uuid, p_approve boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req        public.org_access_requests;
  v_norm       text;
  v_tenant_id  uuid;
  v_auth_phone text;
  v_auth_email text;
  v_name       text;
  v_email      text;
  v_full       text;
  v_shell_name text;
BEGIN
  SELECT regexp_replace(regexp_replace(COALESCE(phone,''),'\s','','g'),'^(\+61|61|0)','')
    INTO v_norm FROM auth.users WHERE id = auth.uid();

  SELECT * INTO v_req FROM public.org_access_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found' USING ERRCODE = 'P0002'; END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'request_not_pending' USING ERRCODE = 'P0008'; END IF;
  IF NOT (v_req.worker_user_id = auth.uid()
          OR (v_norm IS NOT NULL AND v_norm <> '' AND v_req.worker_phone = v_norm)) THEN
    RAISE EXCEPTION 'not_your_request' USING ERRCODE = 'P0009';
  END IF;

  IF NOT p_approve THEN
    UPDATE public.org_access_requests
      SET status = 'declined', responded_at = now(), worker_user_id = auth.uid()
      WHERE id = p_request_id;
    RETURN 'declined';
  END IF;

  -- APPROVE — source identity from the richest available place, never 'Unknown'.
  SELECT name INTO v_shell_name FROM shell_control.users WHERE id = auth.uid();
  v_full := COALESCE(
    (SELECT NULLIF(TRIM(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), '')
       FROM public.workers WHERE user_id = auth.uid() ORDER BY created_at DESC LIMIT 1),
    NULLIF(TRIM(COALESCE(v_shell_name,'')), ''),
    NULLIF(TRIM(COALESCE((SELECT full_name FROM public.profiles WHERE id = auth.uid()),'')), ''),
    NULLIF(TRIM(COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = auth.uid()),'')), '')
  );

  -- [CHANGED 0062] adopt-or-create instead of create-only (was: INSERT ... ON CONFLICT (user_id) DO NOTHING)
  PERFORM public.eq_cards_link_or_create_worker(
    auth.uid(),
    COALESCE((SELECT mobile FROM public.profiles WHERE id = auth.uid()),
             (SELECT phone  FROM auth.users    WHERE id = auth.uid())),
    COALESCE((SELECT email  FROM public.profiles WHERE id = auth.uid()),
             (SELECT email  FROM auth.users    WHERE id = auth.uid())),
    COALESCE(NULLIF(split_part(COALESCE(v_full,''),' ',1),''), 'Unknown'),
    COALESCE(NULLIF(CASE WHEN v_full LIKE '% %'
      THEN substring(v_full FROM position(' ' IN v_full)+1) ELSE NULL END, ''), '')
  );

  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_req.org_id, auth.uid(), 'member', 'active', v_req.requested_by, now())
  ON CONFLICT (org_id, user_id) WHERE status <> 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  SELECT tenant_id INTO v_tenant_id FROM public.organisations WHERE id = v_req.org_id;
  IF v_tenant_id IS NOT NULL THEN
    SELECT phone, email INTO v_auth_phone, v_auth_email FROM auth.users WHERE id = auth.uid();
    IF v_auth_phone IS NULL OR v_auth_phone = '' THEN v_auth_phone := NULL;
    ELSIF left(v_auth_phone,1) <> '+' THEN v_auth_phone := '+' || v_auth_phone; END IF;
    IF v_auth_phone IS NOT NULL AND EXISTS (
      SELECT 1 FROM shell_control.users WHERE phone = v_auth_phone AND id <> auth.uid()
    ) THEN v_auth_phone := NULL; END IF;

    v_name  := COALESCE(v_shell_name, v_full);
    v_email := COALESCE(v_auth_email, (SELECT email FROM public.profiles WHERE id = auth.uid()));
    IF v_email IS NOT NULL AND EXISTS (
      SELECT 1 FROM shell_control.users WHERE email = v_email AND id <> auth.uid()
    ) THEN v_email := NULL; END IF;

    INSERT INTO shell_control.users (id, email, phone, name, role, tenant_id, last_active_tenant_id, active)
    VALUES (auth.uid(), v_email, v_auth_phone, v_name, 'employee'::eq_role, v_tenant_id, v_tenant_id, true)
    ON CONFLICT (id) DO UPDATE SET
      phone                 = COALESCE(EXCLUDED.phone, shell_control.users.phone),
      email                 = COALESCE(shell_control.users.email, EXCLUDED.email),
      name                  = COALESCE(shell_control.users.name, EXCLUDED.name),
      tenant_id             = COALESCE(shell_control.users.tenant_id, EXCLUDED.tenant_id),
      last_active_tenant_id = COALESCE(shell_control.users.last_active_tenant_id, EXCLUDED.last_active_tenant_id),
      active                = true;

    INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
    VALUES (auth.uid(), v_tenant_id, 'employee'::eq_role, true)
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;
  END IF;

  UPDATE public.org_access_requests
    SET status = 'approved', responded_at = now(), worker_user_id = auth.uid()
    WHERE id = p_request_id;
  RETURN 'approved';
END;
$function$;
