-- Migration 0035: phone-fallback in custom_access_token_hook
--
-- Problem: GoTrue stores OTP-verified phones without the leading '+' (e.g.
-- "61432944014") while shell_control.users stores them as E.164 ("+61432944014").
-- An admin back-fill creates shell_control.users with E.164; if the worker's
-- GoTrue session was minted against a bare-digit phone, the hook can't match
-- by UUID and injects no tenant_id → worker JWT is tenant-less → bounce.
--
-- Fix: if the UUID lookup returns nothing, normalize the phone from auth.users
-- via the existing normalise_au_phone() function and retry against
-- shell_control.users.phone. Safe because GoTrue enforces phone uniqueness —
-- one phone can only belong to one person.
--
-- The fallback is intentionally narrow: it only fires when normalization
-- actually changes the value (v_phone <> v_raw_phone), so already-E.164
-- phones that genuinely have no shell entry don't get a spurious match.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user      shell_control.users%rowtype;
  v_claims    jsonb;
  v_raw_phone text;
  v_phone     text;
BEGIN
  BEGIN
    -- Primary: look up by UUID (correct path for all properly-provisioned users).
    SELECT u.*
      INTO v_user
    FROM shell_control.users u
    WHERE u.id = (event->>'user_id')::uuid
    LIMIT 1;

    -- Phone fallback: GoTrue can store phones without the leading '+' while
    -- shell_control always stores E.164. Normalize and retry by phone.
    IF v_user.id IS NULL THEN
      SELECT au.phone
        INTO v_raw_phone
      FROM auth.users au
      WHERE au.id = (event->>'user_id')::uuid;

      IF v_raw_phone IS NOT NULL AND v_raw_phone <> '' THEN
        v_phone := public.normalise_au_phone(v_raw_phone);

        -- Only attempt the fallback when normalization actually changed the value.
        -- This avoids matching non-AU or already-E.164 phones that simply have
        -- no shell entry.
        IF v_phone IS DISTINCT FROM v_raw_phone THEN
          SELECT u.*
            INTO v_user
          FROM shell_control.users u
          WHERE u.phone  = v_phone
            AND u.active = true
          LIMIT 1;

          IF v_user.id IS NOT NULL THEN
            RAISE WARNING
              'custom_access_token_hook: phone-fallback auth=% → shell=% phone=%',
              event->>'user_id', v_user.id, v_phone;
          END IF;
        END IF;
      END IF;
    END IF;

    v_claims := coalesce(event->'claims', '{}'::jsonb);

    IF v_claims->'app_metadata' IS NULL
       OR jsonb_typeof(v_claims->'app_metadata') <> 'object' THEN
      v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb, true);
    END IF;

    IF v_user.id IS NOT NULL AND v_user.active THEN
      v_claims := jsonb_set(
        v_claims, '{app_metadata,tenant_id}',
        to_jsonb(coalesce(v_user.last_active_tenant_id, v_user.tenant_id)::text), true
      );
      v_claims := jsonb_set(
        v_claims, '{app_metadata,eq_role}',
        to_jsonb(v_user.role::text), true
      );
      v_claims := jsonb_set(
        v_claims, '{app_metadata,is_platform_admin}',
        to_jsonb(v_user.is_platform_admin), true
      );
    END IF;

    RETURN jsonb_set(event, '{claims}', v_claims);

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'custom_access_token_hook failed for user %: %',
      event->>'user_id', sqlerrm;
    RETURN event;
  END;
END;
$$;

-- Re-grant execute to supabase_auth_admin (required for the hook to fire).
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb)
  TO supabase_auth_admin;

REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb)
  FROM authenticated, anon, public;
