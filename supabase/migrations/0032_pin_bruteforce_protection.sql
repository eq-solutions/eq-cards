-- 0032_pin_bruteforce_protection.sql
--
-- Per-user brute-force protection for the app-lock PIN.
--
-- Problem (pre-this-migration):
--   public.verify_pin(p_pin)                  -- auth.uid(), callable by `authenticated`
--   shell_control.verify_pin_for_user(uuid,text) -- p_user_id, service-role/gateway only
-- both did a bare `crypt()` compare and returned true/false with NO attempt
-- counter, lockout, or delay. A 4-digit PIN (10,000 combinations) is trivially
-- brute-forceable against either entry point.
--
-- Fix:
--   * Two new columns on shell_control.users track failures + lock window.
--   * A single SECURITY DEFINER helper, shell_control._verify_pin_throttled,
--     holds the throttle logic so the public/auth.uid() and gateway/p_user_id
--     variants can never drift apart.
--   * On the 5th consecutive wrong PIN we arm an exponential lockout
--     (1, 2, 4, 8, ... minutes, capped at 60) that the NEXT attempt hits.
--   * While locked, EVERY attempt (even the correct PIN) is rejected with a
--     clear, retry-after error.
--   * A correct PIN clears the counters.
--   * Setting/resetting a PIN also clears the counters (recovery path).
--
-- Caller contract (unchanged happy path):
--   correct PIN, not locked  -> returns true   (counters reset)
--   wrong PIN, under lock     -> returns false  (counter incremented)
--   any attempt while locked  -> RAISES with hint='pin_locked',
--                                detail=<seconds remaining>,
--                                message='PIN locked. Try again in N second(s).'
-- The only new behaviour is the RAISE on lockout. The false path is untouched,
-- so existing clients keep working; lockout surfaces as a clear error string.
--
-- Gateway twin: eq-shell/netlify/functions/cards-api.ts `verify_pin` op must
-- map this error (error.hint === 'pin_locked') to HTTP 423/429 + retry_after
-- instead of a generic 500. See the matching change in that repo.
--
-- AUTH CHANGE — do NOT apply to live without Royce's explicit approval.
-- Rollback: drop the two functions back to a plain crypt() compare, drop the
-- helper, and (optionally) drop the two columns.

-- ============================================================
-- 1. Tracking columns
-- ============================================================

alter table shell_control.users
  add column if not exists pin_failed_attempts integer     not null default 0,
  add column if not exists pin_locked_until     timestamptz;

comment on column shell_control.users.pin_failed_attempts is
  'Consecutive failed app-lock PIN attempts. Reset to 0 on success or PIN (re)set.';
comment on column shell_control.users.pin_locked_until is
  'If in the future, PIN verification is locked until this time (exponential backoff).';

-- ============================================================
-- 2. Shared throttle helper — single source of truth
--
-- SECURITY DEFINER + takes an explicit p_user_id, so it MUST NOT be callable
-- directly by anon/authenticated (that would let any caller brute-force or
-- lock out an arbitrary user). It is invoked only from the two wrappers below,
-- which run as their definer owner and so are unaffected by the REVOKE.
-- ============================================================

create or replace function shell_control._verify_pin_throttled(p_user_id uuid, p_pin text)
returns boolean
language plpgsql
security definer
set search_path to 'shell_control', 'extensions', 'public'
as $$
declare
  v_threshold constant integer := 5;    -- lock arms on the 5th wrong attempt
  v_cap_min   constant integer := 60;   -- max lock window, minutes
  v_hash      text;
  v_attempts  integer;
  v_locked    timestamptz;
  v_new_att   integer;
  v_lock_min  integer;
  v_remaining integer;
begin
  if p_user_id is null then
    return false;
  end if;

  select pin_hash, coalesce(pin_failed_attempts, 0), pin_locked_until
    into v_hash, v_attempts, v_locked
    from shell_control.users
    where id = p_user_id;

  -- Unknown user or no PIN set: behave as before, no info leak, no counter.
  if v_hash is null then
    return false;
  end if;

  -- Locked out: reject everything (even a correct PIN) with a retry-after.
  -- No write here, so the RAISE rollback has nothing to undo.
  if v_locked is not null and v_locked > now() then
    v_remaining := ceil(extract(epoch from (v_locked - now())))::integer;
    raise exception
      'PIN locked. Too many incorrect attempts. Try again in % second(s).', v_remaining
      using errcode = 'P0001',
            hint    = 'pin_locked',
            detail  = v_remaining::text;
  end if;

  -- Correct PIN: clear counters and admit.
  if crypt(p_pin, v_hash) = v_hash then
    update shell_control.users
       set pin_failed_attempts = 0,
           pin_locked_until     = null
     where id = p_user_id;
    return true;
  end if;

  -- Wrong PIN: count it. At/after the threshold, arm an exponential lock that
  -- the next attempt will hit. Return false (not raise) so the UPDATE commits.
  v_new_att := v_attempts + 1;
  if v_new_att >= v_threshold then
    -- 2^(over-threshold) minutes: 1,2,4,8,...; exponent clamped to avoid
    -- float overflow, total clamped to v_cap_min.
    v_lock_min := least((2 ^ least(v_new_att - v_threshold, 12))::integer, v_cap_min);
    update shell_control.users
       set pin_failed_attempts = v_new_att,
           pin_locked_until     = now() + make_interval(mins => v_lock_min)
     where id = p_user_id;
  else
    update shell_control.users
       set pin_failed_attempts = v_new_att
     where id = p_user_id;
  end if;

  return false;
end;
$$;

-- Lock the helper down: only the definer owner (and service_role) may call it.
revoke all on function shell_control._verify_pin_throttled(uuid, text) from public;
revoke all on function shell_control._verify_pin_throttled(uuid, text) from anon, authenticated;

-- ============================================================
-- 3. public.verify_pin — auth.uid() variant (called by Flutter as `authenticated`)
--
-- Unchanged signature/return/grants. Now delegates to the throttle helper.
-- Stays VOLATILE (it already was) because the helper writes.
-- ============================================================

create or replace function public.verify_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'shell_control'
as $$
begin
  return shell_control._verify_pin_throttled(auth.uid(), p_pin);
end;
$$;

-- ============================================================
-- 4. shell_control.verify_pin_for_user — p_user_id variant (gateway, service role)
--
-- NOTE: was declared STABLE. Dropped here — the throttle helper performs
-- UPDATEs, which a STABLE function may not. Now VOLATILE (default).
-- Signature/return/grants unchanged.
-- ============================================================

create or replace function shell_control.verify_pin_for_user(p_user_id uuid, p_pin text)
returns boolean
language plpgsql
security definer
set search_path to 'shell_control', 'extensions', 'public'
as $$
begin
  return shell_control._verify_pin_throttled(p_user_id, p_pin);
end;
$$;

-- ============================================================
-- 5. Clear lockout state when a PIN is (re)set — recovery path
--
-- Bodies preserved verbatim except for resetting the two counters, so a fresh
-- PIN always starts clean and an admin/self re-enrol can recover a locked user.
-- ============================================================

create or replace function public.set_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path to 'public', 'shell_control'
as $$
begin
  if length(p_pin) != 4 or p_pin !~ '^[0-9]+$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  update shell_control.users
     set pin_hash             = crypt(p_pin, gen_salt('bf', 8)),
         pin_failed_attempts  = 0,
         pin_locked_until     = null
   where id = auth.uid();
end;
$$;

create or replace function shell_control.set_pin_for_user(p_user_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path to 'shell_control', 'extensions', 'public'
as $$
begin
  if length(p_pin) != 4 or p_pin !~ '^\d{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  update shell_control.users
     set pin_hash             = crypt(p_pin, gen_salt('bf', 8)),
         pin_failed_attempts  = 0,
         pin_locked_until     = null
   where id = p_user_id;
end;
$$;
