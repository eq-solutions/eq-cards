-- 0004_rls_with_check.sql
--
-- Adds `with check` clauses to every UPDATE RLS policy. Migration 0001
-- only specified `using` predicates — that restricts which rows are
-- targetable but does NOT restrict what values you can update to.
--
-- Concrete risk closed: a user could `update licences set user_id = '<other>'
-- where id = '<own>'` and silently reassign their own row to someone else,
-- because the `using` clause permits the SELECT/target but no check exists
-- on the new row. Same gap on `profiles.id` and on the storage objects
-- policy.
--
-- This is defense-in-depth. RLS `using` already blocks targeting other
-- users' rows, but the principle is: USING gates SELECT, WITH CHECK gates
-- INSERT/UPDATE values. Always pair them.
--
-- Applied to eq-canonical (jvknxcmbtrfnxfrwfimn) 2026-05-24 via Supabase MCP.
-- Note: the storage.objects block below is omitted from the canonical apply —
-- canonical storage policies use tenant_id isolation (not uid) and were set up separately.

alter policy "users_update_own_profile" on public.profiles
  using (id = auth.uid())
  with check (id = auth.uid());

alter policy "users_update_own_licences" on public.licences
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter policy "users_update_own_custom" on public.licence_types
  using (is_custom = true and user_id = auth.uid())
  with check (is_custom = true and user_id = auth.uid());

-- Storage bucket policy — same pattern.
alter policy "users_update_own_licence_photos" on storage.objects
  using (
    bucket_id = 'licence-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'licence-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
