-- 0050 — Scope licence-photos storage reads/writes to the OWNING worker (not the whole tenant).
--
-- ┌─────────────────────────────────────────────────────────────────────────────────────┐
-- │  ⚠ NOT YET APPLIED — REVIEW BEFORE RUNNING.  This is the planned fix for security      │
-- │  finding C2 (cross-worker document exposure). It changes RLS on storage.objects, so    │
-- │  it must be validated against the admin pre-population upload path first (see below).   │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- PROBLEM (verified live, 2026-06-26):
--   The `licence-photos` bucket (passports, WWCC, police checks, right-to-work, licence
--   scans) had SELECT/INSERT/UPDATE/DELETE policies scoped to folder[1] == jwt.tenant_id.
--   The object path is `{tenant_id}/{user_id}/{licence_id}/{slot}.jpg`, so the policy only
--   checked the TENANT segment — any authenticated worker could list (`storage.list(tenant_id/)`)
--   and read EVERY co-tenant worker's ID documents. Live data showed 5 workers sharing one
--   tenant_id, mutually exposed.
--
-- VERIFIED FACTS this migration relies on:
--   * Path segment [2] is the worker's auth user_id (auth.uid()). Confirmed: 5/6 live objects'
--     seg2 matched workers.user_id; the caller passes `saved.userId` (licence_edit_screen.dart).
--   * Admins legitimately read member photos via the existing `org_admins_read_member_licence_photos`
--     policy, which keys on folder[2] == member_m.user_id — correct, kept as-is.
--   * In Cards, the ONLY uploader is the worker editing their own licence (seg2 == auth.uid()),
--     so owner-only INSERT/UPDATE does not break the worker path.
--
-- ⚠ VALIDATE BEFORE APPLYING:
--   1. Admin pre-population of a worker's licence PHOTO (if it exists) — does it run as the
--      authenticated admin (subject to RLS) or via the service role (bypasses RLS)?
--        - If service role  -> owner-only write policies below are sufficient. APPLY AS-IS.
--        - If authed admin  -> also create the admin write policies in the commented block.
--   2. One live object has seg2 matching no worker (orphan: 7dee117c/.../1244f14a-...). After
--      this migration it becomes readable only if its seg2 == some auth.uid(); otherwise it is
--      locked (safe). Investigate/clean up that orphan separately.

begin;

-- Drop the over-broad tenant-scoped policies.
drop policy if exists licence_photos_select on storage.objects;
drop policy if exists licence_photos_insert on storage.objects;
drop policy if exists licence_photos_update on storage.objects;
drop policy if exists licence_photos_delete on storage.objects;

-- Owner-scoped replacements: a worker may only touch objects under their own user_id segment.
create policy licence_photos_owner_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[2]::uuid = auth.uid()
  );

create policy licence_photos_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[2]::uuid = auth.uid()
  );

create policy licence_photos_owner_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[2]::uuid = auth.uid()
  )
  with check (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[2]::uuid = auth.uid()
  );

create policy licence_photos_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'licence-photos'
    and (storage.foldername(name))[2]::uuid = auth.uid()
  );

-- NOTE: `org_admins_read_member_licence_photos` (admin READ) is intentionally left in place.
-- Admin READ is OR'd with the owner SELECT above, so org admins keep their existing read access.

-- ── Only needed if admin photo pre-population uploads as the AUTHENTICATED admin ──────────────
-- (If pre-population uses the service role, leave this commented — service role bypasses RLS.)
--
-- create policy licence_photos_admin_write on storage.objects
--   for all to authenticated
--   using (
--     bucket_id = 'licence-photos'
--     and exists (
--       select 1
--       from public.org_memberships admin_m
--       join public.org_memberships member_m on member_m.org_id = admin_m.org_id
--       where admin_m.user_id = auth.uid()
--         and admin_m.role = 'admin'
--         and admin_m.status = 'active'
--         and member_m.user_id = (storage.foldername(name))[2]::uuid
--         and member_m.status = 'active'
--     )
--   )
--   with check ( /* same predicate as USING */ true );

commit;
