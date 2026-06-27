-- Modify eq_cards_auto_provision() so it ALWAYS ensures the __personal__
-- user_tenant_memberships row exists, even for Core-first users who already
-- have a shell_control.users row pointing at an org tenant.
--
-- Before: bailed immediately if shell_control.users existed → Core admins
-- visiting Cards for the first time never got a Personal wallet in the switcher.
-- After:  personal membership insert runs first, then early-exit if row exists,
-- returning their actual active tenant unchanged.

CREATE OR REPLACE FUNCTION public.eq_cards_auto_provision()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_personal_tenant_id uuid;
  v_auth_phone         text;
  v_existing_tenant_id uuid;
BEGIN
  SELECT id INTO v_personal_tenant_id
  FROM shell_control.tenants
  WHERE is_personal = true
  LIMIT 1;

  IF v_personal_tenant_id IS NULL THEN
    RAISE EXCEPTION 'personal_tenant_not_found' USING ERRCODE = 'P0010';
  END IF;

  -- Always ensure personal wallet membership regardless of whether
  -- shell_control.users already exists (handles Core-first users).
  INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
  VALUES (auth.uid(), v_personal_tenant_id, 'employee', true)
  ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;

  -- If the user already has a shell_control.users row (Core admin, or
  -- previously provisioned Cards user) return their active tenant unchanged.
  SELECT COALESCE(last_active_tenant_id, tenant_id)
    INTO v_existing_tenant_id
  FROM shell_control.users
  WHERE id = auth.uid();

  IF v_existing_tenant_id IS NOT NULL THEN
    RETURN v_existing_tenant_id;
  END IF;

  -- New user: build the shell_control.users row pointing at personal tenant.
  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();
  IF v_auth_phone IS NOT NULL AND v_auth_phone <> '' THEN
    IF left(v_auth_phone, 1) <> '+' THEN
      v_auth_phone := '+' || v_auth_phone;
    END IF;
    -- Don't steal a phone number already claimed by another user.
    IF EXISTS (
      SELECT 1 FROM shell_control.users
      WHERE phone = v_auth_phone AND id <> auth.uid()
    ) THEN
      v_auth_phone := NULL;
    END IF;
  ELSE
    v_auth_phone := NULL;
  END IF;

  INSERT INTO shell_control.users (id, phone, tenant_id, active)
  VALUES (auth.uid(), v_auth_phone, v_personal_tenant_id, true)
  ON CONFLICT (id) DO NOTHING;

  RETURN v_personal_tenant_id;
END;
$$;
