-- Fix eq_cards_auto_provision() FK ordering bug introduced in 0055.
--
-- 0055 moved the user_tenant_memberships INSERT before the shell_control.users
-- INSERT to handle Core-first users. But user_tenant_memberships.user_id has a
-- FK to shell_control.users.id — so inserting the membership before the users
-- row exists throws:
--   code 23503: insert on "user_tenant_memberships" violates FK
--   "user_tenant_memberships_user_id_fkey"
-- This only hits brand-new users (no shell_control.users row yet), which is
-- why Core admins and re-provisioning worked but first-time sign-ups didn't.
--
-- Fix: ensure shell_control.users exists first (ON CONFLICT DO NOTHING
-- preserves Core-first users' existing tenant_id), then insert membership.

CREATE OR REPLACE FUNCTION public.eq_cards_auto_provision()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_personal_tenant_id uuid;
  v_auth_phone         text;
  v_active_tenant_id   uuid;
BEGIN
  SELECT id INTO v_personal_tenant_id
  FROM shell_control.tenants
  WHERE is_personal = true
  LIMIT 1;

  IF v_personal_tenant_id IS NULL THEN
    RAISE EXCEPTION 'personal_tenant_not_found' USING ERRCODE = 'P0010';
  END IF;

  -- Build phone before any inserts (needed for the users row).
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

  -- shell_control.users MUST exist before membership insert (FK constraint).
  -- ON CONFLICT DO NOTHING preserves Core-first users' existing tenant_id.
  INSERT INTO shell_control.users (id, phone, tenant_id, active)
  VALUES (auth.uid(), v_auth_phone, v_personal_tenant_id, true)
  ON CONFLICT (id) DO NOTHING;

  -- FK now satisfied — ensure personal wallet membership.
  INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
  VALUES (auth.uid(), v_personal_tenant_id, 'employee', true)
  ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;

  -- Return the user's active tenant (may differ from personal for Core admins).
  SELECT COALESCE(last_active_tenant_id, tenant_id)
    INTO v_active_tenant_id
  FROM shell_control.users
  WHERE id = auth.uid();

  RETURN COALESCE(v_active_tenant_id, v_personal_tenant_id);
END;
$$;
