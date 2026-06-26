-- 0051 — APP 3/5 consent timestamp on profiles.
-- Records the moment a worker accepted the EQ Cards privacy notice.
-- NULL = not yet consented; the client gate shows the modal.
-- RLS: existing users_update_own_profile policy already permits id = auth.uid() updates.
alter table public.profiles
  add column if not exists consented_at timestamptz;
