-- 0006_org_layer.sql
--
-- Adds an optional organisation (tenant) layer on top of the existing
-- per-user schema. Key design decisions:
--
--   • No org_id on profiles/licences — membership is a separate relationship.
--     A user's data stays theirs; orgs get read access via policy, not
--     column ownership.
--
--   • Invite-first model: an admin creates a membership row with
--     invited_email + status='pending'. When the invited user signs in
--     (OTP confirms their email), the link_pending_invites trigger auto-
--     promotes that row to status='active' and records their user_id.
--
--   • Frictionless individual use is unchanged: a user with no org
--     membership sees only their own data, exactly as before.
--
--   • Org admins can read (not write) the profiles and licences of every
--     active member in their org — no other escalated access.
--
--   • Only the service role can create/rename organisations (EQ staff do
--     this on behalf of clients). Org admins manage their own membership
--     list after that.

-- ============================================================
-- organisations (table + trigger only — policy added after org_memberships)
-- ============================================================

create table public.organisations (
  id         uuid    primary key default gen_random_uuid(),
  name       text    not null,
  slug       text    not null,               -- short identifier, e.g. "sks" "eq-solutions"
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index organisations_slug_unique
  on public.organisations (lower(slug));

alter table public.organisations enable row level security;

create trigger organisations_set_updated_at
  before update on public.organisations
  for each row execute function public.set_updated_at();

-- ============================================================
-- org_memberships
-- ============================================================

create table public.org_memberships (
  id             uuid    primary key default gen_random_uuid(),
  org_id         uuid    not null references public.organisations(id) on delete cascade,
  user_id        uuid    references auth.users(id) on delete cascade,
  invited_email  text,                       -- populated before user exists; cleared on accept
  role           text    not null default 'member',  -- 'admin' | 'member'
  status         text    not null default 'pending', -- 'pending' | 'active' | 'revoked'
  invited_by     uuid    references auth.users(id),
  invited_at     timestamptz not null default now(),
  accepted_at    timestamptz,
  constraint valid_role   check (role   in ('admin', 'member')),
  constraint valid_status check (status in ('pending', 'active', 'revoked')),
  -- a row must have at least one of user_id or invited_email
  constraint membership_has_identity check (
    user_id is not null or invited_email is not null
  )
);

-- Fast lookup by org (list members) and by user (my orgs)
create index org_memberships_org_idx
  on public.org_memberships (org_id);

create index org_memberships_user_idx
  on public.org_memberships (user_id)
  where user_id is not null;

-- Fast lookup for the trigger that links pending invites on sign-up
create index org_memberships_email_idx
  on public.org_memberships (lower(invited_email))
  where invited_email is not null;

-- Prevent duplicate active memberships for the same user+org
create unique index org_memberships_active_unique
  on public.org_memberships (org_id, user_id)
  where status != 'revoked' and user_id is not null;

alter table public.org_memberships enable row level security;

-- Users can see their own membership rows
create policy "users_read_own_memberships"
  on public.org_memberships for select
  using (user_id = auth.uid());

-- Org admins can see all memberships in their org
create policy "admins_read_org_memberships"
  on public.org_memberships for select
  using (
    exists (
      select 1 from public.org_memberships a
      where a.org_id  = org_id
        and a.user_id = auth.uid()
        and a.role    = 'admin'
        and a.status  = 'active'
    )
  );

-- Org admins can invite new members (insert pending rows)
create policy "admins_insert_org_memberships"
  on public.org_memberships for insert
  with check (
    exists (
      select 1 from public.org_memberships a
      where a.org_id  = org_id
        and a.user_id = auth.uid()
        and a.role    = 'admin'
        and a.status  = 'active'
    )
  );

-- Org admins can update any membership in their org (revoke, change role)
create policy "admins_update_org_memberships"
  on public.org_memberships for update
  using (
    exists (
      select 1 from public.org_memberships a
      where a.org_id  = org_id
        and a.user_id = auth.uid()
        and a.role    = 'admin'
        and a.status  = 'active'
    )
  );

-- Users can accept their own pending invite (status pending → active)
create policy "users_accept_own_invite"
  on public.org_memberships for update
  using  (user_id = auth.uid() and status = 'pending')
  with check (status = 'active');

-- ============================================================
-- organisations policy (added after org_memberships to avoid forward-ref)
-- ============================================================

-- Active members can read their own org record
create policy "members_read_own_org"
  on public.organisations for select
  using (
    exists (
      select 1 from public.org_memberships m
      where m.org_id   = id
        and m.user_id  = auth.uid()
        and m.status   = 'active'
    )
  );

-- No INSERT / UPDATE / DELETE policies — service role only

-- ============================================================
-- Trigger: auto-link pending invites when a user's email is confirmed
-- ============================================================
--
-- Fires after INSERT (e.g. manually created users with email_confirmed_at
-- already set) or after email_confirmed_at is written for the first time
-- (OTP verification). Safe to fire on re-confirmation too — the UPDATE
-- finds no matching pending rows and is a no-op.
--
-- Note: TG_OP cannot be used in the WHEN clause (SQL context only);
-- the idempotent function body handles both INSERT and UPDATE correctly.

create or replace function public.link_pending_invites()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.org_memberships
  set
    user_id       = new.id,
    status        = 'active',
    accepted_at   = now(),
    invited_email = null         -- clean up after linking
  where lower(invited_email) = lower(new.email)
    and status   = 'pending'
    and user_id  is null;

  return new;
end;
$$;

create trigger link_pending_invites_on_confirm
  after insert or update of email_confirmed_at
  on auth.users
  for each row
  when (new.email_confirmed_at is not null)
  execute function public.link_pending_invites();

-- ============================================================
-- Helper: is the calling user an active admin of p_member_id's org?
-- Used in RLS policies on profiles and licences below.
-- ============================================================

create or replace function public.is_org_admin_of(p_member_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from   public.org_memberships admin_m
    join   public.org_memberships member_m
           on member_m.org_id   = admin_m.org_id
           and member_m.user_id = p_member_id
           and member_m.status  = 'active'
    where  admin_m.user_id = auth.uid()
      and  admin_m.role    = 'admin'
      and  admin_m.status  = 'active'
  );
$$;

-- ============================================================
-- RLS additions: org admins can read member profiles + licences
-- ============================================================

-- Org admins can read profiles of active members in their org
create policy "org_admins_read_member_profiles"
  on public.profiles for select
  using (public.is_org_admin_of(id));

-- Org admins can read licences of active members in their org
create policy "org_admins_read_member_licences"
  on public.licences for select
  using (public.is_org_admin_of(user_id));
