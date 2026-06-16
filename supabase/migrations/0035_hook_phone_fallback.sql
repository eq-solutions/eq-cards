-- Migration 0035: HARDENED phone-fallback in custom_access_token_hook
--
-- Supersedes the naive blind-phone-match first draft. A blind fallback is a
-- privilege-escalation vector: GoTrue lets "+61432944014" and "61432944014"
-- coexist as two auth.users rows (uniqueness is on the exact string), so a
-- phone-format collision could match the WRONG shell_control row and inject
-- another person's tenant_id / eq_role / is_platform_admin.
--
-- Hardened rules:
--   1. Fallback fires ONLY when auth.users.phone_confirmed_at IS NOT NULL —
--      the phone was actually proven via OTP, not admin-inserted in bare form.
--   2. It fires ONLY when normalisation changes the raw value (the exact
--      format-drift case this exists to repair) AND exactly ONE active
--      shell_control row carries that E.164 phone. Ambiguous (0 or >1) → no
--      match, fail safe.
--   3. is_platform_admin is UUID-bound ONLY. A phone-matched row NEVER elevates
--      — forced false on the fallback path regardless of the row's value.
--
-- This repairs the existing duplicated accounts (bare-digit auth.users with no
-- shell row) without opening the escalation hole. The proper root-cause fix —
-- auto-routing new workers so a second auth.users is never created — is tracked
-- separately; this is the safety net for rows that already drifted.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user         shell_control.users%rowtype;
  v_claims       jsonb;
  v_raw_phone    text;
  v_phone        text;
  v_confirmed    timestamptz;
  v_match_count  int;
  v_via_fallback boolean := false;
BEGIN
  BEGIN
    -- Primary: UUID lookup (correct path for every properly-provisioned user).
    SELECT u.*
      INTO v_user
    FROM shell_control.users u
    WHERE u.id = (event->>'user_id')::uuid
    LIMIT 1;

    -- Hardened phone fallback — only for the format-drift repair case.
    IF v_user.id IS NULL THEN
      SELECT au.phone, au.phone_confirmed_at
        INTO v_raw_phone, v_confirmed
      FROM auth.users au
      WHERE au.id = (event->>'user_id')::uuid;

      -- Require an OTP-confirmed phone. Admin-inserted bare phones that were
      -- never proven do not qualify.
      IF v_raw_phone IS NOT NULL AND v_raw_phone <> ''
         AND v_confirmed IS NOT NULL THEN
        v_phone := shell_control.normalise_au_phone(v_raw_phone);

        -- Only when normalisation actually changed the value (the drift case).
        IF v_phone IS DISTINCT FROM v_raw_phone THEN
          -- Demand an UNAMBIGUOUS single active match. 0 or >1 → fail safe.
          SELECT count(*)
            INTO v_match_count
          FROM shell_control.users u
          WHERE u.phone = v_phone AND u.active = true;

          IF v_match_count = 1 THEN
            SELECT u.*
              INTO v_user
            FROM shell_control.users u
            WHERE u.phone = v_phone AND u.active = true
            LIMIT 1;
            v_via_fallback := true;
            RAISE WARNING
              'custom_access_token_hook: phone-fallback auth=% -> shell=% phone=%',
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
      -- Platform-admin is UUID-bound only. Never elevate on a phone match.
      v_claims := jsonb_set(
        v_claims, '{app_metadata,is_platform_admin}',
        to_jsonb(CASE WHEN v_via_fallback THEN false ELSE v_user.is_platform_admin END), true
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
