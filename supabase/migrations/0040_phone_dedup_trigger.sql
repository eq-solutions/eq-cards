-- 0040_phone_dedup_trigger.sql
--
-- Addresses the recurring bare-digit phone duplicate auth.users bug.
-- Root cause: GoTrue stores phone OTPs as bare digits (61XXXXXXXXX) but admin
-- back-fills store E.164 (+61XXXXXXXXX). String mismatch → second auth row →
-- no shell entry → notProvisioned loop → auto-provision hijacks to personal wallet.
--
-- Part 1: Immediate data repair for 2 known affected workers
--   Jack Cluff  (ecf0aec4) — bare-digit row; orphan shell 3c0d7a7f (no auth row)
--   Matthew Miller (64f1b976) — bare-digit row; shell on 7d5cac9a (E.164 auth row)
--
-- Part 2: AFTER INSERT trigger on auth.users that auto-merges any future bare-digit
--   row with its matching E.164 shell entry before the JWT hook fires.
--   After the trigger, UUID lookup in custom_access_token_hook works directly →
--   phone fallback not needed → eq_cards_auto_provision returns early (correct tenant).
--
-- This file is idempotent — safe to re-apply on deploy.

-- ─── Part 1: Data repair ────────────────────────────────────────────────────

-- Jack Cluff: orphan shell 3c0d7a7f has UNIQUE phone + UNIQUE email.
-- Clear both from source first, then insert ecf0aec4 with known literal values.
UPDATE shell_control.users
SET phone = NULL, email = NULL
WHERE id = '3c0d7a7f-7596-4400-91fd-76f40c2d67bc'::uuid;

INSERT INTO shell_control.users (
  id, email, tenant_id, role, active, created_at,
  name, phone, is_platform_admin, last_active_tenant_id,
  pin_failed_attempts, preferences
)
SELECT
  'ecf0aec4-ed0b-47a1-a0de-51da000084f0'::uuid,
  'jack.cluff@sks.com.au',
  tenant_id, role, active, now(),
  name, '+61431294493',
  false,
  last_active_tenant_id,
  0,
  coalesce(preferences, '{}'::jsonb)
FROM shell_control.users
WHERE id = '3c0d7a7f-7596-4400-91fd-76f40c2d67bc'::uuid
ON CONFLICT (id) DO NOTHING;

INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
SELECT
  'ecf0aec4-ed0b-47a1-a0de-51da000084f0'::uuid,
  tenant_id, role, active
FROM shell_control.user_tenant_memberships
WHERE user_id = '3c0d7a7f-7596-4400-91fd-76f40c2d67bc'::uuid
ON CONFLICT (user_id, tenant_id) DO NOTHING;

-- Deactivate orphan shell 3c0d7a7f (no auth.users row — nobody authenticates as it)
UPDATE shell_control.users
SET active = false
WHERE id = '3c0d7a7f-7596-4400-91fd-76f40c2d67bc'::uuid;


-- Matthew Miller: 7d5cac9a is still a live auth row — cannot take its email or phone.
-- Insert 64f1b976 with email = NULL, phone = NULL; UUID lookup in the hook works directly.
INSERT INTO shell_control.users (
  id, email, tenant_id, role, active, created_at,
  name, phone, is_platform_admin, last_active_tenant_id,
  pin_failed_attempts, preferences
)
SELECT
  '64f1b976-eb47-48f1-92fa-c55c30fa8743'::uuid,
  NULL::text,
  tenant_id, role, active, now(),
  name, NULL::text,
  false,
  last_active_tenant_id,
  0,
  coalesce(preferences, '{}'::jsonb)
FROM shell_control.users
WHERE id = '7d5cac9a-57d7-4e87-922e-b3da2d703dc3'::uuid
ON CONFLICT (id) DO NOTHING;

INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
SELECT
  '64f1b976-eb47-48f1-92fa-c55c30fa8743'::uuid,
  tenant_id, role, active
FROM shell_control.user_tenant_memberships
WHERE user_id = '7d5cac9a-57d7-4e87-922e-b3da2d703dc3'::uuid
ON CONFLICT (user_id, tenant_id) DO NOTHING;


-- ─── Part 2: Structural trigger ────────────────────────────────────────────

-- Trigger function in public schema (consistent with custom_access_token_hook).
--
-- When GoTrue inserts a bare AU mobile (e.g. 61431294493), this trigger:
--   1. Normalises to E.164 (+61431294493) via shell_control.normalise_au_phone
--   2. Finds an existing provisioned shell entry for that phone:
--        a. Shell attached to a live E.164 auth.users row — new shell gets
--           email = NULL, phone = NULL (live source keeps its unique values)
--        b. Orphan shell (shell.phone = E.164, no auth row yet) — source email
--           and phone are cleared first, new shell takes both
--   3. INSERTs shell entry + memberships for the new UUID
--
-- shell_control.users has UNIQUE constraints on (phone) and (email).
-- The orphan-transfer path (clear source → set new) handles both without conflict.
--
-- Security: is_platform_admin NEVER copied. TOTP/PIN not copied.

CREATE OR REPLACE FUNCTION public.handle_phone_dedup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_normalised   text;
  v_source_id    uuid;
  v_is_orphan    boolean := false;
  v_source_email text;
BEGIN
  -- Skip rows that are already E.164 or have no phone
  IF NEW.phone IS NULL OR NEW.phone = '' OR NEW.phone LIKE '+%' THEN
    RETURN NEW;
  END IF;

  v_normalised := shell_control.normalise_au_phone(NEW.phone);

  -- normalise_au_phone returns input unchanged if not a recognised AU format
  IF v_normalised = NEW.phone THEN
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

  -- Search path b: orphan shell (phone column set, no auth.users row yet)
  IF v_source_id IS NULL THEN
    SELECT scu.id INTO v_source_id
    FROM shell_control.users scu
    LEFT JOIN auth.users au ON au.id = scu.id
    WHERE scu.phone = v_normalised
      AND scu.active = true
      AND au.id IS NULL
    LIMIT 1;
    IF v_source_id IS NOT NULL THEN
      v_is_orphan := true;
    END IF;
  END IF;

  -- No existing provisioned account for this phone — nothing to merge
  IF v_source_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Orphan path: capture email before clearing, then transfer both unique fields
  IF v_is_orphan THEN
    SELECT email INTO v_source_email FROM shell_control.users WHERE id = v_source_id;
    UPDATE shell_control.users SET phone = NULL, email = NULL WHERE id = v_source_id;
  END IF;

  -- Create shell entry for the new UUID by copying from the source.
  -- Orphan path: take phone + email (just vacated). Live-auth path: leave both NULL.
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

  -- Copy tenant memberships
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

DROP TRIGGER IF EXISTS on_auth_users_insert_dedup ON auth.users;
CREATE TRIGGER on_auth_users_insert_dedup
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_phone_dedup();
