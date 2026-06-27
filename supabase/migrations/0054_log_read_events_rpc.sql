-- Migration 0054: client-callable RPC for read/access audit events
--
-- audit_log is populated only by SECURITY DEFINER triggers — no direct
-- client INSERT policy. This function lets authenticated callers log read
-- events (licence.viewed, licence.qr_shared, etc.) into the same table
-- without opening up a write policy on the table itself.
--
-- Usage:
--   select eq_cards_log_read_event('licence.qr_shared', 'licence', '<uuid>');
--
-- The function stamps auth.uid() as user_id, so callers can only log
-- events under their own identity.

create or replace function public.eq_cards_log_read_event(
  p_action      text,
  p_entity_type text,
  p_entity_id   uuid    default null,
  p_metadata    jsonb   default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reject calls from unauthenticated sessions (belt-and-braces;
  -- the grant below restricts to authenticated, but defence-in-depth).
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.audit_log (user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_metadata);
end;
$$;

-- Only authenticated users may call this function.
grant execute
  on function public.eq_cards_log_read_event(text, text, uuid, jsonb)
  to authenticated;

-- Revoke from anon + public (SECURITY DEFINER functions are granted to
-- PUBLIC by default in older Postgres versions).
revoke execute
  on function public.eq_cards_log_read_event(text, text, uuid, jsonb)
  from anon, public;
