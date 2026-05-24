# EQ Cards — Current Status

**Last updated:** 2026-05-24
**Posture:** Active — Unit 4 (canonical flip + Shell SSO) shipped. App is live at
`cards.eq.solutions`, iframe-embedded in EQ Shell at `core.eq.solutions/:tenant/cards`.

---

## What shipped (2026-05-20 → 2026-05-23)

### 2026-05-20 — Pilot readiness: email-OTP + polish + iframe embed

Three back-to-back sessions hardened Cards for real testers:

- **Auth: email OTP (commit `33fcaeb`).** Phone-OTP + Twilio dependency dropped. Auth now
  uses Supabase's built-in mailer: `/auth/email` → enter address → 6-digit code → session.
  `validateEmail()` validator, breadcrumb masks email. 195 tests pass after rename +
  rewrite of `phone_entry_screen_test`.

- **Netlify: `netlify.toml` + site config (commit `fa3bb77`).** Site ID
  `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72`. Deploys are manual (`netlify deploy --prod`
  or drag-drop). GitHub auto-deploy is explicitly NOT wired — production releases are
  gated by an explicit step per global EQ rules.

- **Polish packs A+B+C (commit `0757115`).** 528 lines across 11 files, 196/196 passing.

  - **A1 — OCR rate-limit.** 20 calls/hour/user enforced server-side via a new
    `check_and_record_ocr_usage` RPC + `public.ocr_usage` table (migration 0005).
    Edge Function `ocr-licence` v9 calls it before forwarding to Anthropic; over-limit
    returns HTTP 429 → Flutter shows "you've used your 20 magic-scans for the hour."
    Closes the unbounded-cost risk.

  - **A2 — Privacy consent toggles.** Analytics opt-out + crash-reporting opt-out wired.
    `lib/core/privacy/privacy_prefs.dart` (SharedPreferences). `AnalyticsService` and
    Sentry's `beforeSend` hook both read the prefs; hydrated in `main()` before SDKs
    init. Default: opted in (matches Privacy Policy).

  - **B3 — Splash branding.** Replaced bare `CircularProgressIndicator` with EQ launcher
    mark + "EQ Cards" name + sky spinner.

  - **B4 — Help & feedback in Settings.** Dedicated section with "Get help" + "Send
    feedback" rows. Both compose a prefilled `mailto:contact@eq.solutions`. Sign-out
    copy updated from "phone" to "email" (stale copy from phone-OTP era).

  - **C1 — OCR loading copy.** "First scan of the day may take a few seconds while we
    warm up the magic-scanner" sets the cold-start expectation.

  - **C3 — Error state on licences list.** `_ListErrorState` widget: detects
    `NotAuthenticatedFailure` → "Sign in again" CTA; everything else → "Try again."

- **iframe-embed support (commit `9bcd02c`).** EQ Shell at `<tenant>.eq.solutions` now
  mounts Cards via iframe at `/:tenant/cards`. Changes to `web/_headers`:
  - Dropped `X-Frame-Options: DENY` in favour of granular CSP `frame-ancestors`.
  - `frame-ancestors 'self' https://*.eq.solutions` — only eq.solutions subdomains
    can frame Cards; everything else blocked.

- **Legal docs filled (commit `3f39990`).** Entity placeholders in
  `docs/PRIVACY-POLICY.md` + `docs/TERMS-OF-USE.md` replaced with real names for
  pilot launch.

### 2026-05-21 — Unit 3: Data migration to eq-canonical (commit `df521a9`)

One-time migration script (`scripts/migrate-to-canonical.ts`) migrates EQ Cards data
from the legacy Supabase project (`hshvnjzczdytfiklhojz`) to eq-canonical
(`jvknxcmbtrfnxfrwfimn`):

- Writes via `eq_intake_commit_batch` RPC (not direct INSERT) — idempotent, safe to
  re-run.
- Dry-run by default; `--apply` flag required for writes.
- Photos: `licence-photos` bucket → canonical `tenant-{tenant_id}` bucket, path
  `licences/{licence_id}/{side}.jpg`.
- Per-intake rollback via `eq_intake_rollback` RPC.

**Migration is complete.** The old project is kept live for the rollback window; CSP
allows both.

### 2026-05-21–22 — Unit 4: Canonical flip + Shell SSO (merge `cd00fc1`)

The Flutter app now reads/writes from eq-canonical (`jvknxcmbtrfnxfrwfimn`) via
`public.eq_cards_*` RPCs. Auth is primarily Shell JWT handoff.

**Schema/RPC migrations applied to eq-canonical:**
- `2026_05_21_eq_cards_rpcs` — `eq_cards_list_my_licences`, `eq_cards_upsert_my_licence`,
  `eq_cards_soft_delete_my_licence`
- `2026_05_21_staff_personal_fields_for_cards` — 8 extra columns on `app_data.staff`
  (DOB, address, emergency contact) backfilled for Royce
- `2026_05_21_eq_cards_profile_rpcs` — `eq_cards_current_staff` + `eq_cards_upsert_my_profile`
- `2026_05_21_licence_photos_policies_phase_1f` — licence-photos RLS updated to
  `app_metadata.tenant_id`; path convention: `{tenant_id}/{staff_id}/{licence_id}/{slot}.jpg`

**Flutter changes:**
- New `IframeHandoffScreen`: reads `#sh=<jwt>` from URL hash → `setSession` → `/licences`.
- Auth screens from email-OTP era deleted (Unit 4 initially shipped Shell-only; see Unit 4.1
  below for the restore).
- `LicenceRepository`, `ProfileRepository`, `PhotoUpload` all updated to use RPCs and the
  new canonical photo path.

**Unit 4 fixes:**
- `6b55b22` — `setSession(token, accessToken: token)` — correct keyword arg.
- `e765846` — Read `tenant_id` from `app_metadata` via JWT, not `currentUser.appMetadata`.
- `11f8712` — Disabled the service worker (was caching the old auth flow in the Shell
  iframe).

**Tests after Unit 4:** 190 passing.

### 2026-05-23 — Post-Unit-4 polish (commits `aa43666`, `9afd10c`, `9629fa6`, `2996fb9`, `dad4ad8`, `0471433`, `7db6d3d`)

- **Email-OTP restored alongside Shell handoff (commit `aa43666`).** Unit 4 initially
  dropped email-OTP (Shell-only). This commit restores a two-path auth flow:
  - **Path 1 (Shell iframe):** `#sh=<jwt>` in URL hash → `IframeHandoffScreen` →
    `setSession` → `/licences`.
  - **Path 2 (direct / standalone):** no hash → `/auth/email` → email OTP →
    `/auth/otp` → `/licences`.
  Both paths land in the same authenticated Supabase session on eq-canonical.

- **Live licence-share QR + canonical token alignment (commit `7db6d3d`, fix `0471433`).**
  The QR share feature is now live (was demoware in v0.1.0). Token aligned to canonical;
  two-query pattern to avoid missing FK join on the eq-canonical schema.

- **SW kill-switch for stale cache (commits `2996fb9`, `9629fa6`).** Service worker
  reset deployed for users stuck on the pre-Unit-4 build.

- **CSP fix: eq-canonical in `_headers` (commit `9afd10c`).** Both Supabase projects
  allowed in CSP during rollback window.

- **Redirect fix (commit `dad4ad8`).** Open-shell (no EQ Shell context) redirect goes
  to `core.eq.solutions` not the apex domain.

---

## Current state

### Auth flow

| Entry point | Flow |
|---|---|
| EQ Shell iframe | `#sh=<jwt>` in URL hash → `IframeHandoffScreen` → `setSession` → `/licences` |
| Direct / standalone | No hash → `/auth/email` → email OTP → `/auth/otp` → `/licences` |

### Infrastructure

| Service | URL / ID | Notes |
|---|---|---|
| **Supabase** | `jvknxcmbtrfnxfrwfimn` (eq-canonical) | All profile + licence data; Edge Functions; OCR |
| Edge Function (OCR) | `https://jvknxcmbtrfnxfrwfimn.supabase.co/functions/v1/ocr-licence` | Deployed to eq-canonical 2026-05-24 |
| Edge Function (share) | `https://jvknxcmbtrfnxfrwfimn.supabase.co/functions/v1/share-licence` | Deployed to eq-canonical 2026-05-24 |
| PostHog | `eq-production` project, EU host (`eu.i.posthog.com`) | All 9 v1 events wired |
| Sentry | `eq-cards`, EU host | `runZonedGuarded` wraps `main()` |
| **Live PWA** | `https://cards.eq.solutions` | Netlify, manual deploy, custom domain LIVE |
| Shell embed | `https://core.eq.solutions/:tenant/cards` | Shell hands off JWT via `#sh=` hash |
| Local dev | `http://localhost:8765/` | `flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.json` |
| Netlify site ID | `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72` | `netlify deploy --prod` from `build/web/` |

### Quality

- `flutter analyze`: No issues found (as of Unit 4 merge `cd00fc1`)
- `flutter test`: 190 passing (Unit 4); email-OTP restore added more — run `flutter test`
  for the live count

---

## What's done (cumulative)

Full history in CHANGELOG.md. Key milestones:

- **v0.1.0 phase 1** — auth, profile, licences, OCR, alerts, settings, home shell
- **Overnight sprints** — iPhone OCR fix, search/filter, battle-test, test coverage (+65 tests)
- **Onboarding polish** — cropper UX, skip-OCR, legal links, support dialog (196/196)
- **Agent-review security sweep** — correctness, UX, gitignore, doc hygiene
- **Email-OTP pilot auth** — Twilio dependency dropped; Supabase mailer
- **Polish packs A+B+C** — OCR rate-limit, privacy toggles, splash, help, error states
- **iframe-embed support** — EQ Shell can frame Cards at `*.eq.solutions`
- **Unit 3** — data migrated from legacy Supabase to eq-canonical
- **Unit 4** — Flutter on eq-canonical, Shell JWT handoff, all RPCs updated
- **Two-path auth** — Shell JWT (primary) + email-OTP (standalone/demos) live
- **Live QR share** — canonical token alignment, two-query FK fix
- **SW kill-switch** — users stuck on stale build reset automatically
- **`cards.eq.solutions` custom domain** — LIVE on Netlify

---

## What's next

### 1. GitHub → Netlify auto-deploy

Not wired — `netlify.toml` explicitly gates on manual deploys. Requires Netlify env
vars for dart-defines (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`,
`POSTHOG_API_KEY`). Held pending a production secrets review.

### 5. GTM validation gate — 5 outside-SKS sparkies on Cards

From `eq/pending.md`: the EQ GTM priority is to validate the product with 5
outside-SKS trade subbies before further build investment. Cards is the wedge product.

Steps:
- Identify first 5 outside-SKS trade subbies
- Send outreach message (direct pilot invite via `cards.eq.solutions`)
- Onboard via email-OTP standalone flow
- Track `copy_field` events in PostHog — ≥5/week per user = wedge working

### 6. EQ Intake migration trigger (when canonical is ready)

Per `EQ-CARDS-INTAKE-BRIDGE.md` (Path A decision): Cards data is already in
eq-canonical. When the second EQ surface needs to read shared user data, the
integration will be RLS-gated direct access — no token exchange needed. The remaining
work is confirming the `app_data.staff` ↔ Cards `profiles` field mapping is complete.

---

## What's deferred

- Mobile builds (Android Studio on Windows host; iOS needs Mac)
- Apple Wallet pass generation
- Drift offline cache + offline writes
- Phase 2 share-redeem endpoint (external consumers only — non-EQ surfaces)
- Twilio SMS OTP (email-OTP is standard now; phone-OTP re-evaluation deferred)
- Public launch / wider invite list beyond the 5-sparky pilot

---

## Where things live

### Repo

| Path | What |
|---|---|
| `lib/` | Flutter app source |
| `test/` | Tests (≥190 passing; run `flutter test` for live count) |
| `scripts/migrate-to-canonical.ts` | Unit 3 one-time migration script (idempotent, `--apply` required for writes) |
| `scripts/README.md` | Usage instructions + safety properties for the migration script |
| `supabase/migrations/` | 0001–0005 applied to legacy project; canonical schema managed via MCP/Studio |
| `supabase/functions/ocr-licence/` | Claude Vision Edge Function — deployed to eq-canonical |
| `supabase/functions/share-licence/` | Public QR share endpoint — deployed to eq-canonical |
| `web/` | Web bundle source (`_headers` has CSP; `index.html` has PostHog snippet) |
| `netlify.toml` | Netlify site config — build publish dir + SPA redirect |
| `.dart-defines.prod.json` | Production dart-defines pointing at eq-canonical (gitignored) |
| `ARCHITECTURE.md` | Binding architecture contract (§18 updated for canonical resolution) |
| `CHANGELOG.md` | Full session-by-session history |
| `RUNBOOK.md` | First-morning setup + OCR smoke test |
| `SCHEMA.md` | Legacy DB schema (pre-Unit-4); eq-canonical schema via MCP |

### Tools

- **Supabase CLI** at `C:\Users\EQ\.eq-tools\supabase\supabase.exe` (on PATH).
- **Flutter SDK** at `C:\Projects\flutter`.

---

## Resuming work — first commands

```powershell
cd C:\Projects\eq-cards
flutter analyze              # expect: No issues found
flutter test                 # expect: ≥190 passing
flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.prod.json
# App at http://localhost:8765/
# Direct path: goes to /auth/email (email-OTP flow)
# Shell path: open core.eq.solutions/:tenant/cards (Shell JWT handoff)
```

Both `.dart-defines.prod.json` and `.dart-defines.json` point at eq-canonical (`jvknxcmbtrfnxfrwfimn`). Legacy project decommissioned 2026-05-24.

---

## Notable session-history bookmarks (for future agents)

- **Unit 4 canonical flip** — Flutter now uses `eq_cards_*` RPCs on eq-canonical.
  Flutter models unchanged; the RPCs bridge the column renames (`user_id` → `staff_id`,
  etc.). JWT `app_metadata.tenant_id` is the tenant identifier throughout.
- **Two-path auth** — `IframeHandoffScreen` (`#sh=<jwt>`) for Shell embed; email-OTP
  (`/auth/email` → `/auth/otp`) for standalone/direct access. Both paths land in the
  same Supabase session on eq-canonical.
- **SW kill-switch** — `web/` contains a service-worker-reset mechanism for users
  stuck on old cached builds. Check `11f8712` and `2996fb9` if stale-build issues recur.
- **OCR + share Edge Functions on eq-canonical** — both `ocr-licence` and `share-licence` deployed to `jvknxcmbtrfnxfrwfimn` 2026-05-24. Legacy project decommissioned.
- **§18 reconciliation resolved** — Path A (consolidate to canonical) taken. See
  `ARCHITECTURE.md §18` (updated).
- **7-iteration OCR debug chain** — see CHANGELOG "Edge Function deploys this sprint."
  HTTP 204 No Content forbids response bodies; Deno throws if you set one.
- **"Zone mismatch" Sentry crash** — fixed by wrapping all of `main()` in one
  `runZonedGuarded` and dropping Sentry's `appRunner` parameter.

---

**This file is the source of truth for "where is EQ Cards?" Update it on every meaningful change.**
