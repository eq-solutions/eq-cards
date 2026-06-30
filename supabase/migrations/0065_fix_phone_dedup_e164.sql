-- 0065_fix_phone_dedup_e164.sql
--
-- BUG: handle_phone_dedup was near-inert for all real signups.
-- Supabase stores auth.users.phone in E.164 (+61412345678). The trigger
-- had two early exits that both fired on E.164 input:
--   1. `IF NEW.phone LIKE '+%' THEN RETURN NEW` — explicit E.164 skip
--   2. `IF v_normalised = NEW.phone THEN RETURN NEW` — normalise_au_phone
--      returns E.164 unchanged, so this also fired
--
-- FIX:
--   1. Remove the `LIKE '+%'` exit — E.164 is valid input, not a skip signal
--   2. Change bypass check: only skip if format is unrecognised AND non-E.164
--   3. Normalise both sides in orphan search (scu.phone may be local format
--      0412... from admin pre-population while signup arrives as +61412...)

CREATE OR REPLACE FUNCTION public.handle_phone_dedup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_normalised   text;
  v_source_id    uuid;
  v_is_orphan    boolean := false;
  v_source_email text;
BEGIN
  -- Skip rows with no phone
  IF NEW.phone IS NULL OR NEW.phone = '' THEN
    RETURN NEW;
  END IF;

  v_normalised := shell_control.normalise_au_phone(NEW.phone);

  -- Only skip if normalise couldn't recognise the format AND it's not E.164.
  -- Old code also exited for `LIKE '+%'`, making the trigger inert for all
  -- real signups (Supabase stores phones in E.164 +61...).
  IF v_normalised = NEW.phone AND NEW.phone NOT LIKE '+%' THEN
    RETURN NEW;
  END IF;

  -- Search path a: shell attached to a live E.164 auth.users row
  SELECT scu.id INTO v_source_id
  FROM shell_control.users scu
  JOIN auth.users au ON au.id = scu.id
  WHERE au.phone = v_normalised
    AND scu.active = true
    AND scu.id <> NEW.id
  LIMIT 1;

  -- Search path b: orphan shell (phone column set, no auth.users row yet).
  -- Normalise both sides: admin shells may store 0412... while signup arrives +61412...
  IF v_source_id IS NULL THEN
    SELECT scu.id INTO v_source_id
    FROM shell_control.users scu
    LEFT JOIN auth.users au ON au.id = scu.id
    WHERE shell_control.normalise_au_phone(COALESCE(scu.phone, '')) = v_normalised
      AND scu.active = true
      AND au.id IS NULL
      AND scu.id <> NEW.id
    LIMIT 1;
    IF v_source_id IS NOT NULL THEN
      v_is_orphan := true;
    END IF;
  END IF;

  IF v_source_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_is_orphan THEN
    SELECT email INTO v_source_email FROM shell_control.users WHERE id = v_source_id;
    UPDATE shell_control.users SET phone = NULL, email = NULL WHERE id = v_source_id;
  END IF;

  INSERT INTO shell_control.users (
    id, email, tenant_id, role, active, created_at,
    name, phone, is_platform_admin, last_active_tenant_id,
    pin_failed_attempts, preferences
  )
  SELECT
    NEW.id,
    CASE WHEN v_is_orphan THEN v_source_email ELSE NULL END,
    tenant_id, role, active, now(),
    name,
    CASE WHEN v_is_orphan THEN v_normalised ELSE NULL END,
    false,
    last_active_tenant_id,
    0,
    coalesce(preferences, '{}'::jsonb)
  FROM shell_control.users
  WHERE id = v_source_id
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
  SELECT NEW.id, tenant_id, role, active
  FROM shell_control.user_tenant_memberships
  WHERE user_id = v_source_id
  ON CONFLICT (user_id, tenant_id) DO NOTHING;

  RAISE WARNING
    'handle_phone_dedup: merged shell=% -> new_uuid=% phone=% orphan=%',
    v_source_id, NEW.id, v_normalised, v_is_orphan;

  RETURN NEW;
END;
$$;
