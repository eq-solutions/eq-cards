-- 0001_initial_schema.sql
-- EQ Cards initial schema. Phase 0.5.

create extension if not exists "pgcrypto";

-- ============================================================
-- profiles
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  date_of_birth date,
  mobile text,
  email text,
  address_street text,
  address_suburb text,
  address_state text,
  address_postcode text,
  emergency_contact_name text,
  emergency_contact_relationship text,
  emergency_contact_mobile text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.profiles enable row level security;

create policy "users_read_own_profile"
  on public.profiles for select
  using (id = auth.uid());

create policy "users_insert_own_profile"
  on public.profiles for insert
  with check (id = auth.uid());

create policy "users_update_own_profile"
  on public.profiles for update
  using (id = auth.uid());

-- ============================================================
-- licence_types
-- ============================================================

create table public.licence_types (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  label text not null,
  requires_state boolean not null default false,
  default_validity_months int,
  is_custom boolean not null default false,
  user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint custom_has_user check (
    (is_custom = false and user_id is null)
    or (is_custom = true and user_id is not null)
  )
);

create unique index licence_types_code_seeded_unique
  on public.licence_types (code)
  where is_custom = false;

create index licence_types_user_idx
  on public.licence_types (user_id)
  where is_custom = true;

alter table public.licence_types enable row level security;

create policy "anyone_reads_seeded_or_own_custom"
  on public.licence_types for select
  using (is_custom = false or user_id = auth.uid());

create policy "users_insert_own_custom"
  on public.licence_types for insert
  with check (is_custom = true and user_id = auth.uid());

create policy "users_update_own_custom"
  on public.licence_types for update
  using (is_custom = true and user_id = auth.uid());

-- ============================================================
-- licences
-- ============================================================

create table public.licences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  licence_type text not null,
  licence_number text not null,
  issue_date date not null,
  expiry_date date not null,
  issuing_authority text,
  state text,
  photo_front_url text,
  photo_back_url text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index licences_user_expiry_idx
  on public.licences (user_id, expiry_date)
  where deleted_at is null;

create index licences_user_type_idx
  on public.licences (user_id, licence_type)
  where deleted_at is null;

alter table public.licences enable row level security;

create policy "users_read_own_licences"
  on public.licences for select
  using (user_id = auth.uid());

create policy "users_insert_own_licences"
  on public.licences for insert
  with check (user_id = auth.uid());

create policy "users_update_own_licences"
  on public.licences for update
  using (user_id = auth.uid());

-- ============================================================
-- audit_log
-- ============================================================

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_user_created_idx
  on public.audit_log (user_id, created_at desc);

alter table public.audit_log enable row level security;

create policy "users_read_own_audit"
  on public.audit_log for select
  using (user_id = auth.uid());

-- No INSERT / UPDATE / DELETE policies. Triggers populate via SECURITY DEFINER.

-- ============================================================
-- Trigger: set_updated_at
-- ============================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger licences_set_updated_at
  before update on public.licences
  for each row execute function public.set_updated_at();

-- ============================================================
-- Trigger: audit_log on profile changes
-- ============================================================

create or replace function public.log_profile_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (user_id, action, entity_type, entity_id, metadata)
  values (
    coalesce(new.id, old.id),
    case TG_OP
      when 'INSERT' then 'profile.created'
      when 'UPDATE' then 'profile.updated'
      when 'DELETE' then 'profile.deleted'
    end,
    'profile',
    coalesce(new.id, old.id),
    jsonb_build_object('op', TG_OP)
  );
  return coalesce(new, old);
end;
$$;

create trigger profiles_audit
  after insert or update or delete on public.profiles
  for each row execute function public.log_profile_change();

-- ============================================================
-- Trigger: audit_log on licence changes
-- ============================================================

create or replace function public.log_licence_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (user_id, action, entity_type, entity_id, metadata)
  values (
    coalesce(new.user_id, old.user_id),
    case TG_OP
      when 'INSERT' then 'licence.created'
      when 'UPDATE' then 'licence.updated'
      when 'DELETE' then 'licence.deleted'
    end,
    'licence',
    coalesce(new.id, old.id),
    jsonb_build_object(
      'op', TG_OP,
      'licence_type', coalesce(new.licence_type, old.licence_type)
    )
  );
  return coalesce(new, old);
end;
$$;

create trigger licences_audit
  after insert or update or delete on public.licences
  for each row execute function public.log_licence_change();
