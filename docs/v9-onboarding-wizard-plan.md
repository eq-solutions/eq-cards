# V9 Onboarding Wizard — CANCELLED

Status: **cancelled (2026-06-13).** EQ Cards does not own payroll data. Bank/super/TFN
collection is out of scope — that belongs to EQ Field (payroll/resources rule).
Without steps 4–5, the wizard reduces to screens that already exist in the app
(profile edit, wallet list, claim consent), so there is nothing net-new to build.

## What was planned

A 7-step post-claim intake wizard (Welcome → Personal → Licences → Documents →
Bank & super → Review → Confirmation). The design handoff exists in
`EQ Cards - Onboarding.html` + `eq-tokens.css`.

## Why cancelled

- **Payroll PII** (bank, super, TFN) must not flow through Cards. Suite rule:
  payroll/resources = EQ Field only.
- Removing steps 4–5 leaves steps that duplicate existing claim + profile + wallet
  screens — no user value in adding a wizard wrapper.
- The post-claim experience is handled by the existing wallet (Layer A unified list).

## What shipped (Layer A)

Layer A (V9 component specs + unified wallet list) is live. That is the complete
V9 scope for EQ Cards:
- `EqButton`: CTA radius 13px
- `EqTextField`: white fill + 1px outline
- Home screen = unified wallet list (licences + certs, sorted by expiry)
- Wizard shell components (`WizardShell`) exist in code from a partial build but
  are not wired to any route — safe to leave or remove.
