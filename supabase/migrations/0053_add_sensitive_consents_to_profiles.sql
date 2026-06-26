-- Stores per-category sensitive-information consent timestamps for APP 3.3
-- compliance. Structure: { "biometric": "2026-06-27T10:00:00Z", ... }
-- Categories match SensitiveCategory.name values in the Dart layer.
alter table public.profiles
  add column if not exists sensitive_consents jsonb not null default '{}'::jsonb;
