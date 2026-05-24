-- seed.sql
-- Local dev seed data. Applied after all migrations on `supabase db reset`.
-- Contains NO real credentials — use .env.local for secrets.

-- ============================================================
-- Organisations (local dev only)
-- ============================================================

insert into public.organisations (id, name, slug) values
  ('00000000-0000-0000-0000-000000000001', 'EQ Solutions',    'eq-solutions'),
  ('00000000-0000-0000-0000-000000000002', 'SKS Technologies', 'sks')
on conflict do nothing;

-- ============================================================
-- Note on test users
-- ============================================================
-- Auth users are NOT seeded here — Supabase local auth creates users
-- via OTP or via the dashboard. For scripted test users, run:
--
--   supabase db seed --db-url postgresql://... < scripts/create_test_users.sql
--
-- or use the Supabase Studio (http://127.0.0.1:54323) → Authentication → Users.
--
-- Once test users exist locally, add them to orgs via org_memberships:
--
--   insert into public.org_memberships (org_id, user_id, role, status, accepted_at)
--   values (
--     '00000000-0000-0000-0000-000000000001',
--     '<user-uuid>',
--     'admin', 'active', now()
--   );
