# EQ Cards — First-Morning Runbook

> **Where is EQ Cards right now?** Read [STATUS.md](STATUS.md) first. The app is live at
> `cards.eq.solutions`, reading/writing from eq-canonical (`jvknxcmbtrfnxfrwfimn`) via
> `eq_cards_*` bridge RPCs. Auth is two-path: Shell JWT handoff (`#sh=<jwt>`) for the
> iframe embed; email-OTP for standalone/direct access.

**Status:** Active — Unit 4 shipped (canonical flip + Shell SSO)
**Owner:** Royce Milmlow
**Last updated:** 2026-05-24

This runbook gets you from a fresh `git clone` to a green `flutter analyze` and a running app on iOS, Android, and Chrome. Follow the steps in order; each is independent.

---

## 0. Prereqs (one-time)

- **Flutter SDK ≥ 3.24** — `flutter --version`
- **Xcode** (iOS only — required for `flutter create` to generate the iOS folder)
- **Android Studio + SDK** (Android only)
- **Supabase CLI** — `supabase --version`. Install: `brew install supabase/tap/supabase` or see supabase.com/docs.
- A **Supabase project** at supabase.com — create one for EQ Cards.

---

## 1. Install Plus Jakarta Sans

Architecture §7.3 requires the Plus Jakarta Sans font bundled as an asset.

1. Visit https://fonts.google.com/specimen/Plus+Jakarta+Sans
2. Click "Download family"
3. Unzip and copy these 4 files into `assets/fonts/` (filenames must match exactly):
   - `PlusJakartaSans-Regular.ttf`
   - `PlusJakartaSans-Medium.ttf`
   - `PlusJakartaSans-SemiBold.ttf`
   - `PlusJakartaSans-Bold.ttf`

Without these, the app falls back to the system font.

---

## 2. Generate platform folders

Runs over the existing project — generates `android/`, `ios/`, `web/` without touching `lib/`.

```bash
flutter create . --platforms=android,ios,web --org=solutions.eq
```

`--org=solutions.eq` results in bundle id `solutions.eq.eq_cards`.

---

## 3. Add native permissions

`flutter create` produces baseline files. Append these for the features we use.

### iOS — `ios/Runner/Info.plist`

Inside the top-level `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>EQ Cards uses the camera to capture licence photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>EQ Cards needs access to pick licence photos from your library.</string>
<key>NSFaceIDUsageDescription</key>
<string>EQ Cards uses Face ID to keep your wallet locked when you're not using it.</string>
```

### Android — `android/app/src/main/AndroidManifest.xml`

Before `<application>`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.INTERNET" />
```

### Web — `web/index.html`

Set the brand colour and title (find the existing `<meta name="theme-color">` tag and update):

```html
<meta name="theme-color" content="#3DA8D8">
<title>EQ Cards</title>
```

### Web — `web/manifest.json`

Update the brand fields:

```json
{
  "name": "EQ Cards",
  "short_name": "EQ Cards",
  "background_color": "#FFFFFF",
  "theme_color": "#3DA8D8",
  "description": "Tap-to-copy wallet for tradies."
}
```

(Icons are PWA-polish — v1.1.)

---

## 4. Get dependencies + generate code

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` creates `*.g.dart` and `*.freezed.dart` siblings. **Must succeed before `flutter analyze` will be clean.**

---

## 5. Supabase project + migrations

**Production Supabase project (Unit 4+):** eq-canonical `jvknxcmbtrfnxfrwfimn`.
The Flutter app talks to this project via `eq_cards_*` bridge RPCs applied via
Supabase MCP. The `supabase/migrations/` folder contains the legacy per-module
migrations (0001–0005); canonical schema is managed directly in eq-canonical.

For a fresh dev environment pointing at eq-canonical:

```bash
supabase init
supabase link --project-ref jvknxcmbtrfnxfrwfimn
```

The legacy project (`hshvnjzczdytfiklhojz`) is read-only rollback only — do not
apply new migrations to it.

**Auth:** email OTP via Supabase's built-in mailer. No Twilio configuration needed.
In **Supabase Auth → Providers → Email**, confirm "Enable email signups" is ON and
the Magic Link template includes `{{ .Token }}` (6-digit OTP).

Test by requesting an OTP from your own email address. Code arrives in ~10–30s; check
spam if missing.

---

## 6. dart-defines

EQ Cards reads up to 5 env vars via `--dart-define`. Required ones in **bold**.

| Key | Required? | Source |
|---|---|---|
| **`SUPABASE_URL`** | yes | `https://jvknxcmbtrfnxfrwfimn.supabase.co` (eq-canonical) |
| **`SUPABASE_ANON_KEY`** | yes | Supabase dashboard → eq-canonical → Project Settings → API |
| `SENTRY_DSN` | no | sentry.io project settings → Client Keys |
| `POSTHOG_API_KEY` | no | app.posthog.com → Project settings |
| `POSTHOG_HOST` | no | defaults to `https://us.i.posthog.com` |

Without Sentry/PostHog keys, those services init silently as no-ops (per `main.dart` checks). Recommended for v1: skip them on dev runs, set them on release-tag CI builds.

Save your production defines to `.dart-defines.prod.json` (gitignored):

```json
{
  "SUPABASE_URL": "https://jvknxcmbtrfnxfrwfimn.supabase.co",
  "SUPABASE_ANON_KEY": "eyJxxx"
}
```

Then run with `--dart-define-from-file=.dart-defines.prod.json`.

**Note:** `.dart-defines.json` (without `.prod`) may still point at the legacy project
(`hshvnjzczdytfiklhojz`). Check which file is which before running. The production
defines file is `.dart-defines.prod.json`.

### 6.1 Web OCR — Edge Function deploy

EQ Cards on web does OCR via the `ocr-licence` Supabase Edge Function (Anthropic Claude Vision). Mobile uses on-device ML Kit and ignores the Edge Function.

One-time setup (after `supabase init` + `supabase link`):

```bash
# 1. Set the Anthropic API key as a project secret (NOT committed).
supabase secrets set ANTHROPIC_API_KEY=sk-ant-api03-...

# 2. Deploy the Edge Function.
supabase functions deploy ocr-licence
```

Verify locally before deploying:

```bash
supabase functions serve ocr-licence --env-file .env.local
# Then POST a test image:
curl -X POST http://localhost:54321/functions/v1/ocr-licence \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"image_base64":"<base64>","mime_type":"image/jpeg"}'
```

The function requires a valid Supabase JWT (auth gate handled by Supabase gateway — `verify_jwt = true` is the default). Anonymous users get a 401 before the function ever runs.

**Cost reality:** ~$3-5 per 1000 calls at Sonnet pricing. Each call is one structured tool-use response. If you ever want to cap cost, gate web OCR behind a feature flag and fall through to manual entry on the free tier.

**If you ever change the Anthropic key:** `supabase secrets set ANTHROPIC_API_KEY=...` then re-deploy the function.

### 6.2 PostHog on web — the JS snippet (gotcha)

`posthog_flutter` 4.x's `Posthog().setup()` is a **no-op on web**. The package's web plugin expects `window.posthog` to already exist before any `capture` / `identify` / `reset` call. Without the JS init snippet in `index.html`, every web event silently throws against `undefined` — the dashboard stays empty even though `POSTHOG_API_KEY` is set in dart-defines.

`web/index.html` already has the snippet (added 2026-04-28). It hardcodes the project token + EU host:

```js
posthog.init('phc_vM4Hrh7QhjsUqHRb2xC7LbqSqMsB5tLQqwSApkpEVPnU', {
  api_host: 'https://eu.i.posthog.com',
  person_profiles: 'identified_only'
});
```

`phc_*` keys are **write-only client keys** — safe to commit and serve publicly. PostHog confirms this in the project settings UI ("Safe to use in public apps").

**If you ever rotate the PostHog key, update BOTH:**
1. `web/index.html` (web reads from this).
2. `.dart-defines.json` `POSTHOG_API_KEY` (mobile reads from this via `--dart-define`).

The mobile path uses `Posthog().setup(PostHogConfig)` which DOES work on iOS/Android. The web path uses the JS SDK loaded by the snippet. Two paths, one PostHog project — keep them in sync.

---

## 7. First runs

### iOS simulator

```bash
open -a Simulator
flutter run --dart-define-from-file=.dart-defines.json
```

### Android emulator

```bash
flutter emulators --launch <your_emulator_id>
flutter run --dart-define-from-file=.dart-defines.json
```

### Web (Chrome)

```bash
flutter run -d chrome --dart-define-from-file=.dart-defines.json
```

**Direct / standalone path (email-OTP):** splash → `/auth/email` → enter email →
`/auth/otp` → 6-digit code → empty Licences with the "Complete your profile" banner.
Fill profile, save, add a licence, tap any field → toast confirms copy.

**Shell iframe path:** open `core.eq.solutions/:tenant/cards` in a browser where the
EQ Shell has set up a JWT. The `#sh=<jwt>` hash triggers `IframeHandoffScreen` →
`setSession` → `/licences` directly (no email prompt).

---

## 8. Production web build + deploy

```bash
flutter build web --release --dart-define-from-file=.dart-defines.prod.json
```

Output is in `build/web/`. **Deploy to Netlify** (decided ARCHITECTURE §16 Q5, 2026-04-28) — matches the existing EQ Solutions / SKS deploy pattern.

**GitHub auto-deploy is NOT wired** — per global EQ rules, production releases require an
explicit deploy step. Netlify site config is in `netlify.toml`
(Site ID: `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72`).

Deploy with:

```bash
netlify deploy --prod --dir build/web --site c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72
```

Or drag-drop `build/web/` onto the Netlify dashboard.

Domain: `cards.eq.solutions` (Netlify custom domain — LIVE). **Do not cross-deploy** —
per global CLAUDE.md, EQ files never go to SKS repos and vice versa.

---

## 9. Common errors

| Error | Cause | Fix |
|---|---|---|
| `Target of URI doesn't exist: 'app_router.g.dart'` | `build_runner` hasn't run | Step 4 |
| `MissingPluginException` for camera/biometric | Native permissions not added | Step 3 |
| `Unauthorized` on first Supabase call | Anon key wrong, or RLS blocking | Verify dart-defines + RLS policies in dashboard |
| OTP arrives but `verifyOTP` fails | Wrong `OtpType` or template mismatch | Supabase Auth → Phone settings, verify Twilio config |
| `flutter analyze` shows part-file errors | `.g.dart` / `.freezed.dart` missing | Step 4 (`--delete-conflicting-outputs`) |
| Photo upload fails with 403 | Storage RLS not applied | Check `licence-photos` RLS on eq-canonical; path must be `{tenant_id}/{staff_id}/{licence_id}/{slot}` |
| Web build fails on `dart:io` | Plugin trying mobile-only code on web | Check `kIsWeb` guards (architecture §11.5) — file an issue if a file slipped through |
| Hot reload broken on web | Code-gen out of date | `dart run build_runner build --delete-conflicting-outputs` again |
| Cards shows old auth screen after deploy | Stale service-worker cache | Hard-reload (`Ctrl+Shift+R`) or clear site data in browser DevTools; SW kill-switch should handle it automatically |
| `setSession` fails on iframe handoff | `#sh=<jwt>` hash not present or token expired | Shell must mint a fresh token via `mint-cards-iframe-token`; check Shell logs |
| Licences list returns empty on eq-canonical | `eq_cards_list_my_licences` RPC not found | Migration `2026_05_21_eq_cards_rpcs` may not have been applied; check Supabase MCP → list_migrations |

---

## 10. Suggested first PR scope (post-runbook)

Phase 1 was a brand-new scaffold with §14.2 deliberately relaxed. The first PR should re-engage the rule and add real coverage on whatever feature you exercise first.

Concrete options (pick one):

1. **Harden licences end-to-end** — widget tests for `LicenceCard` + `ExpiryBadge`, plus a manual smoke test (auth → profile → add licence with camera → view detail → tap-to-copy → expiry alert in 90 days).
2. **Wire Sentry + PostHog for real** — set the dart-defines, trigger a controlled crash, confirm Sentry receives it; tap-to-copy 5 fields, confirm `copy_field` events in PostHog.
3. **Lock down the web deploy** — decide §16 Q5 (Cloudflare vs Netlify), point `cards.eq.solutions` at the build, run TestFlight-equivalent invitation flow with 2-3 real users.

**Re-engage architecture rules:** keep PRs scoped to one feature. No more multi-feature batches like Phase 1.

---

## 11. Get a phone build running (Android first, Windows host)

Web works today (Edge). Mobile needs the platform toolchain. This is a one-time Windows setup.

### 11.1 Android Studio + SDK

1. Install Android Studio: https://developer.android.com/studio
2. On first launch, the setup wizard installs the Android SDK + platform-tools. Accept the defaults.
3. Open **SDK Manager** → install:
   - **Android SDK Platform 34** (or latest)
   - **Android SDK Build-Tools 34** (or latest)
   - **Android SDK Command-line Tools (latest)**
   - **Android SDK Platform-Tools** (for `adb`)
4. Open a fresh shell, then verify:
   ```bash
   flutter doctor --android-licenses   # accept all
   flutter doctor                       # Android toolchain should show √
   ```

### 11.2 Pick how you'll run

| Path | Setup cost | Pros | Cons |
|---|---|---|---|
| **Physical Android phone (recommended for OCR)** | Enable Developer Options + USB Debugging | Real camera = real OCR test | Needs USB cable |
| Android Studio emulator | Slow first boot (~5 min) | No cable | Emulator camera = fake images, OCR tests are stubbed |

For the magic-scanner test, a physical phone is the only path that exercises the real ML Kit OCR against a real licence photo.

### 11.3 First mobile run

```bash
flutter devices                         # confirm phone or emulator is listed
flutter run --dart-define-from-file=.dart-defines.json
```

Expected first-launch flow: splash → phone entry → OTP → profile-empty Licences with banner → tap Profile → fill → save → banner gone → add licence (manual) → tap-to-copy on detail.

### 11.4 iOS (deferred — Mac required)

iOS builds need Xcode and a Mac. Options when you're ready:
- Borrow / buy a Mac mini.
- Use a CI runner with macOS (GitHub Actions `macos-latest`, Codemagic, etc.) for TestFlight builds.
- The `ios/` folder + `Info.plist` permissions are already wired (see RUNBOOK §3 + this commit).

---

## 12. Magic-scanner (OCR) smoke test plan

EQ Cards' OCR is on-device ML Kit (mobile-only — web silently no-ops, ARCHITECTURE §11.5). 15 unit tests cover the parsers (`findDatesInText`, `findLicenceNumberInLines`). This section is the **real-photo** verification that should happen once per release on a physical phone.

### 12.1 What you need

- A physical Android phone with the app running (RUNBOOK §11).
- Real licences in your wallet covering at least 3 of the 13 seeded types (`SCHEMA.md` table). Aim for variety — White Card (8-digit number) + HLTAID (e.g. HLTAID011) + a state driver licence.
- The PostHog dashboard open (https://eu.posthog.com → Live events) so you can watch `licence_added` fire in real time.

### 12.2 Test matrix

For each licence below, capture the front photo via the in-app camera flow and verify the prefilled fields. Record pass/fail in a scratch sheet — repeat after every OCR-related code change.

| Licence | What OCR should find | Expected behaviour |
|---|---|---|
| White Card | 8-digit licence number, issue date | Number prefilled. Issue date prefilled. Expiry blank (White Cards don't expire). |
| HLTAID011 (First Aid) | `HLTAID011` code, issue + expiry dates (3-year validity) | Code captured as licence number. Both dates prefilled. |
| NSW driver licence (front) | Card number, expiry date | Card number captured. Expiry prefilled. Issue date often missing — manual entry OK. |
| Forklift (TLILIC0003) | Card number + expiry | Number captured (label-pattern hit). Expiry date prefilled. |
| Construction Induction (any state) | 8–10-digit number, issue date | Number captured. Issue date prefilled. |

### 12.3 Pass criteria

- ≥ 4/5 fields auto-extracted correctly across the matrix.
- `licence_added` event lands in PostHog with `licence_type` set per the seeded enum.
- The user can hand-fix any wrong field and save without losing the photo.

### 12.4 Known accuracy traps (already mitigated in code)

- Numbers that look like compact `YYYYMMDD` dates are rejected (so White Cards survive — see `_looksLikeCompactDate`).
- HLTAID codes are detected first so they always win over generic 6–12-char alphanumeric matches.
- `LICENCE NO` / `CARD NUMBER` labelled lines are pass-1 priorities.

If OCR misses a real-world licence in this matrix, file a sample image as a regression case and add a unit test to `ocr_service_test.dart` before fixing the parser.

---

**End of runbook.** Update when steps change. Date and signature every revision.
