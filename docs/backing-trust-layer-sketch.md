# Backing / Trust Layer — design sketch

_Status: sketch (nothing built). 2026-06-14._

The wallet holds tickets and shows a photo. The boss verifies with their eyes.
This adds the missing middle rung of the trust ladder: **who backs a ticket**,
shown to both the worker and the boss. It's the cheapest, highest-leverage part
of the "rail not app" strategy — the only rung buildable with no external deals.

## The model — backing is *derived*, not a single flag

A ticket's displayed backing = the strongest attestation it currently has:

| Badge | Meaning | Source |
|---|---|---|
| **Just your word** | self-entered, only the worker vouches | no `source_org_id`, no endorsement |
| **Added by &lt;org&gt;** | an employer imported it during onboarding | `licences.source_org_id` (already set on claim) |
| **Confirmed by &lt;org(s)&gt;** | a person at an org sighted the original | ≥1 `sighted` endorsement (new) |
| _Authority-verified_ (future) | checked against the issuing register | rung 3 — not in scope |

Multiple orgs can confirm the same ticket — that's the portability signal
("Confirmed by SKS · also confirmed by Acme"). A single enum can't express that,
so confirmations live in their own ledger.

## Schema

**Phase 1 — surface what already exists (no new table).**
`licences.source_org_id` is populated on every employer-seeded ticket. Today it's
invisible. Surface it in the list RPCs + a badge → instant "Added by SKS" vs
"Just your word."

**Phase 2 — active vouching (new ledger).**

```sql
create table public.credential_endorsements (
  id          uuid primary key default gen_random_uuid(),
  licence_id  uuid not null references public.licences(id) on delete cascade,
  org_id      uuid not null references public.organisations(id),   -- who's vouching
  endorsed_by uuid not null,                                       -- the admin (auth.users)
  kind        text not null default 'sighted'
              check (kind in ('sighted')),                         -- room for 'authority' later
  -- snapshot so a renewal invalidates a stale confirmation:
  licence_number_at text,
  expiry_at         date,
  note        text,
  created_at  timestamptz not null default now(),
  unique (licence_id, org_id)                                      -- one confirmation per org per ticket
);
alter table public.credential_endorsements enable row level security;
-- Reachable only via the SECURITY DEFINER RPCs below.
```

`'added'` provenance stays in `source_org_id`; the ledger holds active
confirmations only. Keeps both signals clean and independently queryable.

## RPCs (all SECURITY DEFINER)

- **`eq_cards_endorse_licence(p_licence_id, p_org_id, p_note)`** — the boss's
  "I've sighted this — confirm" button.
  Guards: `is_org_admin(p_org_id)` **and** the licence owner is an active member
  of `p_org_id` (you can only back tickets of workers connected to you).
  Snapshots the current number+expiry. Idempotent (unique licence+org).
- **`eq_cards_revoke_endorsement(p_endorsement_id)`** — admin removes their org's
  confirmation (mistake / lapsed).
- **Extend the licence-list RPCs** (`eq_cards_list_my_licences` and the admin's
  view of a worker's wallet) to return, per ticket:
  - `backing_level`: `'self' | 'added' | 'confirmed'`
  - `backed_by`: array of org names (the adding org + confirming orgs)
  - `stale_confirmation`: true if a confirmation's snapshot ≠ current number/expiry
  All derived in SQL — cheap.

## RLS

`credential_endorsements` SELECT: caller owns the licence **or**
`is_org_admin_of(owner)` (an admin of an org the owner belongs to — same shape as
the existing `licences` read policy). INSERT/DELETE only through the RPCs.

## UX surfaces

**Worker (their wallet):**
- Trust badge on each licence row + detail — Confirmed / Added / Just your word.
- Self-entered nudge: "ask a boss to confirm it" (drives the flywheel).
- Detail "Backed by" list: org + date (+ "needs re-confirming" if stale).

**Boss / admin** (reuses the existing `admin_worker_detail_screen`):
- Each of the worker's licences: photo + details + **"I've sighted this —
  confirm"** (hidden once their org has confirmed).
- Shows existing confirmations (theirs + other employers') — the portability cue.
- Confirm dialog: "I've sighted the original {licence} for {worker}. Confirm."

## How it ties in

- **S4 is the delivery mechanism.** A connected employer can now confirm a
  tradie's self-entered tickets → upgrades the wallet → worth more at the next
  job. Every connection leaves a deposit. That's the flywheel actually turning.
- Layer 1 (badge) makes the existing data visible for ~nothing; Layer 2 (confirm)
  adds the high-trust rung.

## Rollout

1. **Phase 1 (~1 day):** derive `backing_level` from `source_org_id` in the list
   RPCs + a badge widget. "Added by SKS" / "Just your word." No new table, visible
   immediately.
2. **Phase 2 (~2–3 days):** `credential_endorsements` + endorse/revoke RPCs +
   the boss "Confirm" button + "Confirmed by" badge + worker nudge. Proven E2E
   (impersonation, net-zero) before any UI — same discipline as S4.
3. **Phase 3 (future, big bet):** authority/register verification, one authority
   at a time (electrical, White Card first). Slow, external, high-trust.

## Open questions

- **Renewal:** a confirmation is for a specific number+expiry (snapshotted). On
  renewal it goes "stale → re-confirm." Confirmed above; verify it matches how
  renewals are entered.
- **Privacy between competing employers:** worker sees all confirmations;
  employers see all confirmations (portability needs them visible). Revisit if an
  employer objects to a rival seeing their endorsement.
- **Who counts as "the boss"?** Uses `is_org_admin` (org_memberships role=admin).
  Confirm that's the right authority level vs manager/supervisor.
