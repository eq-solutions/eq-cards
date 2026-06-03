# Changelog

All notable changes to EQ Cards are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### 2026-06-04 — Download licence photos as image files

- **New download action on the licence detail screen.** A download icon in the
  app bar (beside QR share) saves a licence's photo to the device. One photo
  saves immediately; with both front and back present a bottom sheet asks which
  to save; with none it says so. Files are named descriptively, e.g.
  `white-card-12345-front.jpg`.
- **Why a fetch-then-blob, not a plain link.** Licence photos live behind
  cross-origin, short-lived Supabase signed URLs, so an `<a download>` pointing
  at the URL is ignored by the browser. New `core/utils/image_download.dart`
  fetches the bytes with the cross-platform `http` client, then hands them to a
  web-only save step (`image_download_web.dart`, `dart:html` blob + anchor)
  behind the same conditional-import pattern as the rest of the app — the IO
  stub keeps `flutter test` (VM target) compiling. On a failed fetch (e.g. the
  signed URL expired) the user is told to reopen the licence and retry.
- Fires a `licence_photo_downloaded` analytics event. Pure filename builder is
  unit-tested.

### 2026-05-30 — Repo dead-weight audit + cleanup

Audited the repo for unused code, dependencies, and stale artifacts. Removed 8 files;
no behaviour change — every deletion verified zero-reference, codegen rebuilt, and
`flutter analyze` clean (0 errors).

- **Dead Dart removed.** `core/utils/logger.dart` (`logD/logI/logW` — never called),
  `core/error/result.dart` (`Result`/`Success`/`FailureResult` — abandoned pattern; the
  codebase throws `Failure` instead), `core/widgets/eq_snackbar.dart` (`EqSnackbar` —
  never invoked).
- **Duplicate legal docs removed.** `docs/PRIVACY-POLICY.md` and `docs/TERMS-OF-USE.md`
  were byte-identical to the shipped `assets/legal/*.md`, with no generator between them.
  `assets/legal/*` is now the single source of truth; also dropped the internal "Source:"
  footer that was leaking into the in-app Privacy Policy render.
- **Stale artifacts removed.** `progress.html` (manual status board, superseded by
  STATUS.md + this CHANGELOG); `scripts/migrate-to-canonical.ts` (completed one-time
  Unit 3 migration) and its `scripts/README.md`.
- **Docs synced.** `ARCHITECTURE.md` file tree, shared-widgets list, and §18 updated to
  drop references to the removed files.

**Follow-up — flagged items resolved (same day):**

- **Unused deps removed.** `firebase_core` + `firebase_messaging` (push never built; FCM
  stays deferred to v1.1) and `flutter_secure_storage` (orphaned direct dep — Supabase
  persists its session via `shared_preferences`, not secure storage). Corrected the
  inaccurate in-code comment and the ARCHITECTURE §11.1 security note, which had claimed
  tokens lived in encrypted Keychain/EncryptedSharedPreferences (never wired). 13
  transitive packages dropped; no Dart usage existed.
- **Migration filename collision fixed.** `0006_certificates.sql` → `0009_certificates.sql`
  (collided with `0006_org_layer.sql`). Local-only rename — eq-canonical tracks migrations
  by timestamp via MCP (`org_layer` and `certificates` applied at distinct versions), so
  the remote is unaffected.
- **Lint dead code removed.** 3 barrel-redundant imports in `app_router.dart`, an unused
  `dart:typed_data` import, and an unused `AuthChangeEvent` show clause. `flutter analyze`:
  36 → 30 issues, 0 errors.
- **`cards_api.dart` kept + documented.** Decision: retain as intentional built-ahead
  scaffolding for the post-2.B data-plane flip; added a STATUS header so it's not mistaken
  for dead weight. Repos still use direct `eq_cards_*` RPCs until the cutover.
- **Analyzer brought fully clean (30 → 0).** Cleared every remaining `flutter analyze`
  finding (all infos/warnings — 0 errors throughout). `dart fix` auto-applied 19 (directive
  ordering, trailing commas, quote/escape style, an unnecessary cast, null-aware operator,
  and the `DropdownButtonFormField` `value:`→`initialValue:` deprecation). The rest by hand:
  explicit `rpc<dynamic>` type args in `pin_repository`, doc-comment `[Symbol]` → inline
  code where the symbol wasn't in scope, `unawaited()` on a fire-and-forget
  `subscription.cancel()`, three missing end-of-file newlines, and declaring the SDK package
  `flutter_web_plugins` explicitly. Also removed a phantom `image_cropper` import in
  `licence_crop_screen.dart` that existed only to resolve a doc link (the package is still
  used on mobile via `licence_crop.dart`). The dropdown rename was verified
  behaviour-preserving against the Flutter source (`didUpdateWidget` re-syncs `initialValue`
  on rebuild) and by the passing profile/licence hydration tests — test suite unchanged at
  185 pass / 5 pre-existing environmental golden failures.
- **README rewritten.** Replaced the default Flutter stub ("A new Flutter project") with a
  real project README: what Cards is, the stack, local-run + codegen + quality-gate
  commands, the backend/auth model, deploy guardrails, and pointers to ARCHITECTURE /
  STATUS / CHANGELOG.

---

### 2026-05-23 — Post-Unit-4 polish (commits `aa43666`, `9afd10c`, `9629fa6`, `2996fb9`, `dad4ad8`, `0471433`, `7db6d3d`)

Six targeted fixes and one feature restore shipped the day after Unit 4 merge.

- **Email-OTP sign-in restored alongside Shell handoff (commit `aa43666`).** Unit 4
  initially shipped Shell-only auth. This restores a two-path flow:
  - **Path 1 (Shell iframe):** `#sh=<jwt>` in URL hash → `IframeHandoffScreen` →
    `setSession` → `/licences`.
  - **Path 2 (direct / standalone):** no hash → `/auth/email` → email OTP →
    `/auth/otp` → `/licences`.
  New files: `email_entry_screen.dart`, `otp_screen.dart`, `auth_flow_notifier.dart`,
  `auth_flow_state.dart`, `Routes.email`, `Routes.otp`. `IframeHandoffScreen`
  no-hash branch routes to `/auth/email`. All paths land in the same Supabase session
  on eq-canonical.
- **Live licence-share QR + canonical token alignment (commit `7db6d3d`).** QR share
  moved from demoware to live: token aligned to eq-canonical, share URL updated.
- **Share-licence fix: two-query pattern (commit `0471433`).** Switched from a join
  query to a two-query pattern to avoid missing FK join on the eq-canonical schema.
- **Redirect fix: `core.eq.solutions` not apex (commit `dad4ad8`).** Open-shell
  (no EQ Shell context) now redirects to the Shell at `core.eq.solutions` instead of
  the apex domain.
- **SW kill-switch (commits `2996fb9`, merge `9629fa6`).** Service worker reset
  deployed for users stuck on the pre-Unit-4 cached build. Sends `SKIP_WAITING` to
  any registered service worker then reloads.
- **CSP: eq-canonical added to `_headers` (commit `9afd10c`).** All CSP directives now
  include `jvknxcmbtrfnxfrwfimn.supabase.co` alongside the legacy project. Both
  projects allowed during the rollback window.

---

### 2026-05-21–22 — Unit 4: canonical flip + Shell SSO (branch commit `0d14c50`, fixes `6b55b22` `e765846` `11f8712`, merge `cd00fc1`)

The major architectural shift: Cards Flutter app flipped from the legacy per-module
Supabase project (`hshvnjzczdytfiklhojz`) to eq-canonical (`jvknxcmbtrfnxfrwfimn`).
Auth switched to EQ Shell JWT handoff. Resolves `ARCHITECTURE.md §18` reconciliation.

#### Schema / RPCs applied to eq-canonical

Four migrations applied to eq-canonical via MCP:

- `2026_05_21_eq_cards_rpcs` — `eq_cards_list_my_licences`,
  `eq_cards_upsert_my_licence(jsonb)`, `eq_cards_soft_delete_my_licence`. Bridge RPCs
  that handle column renames so Flutter models stay unchanged.
- `2026_05_21_staff_personal_fields_for_cards` — 8 columns added to `app_data.staff`
  (DOB, address fields, emergency contact) so Cards keeps the same profile shape.
  Backfilled for Royce.
- `2026_05_21_eq_cards_profile_rpcs` — `eq_cards_current_staff` +
  `eq_cards_upsert_my_profile`.
- `2026_05_21_licence_photos_policies_phase_1f` — Dropped stale `user_metadata`-based
  `licence_photos_*` policies; recreated against `app_metadata.tenant_id`. New path
  convention: `{tenant_id}/{staff_id}/{licence_id}/{slot}.jpg`.

#### Flutter changes

- New `IframeHandoffScreen` reads `#sh=<jwt>` from URL hash, calls
  `Supabase.auth.setSession(token, accessToken: token)`, then GoRouter lands on
  `/licences`. `dart:html` behind conditional import so `flutter test` (VM target)
  loads cleanly.
- Auth screens from email-OTP era deleted in this commit (restored in `aa43666`
  the next day; see above).
- `LicenceRepository.getAllForCurrentUser` / `upsert` / `softDelete` call the
  `eq_cards_*` RPCs. `licenceToUpsertPayload` no longer takes `userId` (RPC resolves
  `staff_id` server-side from JWT).
- `ProfileRepository.getCurrent` / `upsert` call `eq_cards_current_staff` /
  `eq_cards_upsert_my_profile`. `profileToUpsertPayload` no longer sends `id`.
- `PhotoUpload` paths updated to `{tenant_id}/{staff_id}/{licence_id}/{slot}`.
- Router: `/auth/email` + `/auth/otp` removed, `/auth/handoff` added as the sole
  unauthenticated route. `_redirect` sends unsigned users to `/auth/handoff`.
- New `.dart-defines.prod.json` pointing at `jvknxcmbtrfnxfrwfimn`.

#### Unit 4 fixes

- **`6b55b22`** — `setSession` requires keyword arg: `(token, accessToken: token)`.
- **`e765846`** — `tenant_id` must be read from the JWT `app_metadata`, not
  `currentUser.appMetadata` (which was always null).
- **`11f8712`** — Disabled the service worker; it was caching the old auth flow
  inside the Shell iframe, causing silent auth failures after deploy.

**Tests after Unit 4:** 190 passing (`flutter analyze` clean; 6 email-auth tests
deleted in step 1, restored in `aa43666`).

---

### 2026-05-21 — Unit 3: data migration script (commit `df521a9`)

`scripts/migrate-to-canonical.ts`: one-time migration of Cards Supabase
(`hshvnjzczdytfiklhojz`) `profiles` + `licences` → eq-canonical
(`jvknxcmbtrfnxfrwfimn`) `app_data.staff` + `app_data.licences`.

- Writes via `eq_intake_commit_batch` RPC (not direct INSERT).
- Idempotent: `imported_from = 'eq_cards_supabase_2026_05_20'` dedup key.
- Photo migration: `Cards licence-photos` bucket → canonical
  `tenant-{tenant_id}` bucket with `licences/{licence_id}/{side}.jpg` paths.
- Dry-run by default; `--apply` required for writes.
- Per-intake rollback via `eq_intake_rollback` RPC.
- `scripts/README.md` added with usage instructions + safety properties.

**Migration run completed.** Data is live on eq-canonical.

---

### 2026-05-21 — Onboarding-walkthrough polish (merge `94fd7c5`, branch commit `6c10d53`)

Six fixes flagged by Royce after watching a real user upload a licence
mid-onboarding and look for a "Scan" button that wasn't there. Schema
untouched.

- **Cropper button now reads "Scan licence"** on web + iOS so the
  OCR-trigger intent is obvious. (Previous default was "Crop"/"Done".)
  Cropper config extracted to `lib/features/licences/presentation/helpers/licence_crop.dart`
  and reused on the edit screen, so photo replacements also go through
  crop + JPEG-85 compression. Edit-screen `_pickPhoto` no longer ships
  raw uncompressed photos to storage.
- **Skip-OCR cancel actually short-circuits the flow.** Previously the
  cancel button just dismissed the dialog while OCR kept running
  invisibly, then auto-navigated 5-10s later with the prefill the user
  had asked to skip. Now races OCR vs cancel via `Future.any`; user-skip
  navigates immediately with photo-only.
- **Privacy Policy + Terms of Use linked from the sign-up screen** as a
  Privacy Act collection notice. Layout wrapped in `SingleChildScrollView`
  so the column survives small viewports.
- **Get help / Send feedback** now opens a real composer dialog
  (formatted To/Subject/Body + "Copy email" button) instead of dropping
  a `mailto:` URI on the floor.
- **QR-share sheet copy** softened to be honest about the placeholder
  URL — Phase 2 share-redeem endpoint isn't live, so onboarding demos
  no longer set up a dead-URL surprise.

Quality after the merge: `flutter analyze` clean, `flutter test` 196/196.

---

### 2026-05-20 — Pilot readiness: email-OTP + Polish packs A+B+C + iframe embed

Three sessions on 2026-05-20 hardened Cards for real testers before the SKS-tester
URL went live.

#### Auth: email OTP (commit `33fcaeb`)

Phone-OTP + Twilio dependency dropped. Auth now uses Supabase's built-in mailer —
free for low volume and no Twilio billing or account required for a 5–50 tester
pilot.

- `phone_entry_screen.dart` → `email_entry_screen.dart`. Validates with
  `validateEmail()`, lowercases + trims, explains "new accounts created on first
  sign-in" so testers don't hunt for a signup button.
- `AuthRepository.sendOtp` / `verifyOtp` take `email` instead of `phone`;
  Supabase calls switched to `signInWithOtp(email:)` and
  `verifyOTP(email:, type: OtpType.email)`.
- OTP screen copy updated: "Sent to `<email>`" with spam/60-min-expiry hint.
  PILOT_MODE banner removed.
- Analytics: `signup_completed` method changed from `'phone'` to `'email'`.
- `docs/PRIVACY-POLICY.md` + `TERMS-OF-USE.md` updated: email as sign-in
  identifier; Twilio removed from sub-processor table.
- `ARCHITECTURE.md §16 Q4` marked superseded; platform-parity table updated.
- 195 tests pass (was 194 — +1 empty-email validation case).

Note: `aus_phone.dart` kept — `mobile` is still a profile field for tap-to-copy
onto site induction forms; it's a contact field, not an auth identifier.

#### Netlify: `netlify.toml` + `.netlify/` ignore (commit `fa3bb77`)

Added `netlify.toml` with site ID `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72`,
`publish = "build/web"`, SPA redirect (`/*` → `/index.html` for go_router deep
links), and a comment explaining that GitHub auto-deploy is NOT wired.

#### Legal docs: entity placeholders filled (commit `3f39990`)

`docs/PRIVACY-POLICY.md` + `docs/TERMS-OF-USE.md` entity placeholders replaced
with real names (CDC Solutions Pty Ltd / EQ Solutions) for pilot launch.

#### Polish packs A+B+C (commit `0757115`)

528 lines across 11 files; 196/196 tests pass.

**Pack A — Risk mitigation:**
- **A1 — OCR rate-limit.** 20 calls/hour/user enforced server-side via new
  `check_and_record_ocr_usage` SECURITY DEFINER RPC + `public.ocr_usage` table
  (migration `0005_ocr_rate_limit.sql`). Atomic — two concurrent calls can't both
  pass the boundary. Edge Function `ocr-licence` v9 calls it first; over-limit
  returns HTTP 429 → Flutter shows "you've used your 20 magic-scans for the hour."
  Closes the unbounded-cost risk (~A$0.005/call × unbounded = problem).
- **A2 — Privacy consent toggles.** Analytics opt-out + crash-reporting opt-out
  now exist. `lib/core/privacy/privacy_prefs.dart` (static cache +
  `shared_preferences` I/O). `AnalyticsService.track` / `identify` early-return
  when opted out; Sentry `beforeSend` returns `null`. Hydrated in `main()` before
  either SDK initialises. Default: opted in.

**Pack B — First-tester experience:**
- **B3 — Splash branding.** Replaced bare `CircularProgressIndicator` with EQ
  launcher mark + "EQ Cards" name + sky-coloured spinner.
- **B4 — Help & feedback in Settings.** Dedicated section with "Get help" +
  "Send feedback" rows. Both compose a prefilled `mailto:contact@eq.solutions`.
  Address standardised from `support@` to `contact@eq.solutions`. Sign-out copy
  updated from "phone" to "email".

**Pack C — Reliability:**
- **C1 — OCR loading copy.** "First scan of the day may take a few seconds while
  we warm up the magic-scanner" sets cold-start expectations.
- **C3 — Error state on licences list.** New `_ListErrorState` widget:
  `NotAuthenticatedFailure` / JWT errors → "Sign in again" CTA; everything else
  → "Try again" CTA. Context-appropriate icon (lock vs cloud-off).

Migration `0005_ocr_rate_limit.sql` applied to live `hshvnjzczdytfiklhojz` via
Supabase MCP. Edge Function `ocr-licence` v9 deployed.

#### iframe-embed support (commit `9bcd02c`)

EQ Shell at `<tenant>.eq.solutions` can now mount Cards via iframe at
`/:tenant/cards`. Two changes to `web/_headers`:
- Dropped `X-Frame-Options: DENY` (not granular enough; `ALLOW-FROM` is
  deprecated).
- `frame-ancestors 'self' https://*.eq.solutions` — only eq.solutions subdomains
  can frame Cards.

Note: this is a visual-embedding change only. Cross-origin data access still goes
through the §18 protocol when built.

---

### 2026-05-19 — Agent-review security + UX sweep (commits `3a7045b`, `c63d30c`, `43db5f9`)

Three batches of improvements from an independent agent-review pass:

- **Batch 1 — Security + correctness (`3a7045b`).** SQL injection prevention in
  Supabase queries; auth-guard edge cases hardened; RLS policy audit.
- **Batch 2 — UX additions (`c63d30c`).** Pilot banner added; help UI improved;
  OCR verify flow; wedge promise clarified in UI copy.
- **Batch 3 — Doc + gitignore hygiene (`43db5f9`).** `.gitignore` tightened;
  stale doc references cleaned up.

---

### 2026-05-13 — Repo hygiene (commit `aa7926f`)

Added `.gitattributes` — normalise text files to LF across platforms.

---

### 2026-04-29 overnight (continued) — Battle-test push + tiered-product framing

Picking up from "I want all of EQ products having the starter package all the way through to enterprise style scale." Continuous work through the night within pause-and-polish boundaries (no schema changes).

#### Tier 1 — iPhone OCR fix + cropping + error UX (commit `1cc0351`)
- Re-added `image_cropper` ^9.0.0 with cross-platform UI settings. Cropping happens between picker and OCR; ID-1 card aspect ratio (CR80) as the default. Smaller upload + better extraction accuracy.
- Non-dismissable OCR loading dialog ("Reading your licence…") during the 3-8s Edge Function round-trip.
- `catch (_)` swallow replaced with `catch (e, st)` → `Sentry.captureException` + a friendly SnackBar via `ocrErrorMessage(e)` mapping HEIC/auth/network/timeout/upstream errors to one-line plain English.
- Sentry breadcrumb trail across the OCR pipeline: `capture_flow_started` → `compress_succeeded/failed` → `extract_succeeded`.

#### Tier 2 — Search, filter, expiring-soon, long-press, onboarding (commit `fd32ff2`)
- LicencesListScreen converted from `ConsumerWidget` to `ConsumerStatefulWidget` to manage search query + filter state.
- Search field above the list (matches type label + licence number, case-insensitive). Hidden until total ≥ 3 to avoid friction on tiny lists.
- 3 filter chips: All / Expiring soon (≤30d) / Expired. Reuses existing `Licence.isExpired` and `Licence.daysUntilExpiry` getters.
- Long-press on any LicenceCard opens a quick-actions sheet (Open / Edit). `onLongPress` threaded through all 3 design variants.
- First-launch tap-to-copy hint via SnackBar, persisted via `shared_preferences`. Shown once-ever on the first list render with ≥1 licence.

#### Tier 3 — iPhone PWA viewport polish (commit `5ad17c8`)
- `viewport-fit=cover` so the sky AppBar paints into the iPhone notch.
- `maximum-scale=1.0`, `user-scalable=no` to prevent iOS auto-zoom on input focus.
- Both `mobile-web-app-capable` and `apple-mobile-web-app-capable` set; status bar style → `default` (sky) instead of black.
- Three apple-touch-icon sizes for clean Add-to-Home-Screen.

#### Tier 4 — Battle testing (commit `2dddfb8`)
- OCR Edge Function call retries once on transient failures (5xx / network / timeout) with 1.5s backoff, **never** on 4xx. 30s overall timeout.
- Sentry breadcrumb trail across the auth pipeline (`send_otp_*`, `verify_otp_*`, `sign_out_*`) and licence repo (`licence_insert/update/delete_started/succeeded/failed`). Phone numbers truncated to last 4 digits in breadcrumbs.
- Per-tab `_ShellErrorBoundary` around the home shell's navigationShell — build-phase errors render a friendly fallback ("Something broke on this screen — try a different tab") instead of red-screening the app. Resets on tab switch.

#### CSP hotfix (commit `5f3b08e`)
- Added `blob: data:` to `connect-src` so `image_picker` and `image_cropper` can read picked-photo blob URLs without violating CSP. Caught from Royce's iPhone testing.

#### Tier 5 — Test coverage on new pure helpers
- New `lib/features/licences/presentation/helpers/licences_list_helpers.dart` extracted from the screen. `applyLicenceFilters` + `ocrErrorMessage` are now pure functions.
- 20 new tests: filter buckets, search matching (label + number, case-insensitive), combined filter+search, error-message mapping for every documented branch.

#### Tier 6 — Form validators + 39 tests
- New `lib/core/validators/input_validators.dart` with: `validateMobile` / `validateMobileRequired`, `validateEmail`, `validatePostcode` (4 digits), `validateAuState` (8 valid codes, case-insensitive), `validateDateOfBirth` (≤ today, ≥ 1900), `validateLicenceNumber` (non-empty, alphanumeric+hyphen/space/slash, ≤ 32 chars), `validateIssueDate` (≤ today), `validateExpiryDate` (after issue, ≤ 2100), `validateAddressLine` (≤ 200 chars).
- `EqTextField` extended with optional `validator:` parameter. When non-null, renders as `TextFormField` so the parent `Form` picks up validation; `autovalidateMode: onUserInteraction` so errors appear as the user types.
- Wired across profile-edit (mobile, email, state, postcode, emergency mobile) and licence-edit (number, state).
- 39 unit tests covering every validator's empty/valid/invalid paths.

#### Tier 7 — Wallet stats card on Settings
- `_WalletStats` widget at the top of Settings shows total licences / expiring-30d / expired with colour accents (warning amber if any expiring, error red if any expired). Hidden when wallet is empty. Pure derived view over existing licence data — no new schema. Hint at where the Pro-tier admin-dashboard view will eventually live.

#### Tier 8 — Data export ("Settings → Export my data")
- New `lib/features/settings/presentation/helpers/data_export.dart` — pure function `buildExportPayload(profile, licences, now)` returns a versioned JSON-serialisable map (`_format: 'eq-cards-export'`, `_format_version: 1`) with profile + licences. Honours Privacy Policy §9 access right.
- Settings → Legal → "Export my data" copies the JSON to the clipboard and shows it in a SelectableText dialog. Pragmatic v1; v1.1 may add `share_plus` for native share-sheet downloads.
- 6 new tests covering the payload shape (header, profile mapping with nested address, licence mapping including metadata + signed URLs, multi-licence ordering, JSON round-trip).

#### Bonus — `docs/PRODUCT-TIERS.md`
- Strategic doc covering Free / Starter / Pro / Enterprise tiers across the EQ Solutions suite. Specifically captures the constraints Royce articulated:
  - Tap-to-copy stays free forever
  - Inductions, SWMS, prestarts and other safety-critical features never paywalled
- Tier-by-tier breakdown for EQ Cards; sketch of how the same shape applies to EQ Import / Capture / Field / Expenses / Quotes / Ops.
- Pricing numbers are placeholders pending real-customer-conversation data.

#### Quality after the push

| Metric | Before tonight | After tonight |
|---|---|---|
| `flutter analyze` | No issues | No issues |
| `flutter test` | 129 / 129 | **194 / 194** (+65) |
| Local commits ahead of `gh repo create` | 1 | 6 |
| Open Cards bugs caught from real iPhone testing | 1 (silent OCR fail) | 0 (CSP fix shipped) |

#### Untouched (still in pause-and-polish boundaries)

No new tables, no new columns on `profiles`/`licences`, no multi-tenant migration, no share-redeem endpoint, no Twilio production, no custom domain, no native mobile builds. All wait for INTAKE Sprint-1.

### 2026-04-29 PM — Launcher icons landed

- **`assets/icon/launcher.png`** (1024×1024, sky `#3DA8D8` infinity-loop EQ mark on white) and **`assets/icon/launcher_foreground.png`** (1024×1024, white mark on transparent) committed.
- Asset declarations uncommented in `pubspec.yaml`.
- `dart run flutter_launcher_icons` generated:
  - **iOS:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` — full set (20×20 through 1024×1024 at 1x/2x/3x).
  - **Android legacy:** `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`.
  - **Android adaptive (8+):** `mipmap-anydpi-v26/ic_launcher.xml` layering white-mark foreground over `#3DA8D8` sky background. Parallax-capable on supported launchers.
  - **Web:** `web/icons/Icon-{192,512}.png` plus maskable variants. `web/manifest.json` re-generated to match.
  - Windows skipped (no `windows/` platform folder — desktop not targeted).
- **In-app preview** (`Settings → Design → Linear`) now loads `launcher.png` directly via `Image.asset`, so the picker matches what's installed on the home screen. Wordmark fallback kept in case the asset is ever missing.

### 2026-04-29 PM — Polish bundle (within pause-and-polish boundaries)

A pure-polish pass — no schema touched, no new entities, no migration. All work fell inside the boundaries reaffirmed by Cowork.

#### Decision

- **Keep all 3 design directions in production.** Settings → Design picker is now a permanent user choice, not a temporary review tool. Launcher icon defaults to **Linear** ("EQ" wordmark on sky) since iOS/Android don't easily support per-user-preference launcher icons.

#### Polish bundle

- **`web/_headers`** — security headers for Netlify per the INTAKE bundle's standing rule ("All Netlify/CF Pages apps need a `_headers` file"). CSP enumerated for `self`, Supabase project, PostHog EU host, Sentry; `script-src 'unsafe-inline' 'unsafe-eval'` retained for Flutter bootstrap + DDC. X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy strict-origin-when-cross-origin, Permissions-Policy locked down (camera self-only, microphone/geolocation off, FLoC opt-out), HSTS 1y. Cache rules for `main.dart.js` (immutable) and `index.html` (must-revalidate).
- **Accessibility — Semantics labels.** Wrapped `LicenceCard` (all 3 variants) in a single `Semantics` block announcing "$type, $number, expires $date" + button role. The 3 action tiles in the Wallet empty state get `Semantics(button: true, label: '$label. $subtitle')`. The Design picker rows in Settings get `Semantics(inMutuallyExclusiveGroup: true, selected: ...)` so screen readers announce them as a radio group. Existing coverage on `ExpiryBadge`, `ProfileFieldRow`, `_CopyRow` retained.
- **Loading skeleton on Licences list.** `_LicencesSkeleton` replaces the generic `CircularProgressIndicator` — 1.2s pulse driven by `AnimationController`, lays out the same shape as a real list (banner + 3 cards) so the page doesn't reflow when data arrives. Pure decoration, no semantic content.
- **Error-message audit.** One `_error = '$e'` raw-interpolation site in `licence_edit_screen.dart` (the hydrate `try/catch`) now routes through `userMessageForError()`. The "Not signed in." session-expired message tightened to match the rest of the app's voice.

#### Verification bundle

- **3 new golden tests** for `LicenceCard` per design version (`linear` / `wallet` / `photo_first`). Stable expiry baseline (`DateTime(2099, 1, 1)`) so goldens don't drift with calendar rollover. Captured via `flutter test --update-goldens`.
- **[`docs/analytics-taxonomy-verification.md`](docs/analytics-taxonomy-verification.md)** — cross-reference report. Every event in ARCHITECTURE §10.2 → confirmed exactly one fire site in `lib/`. Every `AnalyticsService.track()` call site → confirmed in the §10.2 table. Two intentional gaps documented (`is_first_open` deferred to v1.1; `expiry_alert_*` events need a deeplink handler that doesn't exist yet). Property contracts spelled out per event with a "no PII" reaffirmation.

#### Icon plumbing

- **`flutter_launcher_icons` ^0.14.0** added as dev dependency. Config at [`flutter_launcher_icons.yaml`](flutter_launcher_icons.yaml) with the EQ Sky `#3DA8D8` background for adaptive icons. `assets/icon/README.md` documents the design spec (Linear default, "EQ" wordmark, 1024×1024, opaque) and three generation paths (render from `AppIconPreview` widget, Figma export, AI image-gen). PNG source files not committed yet — folder reserved.
- Run `dart run flutter_launcher_icons` once a `launcher.png` is in place.

#### Quality

- `flutter analyze`: No issues found.
- `flutter test`: **129 / 129 passing** (was 126; +3 variant goldens).

### 2026-04-29 — Strategic pivot: pause-and-polish for EQ Intake

EQ Cards work shifted to **pause-and-polish posture** following the introduction of the broader **EQ Intake** architecture (canonical schema spine + three intake doors + every output door) in a parallel Cowork session. EQ Cards becomes one of the three intake doors. New feature work on Cards is paused until INTAKE Sprint-1 lands so we don't pay for a rewrite.

- **Added [STATUS.md](STATUS.md)** at repo root — single-page handoff summary covering current state, what's allowed during the pause, what's paused, INTAKE coordination, schema mapping (`profiles` → `staff` canonical), reconciliation paths for §18, standing rules from the INTAKE bundle, where things live, resume commands, and notable session-history bookmarks. **This is the source of truth for "where is EQ Cards?"**
- **ARCHITECTURE §18 prefixed with a RECONCILIATION PENDING block** flagging the §18 ↔ INTAKE conflict. Two reconciliation paths documented; no action until INTAKE Sprint-1 lands.
- **3 design directions remain installed** behind the Settings → Design picker. Pick one when ready; trim the other two as a polish-window task.
- **Edge Function `ocr-licence` left at v7.** Stable, working. Don't redeploy without a reason.
- **No schema migrations during the pause.** No `tenant_id` / `schema_version` columns yet — those land when INTAKE coordination is decided.

Allowed during the pause: bugfixes, OCR accuracy polish, picking the design winner, real-photo testing, pilot-user invitations, doc cleanup. Paused: new entities, multi-tenant migration, custom domain, Twilio production, Apple Wallet, Drift, Phase 2 share-redeem endpoint, public launch, mobile builds.

### Overnight sprint 2026-04-28 PM → 2026-04-29 AM

A 4-pillar polish sweep landed in one autonomous session — finishing half-done OCR, completing the analytics taxonomy from §10.2, building the Phase 1→2 QR-share bridge, and tightening tests + docs.

#### Pillar 1 — Finish half-done

- **OCR polish on Claude Vision Edge Function.** Added `state` to the `extract_licence` tool schema (enum: NSW/VIC/QLD/WA/SA/TAS/NT/ACT). Tightened the system prompt: "Be assertive when there are clear visual cues" — Claude now confidently identifies driver_licence / white_card / first_aid / cpr from obvious markers (photo, "while licence is valid" text, HLTAID code, state branding) instead of conservatively returning null. Re-deployed.
- **`OcrExtraction.stateCandidate`** added (mobile path leaves it null; web path reads from Claude's response).
- **Form prefill** in [licence_edit_screen.dart](lib/features/licences/presentation/screens/licence_edit_screen.dart) now uses `licence_type`, `state`, and `issuing_authority` from OCR. Previously only `number` + dates flowed through.
- **State→authority fallback for driver licences.** When Claude returns `licence_type=driver_licence` + a state but no authority, infer it: NSW→Service NSW, VIC→VicRoads, QLD→Queensland Transport, WA→Department of Transport WA, SA→Service SA, TAS→Department of State Growth, NT→Motor Vehicle Registry NT, ACT→Access Canberra.
- **EXIF strip on web** before the licence image leaves the device. Mobile already stripped at upload time via `flutter_image_compress`; the web OCR path was sending raw bytes (with potential GPS metadata) to the Edge Function. Refactored `PhotoUpload._stripExifAndCompress` into a top-level `stripExifAndCompress(Uint8List)` and called from both paths.
- **ProfileEditScreen widget tests fixed** — the form is taller than the default 800x600 test viewport, so `Emergency contact` / `Emma` widgets weren't rendered (lazy ListView). Bumped surface size to 800x1600 in the test setup.
- **12 golden test baselines captured** via `flutter test --update-goldens`. Was the last pre-existing failure category from the 0.1.0 release.
- **126/126 tests pass** — was 107/126 going into the sprint.

#### Pillar 2 — Analytics taxonomy complete (ARCHITECTURE §10.2)

All v1 events now wired:

| Event | Where it fires | Properties |
|---|---|---|
| `app_opened` | main.dart on launch | `platform` |
| `signup_completed` | identity sync on AuthChangeEvent.signedIn | `method: 'phone'` |
| `profile_field_filled` | per non-null transition on profile-edit save | `field` |
| `profile_completed` | profile transitioned incomplete→complete | — |
| `licence_added` | licence-edit screen on insert | `licence_type`, `via_ocr` |
| `licence_deleted` | licence-detail screen after soft-delete | — |
| `copy_field` | clipboard_utils.copyWithFeedback | `label` |
| `copy_induction_block` | profile bulk-copy button | — |
| `qr_generated` | new QR-share sheet on licence detail | `licence_id` |

Diff transitions (`profile_field_filled`, `profile_completed`) compare against the profile state captured at hydrate-time, so events only fire on actual user-driven fills — not on every save of an already-complete profile.

#### Pillar 3 — Licence QR sharing (Phase 1→2 bridge)

- New **QR icon** on licence detail screen → opens a bottom-sheet with a QR rendered via `qr_flutter` (already in pubspec) plus a "Copy link" action.
- QR encodes a placeholder URL: `https://cards.eq.solutions/share?licence_id=<id>`.
- This is **demoware** — the share-redeem endpoint is documented in ARCHITECTURE §18.2 but scheduled for Phase 2 once another EQ module needs it. The QR proves the flow works end-to-end and lets us count `qr_generated` events for funnel analysis.

#### Pillar 4 — Tests + docs

- Verified `LicenceCard` (5 tests) + `ExpiryBadge` (5 tests) coverage; existing tests are comprehensive.
- This CHANGELOG section + progress.html refresh.

#### Known gaps after the sprint

- **Cost gating on web OCR.** Each call ~$0.003-0.005 (Claude Sonnet). Fine for dev + low-traffic launch. Add a feature flag before any unrestricted public access.
- **Twilio production OTP.** Test OTP via dashboard still required for new sign-ups.
- **`cards.eq.solutions` custom domain.** Currently the app deploys to a `*.netlify.app` subdomain via manual drag-drop. Auto-deploy via GitHub → Netlify pending.
- **Mobile builds.** Android Studio install required on the Windows host. iOS deferred (Mac required).
- **Phase 2 share-redeem endpoint** (ARCHITECTURE §18.2). QR codes currently link to a stub URL.

### Added 2026-04-28 (PM, third pass — web OCR)

- **Web OCR via Anthropic Claude Vision** (revises ARCHITECTURE §16 Q3 + §17 platform parity).
  - **`supabase/functions/ocr-licence/index.ts`** — new Deno Edge Function. Receives base64 image + mime, calls Claude Sonnet 4.6 with a forced `extract_licence` tool-use, returns structured JSON: `{licence_number, licence_type (matching seeded codes), issuing_authority, issue_date, expiry_date, raw_text, confidence}`. Auth-gated (Supabase JWT verified at gateway). 502 on Anthropic upstream errors, 400 on bad input, 405 on non-POST.
  - **`OcrService.extractFromBytesViaEdgeFunction(Uint8List, {mimeType})`** — new web path. Mobile `extractFromFile(File)` unchanged.
  - **`OcrExtraction`** gained `licenceTypeCandidate` + `issuingAuthorityCandidate` (populated by Claude on web; remain null on mobile until the regex layer learns to detect them).
  - **`licences_list_screen.dart`** capture flow now routes web → Edge Function, mobile → ML Kit. Web image source is `gallery` (file picker), mobile is `camera`.
  - **`via_ocr` flag** moved from repo to the edit screen save handler — `licence_added` event now reports `via_ocr: true` whenever the prefill came with an `OcrExtraction`. Architecture §10.1 ("user-action events") respected by keeping analytics out of the data layer.
  - **Cost gate not yet built.** Each web OCR call is ~$0.003-0.005. Fine for dev + low-traffic launch; revisit before unrestricted public access.
- **RUNBOOK §6.1** — new section: Edge Function deploy + `ANTHROPIC_API_KEY` secret setup + local-serve verification.

### Fixed 2026-04-28 (PM, second pass — OCR parsers)

- **5 OCR parser bugs fixed** in `findLicenceNumberInLines`:
  - HLTAID embedded mid-line (`Unit code HLTAID009 - CPR`) — leading `\b` anchor was rejecting matches between word chars after whitespace stripping. Dropped the leading `\b`.
  - `LICENCE NO 12345678` was capturing `NO123456` — the labelled-line regex didn't allow chained label words. Switched to `(?:(?:LICENCE|...)[:.\s]*)+` so `LICENCE NO` consumes both labels before the value.
  - `CARD NUMBER: ABC12345` was returning `NUMBER` for the same reason — same fix.
  - `Issue date` line was being returned as the licence number in pass 2 because `^[A-Z0-9]{6,12}$` matched the pure-letter word. Pass 2 now requires at least one digit (licence numbers always have digits; pure-letter words like `ISSUEDATE` are rejected).
  - Whitespace-stripping case (`LICENCE NO ABC 12345` → `ABC12345`) is now correct via the same chained-label fix.
  - All 15 OCR unit tests pass.

### Fixed 2026-04-28 (PM, second pass)

- **PostHog web events were silently dropping** — `posthog_flutter` 4.x's `Posthog().setup()` is explicitly a no-op on Flutter web (see `posthog_flutter_web_handler.dart` line 10-11); `capture` / `identify` / `reset` all expect `window.posthog` to already exist. Without the JS init snippet in `index.html`, every web event was a silent throw against `undefined`. Added the standard PostHog snippet to `web/index.html` `<head>` with the project token + EU host, plus `person_profiles: 'identified_only'` so anonymous pre-auth visits don't create user profiles.
- **Dual-key situation documented** — web reads the PostHog token from `index.html` (snippet hardcoded — `phc_*` keys are write-only, safe to commit). Mobile reads from `--dart-define`-injected `POSTHOG_API_KEY` in `.dart-defines.json`. **Both must be kept in sync** if the project key ever changes. RUNBOOK §6.1 added.

### Added 2026-04-28 (PM)

- **PostHog user identity sync.** `AnalyticsService.startIdentitySync(SupabaseClient)` listens to Supabase `onAuthStateChange` and calls `Posthog().identify(userId)` on `signedIn` / `initialSession`, and `Posthog().reset()` on `signedOut`. Wired in `main.dart` after PostHog init. Closes the gap where every event was attributed to an anonymous distinct_id; sign-out no longer leaks events into the next user's profile.
- **Three new analytics events** (per ARCHITECTURE §10.2 taxonomy):
  - `app_opened` with `{platform: 'ios'|'android'|'web'|'other'}` — fires once at launch.
  - `signup_completed` with `{method: 'phone'}` — fires from the identity-sync handler on a real `signedIn` event (not on persisted-session restore).
  - `licence_added` with `{licence_type, via_ocr: false}` — fires from `LicenceRepository.upsert` when `licence.id == null` going in (i.e. an insert, not an edit). `via_ocr` will be wired through from the capture flow in a follow-up.
- **Keyboard Enter submits forms** (web parity fix flagged in CHANGELOG):
  - `EqTextField` gained `onSubmitted` + `textInputAction` parameters.
  - Phone-entry → Enter triggers `_submit` (`TextInputAction.send`).
  - OTP → Enter triggers `_verify` (`TextInputAction.done`); the auto-verify-on-6-digits path still works.
  - Profile-edit → wrapped in `CallbackShortcuts` for `LogicalKeyboardKey.enter` + `numpadEnter` → `_save`. Single-binding approach avoids threading FocusNodes through 10 fields.

### Decided 2026-04-28 (PM)

- **Web host: Netlify** (closes ARCHITECTURE §16 Q5). Matches the existing EQ Solutions / SKS deploy pattern (`*.netlify.app`). Target domain: `cards.eq.solutions`. RUNBOOK §8 updated with GitHub-auto-deploy + manual drag-drop paths and the cross-deploy warning from global CLAUDE.md.
- **Supabase project status: Cards-only.** ARCHITECTURE §18 amended: project `hshvnjzczdytfiklhojz` (originally "EQ Assets") is now used exclusively by EQ Cards. The earlier "needs its own project before launch" note is closed — this IS the EQ Cards project. `.dart-defines.json` comment updated.

### Phone-build prep 2026-04-28 (PM)

- **AndroidManifest.xml** — added the 5 required `<uses-permission>` entries (INTERNET, CAMERA, USE_BIOMETRIC, POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM) per RUNBOOK §3. Display name `eq_cards` → `EQ Cards`.
- **iOS Info.plist** — added `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSFaceIDUsageDescription`. Bundle display name `Eq Cards` → `EQ Cards`.
- **web/index.html + web/manifest.json** — title, theme-color (#3DA8D8 EQ Sky), description set per brand spec.
- **RUNBOOK §11** — new section: get an Android build running on Windows (Studio + SDK install, device vs emulator tradeoffs).
- **RUNBOOK §12** — new section: magic-scanner (OCR) smoke test plan with a 5-licence test matrix and pass criteria. Real-photo verification, not unit tests.

### Verified 2026-04-28

- **End-to-end web flow working against real Supabase.** Phone OTP (test OTP via Supabase dashboard, no Twilio billing yet), profile fill, licence add (manual), licence detail tap-to-copy — all green.
- Migrations 0001 / 0002 / 0003 applied to the EQ Assets Supabase project (`hshvnjzczdytfiklhojz`). Dev-only — needs dedicated project before launch per §18.
- Flutter SDK relocated from `OneDrive\Desktop\flutter` to `C:\Projects\flutter` to fix OneDrive sync conflicts with Flutter cache operations.
- ~250 lint info-level warnings remain after disabling `always_use_package_imports` and `always_put_required_named_parameters_first` (style preferences that conflict with project conventions).

### Cleaned 2026-04-28

- **`flutter analyze`: No issues found.** From 259 lints → 0. Cosmetic-preference lints disabled in `analysis_options.yaml` (`avoid_redundant_argument_values`, `cascade_invocations`, `omit_local_variable_types`, `unnecessary_lambdas`, `prefer_const_literals_to_create_immutables`, `prefer_const_constructors`); real bugs / deprecations fixed (`withOpacity` → `withValues`, `activeColor` → `activeThumbColor`, `value` → `initialValue` on `DropdownButtonFormField`, `setEnabled(bool)` → `setEnabled({required bool value})`, redundant `flutter_riverpod` imports removed, unnecessary `meta` import removed, factory before `_()` in `Profile` and `Licence` per `sort_unnamed_constructors_first`, `unawaited()` wrapping `context.push`, `.toString()` removed from String? null-checked items).
- **Plus Jakarta Sans bundled** — single variable font (`PlusJakartaSans-Variable.ttf`, 176 KB) from Google's official fonts repo. Flutter picks weight from the axis at runtime; no separate Regular / Medium / SemiBold / Bold files needed.

### Pre-existing test failures (all resolved in overnight sprint)

All 19 originally-flagged failures are now green. Kept here as the trail for future incidents:

- ~~**12 golden tests**~~ — baselines captured 2026-04-29 via `flutter test --update-goldens`.
- ~~**5 OCR `findLicenceNumberInLines` tests**~~ — parser bugs fixed 2026-04-28 (PM, second pass).
- ~~**2 ProfileEditScreen widget tests**~~ — viewport bumped to 800x1600 2026-04-29.

### Pending

- Real Twilio config for production OTP delivery.
- ~~Sentry DSN + PostHog API key.~~ Both configured 2026-04-28.
- ~~Web deploy decision (Cloudflare vs Netlify — §16 Q5).~~ Decided 2026-04-28: Netlify.
- ~~Move EQ Cards data off the shared EQ Assets Supabase project per §18.~~ Closed 2026-04-28: project is now Cards-only.
- ~~Keyboard `Enter` submits forms~~ — wired 2026-04-28.
- ~~Wire `via_ocr` flag through the capture flow~~ — wired 2026-04-28 (PM); now reports `true` whenever an OcrExtraction reached the form.
- ~~Web OCR~~ — Claude Vision via `ocr-licence` Edge Function, deployed 2026-04-28; polish (state/type/authority + state→authority fallback + EXIF strip) shipped overnight.
- ~~Complete the analytics taxonomy (§10.2)~~ — all 9 events live as of 2026-04-29.
- ~~QR generation for licences~~ — Phase 1.5 demoware shipped 2026-04-29 (placeholder URL until §18.2 share-redeem endpoint exists).
- Mobile builds (iOS / Android) and on-device testing — Android Studio install required on Windows host (RUNBOOK §11). iOS deferred (Mac required).
- PostHog dashboard verification — eyeball Live events after a sign-in + tap-to-copy + add-licence run-through.
- Cost gating on web OCR (Claude Vision ~$3-5 per 1000 calls). Add feature flag before unrestricted public access.
- `cards.eq.solutions` custom domain on Netlify.
- GitHub → Netlify auto-deploy wiring (currently manual drag-drop).
- Phase 2 share-redeem endpoint (ARCHITECTURE §18.2). QR codes will keep linking to a stub URL until built.

## [0.1.0] — 2026-04-28 (Phase 1, unreleased)

Initial Phase 1 of EQ Cards. Mobile (iOS, Android) + web companion. Code is
committed but not yet compiled or run on a real device — `RUNBOOK.md` covers
the verification steps.

### Architecture

- **ARCHITECTURE.md** — 18-section binding contract: stack, folder rules,
  Riverpod patterns, repository pattern, freezed models, routing, EQ brand
  tokens, the wedge clipboard utility, error handling, analytics taxonomy,
  security & privacy, testing strategy, CI/CD, vibe-coding rules, scope, open
  questions, platform parity, and cross-module data architecture (§18 —
  independent products + share API with explicit user consent).
- **SCHEMA.md** — 4 tables (`profiles`, `licence_types`, `licences`,
  `audit_log`) with indexes, RLS policies, and a `metadata jsonb` column for
  type-specific licence extras (Medicare IRN, driver class, forklift class).
- **3 SQL migrations** — initial schema, seeded Australian tradie licence
  types, and the `licence-photos` storage bucket with user-scoped RLS.

### Features

- **Auth** — phone OTP via Supabase native + Twilio backend. Australian
  mobile E.164 normaliser. Auto-submit on 6-digit OTP entry. 60s resend
  cooldown.
- **Profile (the wedge)** — full edit form, tap-to-copy on every field row,
  "Copy all profile fields" induction-block button. Completion detection
  drives the home banner.
- **Licences** — full CRUD, 13 pre-seeded Aus tradie licence types,
  type-specific metadata fields, camera capture → on-device ML Kit OCR with
  Aussie-specific patterns (HLTAID codes, labelled lines, White Card 8-digit
  numbers preserved through smart date filtering), EXIF-stripped photo
  upload via `flutter_image_compress`, signed URLs (1h TTL) for private
  photo display, expiry badges.
- **Alerts** — local notifications at 90/30/7 days before expiry, hardcoded
  `Australia/Sydney` timezone for v1 (so `tz.local` doesn't fall back to
  UTC).
- **Settings** — sign out (with confirm dialog), biometric toggle (persists
  in `shared_preferences`), app version display.
- **Home shell** — 3-tab Material 3 NavigationBar, biometric gate on cold
  launch + 5-min background re-prompt, "Complete your profile" banner shown
  on the Licences tab when the profile is incomplete.
- **Web companion** — `kIsWeb` guards on all mobile-only plugins; the
  capture flow becomes a file picker on web; OCR, biometric, and local
  notifications silently no-op.

### Tests (~85 cases)

- Pure model tests: `Profile.isComplete`, `Profile.fullAddress`,
  `Licence.isExpired`, `daysUntilExpiry`, `isExpiringSoon`, AUS phone
  normaliser/validator (13 cases).
- Repository payload-builder tests — extracted as `@visibleForTesting`
  top-level functions, covers id-handling, snake-case key mapping, date
  formatting, server-managed-timestamp omission, transient signed-URL
  exclusion, metadata pass-through.
- OCR heuristic tests (15 cases) — HLTAID codes, labelled lines, White Card
  survival, all numeric date formats with 2-digit-year expansion.
- Widget tests: `ExpiryBadge`, `LicenceCard`, `CompleteProfileBanner`,
  `PhoneEntryScreen`, `ProfileEditScreen`, `LicenceDetailBody`,
  `clipboard_utils.copyWithFeedback`.
- Golden tests: `EqButton` (5 variants), `EqCard` (2), `EqTextField` (3),
  `EqAppBar` (2). Run `flutter test --update-goldens` once on a clean main
  to capture baselines.

### Quality

- **User-friendly error mapping** via `userMessageForError(Object)` —
  no more raw `'$e'` shown to users; 5 screens wired.
- **Doc comments** on all public APIs the wedge depends on: `Profile`,
  `Licence`, `copyWithFeedback`, the sealed `Failure` hierarchy.
- **Semantics labels** on tap-to-copy rows (`ProfileFieldRow`, `_CopyRow`)
  and the expiry badge — screen readers announce "Mobile, +61412345678,
  button" rather than three disconnected children.

### Fixed

- Race condition in `ProfileEditScreen.initState` where
  `ref.read(profileNotifierProvider).valueOrNull` returned null on cold
  load (deep link, browser refresh, tests) before the async `build()` had
  resolved, silently failing to hydrate the form. Now uses
  `addPostFrameCallback` + `provider.future` to await before hydrating.
- `tz.local` was defaulting to UTC in `AlertsScheduler`, causing local
  notifications to fire ~10 hours off. Now hardcodes `Australia/Sydney`.
  v1.1 will detect via `flutter_native_timezone` for travelling users.
- `Platform.isAndroid` / `Platform.isIOS` would throw on web in
  `AlertsScheduler.init`. Now `kIsWeb`-guards every entry point.
- 3 hard-coded route strings (`'/licences/$id'`, `'$Routes.profile/edit'`,
  etc.) replaced with new `Routes.licenceDetailFor(id)` /
  `Routes.licenceEditFor(id)` / `Routes.profileEdit` helpers so route
  shapes live in one place.
- `sort_pub_dependencies` lint disabled — pubspec is intentionally grouped
  semantically per architecture §1, not alphabetised.

### Infra

- `.github/workflows/ci.yml` — `flutter analyze` + `flutter test` on PRs
  and pushes to main. Release-tag upload jobs (TestFlight, Play, web
  deploy) sketched as TODO pending secrets configuration.
- `RUNBOOK.md` — 10 ordered first-morning setup steps with native
  permission snippets, dart-define table, and a common-errors matrix.
- `progress.html` — single-page status board.
- Memory: cross-module strategy, multi-select question preference, EQ
  Cards strategic context.

### Known limitations

- No code has been compiled or run yet — verification is the next step
  (the entire `RUNBOOK`).
- Sentry DSN + PostHog API key not configured (services init silently as
  no-ops without keys; pass via `--dart-define`).
- §16 Q5 (Cloudflare Pages vs Netlify hosting) still open.
- §16 Q6 (PWA brand polish — icons, install prompt, theme color) deferred
  to v1.1.
- Repository integration tests against a real Supabase fake deferred to
  v1.1 once a mocking framework is chosen.
- Phase 2 share-API code (per §18) not built — forward documentation only.
- Cloud OCR fallback for web deferred to v1.1.
- Apple Wallet pass generation deferred to v1.1.
- Drift offline cache + offline writes deferred to v1.1.

[0.1.0]: https://github.com/eq-solutions/eq-cards/releases/tag/v0.1.0
