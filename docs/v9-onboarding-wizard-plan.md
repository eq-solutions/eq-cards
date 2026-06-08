# V9 Onboarding Wizard — Implementation Plan (Layer B)

Status: **planned, not started.** Layer A (V9 component specs + unified wallet
list) shipped separately. This document scopes the 7-step onboarding wizard
from the V9 Claude Design handoff (`EQ Cards - Onboarding.html`).

## What it is

A linear, one-time intake wizard a new worker completes after claiming their
invite. It is **the post-claim experience**, not a replacement for the wallet:

```
admin pre-populates  →  worker claims invite  →  V9 onboarding wizard  →  wallet (ongoing)
   (done, hardened)        (done, hardened)          (THIS PLAN)          (Layer A unified list)
```

The wizard's "Welcome aboard, Tom" with pre-filled details *is* the claim
identity carried forward — it confirms and completes, it doesn't re-key.

## The 7 steps

| # | Screen | Source of fields | Reuse |
|---|--------|------------------|-------|
| 1 | Welcome | name + role + start date from the claimed worker profile | — |
| 2 | Personal details | name, DOB, mobile, email, address | existing **profile** feature + licence OCR ("Scan licence" tile) |
| 3 | Licences & certificates | unified tile list | existing **licences** (OCR) + **certificates** |
| 4 | Documents | Photo ID, bank statement, TFN declaration, super form | **new** — file upload + storage |
| 5 | Bank & super | account name, BSB+account, super fund, member no. | **new** — sensitive PII |
| 6 | Review & submit | read-only summary + consent | sky review headers + consent block (V9 specs) |
| 7 | Confirmation | success + first-day/crew-lead info | — |

> Note: the prototype HTML omits Screen 5 (Bank & super) — the README lists it.
> Build all 7; the HTML is missing one screen, not the spec.

## Open decisions — these BLOCK the build

1. **Where does bank/super/TFN data land?** This is payroll PII. Per the suite
   rule, payroll/resources live in **EQ Field**, while Cards is the onboarding
   source of record. Likely shape: Cards collects → emits to canonical/Intake →
   SKS payroll consumes. Needs an explicit destination + encryption-at-rest +
   consent record + a security review before any field is collected.
2. **Document storage.** Bucket (Supabase storage?), per-worker access control
   (RLS), virus/*type* validation, and retention policy for ID + bank docs.
3. **"Submit onboarding" semantics.** What the final button does: create an
   onboarding-submission record, notify the admin/SKS, set worker status.
4. **Gating + resume.** Does every claimed worker hit the wizard once? How is
   "onboarding complete" tracked, and can a worker resume a half-finished draft
   (drafts must persist — it's a 5-min, multi-screen, PII-heavy flow)?
5. **Relationship to the existing claim consent.** The claim screen already has
   a consent step; Screen 6 has another. Reconcile so the worker consents once,
   clearly.

## Architecture (once decisions land)

- New `features/onboarding/` feature: a **wizard shell** (stepper + progress bar
  + step pills + back/next action bar per V9), per-step screens, a persisted
  **draft state** (Riverpod + local cache so refresh/return resumes), and a
  **submit repository**.
- Reuse existing features as steps where possible (profile, licences OCR,
  certificates) rather than re-implementing.
- Components are already V9-aligned from Layer A (CTA 13px, inputs white+outline,
  EqCard tiles). The wizard adds: the 3px sky **progress bar**, **step counter
  pill**, **sky review-section headers** (`rev-h`), and the **ice consent block**.

## Suggested phasing of B

- **B1 — Scaffold:** wizard shell, navigation logic (labels per V9: Get started
  / Continue / Submit onboarding / Done), progress, and Screens 1–3 wired to
  existing profile/licence/cert features. No new backend.
- **B2 — Documents + Bank/super:** Screens 4–5. Needs decisions #1–#2 (storage +
  PII destination) + a security review.
- **B3 — Review + Submit:** Screen 6 (sky headers, consent), Screen 7, and the
  submit endpoint (decision #3).
- **B4 — Integration:** gating after claim, draft resume, consent reconciliation
  (decisions #4–#5).

## Reference

Design handoff: `EQ Cards - Onboarding.html` + `eq-tokens.css` (V9 Claude Design
export). Hard rules: CTA radius 13px, inputs 6px/white/outline, section headers
sky+white, no gradients, Plus Jakarta Sans.
