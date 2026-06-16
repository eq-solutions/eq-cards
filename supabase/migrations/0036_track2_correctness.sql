-- Migration 0036: Track 2 (employer-connects-to-existing-wallet) correctness + security
--
-- The org_access_requests pathway + RPCs are live but were never exercised
-- (0 rows). A deep review found they cannot ship as-is. This migration fixes
-- the five blockers BEFORE any UI is wired to them. Nothing here is applied by
-- merging — it is an auth/consent change and must be signed off before deploy.
--
--   A. 'Unknown' workers — respond_to_access_request read names from the near-
--      empty public.profiles table (2 rows / 17 users). Source from the richest
--      available identity instead; 'Unknown' becomes a true last resort.
--   B. Non-atomic revoke — eq_cards_revoke_org_access flipped only the
--      user_tenant_memberships flag, leaving org_memberships active, so
--      is_org_admin_of() kept returning true and the employer kept reading the
--      worker's licences after "disconnect". Now revokes the membership too.
--   C. Unauthenticated PII — eq_field_get_worker_summary is SECURITY DEFINER
--      with no auth check and returns next-of-kin name+phone for any worker id.
--      Add an authorization predicate (the worker, an admin of an org they
--      belong to, or an admin of an org that invited them).
--   D. Enumeration oracle — eq_cards_request_worker_access had no throttle; an
--      org admin could probe unlimited phone numbers. Add a per-admin rate cap.
--   E. Claim/request desync — when a worker claims an invite while a pending
--      access request exists for the same (org, phone), the request goes stale.
--      Mark it 'fulfilled' via an exception-safe trigger (never touches the
--      critical claim path).
--
-- NOT included (deliberately): the index/column cleanups and E.164 storage
-- unification the review listed as optional. org_access_requests.worker_phone
-- keeps its normalised-suffix convention (internally consistent, table empty);
-- churning it adds risk for no correctness gain. Tracked as follow-up polish.


-- ── E (part 1): allow 'fulfilled' in the status CHECK ───────────────────────
ALTER TABLE public.org_access_requests
  DROP CONSTRAINT IF EXISTS org_access_requests_status_check;
ALTER TABLE public.org_access_requests
  ADD CONSTRAINT org_access_requests_status_check
  CHECK (status IN ('pending','approved','declined','cancelled','fulfilled'));


-- ── A: kill the 'Unknown' worker in the access-request approve path ─────────
CREATE OR REPLACE FUNCTION public.eq_cards_respond_to_access_request(
  p_request_id uuid, p_approve boolean)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
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

  -- APPROVE.
  -- Identity sourcing — prefer an existing workers/shell identity over the
  -- near-empty profiles table so a connecting worker is never named 'Unknown'.
  -- Order: existing workers row → shell_control.users.name → profiles.full_name
  -- → auth user metadata. Phone/email come from auth.users (always present for
  -- the authenticated caller), with profiles as an optional override.
  SELECT name INTO v_shell_name FROM shell_control.users WHERE id = auth.uid();
  v_full := COALESCE(
    (SELECT NULLIF(TRIM(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), '')
       FROM public.workers WHERE user_id = auth.uid() ORDER BY created_at DESC LIMIT 1),
    NULLIF(TRIM(COALESCE(v_shell_name,'')), ''),
    NULLIF(TRIM(COALESCE((SELECT full_name FROM public.profiles WHERE id = auth.uid()),'')), ''),
    NULLIF(TRIM(COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = auth.uid()),'')), '')
  );

  -- 1. Ensure a public.workers row so the admin's team list shows them.
  INSERT INTO public.workers (user_id, first_name, last_name, phone, email)
  VALUES (
    auth.uid(),
    COALESCE(NULLIF(split_part(COALESCE(v_full,''),' ',1),''), 'Unknown'),
    COALESCE(NULLIF(CASE WHEN v_full LIKE '% %'
      THEN substring(v_full FROM position(' ' IN v_full)+1) ELSE NULL END, ''), ''),
    COALESCE((SELECT mobile FROM public.profiles WHERE id = auth.uid()),
             (SELECT phone FROM auth.users WHERE id = auth.uid())),
    COALESCE((SELECT email FROM public.profiles WHERE id = auth.uid()),
             (SELECT email FROM auth.users WHERE id = auth.uid()))
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- 2. Active org membership (Cards-app layer).
  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_req.org_id, auth.uid(), 'member', 'active', v_req.requested_by, now())
  ON CONFLICT (org_id, user_id) WHERE status <> 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- 3. Identity layer (JWT hook + workspace switcher). COALESCE preserves the
  --    worker's existing home/active tenant — connecting adds a switchable
  --    membership, it does not yank their context.
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
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_respond_to_access_request(uuid, boolean) TO authenticated;


-- ── B: make revoke atomic — also revoke the org_membership ──────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_revoke_org_access(p_org_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user        shell_control.users%ROWTYPE;
  v_is_personal boolean;
BEGIN
  SELECT * INTO v_user FROM shell_control.users WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- NOTE: p_org_id is a TENANT id despite the legacy param name (it is compared
  -- against shell_control.tenants.id and user_tenant_memberships.tenant_id).
  IF p_org_id = v_user.tenant_id THEN
    RAISE EXCEPTION 'cannot_revoke_home_tenant' USING ERRCODE = 'P0012';
  END IF;

  SELECT is_personal INTO v_is_personal
  FROM shell_control.tenants WHERE id = p_org_id;
  IF v_is_personal IS TRUE THEN
    RAISE EXCEPTION 'cannot_revoke_personal_tenant' USING ERRCODE = 'P0012';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM shell_control.user_tenant_memberships
    WHERE user_id = auth.uid() AND tenant_id = p_org_id AND active = true
  ) THEN
    RAISE EXCEPTION 'not_a_member' USING ERRCODE = 'P0011';
  END IF;

  -- Identity-layer revoke (workspace switcher / JWT hook).
  UPDATE shell_control.user_tenant_memberships
  SET    active = false
  WHERE  user_id = auth.uid() AND tenant_id = p_org_id;

  -- Consent revoke (THE fix): also revoke the Cards-layer org_membership so the
  -- employer's licence-read RLS (is_org_admin_of) stops returning true. Revoke
  -- works in tenant_id space; org_memberships is org_id space — resolve via
  -- organisations.tenant_id.
  UPDATE public.org_memberships om
  SET    status = 'revoked', updated_at = now()
  FROM   public.organisations o
  WHERE  o.tenant_id = p_org_id
    AND  om.org_id   = o.id
    AND  om.user_id  = auth.uid()
    AND  om.status  <> 'revoked';

  IF v_user.last_active_tenant_id = p_org_id THEN
    UPDATE shell_control.users
    SET    last_active_tenant_id = v_user.tenant_id
    WHERE  id = auth.uid();
  END IF;

  RETURN v_user.tenant_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_revoke_org_access(uuid) TO authenticated;


-- ── C: authorize eq_field_get_worker_summary (was unauthenticated PII) ──────
-- Returns 0 rows (not PII) to unauthorized callers. SECURITY DEFINER is kept so
-- it can read across RLS, but it now self-authorizes:
--   * the worker themselves, OR
--   * an admin of an org the (claimed) worker belongs to, OR
--   * an admin of an org that INVITED this worker (covers un-claimed workers,
--     who have user_id = NULL and no org_membership — the org link is the
--     worker_invite). cards_claimed is a return column, so this endpoint is
--     explicitly used for not-yet-claimed workers.
CREATE OR REPLACE FUNCTION public.eq_field_get_worker_summary(p_worker_id uuid)
RETURNS TABLE(cards_claimed boolean, right_to_work_type text, right_to_work_expiry date,
              emergency_contact_name text, emergency_contact_phone text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    (w.user_id IS NOT NULL)    AS cards_claimed,
    w.right_to_work_type::text AS right_to_work_type,
    w.right_to_work_expiry     AS right_to_work_expiry,
    w.emergency_contact_name   AS emergency_contact_name,
    w.emergency_contact_phone  AS emergency_contact_phone
  FROM public.workers w
  WHERE w.id = p_worker_id
    AND (
      w.user_id = auth.uid()
      OR (w.user_id IS NOT NULL AND public.is_org_admin_of(w.user_id))
      OR EXISTS (
        SELECT 1
        FROM public.worker_invites wi
        JOIN public.org_memberships am
          ON am.org_id  = wi.org_id
         AND am.user_id = auth.uid()
         AND am.role    = 'admin'
         AND am.status  = 'active'
        WHERE wi.worker_id = p_worker_id
      )
    );
$$;


-- ── D: throttle eq_cards_request_worker_access (enumeration oracle) ─────────
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
  -- 30/hour/admin — generous for real onboarding (a few per month) but closes
  -- the privacy oracle. Reuses the 2026-06-15 hardening-sprint bucket infra.
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


-- ── E (part 2): reconcile claim ↔ pending request via a safe trigger ────────
-- When a worker claims an invite while a pending access request exists for the
-- same (org, phone), the request is now stale. Mark it 'fulfilled'. Wrapped so
-- a cleanup error can NEVER abort the claim (the critical path).
CREATE OR REPLACE FUNCTION public.tg_fulfil_access_requests_on_claim()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_suffix text;
BEGIN
  IF NEW.claimed_at IS NOT NULL AND OLD.claimed_at IS NULL THEN
    BEGIN
      SELECT regexp_replace(regexp_replace(
               COALESCE(
                 (SELECT phone FROM public.workers WHERE id = NEW.worker_id),
                 NEW.profile_data->>'mobile',
                 NEW.profile_data->>'phone',
                 ''
               ), '\s','','g'), '^(\+61|61|0)','')
        INTO v_suffix;

      IF v_suffix IS NOT NULL AND v_suffix <> '' THEN
        UPDATE public.org_access_requests
        SET    status = 'fulfilled', responded_at = now()
        WHERE  status = 'pending'
          AND  org_id = NEW.org_id
          AND  worker_phone = v_suffix;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fulfil_access_requests_on_claim failed for invite %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fulfil_access_requests_on_claim ON public.worker_invites;
CREATE TRIGGER trg_fulfil_access_requests_on_claim
  AFTER UPDATE ON public.worker_invites
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_fulfil_access_requests_on_claim();
