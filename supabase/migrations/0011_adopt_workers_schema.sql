-- 0011_adopt_workers_schema.sql
--
-- Adopts the workers/worker_credentials schema (built 2026-06-01) as the
-- primary model for the admin onboarding flow, replacing the profiles/licences
-- target in 0010_admin_onboarding.
--
-- Changes:
--   1. workers.user_id → nullable (admin can pre-create before auth exists)
--   2. worker_invites gets a worker_id FK (replaces JSONB snapshot approach)
--   3. worker_credential_type enum extended for all training matrix columns
--   4. Admin RPCs: eq_cards_admin_upsert_worker, eq_cards_admin_upsert_worker_credential
--   5. eq_cards_claim_invite updated to link workers.user_id + org membership

-- ============================================================
-- 1. Make workers.user_id nullable
--    Allows admin to pre-create a worker record before the
--    person has a Supabase auth account.
-- ============================================================

ALTER TABLE public.workers
  ALTER COLUMN user_id DROP NOT NULL;

CREATE UNIQUE INDEX workers_user_id_unique
  ON public.workers (user_id)
  WHERE user_id IS NOT NULL;

-- ============================================================
-- 2. Add worker_id to worker_invites
--    The invite now references a pre-created worker record.
--    profile_data/licences_data kept for fallback but worker_id
--    is the preferred path.
-- ============================================================

ALTER TABLE public.worker_invites
  ADD COLUMN worker_id uuid REFERENCES public.workers(id) ON DELETE CASCADE;

CREATE INDEX worker_invites_worker_idx ON public.worker_invites (worker_id)
  WHERE worker_id IS NOT NULL;

-- ============================================================
-- 3. Extend worker_credential_type enum
--    Adds all training matrix credential types not already present.
-- ============================================================

ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'open_cabling';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'scissor_lift';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'boom_lift';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'vertical_lift';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'hrwl_boom_11m';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'hrwl_dogging';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'riw';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'lvr';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'hv_switching';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'hv_operators';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'manual_handling';
ALTER TYPE public.worker_credential_type ADD VALUE IF NOT EXISTS 'silica_awareness';

-- ============================================================
-- 4. eq_cards_admin_upsert_worker
--    Admin creates or updates a worker record on behalf of
--    someone who may not have an auth account yet.
--    Requires caller to be an active admin of p_org_id.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_upsert_worker(
  p_org_id    uuid,
  p_payload   jsonb
)
RETURNS SETOF public.workers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id uuid;
  v_row       public.workers;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501';
  END IF;

  v_worker_id := (p_payload->>'id')::uuid;

  IF v_worker_id IS NOT NULL THEN
    -- Update existing worker
    UPDATE public.workers SET
      first_name                     = COALESCE(p_payload->>'first_name',                     first_name),
      last_name                      = COALESCE(p_payload->>'last_name',                      last_name),
      preferred_name                 = COALESCE(p_payload->>'preferred_name',                 preferred_name),
      email                          = COALESCE(p_payload->>'email',                          email),
      phone                          = COALESCE(p_payload->>'phone',                          phone),
      date_of_birth                  = COALESCE((p_payload->>'date_of_birth')::date,          date_of_birth),
      address_street                 = COALESCE(p_payload->>'address_street',                 address_street),
      address_suburb                 = COALESCE(p_payload->>'address_suburb',                 address_suburb),
      address_state                  = COALESCE(p_payload->>'address_state',                  address_state),
      address_postcode               = COALESCE(p_payload->>'address_postcode',               address_postcode),
      emergency_contact_name         = COALESCE(p_payload->>'emergency_contact_name',         emergency_contact_name),
      emergency_contact_phone        = COALESCE(p_payload->>'emergency_contact_phone',        emergency_contact_phone),
      emergency_contact_relationship = COALESCE(p_payload->>'emergency_contact_relationship', emergency_contact_relationship),
      right_to_work_type             = COALESCE((p_payload->>'right_to_work_type')::right_to_work_type, right_to_work_type),
      right_to_work_expiry           = COALESCE((p_payload->>'right_to_work_expiry')::date,   right_to_work_expiry),
      updated_at                     = now()
    WHERE id = v_worker_id
    RETURNING * INTO v_row;

    IF v_row IS NULL THEN
      RAISE EXCEPTION 'worker_not_found' USING ERRCODE = 'P0002';
    END IF;
  ELSE
    -- Create new worker (no user_id — will be linked at claim time)
    INSERT INTO public.workers (
      first_name, last_name, preferred_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship,
      right_to_work_type, right_to_work_expiry
    ) VALUES (
      p_payload->>'first_name',
      p_payload->>'last_name',
      p_payload->>'preferred_name',
      p_payload->>'email',
      p_payload->>'phone',
      (p_payload->>'date_of_birth')::date,
      p_payload->>'address_street',
      p_payload->>'address_suburb',
      p_payload->>'address_state',
      p_payload->>'address_postcode',
      p_payload->>'emergency_contact_name',
      p_payload->>'emergency_contact_phone',
      p_payload->>'emergency_contact_relationship',
      (p_payload->>'right_to_work_type')::right_to_work_type,
      (p_payload->>'right_to_work_expiry')::date
    )
    RETURNING * INTO v_row;
  END IF;

  RETURN NEXT v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_upsert_worker(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_upsert_worker(uuid, jsonb) TO authenticated;

-- ============================================================
-- 5. eq_cards_admin_upsert_worker_credential
--    Admin adds or updates a credential on a pre-created worker.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_upsert_worker_credential(
  p_org_id        uuid,
  p_worker_id     uuid,
  p_payload       jsonb
)
RETURNS SETOF public.worker_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id     uuid;
  v_status public.worker_credential_status;
  v_row    public.worker_credentials;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501';
  END IF;

  v_id := (p_payload->>'id')::uuid;

  -- Auto-compute status from expiry date
  v_status := CASE
    WHEN (p_payload->>'expiry_date')::date IS NOT NULL
      AND (p_payload->>'expiry_date')::date < CURRENT_DATE THEN 'expired'::worker_credential_status
    ELSE 'active'::worker_credential_status
  END;

  IF v_id IS NOT NULL THEN
    UPDATE public.worker_credentials SET
      credential_type  = COALESCE((p_payload->>'credential_type')::worker_credential_type, credential_type),
      licence_number   = COALESCE(p_payload->>'licence_number',   licence_number),
      issuing_body     = COALESCE(p_payload->>'issuing_body',     issuing_body),
      state_territory  = COALESCE(p_payload->>'state_territory',  state_territory),
      issue_date       = COALESCE((p_payload->>'issue_date')::date, issue_date),
      expiry_date      = COALESCE((p_payload->>'expiry_date')::date, expiry_date),
      notes            = COALESCE(p_payload->>'notes',            notes),
      metadata         = COALESCE(p_payload->'metadata',          metadata),
      status           = v_status,
      updated_at       = now()
    WHERE id = v_id AND worker_id = p_worker_id
    RETURNING * INTO v_row;
  ELSE
    INSERT INTO public.worker_credentials (
      worker_id, credential_type, licence_number, issuing_body,
      state_territory, issue_date, expiry_date, notes, metadata, status
    ) VALUES (
      p_worker_id,
      (p_payload->>'credential_type')::worker_credential_type,
      p_payload->>'licence_number',
      p_payload->>'issuing_body',
      p_payload->>'state_territory',
      (p_payload->>'issue_date')::date,
      (p_payload->>'expiry_date')::date,
      p_payload->>'notes',
      COALESCE(p_payload->'metadata', '{}'::jsonb),
      v_status
    )
    RETURNING * INTO v_row;
  END IF;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'credential_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN NEXT v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_upsert_worker_credential(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_upsert_worker_credential(uuid, uuid, jsonb) TO authenticated;

-- ============================================================
-- 6. eq_cards_admin_list_workers
--    Returns all pre-created (unclaimed) and active workers in the org.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_list_workers(p_org_id uuid)
RETURNS SETOF public.workers
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT w.* FROM public.workers w
  JOIN public.org_memberships m ON m.user_id = w.user_id AND m.org_id = p_org_id
  WHERE public.is_org_admin(p_org_id)
    AND m.status IN ('active', 'pending')
  UNION ALL
  -- Also return pre-created workers (no user_id yet) linked via invite
  SELECT w.* FROM public.workers w
  JOIN public.worker_invites i ON i.worker_id = w.id AND i.org_id = p_org_id
  WHERE public.is_org_admin(p_org_id)
    AND w.user_id IS NULL
    AND i.claimed_at IS NULL
  ORDER BY last_name, first_name;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_list_workers(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_list_workers(uuid) TO authenticated;

-- ============================================================
-- 7. Replace eq_cards_claim_invite
--    Now links workers.user_id instead of creating a profiles row.
--    Falls back to JSONB snapshot if no worker_id on the invite
--    (backwards compat with any invites created before this migration).
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_claim_invite(p_token uuid)
RETURNS SETOF public.workers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite  public.worker_invites;
  v_worker  public.workers;
  v_licence jsonb;
  v_status  public.worker_credential_status;
BEGIN
  SELECT * INTO v_invite
  FROM public.worker_invites
  WHERE token = p_token
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_invite.claimed_at IS NOT NULL THEN
    RAISE EXCEPTION 'invite_already_claimed' USING ERRCODE = 'P0003';
  END IF;

  IF v_invite.expires_at < now() THEN
    RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0004';
  END IF;

  IF v_invite.worker_id IS NOT NULL THEN
    -- Primary path: link pre-created worker record to this auth user
    UPDATE public.workers
    SET user_id = auth.uid(), updated_at = now()
    WHERE id = v_invite.worker_id
      AND user_id IS NULL  -- only claim unclaimed records
    RETURNING * INTO v_worker;

    IF v_worker IS NULL THEN
      -- Worker record was already claimed (re-try scenario)
      SELECT * INTO v_worker FROM public.workers WHERE id = v_invite.worker_id;
      IF v_worker.user_id != auth.uid() THEN
        RAISE EXCEPTION 'worker_already_claimed_by_another_user' USING ERRCODE = 'P0005';
      END IF;
    END IF;
  ELSE
    -- Fallback: create worker from JSONB snapshot (pre-0011 invites)
    INSERT INTO public.workers (
      user_id, first_name, last_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship
    ) VALUES (
      auth.uid(),
      v_invite.profile_data->>'first_name',
      COALESCE(v_invite.profile_data->>'last_name', v_invite.profile_data->>'full_name'),
      v_invite.profile_data->>'email',
      v_invite.profile_data->>'mobile',
      (v_invite.profile_data->>'date_of_birth')::date,
      v_invite.profile_data->>'address_street',
      v_invite.profile_data->>'address_suburb',
      v_invite.profile_data->>'address_state',
      v_invite.profile_data->>'address_postcode',
      v_invite.profile_data->>'emergency_contact_name',
      v_invite.profile_data->>'emergency_contact_mobile',
      v_invite.profile_data->>'emergency_contact_relationship'
    )
    ON CONFLICT (user_id) WHERE user_id IS NOT NULL DO UPDATE SET
      updated_at = now()
    RETURNING * INTO v_worker;

    -- Create credentials from JSONB licences_data snapshot
    FOR v_licence IN SELECT value FROM jsonb_array_elements(v_invite.licences_data)
    LOOP
      CONTINUE WHEN v_licence->>'credential_type' IS NULL
                AND v_licence->>'licence_type' IS NULL;

      v_status := CASE
        WHEN (v_licence->>'expiry_date')::date IS NOT NULL
          AND (v_licence->>'expiry_date')::date < CURRENT_DATE THEN 'expired'::worker_credential_status
        ELSE 'active'::worker_credential_status
      END;

      INSERT INTO public.worker_credentials (
        worker_id, credential_type, licence_number,
        expiry_date, notes, metadata, status
      ) VALUES (
        v_worker.id,
        COALESCE(v_licence->>'credential_type', v_licence->>'licence_type')::worker_credential_type,
        v_licence->>'licence_number',
        (v_licence->>'expiry_date')::date,
        v_licence->>'notes',
        COALESCE(v_licence->'metadata', '{}'::jsonb),
        v_status
      )
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  -- Link to org (upsert active membership)
  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_invite.org_id, auth.uid(), 'member', 'active', v_invite.created_by, now())
  ON CONFLICT (org_id, user_id) WHERE status != 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- Mark invite claimed
  UPDATE public.worker_invites
  SET claimed_at = now(), claimed_by = auth.uid()
  WHERE id = v_invite.id;

  RETURN NEXT v_worker;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_claim_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_claim_invite(uuid) TO authenticated;

-- ============================================================
-- 8. Update eq_cards_admin_create_invite to accept worker_id
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_create_invite(
  p_org_id        uuid,
  p_worker_id     uuid    DEFAULT NULL,
  p_profile_data  jsonb   DEFAULT '{}',
  p_licences_data jsonb   DEFAULT '[]'
)
RETURNS TABLE (invite_id uuid, token uuid, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite public.worker_invites;
BEGIN
  IF NOT public.is_org_admin(p_org_id) THEN
    RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.worker_invites (org_id, worker_id, profile_data, licences_data, created_by)
  VALUES (p_org_id, p_worker_id, p_profile_data, p_licences_data, auth.uid())
  RETURNING * INTO v_invite;

  RETURN QUERY SELECT v_invite.id, v_invite.token, v_invite.expires_at;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_create_invite(uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_create_invite(uuid, uuid, jsonb, jsonb) TO authenticated;
