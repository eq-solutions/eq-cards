-- ============================================================================
-- custom_access_token_hook  (LIVE — DEPLOYED & ENABLED on eq-canonical)
-- ============================================================================
--
-- ⚠️  THIS FILE IS NOT A MIGRATION AND MUST NOT BE AUTO-APPLIED.
--     It lives in supabase/manual/ (NOT supabase/migrations/) precisely so
--     that `supabase db push` never runs it. This function is an auth-critical
--     SECURITY DEFINER access-token hook; any change to it changes LIVE auth
--     behaviour of eq-canonical and is gated on Royce's explicit approval per
--     the global non-negotiables (auth changes require approval before deploy).
--
-- STATUS (verified against live 2026-06-15)
--   This SQL is a faithful reconciliation of the function ACTUALLY DEPLOYED on
--   eq-canonical (jvknxcmbtrfnxfrwfimn), captured via
--     SELECT pg_get_functiondef(oid) FROM pg_proc
--      WHERE proname = 'custom_access_token_hook';
--   The hook is enabled (Authentication → Hooks → Customize Access Token).
--   Earlier this file was labelled "PROPOSED" and injected ONLY tenant_id; the
--   live function had drifted ahead of it. This header + body now match live.
--
-- WHAT IT DOES
--   On every Supabase-native access token mint (OTP sign-in, Google OAuth, and
--   every token refresh) it injects, into app_metadata:
--     • tenant_id          — COALESCE(last_active_tenant_id, tenant_id)
--     • eq_role            — shell_control.users.role (enum, as text)
--     • is_platform_admin  — shell_control.users.is_platform_admin (boolean)
--   so the tokens match the Shell-handoff token shape and pass the cards-api
--   gateway. Without tenant_id, cards-api returns 401 jwt_missing_tenant_or_user.
--   (The Shell-handoff path injects these at mint time in
--   netlify/functions/shell-verify.js.)
--
-- WHERE IT LIVES
--   Project: eq-canonical (jvknxcmbtrfnxfrwfimn) — the auth project Cards
--   signs in against.
--
-- SOURCE OF TRUTH FOR tenant_id
--   shell_control.users — the SAME table the Shell handoff trusts and the key
--   into shell_control.tenant_routing used by cards-api's
--   getTenantRpcClientById(). tenant_id resolves to
--   COALESCE(last_active_tenant_id, tenant_id): a user's most recently active
--   tenant if set, else their home tenant. Do NOT source this from
--   public.org_memberships: if org_id ever diverged from
--   shell_control.users.tenant_id, an OTP user would route to a different (or
--   missing) tenant_routing row than the same user signing in via the Shell —
--   a silent cross-tenant / empty-data bug.
--
-- USER GATE
--   Claims are injected only when the user row exists AND users.active is true.
--   An inactive or unknown user gets NO tenant_id/eq_role/is_platform_admin and
--   will 401 at the gateway.
--
-- EXCEPTION HANDLER (fail-open to no-tenant-scope — RESOLVED 2026-06-15)
--   The body wraps everything in `EXCEPTION WHEN OTHERS`. If anything in the
--   hook raises (e.g. shell_control.users unreadable, a cast fails, a transient
--   error), it returns the event UNMODIFIED — minting a valid token with NO
--   tenant_id / eq_role / is_platform_admin. That token then 401s at cards-api.
--   DECISION (Royce, 2026-06-15): keep fail-OPEN. Failing closed would convert
--   any transient read error into a platform-wide sign-in outage; fail-open
--   denies access (scopeless token → 401) rather than granting it, so it errs
--   on the safe side. The only real defect was silence, now fixed: the handler
--   RAISEs WARNING (with SQLERRM + user_id) so degradations surface in Postgres
--   logs. Applied to live eq-canonical 2026-06-15; this file matches.
--
-- HOW TO RE-APPLY (only after review — this is auth-critical)
--   1. Run the body below against eq-canonical (Supabase SQL editor or MCP).
--   2. Confirm Dashboard → Authentication → Hooks → Customize Access Token (JWT)
--      → public.custom_access_token_hook → Enabled.
--   3. Verify per docs/cards-canonical-api-rewire.md §5.4 (decode an OTP token,
--      an OAuth token, and a refreshed token; confirm tenant_id + eq_role +
--      is_platform_admin present; then hit cards-api?op=current_staff).
-- ============================================================================

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer            -- must read shell_control.users despite RLS
set search_path = 'public'
as $$
declare
  v_user   shell_control.users%rowtype;
  v_claims jsonb;
begin
  begin
    select u.*
      into v_user
    from shell_control.users u
    where u.id = (event->>'user_id')::uuid
    limit 1;

    v_claims := coalesce(event->'claims', '{}'::jsonb);

    -- Ensure app_metadata exists and is an object before writing into it.
    if v_claims->'app_metadata' is null
       or jsonb_typeof(v_claims->'app_metadata') <> 'object' then
      v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb, true);
    end if;

    if v_user.id is not null and v_user.active then
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
    end if;
    -- If the user row is missing or inactive we deliberately add nothing;
    -- cards-api then 401s with jwt_missing_tenant_or_user.

    return jsonb_set(event, '{claims}', v_claims);

  exception when others then
    -- Fail-open to no-tenant-scope (deliberate — see header "EXCEPTION HANDLER").
    -- Failing CLOSED here would turn any transient read error into a
    -- platform-wide sign-in outage; fail-open denies access (scopeless token
    -- 401s at cards-api) rather than granting it. RAISE WARNING makes the
    -- otherwise-silent degradation observable in Postgres logs.
    raise warning 'custom_access_token_hook failed for user %: %',
      event->>'user_id', sqlerrm;
    return event;
  end;
end;
$$;

-- Supabase runs access-token hooks as the supabase_auth_admin role.
-- Live grant state (verified 2026-06-15): EXECUTE held by supabase_auth_admin,
-- postgres, service_role; NOT granted to authenticated/anon/public.
grant execute on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb)
  from authenticated, anon, public;
