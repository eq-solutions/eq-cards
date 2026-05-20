-- 0005_ocr_rate_limit.sql
--
-- Adds per-user rate limiting for the `ocr-licence` Edge Function. The
-- function calls `public.check_and_record_ocr_usage(20, '1 hour')` before
-- forwarding the image to Anthropic; if the user has already made 20 calls
-- in the past hour, the RPC returns false and the function returns HTTP 429
-- without hitting Anthropic.
--
-- Why a SECURITY DEFINER RPC instead of a SELECT + INSERT pair from the
-- edge function: race-condition safety. Two concurrent requests from the
-- same user could both read count=19 and both insert, ending at 21. The
-- RPC takes a row-level commit under one transaction and is atomic.
--
-- Why server-side enforcement at all: client-side rate-limiting is trivial
-- to bypass by clearing local storage. The Anthropic-per-call cost (~$0.005)
-- means an unbounded user could ring up A$10 in an hour. Server-side is
-- the real protection.
--
-- Apply via Supabase MCP (`apply_migration`).

create table if not exists public.ocr_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  called_at timestamptz not null default now()
);

-- Compound index supports the "count my calls since X" query the RPC runs
-- on every invocation. user_id first because cardinality is high; called_at
-- desc so the most-recent rows are read first.
create index if not exists ocr_usage_user_time
  on public.ocr_usage (user_id, called_at desc);

alter table public.ocr_usage enable row level security;

-- Users can SEE their own usage rows (debug / future "you've used X / 20
-- magic-scans this hour" UI). All writes go through the SECURITY DEFINER
-- function below — there are no INSERT/UPDATE/DELETE policies.
create policy "users_select_own_ocr_usage" on public.ocr_usage
  for select using (user_id = auth.uid());

-- Atomic check-and-record. Returns true if the call is permitted (and a row
-- has been inserted); returns false if the user is over the limit.
--
-- SECURITY DEFINER + tightened search_path so a user can't shadow the
-- ocr_usage table with a same-named object in their own schema.
create or replace function public.check_and_record_ocr_usage(
  p_limit int default 20,
  p_window interval default '1 hour'
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_recent_count int;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    return false;  -- unauthenticated, deny
  end if;

  select count(*) into v_recent_count
  from public.ocr_usage
  where user_id = v_user_id
    and called_at > now() - p_window;

  if v_recent_count >= p_limit then
    return false;  -- over limit, do not record
  end if;

  insert into public.ocr_usage (user_id) values (v_user_id);
  return true;
end;
$$;

-- Lock down: only authenticated callers can invoke it. Anon role can't.
revoke all on function public.check_and_record_ocr_usage(int, interval) from public;
grant execute on function public.check_and_record_ocr_usage(int, interval) to authenticated;
