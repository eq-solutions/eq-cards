-- 0007_org_layer_hardening.sql
--
-- Fixes five issues from 0006_org_layer:
--
--   1. Recursive RLS — the three admins_* policies on org_memberships queried
--      org_memberships from inside their own policy expressions, causing
--      infinite recursion. Fixed by routing through a security definer
--      function (is_org_admin) that bypasses RLS.
--
--   2. Missing updated_at on org_memberships — inconsistent with every other
--      mutable table in the schema.
--
--   3. No audit trail for membership changes — invites, accepts, revocations,
--      and role changes were silent. Added trigger + log_membership_change().
--
--   4. users_accept_own_invite allowed column changes beyond status — a user
--      accepting an invite could also change their role. A BEFORE UPDATE
--      trigger now force-resets all columns except status and accepted_at.

-- ============================================================
-- 1. Security definer helper: is the caller an active admin of p_org_id?
--
-- Bypasses RLS (security definer) so it can safely query org_memberships
-- from within policy context without infinite recursion.
-- Named is_org_admin (vs the existing is_org_admin_of which checks cross-
-- org membership for the profiles/licences policies).
-- ============================================================

create or replace function public.is_org_admin(p_org_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.org_memberships
    where org_id  = p_org_id
      and user_id = auth.uid()
      and role    = 'admin'
      and status  = 'active'
  );
$$;

-- ============================================================
-- 2. Replace recursive policies with non-recursive equivalents
-- ============================================================

drop policy "admins_read_org_memberships"   on public.org_memberships;
drop policy "admins_insert_org_memberships" on public.org_memberships;
drop policy "admins_update_org_memberships" on public.org_memberships;
drop policy "users_accept_own_invite"       on public.org_memberships;

-- Org admins can read all membership rows in their org
create policy "admins_read_org_memberships"
  on public.org_memberships for select
  using (public.is_org_admin(org_id));

-- Org admins can invite new members
create policy "admins_insert_org_memberships"
  on public.org_memberships for insert
  with check (public.is_org_admin(org_id));

-- Org admins can update any membership in their org (revoke, change role)
create policy "admins_update_org_memberships"
  on public.org_memberships for update
  using (public.is_org_admin(org_id));

-- Users can flip their own pending invite to active.
-- Column immutability is enforced by lock_invite_accept_columns trigger below.
create policy "users_accept_own_invite"
  on public.org_memberships for update
  using  (user_id = auth.uid() and status = 'pending')
  with check (status = 'active');

-- ============================================================
-- 3. updated_at on org_memberships
-- ============================================================

alter table public.org_memberships
  add column updated_at timestamptz not null default now();

create trigger org_memberships_set_updated_at
  before update on public.org_memberships
  for each row execute function public.set_updated_at();

-- ============================================================
-- 4. Column-lock on user-initiated invite acceptance
--
-- Prevents a user from exploiting users_accept_own_invite to also change
-- their role, org_id, or any other column they shouldn't control.
-- Only status (→ active) and accepted_at may change via this path.
-- ============================================================

create or replace function public.lock_invite_accept_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only locks when a non-admin is accepting their own pending invite.
  -- Admins going through admins_update_org_memberships are unaffected.
  if old.status = 'pending' and new.status = 'active'
     and new.user_id = auth.uid()
     and not public.is_org_admin(old.org_id)
  then
    new.org_id        := old.org_id;
    new.user_id       := old.user_id;
    new.invited_email := old.invited_email;
    new.role          := old.role;
    new.invited_by    := old.invited_by;
    new.invited_at    := old.invited_at;
    -- accepted_at and status are the only columns a user may change
  end if;
  return new;
end;
$$;

create trigger org_memberships_lock_invite_accept
  before update on public.org_memberships
  for each row execute function public.lock_invite_accept_columns();

-- ============================================================
-- 5. Audit log for membership changes
-- ============================================================

create or replace function public.log_membership_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_action  text;
begin
  -- Resolve the actor: prefer the affected user; fall back to the inviter
  -- (for pending invites where user_id is null at INSERT time).
  v_user_id := coalesce(
    coalesce(new.user_id, old.user_id),
    new.invited_by,
    old.invited_by
  );

  if v_user_id is null then
    return coalesce(new, old);   -- no actor — skip (satisfies NOT NULL on audit_log)
  end if;

  v_action := case TG_OP
    when 'INSERT' then 'membership.invited'
    when 'UPDATE' then
      case
        when old.status = 'pending' and new.status = 'active'  then 'membership.accepted'
        when new.status = 'revoked'                             then 'membership.revoked'
        when old.role != new.role                               then 'membership.role_changed'
        else 'membership.updated'
      end
    when 'DELETE' then 'membership.deleted'
  end;

  insert into public.audit_log (user_id, action, entity_type, entity_id, metadata)
  values (
    v_user_id,
    v_action,
    'membership',
    coalesce(new.id, old.id),
    jsonb_build_object(
      'op',     TG_OP,
      'org_id', coalesce(new.org_id,  old.org_id),
      'role',   coalesce(new.role,    old.role),
      'status', coalesce(new.status,  old.status)
    )
  );

  return coalesce(new, old);
end;
$$;

create trigger org_memberships_audit
  after insert or update or delete on public.org_memberships
  for each row execute function public.log_membership_change();
