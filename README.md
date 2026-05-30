# EQ Cards

> Wallet for tradies. Tap-to-copy profile and licence fields, on-device OCR for licence capture, and QR sharing.

A Flutter PWA in the [EQ Solutions](https://eq.solutions) suite. Runs standalone at
[cards.eq.solutions](https://cards.eq.solutions) and iframe-embedded in EQ Shell at
`core.eq.solutions/:tenant/cards`. Targets iOS, Android, and Web — web-first for v1.

The strategic wedge is **tap-to-copy**: one tap on any profile or licence field copies it,
with haptic + toast + analytics. Everything else supports getting accurate licence data into
the wallet with as little typing as possible.

## What it does

- **Licences** — capture a licence card by photo, extract fields via on-device OCR, store and
  display them. Three card layouts (linear, wallet, photo-first).
- **Profile** — the tradie's details (name, DOB, contact, trade), tap-to-copy on every field.
- **Certificates** — attach PDFs/images (white card, tickets) with signed-URL viewing.
- **QR + share** — generate a QR for quick handoff of profile/licence data.
- **Expiry alerts** — local notifications for licences nearing expiry (in-app badges on web).

## Stack

| Layer | Choice |
|---|---|
| Language / framework | Dart ≥ 3.5 · Flutter ≥ 3.24 |
| State | Riverpod 2.x (`riverpod_generator`) |
| Models | `freezed` + `json_serializable` |
| Routing | `go_router` |
| Backend | `supabase_flutter` (eq-canonical) · `dio` for non-Supabase HTTP |
| Local storage | `shared_preferences` (prefs + Supabase auth session) |
| OCR | Google ML Kit (`google_mlkit_text_recognition`) — mobile only; manual entry on web |
| Analytics / crash | `posthog_flutter` · `sentry_flutter` |
| Lint | `very_good_analysis` |

`ARCHITECTURE.md` is the binding contract for these choices — read it before adding code.
Three rules govern the codebase: **boring beats clever**, **features are folders**
(cross-feature deps go through `core/`, never sideways), and **no business logic in widgets**.

## Project layout

```
lib/
├── main.dart        # Bootstraps Supabase, Sentry, PostHog
├── app.dart         # Root MaterialApp.router + BiometricGate
├── core/            # Cross-feature shared concerns (theme, router, supabase client, widgets)
└── features/        # One folder per feature (auth, licences, profile, certificates, …)
```

Full tree and the rationale for each folder: `ARCHITECTURE.md` §2.

## Running locally

Requires the Flutter SDK (≥ 3.24).

```powershell
flutter pub get

# Generate freezed / json / riverpod parts (see "Code generation" below)
dart run build_runner build --delete-conflicting-outputs

# Run against the production backend on Edge
flutter run -d edge --web-port=8765 --dart-define-from-file=.dart-defines.prod.json
```

Config (Supabase URL/anon key, Sentry DSN, PostHog key) is supplied via
`--dart-define-from-file` — never hardcoded. The anon key is a public client key; no secrets
live in the repo.

## Code generation

`*.g.dart` and `*.freezed.dart` files are **generated, not committed** (they're gitignored).
After editing any model (`freezed`), JSON-serialisable class, or Riverpod provider, regenerate:

```powershell
dart run build_runner build --delete-conflicting-outputs
# or, while iterating:
dart run build_runner watch --delete-conflicting-outputs
```

A clean checkout will not analyze or test until codegen has run once.

## Quality gates

```powershell
flutter analyze   # very_good_analysis — expect 0 errors
flutter test      # widget + unit + golden tests
```

> **Golden tests** are pixel-exact and were baked on Linux/CI. They may fail locally on
> Windows/macOS due to font-rendering differences — that is environmental, not a regression.
> Don't regenerate goldens locally (it breaks CI); let CI own the baselines.

## Backend & auth

All data lives on the **eq-canonical** Supabase project, accessed through `eq_cards_*` RPCs.
Two sign-in paths land in the same session:

- **Shell handoff** — `#sh=<jwt>` when embedded in EQ Shell.
- **Email OTP** — 6-digit code for standalone use.

A **PIN app-lock** gates every cold start thereafter. Details: `ARCHITECTURE.md` §11 and `STATUS.md`.

## Deploy

Manual only, and **explicit instruction is required** — building is not deploying. Always run
from the `eq-cards` directory (the Netlify CLI must pick up *this* project's config, not Shell's).
The exact build/deploy commands and the headers/CSP rules live in `STATUS.md`.

## Docs

| File | What it covers |
|---|---|
| `ARCHITECTURE.md` | Binding architecture contract — stack, folder rules, data model, platform parity |
| `STATUS.md` | Current state, what shipped, deploy process, what's next |
| `CHANGELOG.md` | Dated change history |
