-- 0010_admin_onboarding.sql
--
-- Admin-led worker onboarding flow:
--
--   1. Admin creates an invite (profile data + licence list pre-filled).
--   2. A claim token (UUID) is generated with a 14-day TTL.
--   3. Admin shares the claim link; worker authenticates and calls
--      eq_cards_claim_invite() — profile + licences are created atomically.
--
-- Design decisions:
--
--   • worker_invites holds all profile + licence data as JSONB snapshots.
--     No stub auth user is needed before the worker claims — the token IS
--     the pre-auth identity.
--
--   • licences.licence_number / issue_date / expiry_date relaxed to nullable.
--     Training matrix entries often have no number or date (just "held").
--     Existing worker-entry RPCs are unaffected; callers that previously
--     sent non-null values continue to work.
--
--   • All admin RPCs are SECURITY DEFINER and perform explicit is_org_admin()
--     checks so they can bypass the per-row RLS on profiles and licences.

-- ============================================================
-- 1. Relax NOT NULL constraints on licences
--    (many training-matrix entries have no number / no expiry)
-- ============================================================

ALTER TABLE public.licences
  ALTER COLUMN licence_number DROP NOT NULL,
  ALTER COLUMN issue_date     DROP NOT NULL,
  ALTER COLUMN expiry_date    DROP NOT NULL;

-- ============================================================
-- 2. Add title to profiles (job title / trade)
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS title text;

-- ============================================================
-- 3. worker_invites table
-- ============================================================

CREATE TABLE public.worker_invites (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid        NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  token          uuid        NOT NULL DEFAULT gen_random_uuid(),
  profile_data   jsonb       NOT NULL DEFAULT '{}',
  licences_data  jsonb       NOT NULL DEFAULT '[]',
  created_by     uuid        NOT NULL REFERENCES auth.users(id),
  expires_at     timestamptz NOT NULL DEFAULT now() + interval '14 days',
  claimed_at     timestamptz,
  claimed_by     uuid        REFERENCES auth.users(id),
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX worker_invites_token_unique ON public.worker_invites (token);
CREATE INDEX worker_invites_org_idx             ON public.worker_invites (org_id);
CREATE INDEX worker_invites_unclaimed_idx
  ON public.worker_invites (org_id, expires_at)
  WHERE claimed_at IS NULL;

ALTER TABLE public.worker_invites ENABLE ROW LEVEL SECURITY;

-- Admins can view invites in their org
CREATE POLICY "admins_read_org_invites"
  ON public.worker_invites FOR SELECT
  USING (public.is_org_admin(org_id));

-- Admins can create invites
CREATE POLICY "admins_insert_org_invites"
  ON public.worker_invites FOR INSERT
  WITH CHECK (public.is_org_admin(org_id));

-- Admins can update invites (revoke / extend)
CREATE POLICY "admins_update_org_invites"
  ON public.worker_invites FOR UPDATE
  USING (public.is_org_admin(org_id));

-- ============================================================
-- 4. eq_cards_admin_create_invite
--    Admin pre-fills a worker's profile + licences and gets back a
--    claim token. The token is embedded in the deep-link sent to the worker.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_create_invite(
  p_org_id        uuid,
  p_profile_data  jsonb,
  p_licences_data jsonb DEFAULT '[]'
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

  INSERT INTO public.worker_invites (org_id, profile_data, licences_data, created_by)
  VALUES (p_org_id, p_profile_data, p_licences_data, auth.uid())
  RETURNING * INTO v_invite;

  RETURN QUERY SELECT v_invite.id, v_invite.token, v_invite.expires_at;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_create_invite(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_create_invite(uuid, jsonb, jsonb) TO authenticated;

-- ============================================================
-- 5. eq_cards_admin_list_invites
--    Returns all invites for the org, newest first.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_list_invites(p_org_id uuid)
RETURNS SETOF public.worker_invites
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT * FROM public.worker_invites
  WHERE org_id = p_org_id
    AND public.is_org_admin(p_org_id)
  ORDER BY created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_list_invites(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_list_invites(uuid) TO authenticated;

-- ============================================================
-- 6. eq_cards_admin_revoke_invite
--    Admin invalidates an unused invite (e.g. to re-issue).
--    Sets expires_at to now() so the token is immediately dead.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_admin_revoke_invite(p_invite_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.worker_invites
  SET expires_at = now() - interval '1 second'
  WHERE id          = p_invite_id
    AND claimed_at  IS NULL
    AND public.is_org_admin(org_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invite_not_found_or_already_claimed' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_admin_revoke_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_admin_revoke_invite(uuid) TO authenticated;

-- ============================================================
-- 7. eq_cards_claim_invite
--    Worker calls this immediately after authenticating.
--    Validates the token, creates their profile + licences, links
--    them to the org, and marks the invite claimed — all in one
--    transaction so a partial failure leaves no orphaned rows.
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_claim_invite(p_token uuid)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite  public.worker_invites;
  v_profile public.profiles;
  v_licence jsonb;
BEGIN
  -- Lock the invite to prevent concurrent claims
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

  -- Create profile from invite snapshot (upsert so re-claiming after
  -- a partial failure is safe — idempotent on the profile row)
  INSERT INTO public.profiles (
    id,
    full_name,
    date_of_birth,
    mobile,
    email,
    title,
    address_street,
    address_suburb,
    address_state,
    address_postcode,
    emergency_contact_name,
    emergency_contact_relationship,
    emergency_contact_mobile
  ) VALUES (
    auth.uid(),
    v_invite.profile_data->>'full_name',
    (v_invite.profile_data->>'date_of_birth')::date,
    v_invite.profile_data->>'mobile',
    v_invite.profile_data->>'email',
    v_invite.profile_data->>'title',
    v_invite.profile_data->>'address_street',
    v_invite.profile_data->>'address_suburb',
    v_invite.profile_data->>'address_state',
    v_invite.profile_data->>'address_postcode',
    v_invite.profile_data->>'emergency_contact_name',
    v_invite.profile_data->>'emergency_contact_relationship',
    v_invite.profile_data->>'emergency_contact_mobile'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name                      = COALESCE(EXCLUDED.full_name,                      profiles.full_name),
    date_of_birth                  = COALESCE(EXCLUDED.date_of_birth,                  profiles.date_of_birth),
    mobile                         = COALESCE(EXCLUDED.mobile,                         profiles.mobile),
    email                          = COALESCE(EXCLUDED.email,                          profiles.email),
    title                          = COALESCE(EXCLUDED.title,                          profiles.title),
    address_street                 = COALESCE(EXCLUDED.address_street,                 profiles.address_street),
    address_suburb                 = COALESCE(EXCLUDED.address_suburb,                 profiles.address_suburb),
    address_state                  = COALESCE(EXCLUDED.address_state,                  profiles.address_state),
    address_postcode               = COALESCE(EXCLUDED.address_postcode,               profiles.address_postcode),
    emergency_contact_name         = COALESCE(EXCLUDED.emergency_contact_name,         profiles.emergency_contact_name),
    emergency_contact_relationship = COALESCE(EXCLUDED.emergency_contact_relationship, profiles.emergency_contact_relationship),
    emergency_contact_mobile       = COALESCE(EXCLUDED.emergency_contact_mobile,       profiles.emergency_contact_mobile),
    updated_at                     = now()
  RETURNING * INTO v_profile;

  -- Insert pre-filled licences (skip if licence_type is missing)
  FOR v_licence IN SELECT value FROM jsonb_array_elements(v_invite.licences_data)
  LOOP
    CONTINUE WHEN v_licence->>'licence_type' IS NULL;
    INSERT INTO public.licences (
      user_id,
      licence_type,
      licence_number,
      expiry_date,
      issuing_authority,
      state,
      notes,
      metadata
    ) VALUES (
      auth.uid(),
      v_licence->>'licence_type',
      v_licence->>'licence_number',
      (v_licence->>'expiry_date')::date,
      v_licence->>'issuing_authority',
      v_licence->>'state',
      v_licence->>'notes',
      COALESCE(v_licence->'metadata', '{}'::jsonb)
    )
    -- If the worker re-claims (e.g. retry after network drop) skip dupes
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Link worker to org: promote a pending membership if one exists,
  -- otherwise insert a fresh active membership.
  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_invite.org_id, auth.uid(), 'member', 'active', v_invite.created_by, now())
  ON CONFLICT (org_id, user_id) WHERE status != 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- Mark invite claimed
  UPDATE public.worker_invites
  SET claimed_at = now(), claimed_by = auth.uid()
  WHERE id = v_invite.id;

  RETURN NEXT v_profile;
END;
$$;

-- Claim requires an authenticated session: EXECUTE is REVOKEd from PUBLIC/anon
-- and granted only to `authenticated`. The worker signs in before the app calls
-- this RPC, and the function additionally enforces auth.uid() internally.
-- (An earlier version of this comment wrongly stated anon could call it.)
REVOKE ALL ON FUNCTION public.eq_cards_claim_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_claim_invite(uuid) TO authenticated;

-- ============================================================
-- 8. Update eq_cards_upsert_my_licence to handle nullable fields
--    (licence_number / issue_date / expiry_date now optional)
-- ============================================================

CREATE OR REPLACE FUNCTION public.eq_cards_upsert_my_licence(p_payload jsonb)
RETURNS SETOF public.licences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id  uuid;
  v_row public.licences;
BEGIN
  v_id := (p_payload->>'id')::uuid;

  IF v_id IS NOT NULL THEN
    UPDATE public.licences SET
      licence_type      = COALESCE(p_payload->>'licence_type',      licence_type),
      licence_number    = COALESCE(p_payload->>'licence_number',    licence_number),
      issue_date        = COALESCE((p_payload->>'issue_date')::date, issue_date),
      expiry_date       = COALESCE((p_payload->>'expiry_date')::date, expiry_date),
      issuing_authority = p_payload->>'issuing_authority',
      state             = p_payload->>'state',
      photo_front_url   = COALESCE(p_payload->>'photo_front_url',   photo_front_url),
      photo_back_url    = COALESCE(p_payload->>'photo_back_url',    photo_back_url),
      notes             = p_payload->>'notes',
      metadata          = COALESCE(p_payload->'metadata',           metadata),
      updated_at        = now()
    WHERE id = v_id AND user_id = auth.uid()
    RETURNING * INTO v_row;
  ELSE
    INSERT INTO public.licences (
      user_id, licence_type, licence_number, issue_date, expiry_date,
      issuing_authority, state, photo_front_url, photo_back_url, notes, metadata
    ) VALUES (
      auth.uid(),
      p_payload->>'licence_type',
      p_payload->>'licence_number',
      (p_payload->>'issue_date')::date,
      (p_payload->>'expiry_date')::date,
      p_payload->>'issuing_authority',
      p_payload->>'state',
      p_payload->>'photo_front_url',
      p_payload->>'photo_back_url',
      p_payload->>'notes',
      COALESCE(p_payload->'metadata', '{}'::jsonb)
    )
    RETURNING * INTO v_row;
  END IF;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'licence not found or not owned by caller';
  END IF;

  RETURN NEXT v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_upsert_my_licence(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_upsert_my_licence(jsonb) TO authenticated;
