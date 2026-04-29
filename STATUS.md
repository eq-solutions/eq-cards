# EQ Cards — Current Status

**Last updated:** 2026-04-29 PM (overnight push)
**Posture:** Pause-and-polish + reauthorized UX/robustness work. Schema still frozen.

---

## TL;DR

EQ Cards v0.1.0 is **feature-complete for the wedge** (tap-to-copy on profile + licence fields), now with iPhone OCR fix, image cropping, search/filter/long-press, full Sentry breadcrumb trail, network retry, and a per-tab error boundary. Royce can dogfood end-to-end on iPhone PWA via Brave/Safari. Mobile native builds still deferred (Android Studio install required on the Windows host; iOS needs a Mac).

Strategic context: the broader **EQ Intake** architecture (canonical schema spine + three intake doors + every export door) is being built in a parallel Cowork session. EQ Cards is one of the three intake doors. **No schema changes** in Cards until INTAKE Sprint-1 lands. UX/robustness work on existing flows is allowed and was completed overnight (see "Latest" below).

A separate `docs/PRODUCT-TIERS.md` covers the Starter → Pro → Enterprise framing across the EQ Solutions suite — drafted overnight, awaiting real-customer-conversation pricing data before any of it goes live.

---

## Latest (overnight 2026-04-29 PM)

Four-tier overnight push, four local commits, all on `main`:

- **1cc0351 — Tier 1: iPhone OCR fix + image cropping + error UX.** `image_cropper` re-added (was deferred Phase 1). New crop step between picker and OCR with ID-1 card aspect ratio default. OCR loading dialog. Errors surfaced via SnackBar (no more silent `catch (_)` swallow). Sentry breadcrumbs across the OCR pipeline.
- **fd32ff2 — Tier 2: Search, filter, expiring-soon, long-press, onboarding.** Search field + 3 filter chips above the licence list. Long-press any card → quick-actions sheet (Open / Edit). First-launch tap-to-copy hint via SnackBar (persisted in shared_preferences). All wired without schema changes.
- **5ad17c8 — Tier 3: iPhone PWA viewport tuning.** `viewport-fit=cover` so the sky AppBar paints into the iPhone notch. `maximum-scale=1` prevents iOS auto-zoom on input focus. Multiple `apple-touch-icon` sizes for clean Add-to-Home-Screen.
- **2dddfb8 — Tier 4: Battle-testing.** Edge Function call now retries once on 5xx/network with 1.5s backoff (never on 4xx). 30s timeout. Sentry breadcrumb trail across auth + licence repos. Per-tab `_ShellErrorBoundary` so a build-phase exception in one tab renders a fallback instead of red-screening the app.
- **`docs/PRODUCT-TIERS.md`** drafted — Starter → Pro → Enterprise framing across the EQ Solutions suite. Working draft; pricing numbers placeholder, await real-customer conversations.

**Quality after the push:** `flutter analyze` No issues · `flutter test` 129/129 passing.

---

## What's done

### Code shipped this week

- **Auth** — phone OTP via Supabase. AUS mobile validator. Auto-submit on 6-digit OTP.
- **Profile** — full edit form, tap-to-copy on every row, "Copy all profile fields" induction-block button. Completion detection drives the home banner.
- **Licences** — full CRUD. 13 pre-seeded Aus tradie licence types. Type-specific metadata fields. Camera capture (mobile) → on-device ML Kit OCR + parser. Web file picker → Anthropic Claude Vision via Supabase Edge Function. Photo upload (EXIF-stripped both paths). Signed URLs for private photos. Expiry badges.
- **Magic-scanner OCR** — pre-fills `licence_number`, `licence_type`, `state`, `issuing_authority`, `issue_date`, `expiry_date` from a photo. State→authority fallback for driver licences (NSW→Service NSW, etc.).
- **Alerts** — local notifications at 90 / 30 / 7 days before expiry (mobile only).
- **Settings** — sign out, biometric toggle, app version, and a **3-direction Design picker** (Linear / Wallet / Photo-first) with persisted selection.
- **Home shell** — 3-tab Material 3 NavigationBar, biometric gate, "Complete your profile" banner.
- **Web companion** — `kIsWeb` guards on mobile-only plugins. PostHog JS snippet in `web/index.html`. CORS-safe Edge Function.
- **QR sharing** — new bottom-sheet on licence detail with `qr_flutter`-rendered QR + Copy link. Encodes a placeholder URL (`cards.eq.solutions/share?licence_id=…`) until the §18.2 share-redeem endpoint exists.

### Observability

- **PostHog** — all 9 events from ARCHITECTURE §10.2 wired and verified flowing on web (EU host). Identity sync on auth state changes. `app_opened` → `signup_completed` → `copy_field` → `licence_added` → `licence_deleted` → `qr_generated` → `profile_field_filled` → `profile_completed` → `copy_induction_block`.
- **Sentry** — DSN configured, `runZonedGuarded` wraps all of `main()` so uncaught zone errors capture cleanly. Verified by the historical "Zone mismatch" capture in the dashboard.

### Quality

- `flutter analyze`: **No issues found.**
- `flutter test`: **126 / 126 passing.** All 19 pre-existing failures from the 0.1.0 release are now green (12 golden baselines captured, 5 OCR parser bugs fixed, 2 ProfileEdit viewport tests fixed).
- **All 3 design directions ship in production** behind the Settings → Design picker (decided 2026-04-29 PM — keep all 3 as a permanent user choice, not a review tool). Persisted via `shared_preferences`.
- **Launcher icon: EQ infinity-loop mark.** Sky-on-white for iOS / web / Android legacy; white-on-sky adaptive for Android 8+ (parallax-capable). Source PNGs at `assets/icon/launcher.png` + `assets/icon/launcher_foreground.png`. Generated platform icons committed at the standard paths. In-app `Settings → Design → Linear` preview loads the same asset so it matches the home-screen icon.

### Infra

- Supabase project **`hshvnjzczdytfiklhojz`** (originally "EQ Assets") is now exclusively EQ Cards. Migrations 0001, 0002, 0003 applied.
- Edge Function **`ocr-licence`** deployed (v7). Uses Anthropic Claude Sonnet 4.6 with a forced `extract_licence` tool. JWT verified manually inside the function (gateway `--no-verify-jwt` so CORS preflight works).
- **Netlify drag-drop deploy** working. Production builds at `build/web/`. Auto-deploy via GitHub not yet wired.

---

## What's paused

Nothing in this list should be picked up unilaterally — wait for INTAKE Phase 1 to land or an explicit instruction.

**Schema is frozen.** No new tables. **No new columns on `profiles` or `licences`.** The current shape is what we polish on; any data-model change waits for the canonical spine. (Reaffirmed by Cowork 2026-04-29.)

- Multi-tenant migration (`tenant_id`, `schema_version` columns) — spine work, not Cards work
- New canonical entities (SWMS / prestarts / JSAs / toolbox / incidents / ITPs) — those land in the canonical project from day one, not in Cards
- Share-redeem endpoint — external-consumer work, post-migration (the QR currently links to a stub URL; fine for the pause window)
- Custom domain `cards.eq.solutions` (Netlify custom domain)
- GitHub → Netlify auto-deploy wiring
- Twilio production OTP delivery (test OTP via dashboard still required)
- Apple Wallet pass generation
- Drift offline cache
- Public launch / wider invite list
- Mobile builds (Android Studio install on Windows host; iOS deferred — Mac required)

---

## What's allowed during the pause

- Bugfixes on the existing code paths
- Polishing OCR accuracy if real photos surface gaps
- ~~Picking ONE of the 3 design directions and trimming the other two~~ **Decided 2026-04-29 PM:** all 3 ship in production behind the Settings picker. No trimming.
- Real licence-photo testing on a phone (RUNBOOK §12)
- ~~Pilot 2-3 real users on what's already built~~ **Decided 2026-04-29 PM:** no public/real-user pilots until INTAKE Sprint-1 lands. Royce uses the Netlify zip for personal demos only.
- Documentation cleanup (this file, CHANGELOG, RUNBOOK, ARCHITECTURE)
- Verifying analytics taxonomy continues to fire cleanly in PostHog

### Production-quality work explicitly parked (2026-04-29 PM)

Considered and deferred. INTAKE Sprint-1 will reshape the data model; production-quality investment in current Cards architecture compounds with that work, so it waits.

- Twilio production OTP wiring
- Cost cap / rate-limit on the `ocr-licence` Edge Function
- Privacy policy + Terms of Use drafting and Settings wiring
- Real iOS app on TestFlight (needs Mac / CI runner / Apple Dev account)
- Real Android APK / Play Internal Testing
- Customer-support email + onboarding flow
- App Store / Play Store listings
- Pilot users / wider invite list

**Do not pick any of these up unilaterally.** Reauthorize individually, or wait for INTAKE Sprint-1 to ship and re-evaluate the whole list.

---

## Coordination with EQ Intake

EQ Intake is the broader frame: a canonical schema spine that every EQ surface (Cards mobile, Import desktop, Capture vision) feeds, and that every output target (job-mgt, accounting, client portals, compliance bundles) consumes.

EQ Cards is **one of the three intake doors.** Specifically the mobile surface. The first wedge there is **inductions** — do once in EQ, export in whichever format the next site demands.

### Schema mapping (current → INTAKE canonical)

| EQ Cards (today) | EQ Intake canonical |
|---|---|
| `profiles` | `staff` (a Cards user is a Staff record where `role = self`) |
| `licences` | (no direct canonical equivalent yet — a `licence` entity is implied by inductions/SWMS attachments and may be added) |
| `audit_log` | Subsumed by `eq_intake_row_audit` + `eq_intake_events` |

### Document reconciliation pending

`ARCHITECTURE.md §18` of this repo says "no shared database, each EQ module gets its own Supabase project, share API with consent." That's a different architecture from INTAKE's "one canonical schema spine, multi-tenant by RLS." Two ways to reconcile when INTAKE Sprint-1 lands:

1. **§18 is replaced.** EQ Cards data moves to (or is mirrored in) the canonical Supabase project. The share API §18.2 becomes the export profile for the "Cards user shares their wallet with this site" scenario.
2. **§18 is reframed as a module-local cache.** EQ Cards keeps its own Supabase project for offline-first / latency reasons. A federated layer pulls from it into the canonical spine.

Don't action either yet. Flagged in `ARCHITECTURE.md §18` with a TODO referencing this file.

### Standing rules from the INTAKE bundle that apply here

- **Generic placeholders only** in any output. No real client names. (Already followed.)
- **Inductions / SWMS / safety-critical features never paywalled.** When EQ Cards eventually exposes induction export, that path is free.
- **Auth changes require Chat review before deployment.** (Already in the global CLAUDE.md.)
- **SELECT-only on Supabase without approval; never touch SKS live data unless explicitly told.**
- **Self-critique applied** — high-stakes, real people depend on it.

---

## Where things live

### Repo (this folder)

| Path | What |
|---|---|
| `lib/` | Flutter app source |
| `test/` | Tests (126/126) |
| `supabase/migrations/` | 0001 / 0002 / 0003 — applied |
| `supabase/functions/ocr-licence/` | Claude Vision Edge Function |
| `web/` | Web bundle source (`index.html` has the PostHog JS snippet) |
| `android/`, `ios/` | Platform folders (manifests + Info.plist wired with permissions) |
| `ARCHITECTURE.md` | Phase-0 binding contract + open questions |
| `CHANGELOG.md` | Full session-by-session history |
| `RUNBOOK.md` | First-morning setup + OCR smoke test plan |
| `SCHEMA.md` | DB schema with RLS policies |
| `progress.html` | Single-page status board (visual) |
| `STATUS.md` | This file |
| `.dart-defines.json` | Dev secrets (gitignored) |

### Live infrastructure

| Service | URL / ID |
|---|---|
| Supabase project | `hshvnjzczdytfiklhojz` (eq-cards) |
| Edge Function | `https://hshvnjzczdytfiklhojz.supabase.co/functions/v1/ocr-licence` |
| PostHog | `eq-production` project, EU host (`eu.i.posthog.com`), token in `.dart-defines.json` |
| Sentry | `eq-cards` project, EU host, DSN in `.dart-defines.json` |
| Local dev | `http://localhost:8765/` (when `flutter run -d edge --web-port=8765` is running) |
| Netlify | Manual drag-drop only; no fixed URL yet |

### Tools installed this week

- **Supabase CLI** at `C:\Users\EQ\.eq-tools\supabase\supabase.exe` (on user PATH). Already linked to the eq-cards project.
- **Flutter SDK** at `C:\Projects\flutter` (relocated from OneDrive).

---

## Resuming work — first commands

```powershell
# In a fresh PowerShell window.
cd C:\Projects\eq-cards
flutter analyze              # expect: No issues found
flutter test                 # expect: 126 / 126 passing
flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.json
# App at http://localhost:8765/
```

If `flutter` isn't on PATH, the SDK is at `C:\Projects\flutter\bin`.

---

## When something needs to change

- **Approve a deploy** — say "deploy". I'll re-deploy the Edge Function or build the web bundle as appropriate.
- **Pick a design** — tell me which of Linear / Wallet / Photo-first wins; I trim the other two and wire the chosen icon into `ios/Runner/Assets.xcassets/AppIcon.appiconset/` + `android/.../mipmap-*/`.
- **Re-evaluate the pause** — when INTAKE Phase 1 ships (or earlier if you decide), come back and say which of the two §18 reconciliation paths to take.

---

## Notable session-history bookmarks (for future agents)

- 7-iteration OCR Edge Function debug chain — see `CHANGELOG.md` "Edge Function deploys this sprint." TL;DR: HTTP 204 No Content forbids response bodies, Deno throws if you set one.
- "Zone mismatch" Sentry crash → fixed by wrapping all of `main()` in one `runZonedGuarded` and dropping Sentry's `appRunner` parameter.
- Pre-existing test failures (12 goldens, 5 OCR parsers, 2 ProfileEdit viewport) — all closed during the overnight sprint 2026-04-28→29.

---

**This file is the source of truth for "where is EQ Cards?" Update it on every meaningful change.**
