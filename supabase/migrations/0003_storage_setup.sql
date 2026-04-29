-- 0003_storage_setup.sql
-- Create the licence-photos bucket and apply user-scoped RLS on storage.objects.
-- This migration must run AFTER Supabase has provisioned the storage extension.

insert into storage.buckets (id, name, public)
values ('licence-photos', 'licence-photos', false)
on conflict (id) do nothing;

-- Path convention: {user_id}/{licence_id}/front.jpg or back.jpg
-- The first segment of the path must equal auth.uid().

create policy "users_read_own_licence_photos"
  on storage.objects for select
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_insert_own_licence_photos"
  on storage.objects for insert
  with check (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_update_own_licence_photos"
  on storage.objects for update
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users_delete_own_licence_photos"
  on storage.objects for delete
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
