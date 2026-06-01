-- ============================================================================
-- custom_access_token_hook  (PROPOSED — MANUAL APPLY ONLY)
-- ============================================================================
--
-- ⚠️  THIS FILE IS NOT A MIGRATION AND MUST NOT BE AUTO-APPLIED.
--     It lives in supabase/manual/ (NOT supabase/migrations/) precisely so
--     that `supabase db push` never runs it. Applying it changes the LIVE auth
--     behaviour of eq-canonical and is gated on Royce's explicit approval per
--     the global non-negotiables (auth changes require approval before deploy).
--
-- WHAT IT DOES
--   Injects app_metadata.tenant_id into Supabase-native access tokens (the
--   tokens minted by OTP sign-in, Google OAuth, and every token refresh) so
--   they match the Shell-handoff token shape and can use the cards-api gateway.
--   Without this, OTP/OAuth sessions carry no tenant_id and cards-api returns
--   401 jwt_missing_tenant_or_user. (The Shell-handoff path already injects
--   tenant_id at mint time in netlify/functions/shell-verify.js.)
--
-- WHERE TO APPLY
--   Project: eq-canonical (jvknxcmbtrfnxfrwfimn) — the auth project Cards
--   signs in against.
--
-- SOURCE OF TRUTH FOR tenant_id
--   shell_control.users.tenant_id — the SAME table the Shell handoff trusts and
--   the key into shell_control.tenant_routing used by cards-api's
--   getTenantRpcClientById(). Do NOT source this from public.org_memberships:
--   if org_id ever diverged from shell_control.users.tenant_id, an OTP user
--   would route to a different (or missing) tenant_routing row than the same
--   user signing in via the Shell — a silent cross-tenant / empty-data bug.
--
-- HOW TO ENABLE (after review)
--   1. Run this SQL against eq-canonical (Supabase SQL editor or MCP).
--   2. Dashboard → Authentication → Hooks → Customize Access Token (JWT) →
--      select public.custom_access_token_hook → Enable.
--      (Optionally mirror locally by uncommenting the
--       [auth.hook.custom_access_token] block in supabase/config.toml.)
--   3. Verify per docs/cards-canonical-api-rewire.md §5.4 (decode an OTP token,
--      an OAuth token, and a refreshed token; then hit cards-api?op=current_staff).
--
-- OPEN QUESTION (see design doc §5.2 / §10): confirm shell_control.users is
-- populated for every OTP/OAuth-capable Cards user. A user with no row gets no
-- tenant_id and will 401 at the gateway — decide reject-with-message vs
-- auto-provision before relying on this in production.
-- ============================================================================

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer            -- must read shell_control.users despite RLS
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_claims    jsonb;
begin
  select u.tenant_id
    into v_tenant_id
  from shell_control.users u
  where u.user_id = (event->>'user_id')::uuid;

  v_claims := coalesce(event->'claims', '{}'::jsonb);

  -- Ensure app_metadata exists and is an object before writing into it.
  if v_claims->'app_metadata' is null
     or jsonb_typeof(v_claims->'app_metadata') <> 'object' then
    v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb, true);
  end if;

  if v_tenant_id is not null then
    v_claims := jsonb_set(
      v_claims, '{app_metadata,tenant_id}', to_jsonb(v_tenant_id::text), true
    );
  end if;
  -- If v_tenant_id IS NULL we deliberately add nothing; cards-api then 401s
  -- with jwt_missing_tenant_or_user (see OPEN QUESTION above for desired UX).

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

-- Supabase runs access-token hooks as the supabase_auth_admin role.
grant execute on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb)
  from authenticated, anon, public;
