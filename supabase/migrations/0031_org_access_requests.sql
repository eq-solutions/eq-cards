-- 0031_org_access_requests.sql
--
-- S4: employer-initiated access requests.
--
-- The inverse of claim/join: instead of a worker claiming an employer-made
-- account, an employer asks an EXISTING (standalone) tradie to connect their
-- already-built wallet. Consent-gated — the worker must approve.
--
-- Model notes (verified against live schema):
--   * "Joining an org" spans 3 id-spaces: org_id (public.organisations.id) →
--     tenant_id (organisations.tenant_id → shell_control.tenants) → auth.uid().
--   * Admin auth = public.is_org_admin(org_id) (org_memberships.role='admin').
--   * Approving must mirror eq_cards_claim_invite's reconciliation: ensure a
--     public.workers row (so the admin's team list sees them), an active
--     public.org_memberships row, AND the shell_control identity pair
--     (users + user_tenant_memberships) that the JWT hook + workspace switcher
--     read. It does NOT promote credentials — a standalone tradie owns their
--     own wallet; the employer is connecting to it, not seeding it.
--   * Privacy: requests are keyed by normalised phone and return success
--     regardless of whether a wallet exists, so an employer cannot enumerate
--     which numbers have EQ Cards. Only the targeted worker can approve.

CREATE TABLE IF NOT EXISTS public.org_access_requests (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  worker_phone   text NOT NULL,            -- normalised suffix (no +61/0/spaces)
  worker_user_id uuid,                     -- resolved when a matching user exists
  status         text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','approved','declined','cancelled')),
  note           text,
  requested_by   uuid,
  requested_at   timestamptz NOT NULL DEFAULT now(),
  responded_at   timestamptz
);

-- At most one live request per (org, phone).
CREATE UNIQUE INDEX IF NOT EXISTS org_access_requests_one_pending
  ON public.org_access_requests (org_id, worker_phone) WHERE status = 'pending';
-- Worker-side lookup by phone.
CREATE INDEX IF NOT EXISTS org_access_requests_phone_pending
  ON public.org_access_requests (worker_phone) WHERE status = 'pending';

-- Lock down direct access: the table is reachable only through the SECURITY
-- DEFINER RPCs below (which bypass RLS). No policies = deny all direct reads.
ALTER TABLE public.org_access_requests ENABLE ROW LEVEL SECURITY;


-- ── Admin: request access to a worker by phone ──────────────────────────────
-- Idempotent. Returns the (new or existing) pending request id. Reveals nothing
-- about whether the phone has a wallet.
CREATE OR REPLACE FUNCTION public.eq_cards_request_worker_access(
  p_org_id uuid, p_phone text, p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_norm        text := regexp_replace(regexp_replace(COALESCE(p_phone,''),'\s','','g'),'^(\+61|61|0)','');
  v_worker_user uuid;
  v_request_id  uuid;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
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
  DO UPDATE SET note           = COALESCE(EXCLUDED.note, public.org_access_requests.note),
               worker_user_id  = COALESCE(public.org_access_requests.worker_user_id, EXCLUDED.worker_user_id)
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_request_worker_access(uuid, text, text) TO authenticated;


-- ── Worker: list pending requests addressed to me ───────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_list_incoming_requests()
RETURNS TABLE (request_id uuid, org_id uuid, org_name text, org_slug text, note text, requested_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_norm text;
BEGIN
  SELECT regexp_replace(regexp_replace(COALESCE(phone,''),'\s','','g'),'^(\+61|61|0)','')
    INTO v_norm FROM auth.users WHERE id = auth.uid();

  RETURN QUERY
  SELECT r.id, r.org_id, o.name, o.slug, r.note, r.requested_at
  FROM   public.org_access_requests r
  JOIN   public.organisations o ON o.id = r.org_id
  WHERE  r.status = 'pending'
    AND (r.worker_user_id = auth.uid()
         OR (v_norm IS NOT NULL AND v_norm <> '' AND r.worker_phone = v_norm))
  ORDER  BY r.requested_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_list_incoming_requests() TO authenticated;


-- ── Worker: approve or decline a request ────────────────────────────────────
-- Approve mirrors eq_cards_claim_invite's org reconciliation (no cred promotion).
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
  -- 1. Ensure a public.workers row so the admin's team list shows them.
  --    Mirror eq_cards_upsert_my_worker's NOT-NULL convention (Unknown/'').
  v_full := (SELECT full_name FROM public.profiles WHERE id = auth.uid());
  INSERT INTO public.workers (user_id, first_name, last_name, phone, email)
  VALUES (
    auth.uid(),
    COALESCE(NULLIF(split_part(COALESCE(v_full,''),' ',1),''), 'Unknown'),
    COALESCE(NULLIF(CASE WHEN v_full LIKE '% %'
      THEN substring(v_full FROM position(' ' IN v_full)+1) ELSE NULL END, ''), ''),
    COALESCE((SELECT mobile FROM public.profiles WHERE id = auth.uid()),
             (SELECT phone  FROM auth.users      WHERE id = auth.uid())),
    COALESCE((SELECT email  FROM public.profiles WHERE id = auth.uid()),
             (SELECT email  FROM auth.users      WHERE id = auth.uid()))
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- 2. Active org membership (Cards-app layer).
  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_req.org_id, auth.uid(), 'member', 'active', v_req.requested_by, now())
  ON CONFLICT (org_id, user_id) WHERE status <> 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- 3. Identity layer (what the JWT hook + workspace switcher read). Preserve
  --    the worker's existing home/active tenant via COALESCE — approving adds
  --    the org as a switchable membership, it does not yank their context.
  SELECT tenant_id INTO v_tenant_id FROM public.organisations WHERE id = v_req.org_id;
  IF v_tenant_id IS NOT NULL THEN
    SELECT phone, email INTO v_auth_phone, v_auth_email FROM auth.users WHERE id = auth.uid();
    IF v_auth_phone IS NULL OR v_auth_phone = '' THEN v_auth_phone := NULL;
    ELSIF left(v_auth_phone,1) <> '+' THEN v_auth_phone := '+' || v_auth_phone; END IF;
    IF v_auth_phone IS NOT NULL AND EXISTS (
      SELECT 1 FROM shell_control.users WHERE phone = v_auth_phone AND id <> auth.uid()
    ) THEN v_auth_phone := NULL; END IF;

    v_name  := COALESCE((SELECT name FROM shell_control.users WHERE id = auth.uid()), v_full);
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


-- ── Admin: list my org's requests (for the admin UI) ────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_list_outgoing_requests(p_org_id uuid)
RETURNS TABLE (request_id uuid, worker_phone text, status text, note text,
               requested_at timestamptz, responded_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;
  RETURN QUERY
  SELECT r.id, r.worker_phone, r.status, r.note, r.requested_at, r.responded_at
  FROM   public.org_access_requests r
  WHERE  r.org_id = p_org_id
  ORDER  BY r.requested_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_list_outgoing_requests(uuid) TO authenticated;


-- ── Admin: cancel a pending request ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_cancel_access_request(p_request_id uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_req public.org_access_requests;
BEGIN
  SELECT * INTO v_req FROM public.org_access_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.is_org_admin(v_req.org_id) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'request_not_pending' USING ERRCODE = 'P0008'; END IF;
  UPDATE public.org_access_requests SET status = 'cancelled', responded_at = now() WHERE id = p_request_id;
  RETURN 'cancelled';
END;
$$;
GRANT EXECUTE ON FUNCTION public.eq_cards_cancel_access_request(uuid) TO authenticated;
