-- Update eq_cards_upsert_my_licence to write never_expires and is_private.
-- Both columns were added (0021, 0046) but the RPC was never updated to accept them.
-- Effect: toggling never_expires in the edit screen and is_private from the wallet
-- tile now actually persist to the DB.
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
      licence_type      = COALESCE(p_payload->>'licence_type',       licence_type),
      licence_number    = COALESCE(p_payload->>'licence_number',     licence_number),
      issue_date        = COALESCE((p_payload->>'issue_date')::date,  issue_date),
      expiry_date       = COALESCE((p_payload->>'expiry_date')::date, expiry_date),
      issuing_authority = p_payload->>'issuing_authority',
      state             = p_payload->>'state',
      photo_front_url   = COALESCE(p_payload->>'photo_front_url',    photo_front_url),
      photo_back_url    = COALESCE(p_payload->>'photo_back_url',     photo_back_url),
      notes             = p_payload->>'notes',
      metadata          = COALESCE(p_payload->'metadata',            metadata),
      never_expires     = COALESCE((p_payload->>'never_expires')::boolean, never_expires),
      is_private        = COALESCE((p_payload->>'is_private')::boolean,    is_private),
      updated_at        = now()
    WHERE id = v_id AND user_id = auth.uid()
    RETURNING * INTO v_row;
  ELSE
    INSERT INTO public.licences (
      user_id, licence_type, licence_number, issue_date, expiry_date,
      issuing_authority, state, photo_front_url, photo_back_url, notes, metadata,
      never_expires, is_private
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
      COALESCE(p_payload->'metadata', '{}'::jsonb),
      COALESCE((p_payload->>'never_expires')::boolean, false),
      COALESCE((p_payload->>'is_private')::boolean, false)
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
