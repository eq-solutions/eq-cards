-- eq_cards_upsert_my_worker previously did INSERT ... ON CONFLICT (user_id) with no
-- orphan-adoption step. When an admin pre-creates a worker shell (user_id=null) and
-- the worker later fills in their profile, a duplicate row was created because the
-- insert keyed only on user_id, never checked existing unlinked rows by phone/email.
--
-- Fix: call eq_cards_link_or_create_worker first (which adopts by normalised phone
-- or email), then UPDATE the returned row with the full profile payload. The duplicate
-- path is now impossible — there is always exactly one row before the UPDATE runs.

CREATE OR REPLACE FUNCTION public.eq_cards_upsert_my_worker(
  p_first_name              text,
  p_last_name               text,
  p_email                   text,
  p_phone                   text,
  p_date_of_birth           date,
  p_preferred_name          text,
  p_address_street          text,
  p_address_suburb          text,
  p_address_state           text,
  p_address_postcode        text,
  p_emergency_contact_name  text,
  p_emergency_contact_phone text,
  p_emergency_contact_relationship text,
  p_right_to_work_type      worker_rtw_type,
  p_right_to_work_expiry    date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  -- Adopt an existing unlinked shell (pre-created by admin) if one matches
  -- on normalised phone or email, then link it to this auth user.
  -- If no orphan exists, creates a new row. Either way returns the worker id.
  v_id := public.eq_cards_link_or_create_worker(
    auth.uid(),
    p_phone,
    p_email,
    COALESCE(NULLIF(p_first_name, ''), 'Unknown'),
    COALESCE(p_last_name, '')
  );

  -- Update the (now-linked) row with the full profile payload.
  UPDATE public.workers SET
    first_name                   = p_first_name,
    last_name                    = p_last_name,
    email                        = p_email,
    phone                        = COALESCE(p_phone, phone),
    date_of_birth                = COALESCE(p_date_of_birth, date_of_birth),
    preferred_name               = COALESCE(p_preferred_name, preferred_name),
    address_street               = COALESCE(p_address_street, address_street),
    address_suburb               = COALESCE(p_address_suburb, address_suburb),
    address_state                = COALESCE(p_address_state, address_state),
    address_postcode             = COALESCE(p_address_postcode, address_postcode),
    emergency_contact_name       = COALESCE(p_emergency_contact_name, emergency_contact_name),
    emergency_contact_phone      = COALESCE(p_emergency_contact_phone, emergency_contact_phone),
    emergency_contact_relationship = COALESCE(p_emergency_contact_relationship, emergency_contact_relationship),
    right_to_work_type           = COALESCE(p_right_to_work_type, right_to_work_type),
    right_to_work_expiry         = COALESCE(p_right_to_work_expiry, right_to_work_expiry),
    updated_at                   = now()
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
