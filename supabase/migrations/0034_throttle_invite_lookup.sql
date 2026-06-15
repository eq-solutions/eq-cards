-- 0034_throttle_invite_lookup.sql  —  APPLIED to eq-canonical (jvknxcmbtrfnxfrwfimn)
--
-- Status verified live 2026-06-15: eq_cards_lookup_invite_by_phone carries the
-- per-slug guard below. (Header previously read "DRAFT, NOT APPLIED" — stale;
-- the function is live. The live system is the source of truth.)
--
-- This was a behaviour change to an anon onboarding endpoint, so it required
-- Royce's approval (auth flow change) and a decision on enforcement point.
--
-- COMPLEMENTARY LAYER: the per-attacker (IP) throttle now lives at the cards-api
-- gateway (eq-shell netlify/functions/cards-api.ts, op=lookup_invite_by_phone),
-- which the Cards app routes invite lookups through. The DB guard below cannot
-- see the client IP, so the two layers are complementary, not exclusive.
--
-- FINDING: eq_cards_lookup_invite_by_phone(p_phone, p_slug) is anon-callable and
-- returns a live invite claim token given (phone, slug). Unthrottled, phone
-- enumeration against a known tenant slug harvests claim tokens -> unauthorized
-- onboarding/impersonation. Same class as the PIN brute-force (migration 0032).
--
-- FIX: reuse the platform limiter public.check_and_increment_rate_limit, keyed
-- by SLUG. Slug is the only enumeration-stable dimension available in-DB — a
-- phone key would hand the attacker a fresh bucket per guess and do nothing.
-- Limit 50 lookups / 10 min / slug, 10 min lockout: generous for a tenant
-- onboarding a batch of workers, tight enough to stop bulk enumeration.
--
-- CEILING: per-slug is the best achievable in the DB (no client IP here). For
-- per-attacker (IP) throttling, route this op through the cards-api gateway and
-- rate-limit on IP there. The two are complementary, not exclusive.
--
-- Body below is the live function verbatim plus the guard block; nothing else
-- changed (still VOLATILE, SECURITY DEFINER, search_path=public).

create or replace function public.eq_cards_lookup_invite_by_phone(p_phone text, p_slug text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id  uuid;
  v_token   uuid;
  v_rl      jsonb;
  v_suffix  text := regexp_replace(
                      regexp_replace(p_phone, '\s', '', 'g'),
                      '^(\+61|61|0)', ''
                    );
begin
  select id into v_org_id
  from   public.tenants
  where  slug   = lower(trim(p_slug))
    and  status = 'active'
  limit  1;

  if v_org_id is null then
    return null;
  end if;

  -- Enumeration guard (migration 0034). Keyed by slug; see header.
  v_rl := public.check_and_increment_rate_limit(
            'invite_lookup:' || lower(trim(p_slug)), 600, 50, 600);
  if (v_rl->>'blocked')::boolean then
    raise exception
      'Too many invite lookups. Try again in % second(s).', (v_rl->>'retry_after_seconds')
      using errcode = 'P0001',
            hint    = 'rate_limited',
            detail  = (v_rl->>'retry_after_seconds');
  end if;

  select wi.token into v_token
  from   public.worker_invites wi
  left join public.workers w on w.id = wi.worker_id
  where  wi.org_id    = v_org_id
    and  wi.claimed_at is null
    and  wi.expires_at > now()
    and (
      regexp_replace(regexp_replace(coalesce(w.phone,                    ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
      or
      regexp_replace(regexp_replace(coalesce(wi.profile_data->>'mobile', ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
      or
      regexp_replace(regexp_replace(coalesce(wi.profile_data->>'phone',  ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
    )
  order  by wi.created_at desc
  limit  1;

  return v_token;
end;
$function$;
