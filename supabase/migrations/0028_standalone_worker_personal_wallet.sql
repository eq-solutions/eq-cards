-- 0028_standalone_worker_personal_wallet.sql
--
-- Enables EQ Cards as a standalone tradie platform.
-- A worker can sign in, create a personal wallet, and use the app without
-- an employer invite. Employers request access to a worker's wallet in
-- Phase 2 (see 0029).
--
-- Changes:
--   1. shell_control.tenants: add is_personal flag so Shell UIs can filter
--      personal wallets out of org lists.
--   2. Seed __personal__ tenant — the home for standalone workers.
--   3. Update custom_access_token_hook to use COALESCE(last_active_tenant_id,
--      tenant_id). Zero breaking change for existing users (last_active is NULL
--      for all → falls back to tenant_id as before). Required for Phase 2
--      tenant switching to work without destructive writes to tenant_id.
--   4. New RPC eq_cards_auto_provision(): idempotent self-provisioning for
--      workers who sign in without an employer invite. Called from the
--      WelcomeScreen "Start my personal wallet" button.

-- 1. Personal-tenant flag -------------------------------------------------------
ALTER TABLE shell_control.tenants
  ADD COLUMN IF NOT EXISTS is_personal boolean NOT NULL DEFAULT false;

-- 2. Seed the personal tenant ---------------------------------------------------
INSERT INTO shell_control.tenants (slug, name, is_personal, tier, active)
VALUES ('__personal__', 'Personal Wallet', true, 'standard', true)
ON CONFLICT (slug) DO UPDATE SET is_personal = true;

-- 3. Update custom_access_token_hook -------------------------------------------
-- Prefer last_active_tenant_id when set; fall back to primary tenant_id.
-- The EXCEPTION WHEN OTHERS block is unchanged — fail-open so a hook bug
-- never locks users out.
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user   shell_control.users%ROWTYPE;
  v_claims jsonb;
BEGIN
  BEGIN
    SELECT u.* INTO v_user
    FROM shell_control.users u
    WHERE u.id = (event->>'user_id')::uuid
    LIMIT 1;

    v_claims := coalesce(event->'claims', '{}'::jsonb);

    IF v_claims->'app_metadata' IS NULL
       OR jsonb_typeof(v_claims->'app_metadata') <> 'object' THEN
      v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb, true);
    END IF;

    IF v_user.id IS NOT NULL AND v_user.active THEN
      v_claims := jsonb_set(v_claims, '{app_metadata,tenant_id}',
                    to_jsonb(COALESCE(v_user.last_active_tenant_id, v_user.tenant_id)::text), true);
      v_claims := jsonb_set(v_claims, '{app_metadata,eq_role}',
                    to_jsonb(v_user.role::text), true);
      v_claims := jsonb_set(v_claims, '{app_metadata,is_platform_admin}',
                    to_jsonb(v_user.is_platform_admin), true);
    END IF;

    RETURN jsonb_set(event, '{claims}', v_claims);

  EXCEPTION WHEN OTHERS THEN
    -- Fail open: return token without custom claims rather than blocking login.
    RETURN event;
  END;
END;
$$;

-- 4. Auto-provision RPC --------------------------------------------------------
-- SECURITY DEFINER so it can write to shell_control (same pattern as
-- eq_cards_claim_invite). Idempotent — safe to call multiple times.
-- Returns the effective tenant_id so Flutter can confirm provisioning succeeded.
CREATE OR REPLACE FUNCTION public.eq_cards_auto_provision()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_personal_tenant_id uuid;
  v_auth_phone         text;
  v_existing_tenant_id uuid;
BEGIN
  -- Idempotent: if a shell identity already exists, return its effective tenant.
  SELECT COALESCE(last_active_tenant_id, tenant_id)
    INTO v_existing_tenant_id
  FROM shell_control.users
  WHERE id = auth.uid();

  IF v_existing_tenant_id IS NOT NULL THEN
    RETURN v_existing_tenant_id;
  END IF;

  -- Resolve the personal tenant.
  SELECT id INTO v_personal_tenant_id
  FROM shell_control.tenants
  WHERE is_personal = true
  LIMIT 1;

  IF v_personal_tenant_id IS NULL THEN
    RAISE EXCEPTION 'personal_tenant_not_found' USING ERRCODE = 'P0010';
  END IF;

  -- Normalise GoTrue-verified phone to E.164.
  -- GoTrue stores auth.users.phone as bare digits (e.g. '61432944014');
  -- shell_control.users.phone is the phone-OTP login key and must have '+'.
  SELECT phone INTO v_auth_phone FROM auth.users WHERE id = auth.uid();
  IF v_auth_phone IS NOT NULL AND v_auth_phone <> '' THEN
    IF left(v_auth_phone, 1) <> '+' THEN
      v_auth_phone := '+' || v_auth_phone;
    END IF;
    -- Drop phone if it already belongs to another shell user (recycled number).
    IF EXISTS (
      SELECT 1 FROM shell_control.users
      WHERE phone = v_auth_phone AND id <> auth.uid()
    ) THEN
      v_auth_phone := NULL;
    END IF;
  ELSE
    v_auth_phone := NULL;
  END IF;

  -- Create the shell identity with the personal tenant.
  INSERT INTO shell_control.users (id, phone, tenant_id, active)
  VALUES (auth.uid(), v_auth_phone, v_personal_tenant_id, true)
  ON CONFLICT (id) DO NOTHING;

  -- Create the personal tenant membership.
  INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
  VALUES (auth.uid(), v_personal_tenant_id, 'employee', true)
  ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;

  RETURN v_personal_tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.eq_cards_auto_provision() TO authenticated;
