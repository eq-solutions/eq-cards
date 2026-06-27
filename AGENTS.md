# AGENTS.md — eq-cards

Machine-readable entry point for agents working in this repo (the AGENTS.md
convention — read natively by Claude Code, Codex, Cursor, Copilot, et al.).
This repo has **no CLAUDE.md**, so this file is the primary agent guidance —
read it before acting.

## Repo
**EQ Cards** — a Flutter PWA "wallet for tradies": tap-to-copy profile + licence
fields, on-device OCR for licence capture, QR sharing. The onboarding-intake app
of the EQ suite. Prod: **cards.eq.solutions** (standalone) + iframe-embedded in
EQ Shell at `core.eq.solutions/:tenant/cards`. Targets iOS / Android / Web (web-first).

Stack: Flutter ≥3.32 / Dart ≥3.8 · Riverpod 3 (state) · freezed + json_serializable
(models) · go_router 17 (routing) · supabase_flutter 2.5 (backend) · PostHog + Sentry.

## EQ substrate — read for cross-app rules
Cross-app behaviour, brand, infra, and decisions live in the public eq-context repo:
`https://raw.githubusercontent.com/eq-solutions/eq-context/main/CLAUDE.md`
Load the EQ tier defaults from there. That contract governs tone, brand, deploy,
and entity rules across the whole suite.

## Commands
```
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # codegen: freezed / json
flutter run -d chrome            # web-first dev
flutter analyze                  # must be clean — token-drift.yml gates on it
flutter test                     # unit / widget tests
flutter test --update-goldens    # regenerate golden files (see update-goldens.yml)
flutter build web                # production web build
```

## Guardrails — do not bypass
- **Design tokens are vendored.** `eq_design_tokens` resolves as a Flutter git dep;
  `token-drift.yml` fails if tokens are hand-edited instead of re-vendored, or if
  `flutter analyze` reports warnings. Re-vendor, don't hand-patch.
- **Deploy is explicit-only.** `deploy.yml` ships to cards.eq.solutions. Never deploy
  without instruction.
- **EQ ≠ SKS.** Never cross-deploy or mix credentials/data across entities.
- **No hardcoded secrets.** Supabase / PostHog / Sentry keys via env, never committed.

## Conventions
Plain English on user-facing surfaces. EQ brand: Plus Jakarta Sans; sky / deep / ice /
ink palette; no gradients or shadows; Linear/Notion aesthetic. Ask questions with
options. Full brand + voice in the substrate.

## Layout
`lib/main.dart` · `lib/app.dart` · `lib/core/` · `lib/features/<feature>/`.
See [README.md](README.md) for the product overview.
