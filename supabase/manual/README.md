# supabase/manual

SQL in this folder is **intentionally outside `supabase/migrations/`** so that
`supabase db push` / `supabase db reset` never run it automatically.

These are changes that:

- alter **live auth behaviour** (and so require explicit sign-off before being
  applied — see the global non-negotiables: auth changes need approval before
  deployment), and/or
- target a **different project** than this repo's migrations (e.g. the
  eq-canonical control plane rather than the Cards schema), and/or
- must be applied + toggled through the **Supabase dashboard** (e.g. auth hooks),
  not via the migration runner.

Apply them by hand, deliberately, after review.

| File | Target project | What | Status |
|------|----------------|------|--------|
| `custom_access_token_hook.sql` | eq-canonical (`jvknxcmbtrfnxfrwfimn`) | Injects `app_metadata.tenant_id` + `eq_role` + `is_platform_admin` into OTP/OAuth JWTs so they can use the `cards-api` gateway | **LIVE — deployed & enabled** (verified against live 2026-06-15). File reconciled to the deployed definition. Exception handler resolved (2026-06-15): kept fail-open, added `RAISE WARNING` for observability — applied live. See `docs/cards-canonical-api-rewire.md`. |
