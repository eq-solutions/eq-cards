-- handle_phone_dedup accesses shell_control.users and shell_control.normalise_au_phone.
-- Without SECURITY DEFINER it runs as `authenticator` which has no USAGE on shell_control,
-- causing "permission denied" → transaction abort → 500 "Database error saving new user"
-- on every new phone OTP signup. Applied 2026-07-01 to fix new user registration.
ALTER FUNCTION public.handle_phone_dedup()
  SECURITY DEFINER
  SET search_path = public, auth, shell_control;
