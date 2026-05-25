# EQ Cards — Current Status

**Last updated:** 2026-05-25
**Posture:** Active — live at `cards.eq.solutions`. Auth (both paths) working.
Branch `claude/cards-api-cutover` is ahead of `main` — merge when ready.

---

## What's live (as of 2026-05-25)

### Auth flows

| Entry point | Flow |
|---|---|
| EQ Shell iframe | `#sh=<jwt>` in URL hash → `IframeHandoffScreen` → `setSession` → `/licences` |
| Direct / standalone | No hash → `/auth/email` → 6-digit email OTP → `/auth/otp` → `/licences` |

Both paths authenticate against **eq-canonical** (`jvknxcmbtrfnxfrwfimn`).

### Infrastructure

| Service | URL / ID | Notes |
|---|---|---|
| **Supabase** | `jvknxcmbtrfnxfrwfimn` (eq-canonical) | All profile + licence data; Edge Functions; OCR |
| Edge Function (OCR) | `https://jvknxcmbtrfnxfrwfimn.supabase.co/functions/v1/ocr-licence` | Claude Vision |
| Edge Function (share) | `https://jvknxcmbtrfnxfrwfimn.supabase.co/functions/v1/share-licence` | Public QR share |
| PostHog | `eq-production` project, EU host (`eu.i.posthog.com`) | All 9 v1 events wired |
| Sentry | `eq-cards`, EU ingest | `runZonedGuarded` wraps `main()` |
| **Live PWA** | `https://cards.eq.solutions` | Netlify, site ID `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72` |
| Shell embed | `https://core.eq.solutions/:tenant/cards` | Shell hands off JWT via `#sh=` hash |
| Local dev | `http://localhost:8765/` | `flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.prod.json` |

---

## Recent fixes (2026-05-25)

### `c12f6e2` — OTP loop fix

`AuthFlowError` was dropping the email field. Every retry called `verifyOtp('', code)`
which hit the `catch (_)` branch → "Something went wrong" → infinite loop.

- `auth_flow_state.dart`: Added `email` field to `AuthFlowError`
- `auth_flow_notifier.dart`: Pass `email` to both error paths in `verifyOtp`
- `otp_screen.dart`: Read email from `AuthFlowError` state (not `''`); clear code field on error

### `f1eb652` — CSP headers + iframe framing + handoff navigation

Three bugs in one commit:

1. **`netlify.toml`**: Removed `X-Frame-Options: DENY`. Changed `frame-ancestors 'none'`
   to `frame-ancestors 'self' https://*.eq.solutions`. Added `worker-src blob:` for
   Flutter web workers. App can now be embedded in Shell and loads correctly.

2. **`iframe_handoff_screen.dart`**: Added `context.go(Routes.licencesList)` after
   `setSession` succeeds. GoRouter's redirect intentionally excludes `/auth/handoff`
   from the sign-in redirect (to allow stale-session replacement), so the screen must
   drive the final navigation itself — otherwise the spinner runs forever.

### Netlify env vars set (2026-05-25)

The Netlify site now has all 5 required build-time env vars configured:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`, `POSTHOG_API_KEY`, `POSTHOG_HOST`.

`scripts/netlify_build.sh` is now unblocked for GitHub → Netlify CI (previously
held pending secrets review).

---

## Deploy process

Always deploy from the `eq-cards` directory so `netlify.toml` is picked up correctly:

```powershell
cd C:\Projects\eq-cards
flutter build web --release --dart-define-from-file=.dart-defines.prod.json
netlify deploy --dir=build/web --prod --site=c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72
```

**Never run `netlify deploy` from the eq-shell directory** — it will pick up Shell's
`netlify.toml` and apply Shell's `script-src 'self'` (no `unsafe-inline`) which
blocks Flutter web's inline scripts and prevents the app from loading.

---

## Branch state

| Branch | State |
|---|---|
| `claude/cards-api-cutover` | Ahead of `main` — all fixes committed, deployed live |
| `main` | Behind — merge `claude/cards-api-cutover` when confirmed working |

---

## What's next

### Supabase Email OTP (manual check required)

Go to Supabase dashboard → eq-canonical → Auth → Email settings:
- **Enable Email OTP** must be **ON**
- OTP expiry: **3600** seconds
- If this is set to magic link mode, the `/auth/email` → `/auth/otp` flow will send a
  link rather than a 6-digit code and the OTP screen will always fail.

### GitHub → Netlify CI auto-deploy

Netlify env vars are now set. To wire auto-deploy:
1. Connect the GitHub repo in Netlify site settings → Build & deploy
2. The `scripts/netlify_build.sh` script will run on every push to the deploy branch
3. Set the deploy branch to `main` (or a dedicated `production` branch)

### GTM validation — 5 outside-SKS tradies on Cards

From `eq/pending.md`: validate the product with 5 outside-SKS trade subbies before
further build investment. Cards is the wedge product. Onboard via direct `cards.eq.solutions`
link (email-OTP standalone flow). Track `copy_field` events in PostHog.

---

## What's deferred

- Mobile builds (Android Studio on Windows host; iOS needs Mac)
- Apple Wallet pass generation
- Drift offline cache + offline writes
- Phase 2 share-redeem endpoint (external consumers only)
- Public launch beyond the 5-sparky pilot

---

## Where things live

| Path | What |
|---|---|
| `lib/` | Flutter app source |
| `test/` | Tests — run `flutter test` for live count |
| `scripts/netlify_build.sh` | Netlify CI build script (reads env vars, runs flutter build web) |
| `scripts/migrate-to-canonical.ts` | Unit 3 one-time migration (idempotent, `--apply` required) |
| `supabase/functions/ocr-licence/` | Claude Vision Edge Function on eq-canonical |
| `supabase/functions/share-licence/` | Public QR share endpoint on eq-canonical |
| `web/index.html` | PostHog JS snippet (hardcoded EU host + write-only key) |
| `netlify.toml` | Netlify config — SPA redirect + CSP headers. No build command (manual deploy). |
| `.dart-defines.prod.json` | Production dart-defines → eq-canonical (gitignored) |
| `ARCHITECTURE.md` | Architecture contract |
| `CHANGELOG.md` | Full session history |
| `RUNBOOK.md` | First-morning setup + OCR smoke test |

---

## Resuming work — first commands

```powershell
cd C:\Projects\eq-cards
git status                   # confirm on claude/cards-api-cutover
flutter analyze              # expect: 0 errors (2 pre-existing info warnings OK)
flutter test                 # expect: ≥190 passing
flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.prod.json
```

Both `.dart-defines.prod.json` and `.dart-defines.json` point at eq-canonical.
Legacy project (`hshvnjzczdytfiklhojz`) decommissioned 2026-05-24.

---

## Key architecture notes (for future agents)

- **eq-canonical is the only Supabase project.** All RPCs are `eq_cards_*` on
  `jvknxcmbtrfnxfrwfimn`. The legacy project is gone.
- **Two-path auth:** `IframeHandoffScreen` (`#sh=<jwt>`) for Shell embed;
  email-OTP (`/auth/email` → `/auth/otp`) for standalone. Both land in the same
  Supabase session on eq-canonical.
- **GoRouter/handoff contract:** `/auth/handoff` is excluded from the router's
  sign-in redirect on purpose (to allow stale-session replacement). The handoff
  screen navigates explicitly to `/licences` after `setSession`.
- **Deploy from eq-cards dir always.** `netlify.toml` must come from this repo,
  not from a sibling repo's worktree.
- **SW kill-switch is active.** `web/index.html` unregisters any installed service
  worker on load. Don't re-enable the SW without removing this first.

**This file is the source of truth for "where is EQ Cards?" Update it on every meaningful change.**
