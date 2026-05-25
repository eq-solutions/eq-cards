-- 0008_restore_eq_cards_rpcs.sql
--
-- Restores the five eq_cards_* RPCs that were dropped by CASCADE when
-- the app_data schema was removed (2026-05-25, arch-v2 Phase 2.B.7).
--
-- The original RPCs bridged app_data.staff → Flutter models. Now that
-- public.profiles and public.licences directly match the Flutter model
-- shapes, these are simple pass-through wrappers — no column renaming
-- needed.
--
-- Applied to eq-canonical (jvknxcmbtrfnxfrwfimn) via Supabase MCP.

-- ────────────────────────────────────────────────────────────
-- eq_cards_list_my_licences
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_list_my_licences()
RETURNS SETOF public.licences
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT * FROM public.licences
  WHERE user_id = auth.uid()
    AND deleted_at IS NULL
  ORDER BY created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_list_my_licences() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_list_my_licences() TO authenticated;

-- ────────────────────────────────────────────────────────────
-- eq_cards_upsert_my_licence
-- ────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────
-- eq_cards_soft_delete_my_licence
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_soft_delete_my_licence(p_licence_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.licences
  SET deleted_at = now()
  WHERE id = p_licence_id
    AND user_id = auth.uid()
    AND deleted_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_soft_delete_my_licence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_soft_delete_my_licence(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- eq_cards_current_staff
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_current_staff()
RETURNS SETOF public.profiles
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT * FROM public.profiles
  WHERE id = auth.uid()
    AND deleted_at IS NULL;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_current_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_current_staff() TO authenticated;

-- ────────────────────────────────────────────────────────────
-- eq_cards_upsert_my_profile
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.eq_cards_upsert_my_profile(p_payload jsonb)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.profiles;
BEGIN
  INSERT INTO public.profiles (
    id, full_name, date_of_birth, mobile, email,
    address_street, address_suburb, address_state, address_postcode,
    emergency_contact_name, emergency_contact_relationship, emergency_contact_mobile
  ) VALUES (
    auth.uid(),
    p_payload->>'full_name',
    (p_payload->>'date_of_birth')::date,
    p_payload->>'mobile',
    p_payload->>'email',
    p_payload->>'address_street',
    p_payload->>'address_suburb',
    p_payload->>'address_state',
    p_payload->>'address_postcode',
    p_payload->>'emergency_contact_name',
    p_payload->>'emergency_contact_relationship',
    p_payload->>'emergency_contact_mobile'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name                      = COALESCE(EXCLUDED.full_name,                      profiles.full_name),
    date_of_birth                  = COALESCE(EXCLUDED.date_of_birth,                  profiles.date_of_birth),
    mobile                         = COALESCE(EXCLUDED.mobile,                         profiles.mobile),
    email                          = COALESCE(EXCLUDED.email,                          profiles.email),
    address_street                 = COALESCE(EXCLUDED.address_street,                 profiles.address_street),
    address_suburb                 = COALESCE(EXCLUDED.address_suburb,                 profiles.address_suburb),
    address_state                  = COALESCE(EXCLUDED.address_state,                  profiles.address_state),
    address_postcode               = COALESCE(EXCLUDED.address_postcode,               profiles.address_postcode),
    emergency_contact_name         = COALESCE(EXCLUDED.emergency_contact_name,         profiles.emergency_contact_name),
    emergency_contact_relationship = COALESCE(EXCLUDED.emergency_contact_relationship, profiles.emergency_contact_relationship),
    emergency_contact_mobile       = COALESCE(EXCLUDED.emergency_contact_mobile,       profiles.emergency_contact_mobile),
    updated_at                     = now()
  RETURNING * INTO v_row;

  RETURN NEXT v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.eq_cards_upsert_my_profile(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eq_cards_upsert_my_profile(jsonb) TO authenticated;
