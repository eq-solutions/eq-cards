# EQ Cards — Current Status

**Last updated:** 2026-05-30
**Branch:** `main` — all fixes live at `cards.eq.solutions`

---

## Auth flows

| Entry point | Flow |
|---|---|
| EQ Shell iframe | `#sh=<jwt>` → `IframeHandoffScreen` → `setSession` → `/licences` |
| Direct / standalone | `/auth/email` → 6-digit email OTP → `/auth/otp` → `/licences` |

Both paths authenticate against **eq-canonical** (`jvknxcmbtrfnxfrwfimn`).

---

## Infrastructure

| Service | Detail |
|---|---|
| Supabase | `jvknxcmbtrfnxfrwfimn` (eq-canonical) — licences, profiles, OCR, share |
| Live PWA | `https://cards.eq.solutions` — Netlify, site ID `c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72` |
| Shell embed | `https://core.eq.solutions/:tenant/cards` |
| PostHog | `eq-production`, EU host `eu.i.posthog.com` |
| Sentry | `eq-cards`, EU ingest |
| Local dev | `flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.prod.json` |

---

## Fixes shipped 2026-05-25

### OTP loop (`430838e`)
`AuthFlowError` dropped the email field — every retry called `verifyOtp('', code)`, hit
the catch-all, showed "Something went wrong" indefinitely. Fixed by carrying `email`
through the error state so retries use the correct address.

### Shell handoff stuck on spinner (`430838e`)
`IframeHandoffScreen` called `setSession` then relied on GoRouter to navigate. GoRouter
intentionally excludes `/auth/handoff` from its sign-in redirect (to allow stale-session
replacement), so the spinner ran forever. Fixed by calling `context.go(Routes.licencesList)`
explicitly after `setSession` succeeds.

### Blank screen — duplicate CSP (`00fcf30`)
`netlify.toml` and `web/_headers` both sent `Content-Security-Policy`. Browsers apply the
more restrictive when duplicate headers are present. `netlify.toml` lacked
`https://www.gstatic.com`; `web/_headers` had it. The stricter policy won, blocking
Flutter's CanvasKit renderer (loaded from `gstatic.com` CDN when `engineRevision` is set)
→ blank white screen on all devices. Fixed by removing `[[headers]]` from `netlify.toml`
entirely — `web/_headers` is the sole source of truth for CSP.

### iframe framing (`430838e`)
`netlify.toml` had `X-Frame-Options: DENY` and `frame-ancestors 'none'` — Cards could
never be embedded in Shell. Fixed: removed `X-Frame-Options`, `frame-ancestors` now
`'self' https://*.eq.solutions`.

---

## Maintenance 2026-05-30 — repo dead-weight cleanup

Removed 8 unused/stale files: dead Dart helpers (`logger.dart`, `result.dart`,
`eq_snackbar.dart`), the duplicate `docs/` legal copies, `progress.html`, and the
completed `scripts/migrate-to-canonical.ts` (+ its README). Code/docs only — no
behaviour change, not a deploy. `flutter analyze` clean, codegen rebuilt. Full detail
in CHANGELOG. Firebase deps, `cards_api.dart`, and duplicate `0006_*` migration
filenames are flagged there for a later decision.

---

## Headers architecture

**`web/_headers`** is the authoritative source for all security headers. It is copied
verbatim to `build/web/_headers` by `flutter build web` and deployed with the static
assets. It includes:
- CSP with `https://www.gstatic.com` (Flutter CanvasKit CDN)
- `frame-ancestors 'self' https://*.eq.solutions` (Shell iframe embed)
- Cache-control per file type

**`netlify.toml`** has NO `[[headers]]` section. Adding headers there creates duplicate
CSP headers — browsers apply the more restrictive, breaking the app.

---

## Deploy process

Always from the `eq-cards` directory:

```powershell
cd C:\Projects\eq-cards
flutter build web --release --dart-define-from-file=.dart-defines.prod.json
netlify deploy --dir=build/web --prod --site=c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72
```

**Never run from the eq-shell directory** — the Netlify CLI picks up Shell's
`netlify.toml`, applies Shell's `script-src 'self'` (no `unsafe-inline`), blocks Flutter
web's inline bootstrap scripts, and the app shows a blank screen.

Netlify env vars required for CI build (`scripts/netlify_build.sh`):
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`, `POSTHOG_API_KEY`, `POSTHOG_HOST`
— all set on site `c1bf4b4d` as of 2026-05-25.

---

## What's next

**Supabase Email OTP (manual check):** Supabase dashboard → eq-canonical → Auth → Email
→ confirm **Enable Email OTP** is ON and expiry = 3600s. If in magic link mode, users
get a link in email instead of a 6-digit code and the OTP screen will always fail.

**GitHub → Netlify CI auto-deploy:** Env vars are set. Wire the GitHub repo in Netlify
site settings → Build & deploy, deploy branch = `main`.

**GTM validation:** 5 outside-SKS tradies on Cards. Onboard via direct `cards.eq.solutions`
link. Track `copy_field` events in PostHog.

---

## Resuming work

```powershell
cd C:\Projects\eq-cards
git status              # expect: clean, on main
flutter analyze         # expect: 0 errors
flutter test            # expect: ≥190 passing
```

---

## Key architecture notes

- **eq-canonical only.** All RPCs are `eq_cards_*` on `jvknxcmbtrfnxfrwfimn`. Legacy
  project decommissioned 2026-05-24.
- **Two-path auth.** Shell iframe (`#sh=<jwt>`) and direct email-OTP both land in the
  same Supabase session. GoRouter excludes `/auth/handoff` from sign-in redirect on
  purpose — the screen navigates explicitly after `setSession`.
- **`web/_headers` owns CSP.** Never add `[[headers]]` to `netlify.toml`.
- **Deploy from `eq-cards` dir always.** Context matters for which `netlify.toml` the CLI picks up.
- **SW intentionally disabled.** `web/index.html` unregisters any service worker on
  load. Don't re-enable without removing the kill-switch first.
