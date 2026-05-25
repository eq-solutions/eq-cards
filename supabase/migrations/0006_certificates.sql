-- 0006_certificates.sql
-- Certificates wallet — PDFs and photos for First Aid, Working at Heights,
-- LV CPR, induction cards, and anything else that isn't a structured licence.

-- ============================================================
-- certificates
-- ============================================================

create table public.certificates (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  title        text        not null,
  certificate_type text    not null,
  issuer       text,
  issue_date   date,
  expiry_date  date,
  -- Storage path in the `certificates` bucket. Format:
  -- {user_id}/{certificate_id}.{pdf|jpg|png|...}
  file_path    text        not null,
  -- 'pdf' or 'image' — drives the viewer in the Flutter app.
  file_type    text        not null check (file_type in ('pdf', 'image')),
  notes        text,
  active       boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index certificates_user_active_idx
  on public.certificates (user_id)
  where active = true;

create index certificates_user_expiry_idx
  on public.certificates (user_id, expiry_date)
  where active = true;

alter table public.certificates enable row level security;

create policy "users_read_own_certs"
  on public.certificates for select
  using (user_id = auth.uid());

create policy "users_insert_own_certs"
  on public.certificates for insert
  with check (user_id = auth.uid());

create policy "users_update_own_certs"
  on public.certificates for update
  using  (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Reuse set_updated_at() from migration 0001.
create trigger certificates_set_updated_at
  before update on public.certificates
  for each row execute function public.set_updated_at();

-- ============================================================
-- certificates storage bucket
-- ============================================================

insert into storage.buckets (id, name, public)
values ('certificates', 'certificates', false)
on conflict (id) do nothing;

-- Path: {user_id}/{certificate_id}.{ext}
-- First path segment must equal auth.uid().

create policy "users_read_own_certs_files"
  on storage.objects for select
  using (
    bucket_id = 'certificates'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_insert_own_certs_files"
  on storage.objects for insert
  with check (
    bucket_id = 'certificates'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_update_own_certs_files"
  on storage.objects for update
  using (
    bucket_id = 'certificates'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_delete_own_certs_files"
  on storage.objects for delete
  using (
    bucket_id = 'certificates'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
