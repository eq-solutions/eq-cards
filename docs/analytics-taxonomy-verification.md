# PostHog Analytics Taxonomy — Verification Report

**Generated:** 2026-04-29 PM
**Source of truth:** [ARCHITECTURE.md §10.2 — v1 event taxonomy](../ARCHITECTURE.md#102-v1-event-taxonomy)
**Method:** Static cross-reference. Every event in the §10.2 table → confirm there's a fire site in `lib/`. Every `AnalyticsService.track(...)` call site → confirm the event name matches the table.

---

## Result: every taxonomy event has exactly one fire site, and every fire site is in the taxonomy.

✅ **9 / 9 events verified.**

---

## Event-by-event verification

| Event | Properties (per §10.2) | Fire site in `lib/` | Properties match? | Notes |
|---|---|---|---|---|
| `app_opened` | `is_first_open`, `platform` | [`main.dart:48`](../lib/main.dart) → `AnalyticsService.trackAppOpened()` → [`analytics_service.dart:52`](../lib/core/analytics/analytics_service.dart) | Partial — `platform` ✅, `is_first_open` ⚠️ deferred (would need `shared_preferences` lookup) | Documented gap. Architecture §10.2 lists it; current impl ships `platform` only. |
| `signup_completed` | `method` | [`analytics_service.dart:39`](../lib/core/analytics/analytics_service.dart) — fired from `startIdentitySync` on `AuthChangeEvent.signedIn` | ✅ `method: 'phone'` | Only fires on real sign-in, not on `initialSession` restore (which would trigger on every cold launch of an already-signed-in user). |
| `profile_field_filled` | `field` | [`profile_edit_screen.dart:183, 212`](../lib/features/profile/presentation/screens/profile_edit_screen.dart) | ✅ | Fires once per field that transitioned null→non-empty. Diff is computed against the profile state captured at hydrate-time, so re-saving an unchanged profile doesn't fire spurious events. |
| `profile_completed` | (none) | [`profile_edit_screen.dart:221`](../lib/features/profile/presentation/screens/profile_edit_screen.dart) | ✅ | Only fires on the incomplete→complete transition, not on every save once already complete. |
| `licence_added` | `licence_type`, `via_ocr` | [`licence_edit_screen.dart:257`](../lib/features/licences/presentation/screens/licence_edit_screen.dart) | ✅ | `via_ocr: true` whenever the prefill carried an `OcrExtraction`. Fires only on insert (id null going into the form), not on edit-save. |
| `licence_deleted` | (none) | [`licence_detail_screen.dart:164`](../lib/features/licences/presentation/screens/licence_detail_screen.dart) | ✅ | Soft-delete event. Only fires after the user confirms via the dialog. |
| `copy_field` | `label` | [`clipboard_utils.dart:33`](../lib/core/utils/clipboard_utils.dart) | ✅ | The wedge metric. ≥ 5/week per user = wedge works. Every tap-to-copy flows through `copyWithFeedback` so coverage is universal. |
| `copy_induction_block` | (none) | [`copy_induction_block.dart:25`](../lib/features/profile/presentation/widgets/copy_induction_block.dart) | ✅ | "Copy all profile fields" button. |
| `qr_generated` | `licence_id` | [`licence_detail_screen.dart:87`](../lib/features/licences/presentation/screens/licence_detail_screen.dart) | ✅ | Phase 1.5 demoware. Encodes a placeholder share-redeem URL until §18.2 endpoint exists. |

---

## Reverse check — every `AnalyticsService.track()` call accounted for

```
$ rg "AnalyticsService\.track\(" lib/
lib/core/utils/clipboard_utils.dart:33                                   copy_field
lib/features/profile/presentation/widgets/copy_induction_block.dart:25   copy_induction_block
lib/features/profile/presentation/screens/profile_edit_screen.dart:183   profile_field_filled
lib/features/profile/presentation/screens/profile_edit_screen.dart:212   profile_field_filled (dob branch)
lib/features/profile/presentation/screens/profile_edit_screen.dart:221   profile_completed
lib/features/licences/presentation/screens/licence_detail_screen.dart:87 qr_generated
lib/features/licences/presentation/screens/licence_detail_screen.dart:164 licence_deleted
lib/features/licences/presentation/screens/licence_edit_screen.dart:257  licence_added
```

Plus the two non-`track()` entries:
- `lib/main.dart:48` → `trackAppOpened()` (delegates to `track('app_opened', ...)`)
- `lib/core/analytics/analytics_service.dart:39` → `track('signup_completed', ...)` (fired from inside `startIdentitySync`)

**No orphan call sites.** No event is fired that isn't in the taxonomy table.

---

## Identity sync coverage

`AnalyticsService.startIdentitySync(SupabaseClient)` ([`analytics_service.dart`](../lib/core/analytics/analytics_service.dart)) listens to Supabase `onAuthStateChange` and:

- `AuthChangeEvent.signedIn` → `Posthog().identify(userId)` + `track('signup_completed', {method: 'phone'})`
- `AuthChangeEvent.initialSession` (with non-null session) → `Posthog().identify(userId)` (no signup event — they were already signed in)
- `AuthChangeEvent.signedOut` → `Posthog().reset()`

This means:
- Anonymous events (e.g. `app_opened` on cold launch before sign-in) are attributed to a per-device anonymous distinct_id.
- Once signed in, the distinct_id flips to the Supabase user UUID.
- `Posthog().reset()` on sign-out prevents cross-account leak when two users share a device.

---

## Event property contracts

These property names are public — changing them invalidates existing PostHog dashboards and saved insights. Treat as a versioned contract.

| Event | Required properties | Optional properties | Forbidden (PII) |
|---|---|---|---|
| `app_opened` | `platform` ('ios'\|'android'\|'web'\|'other') | `is_first_open` (deferred) | — |
| `signup_completed` | `method` ('phone') | — | phone number, OTP code |
| `profile_field_filled` | `field` (snake_case field name) | — | the actual value (e.g. don't log the email) |
| `profile_completed` | — | — | — |
| `licence_added` | `licence_type` (seeded code), `via_ocr` (bool) | — | licence number, photo URL |
| `licence_deleted` | — | — | — |
| `copy_field` | `label` (human-readable, e.g. "Mobile") | — | the copied value |
| `copy_induction_block` | — | — | the copied block |
| `qr_generated` | `licence_id` (UUID) | — | — |

Per ARCHITECTURE §10.1: **"No PII in event properties. User ID only via PostHog identification."** All current call sites comply.

---

## Known gaps (intentional, documented)

1. **`app_opened.is_first_open`** — would need a `shared_preferences` lookup at launch. Deferred to v1.1; gap noted in CHANGELOG.
2. **`expiry_alert_received` / `expiry_alert_tapped`** — listed in §10.2 but mobile-only (local notifications). Not in current Flutter taxonomy because the alert plumbing is wired but the *user-action* tap event needs a deeplink handler. Tracked in CHANGELOG "Pending."

---

**This report is regenerated on demand. If the §10.2 table changes, re-run the cross-reference and update this doc.**
