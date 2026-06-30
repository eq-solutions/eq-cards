# ARMADA — eq-cards setup notes

Configured 2026-06-30. Pre-baked (not via /commission).

## Stack
Flutter mobile app. No package.json. No Netlify deploy.

## Build gate
`flutter analyze` — static analysis equivalent to tsc. No test suite yet.

## Safety rail
`autoMerge: false` — eq-cards is live taking real SKS worker signups.
Every PR requires a human eye before merge.

## Labels
- `armada` — triggers shipwright PR review
- `armada:lighthouse` — triggers lighthouse health scan

## Migrations tracked here
- 0062: adopt-or-create worker (prevent duplicates on approve)
- 0063: cleanup 7 orphan worker rows (reversible, self-verifying)
- 0065: fix handle_phone_dedup E.164 skip
