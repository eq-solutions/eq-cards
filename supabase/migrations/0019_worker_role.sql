-- 0019_worker_role.sql
--
-- Write side of role-on-invite (pairs with 0018, which is the read side).
--
-- 0018 made eq_cards_claim_invite read profile_data->>'role', but nothing wrote
-- it — every claimer still became 'employee'. This migration makes the worker
-- profile the source of truth for role:
--   1. workers.role (eq_role, nullable) — admin sets it when pre-populating.
--   2. eq_cards_admin_upsert_worker persists payload.role.
--   3. eq_cards_admin_create_invite copies the worker's role into
--      profile_data.role, so the claim RPC (0018) reads it on activation.
--
-- Nullable + no backfill: a worker with no role → invite carries no role →
-- claim defaults to 'employee' (unchanged behaviour for the existing 59 invites).

-- 1. Role lives on the worker.
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS role public.eq_role;

COMMENT ON COLUMN public.workers.role IS
  'Intended eq_role for this worker; copied into the invite and applied on claim. Null → claim defaults to employee.';

-- 2. Persist role through the admin upsert. (Only the role lines are new vs the
--    prior definition; every other column is copied verbatim.)
CREATE OR REPLACE FUNCTION public.eq_cards_admin_upsert_worker(p_org_id uuid, p_payload jsonb)
 RETURNS SETOF workers LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_worker_id uuid; v_row public.workers;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501'; END IF;
  v_worker_id := (p_payload->>'id')::uuid;
  IF v_worker_id IS NOT NULL THEN
    UPDATE public.workers SET
      first_name = COALESCE(p_payload->>'first_name', first_name),
      last_name = COALESCE(p_payload->>'last_name', last_name),
      preferred_name = COALESCE(p_payload->>'preferred_name', preferred_name),
      email = COALESCE(p_payload->>'email', email),
      phone = COALESCE(p_payload->>'phone', phone),
      date_of_birth = COALESCE((p_payload->>'date_of_birth')::date, date_of_birth),
      address_street = COALESCE(p_payload->>'address_street', address_street),
      address_suburb = COALESCE(p_payload->>'address_suburb', address_suburb),
      address_state = COALESCE(p_payload->>'address_state', address_state),
      address_postcode = COALESCE(p_payload->>'address_postcode', address_postcode),
      emergency_contact_name = COALESCE(p_payload->>'emergency_contact_name', emergency_contact_name),
      emergency_contact_phone = COALESCE(p_payload->>'emergency_contact_phone', emergency_contact_phone),
      emergency_contact_relationship = COALESCE(p_payload->>'emergency_contact_relationship', emergency_contact_relationship),
      right_to_work_expiry = COALESCE((p_payload->>'right_to_work_expiry')::date, right_to_work_expiry),
      role = COALESCE((p_payload->>'role')::public.eq_role, role),
      updated_at = now()
    WHERE id = v_worker_id RETURNING * INTO v_row;
    IF v_row IS NULL THEN RAISE EXCEPTION 'worker_not_found' USING ERRCODE = 'P0002'; END IF;
  ELSE
    INSERT INTO public.workers (first_name, last_name, preferred_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship, role)
    VALUES (p_payload->>'first_name', p_payload->>'last_name', p_payload->>'preferred_name',
      p_payload->>'email', p_payload->>'phone', (p_payload->>'date_of_birth')::date,
      p_payload->>'address_street', p_payload->>'address_suburb', p_payload->>'address_state',
      p_payload->>'address_postcode', p_payload->>'emergency_contact_name',
      p_payload->>'emergency_contact_phone', p_payload->>'emergency_contact_relationship',
      (p_payload->>'role')::public.eq_role)
    RETURNING * INTO v_row;
  END IF;
  RETURN NEXT v_row;
END; $function$;

-- 3. Copy the worker's role into the invite so claim (0018) applies it.
--    An explicit role in p_profile_data is honoured only when the worker has none.
CREATE OR REPLACE FUNCTION public.eq_cards_admin_create_invite(p_org_id uuid, p_worker_id uuid DEFAULT NULL::uuid, p_profile_data jsonb DEFAULT '{}'::jsonb, p_licences_data jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(invite_id uuid, token uuid, expires_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_invite public.worker_invites; v_role text;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501'; END IF;

  IF p_worker_id IS NOT NULL THEN
    SELECT role::text INTO v_role FROM public.workers WHERE id = p_worker_id;
  END IF;
  v_role := COALESCE(v_role, p_profile_data->>'role');
  IF v_role IS NOT NULL THEN
    p_profile_data := p_profile_data || jsonb_build_object('role', v_role);
  END IF;

  INSERT INTO public.worker_invites (org_id, worker_id, profile_data, licences_data, created_by)
  VALUES (p_org_id, p_worker_id, p_profile_data, p_licences_data, auth.uid())
  RETURNING * INTO v_invite;
  RETURN QUERY SELECT v_invite.id, v_invite.token, v_invite.expires_at;
END; $function$;
