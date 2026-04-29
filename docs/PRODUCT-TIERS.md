# EQ Cards — Product Tiers

**Drafted:** 2026-04-29 PM
**Author:** Working draft for Royce's review. Not yet approved or shared.
**Context:** Royce's framing — "all of EQ products having the starter package all the way through to enterprise style scale." This doc covers EQ Cards specifically; same shape applies to other EQ Solutions products with their own surface specifics.

---

## Why tiered

The EQ Solutions suite serves trade subbies from "one electrician with an apprentice" up through "50+ field staff at SKS-scale data-centre work." A single tier price-anchors wrongly — too cheap to sustain enterprise infrastructure, too expensive for a 5-person crew. Tiering also lets the **wedge** (tap-to-copy on profile + licence fields) stay free and friction-free, with paid surface area added only where the value compounds with team size.

Two anchors that don't move regardless of tier:

1. **Inductions, SWMS, prestarts and other safety-critical features are never paywalled.** (Standing rule from the EQ Intake bundle.) People not doing inductions because of money is unacceptable.
2. **The wedge — tap-to-copy on profile + licence fields — is free forever.** It's the reason someone installs the app at all. Charging for it kills the funnel.

---

## Tier 0 — Free wallet

**Audience:** Individual tradies, apprentices, sole-traders. The "one person trying to keep their licences in one place" customer.

**Price:** $0 forever.

**Includes:**
- Phone-OTP sign-in
- Profile + tap-to-copy on every field (the wedge)
- Up to **10 licences** in the wallet, with photos
- Mobile OCR (on-device ML Kit) — free, no cost to us
- Web OCR (Anthropic Claude Vision) — capped at **20 calls / month** so cost stays bounded
- Local expiry alerts (90 / 30 / 7 days) on mobile
- QR sharing (Phase 2 share-redeem when it ships)
- All 3 design directions (Linear / Wallet / Photo-first)
- Privacy / Terms / safety-critical features

**Caps that nudge upgrade:**
- 10-licence cap (most trades carry 4-8 active licences; only outliers hit it)
- 20 web-OCR calls / month (heavy users would notice)

**Cost to us per user / month:** ~AUD $0.10 worst case (Twilio OTP, Supabase storage, occasional OCR call). Sustainable indefinitely on dev tier.

---

## Tier 1 — Starter (1-5 person team)

**Audience:** Small electrical / plumbing / data subbies. The boss + 1-4 tradies. Enough scale that the boss is the one chasing inductions for the apprentice.

**Price:** ~AUD $9 / user / month (illustrative — pricing power tested via real conversations).

**Adds on top of Free:**
- **Unlimited licences + unlimited web OCR**
- **Team view** — boss sees an overview of all team members' licences and expiries (read-only)
- **Cross-sharing** — when the boss adds a job site, team members can one-tap share their wallet to that site (Phase 2 share-redeem flow)
- **CSV export** of a team member's licence data (for admin tasks)
- **Email expiry summary** — weekly digest to the boss showing who's about to expire
- **Priority support** — email response within 24 hrs

**Cost to us per user / month:** ~AUD $0.80 (more OCR usage, weekly email send, support touchpoints).

**Margin:** ~$8 / user / month. Healthy.

---

## Tier 2 — Pro (5-30 person team)

**Audience:** Established trade businesses. The 5-30 person team that has an office admin or a part-time bookkeeper. The customer who would otherwise be wrangling licences in spreadsheets and group SMS chats.

**Price:** ~AUD $19 / user / month (volume discount: $14 / user above 10 seats).

**Adds on top of Starter:**
- **Admin dashboard** — single-screen view of licence currency across the whole team. Filter by site, by trade, by expiry-window. Export.
- **Site profiles** — pre-configure principal-contractor templates (Equinix induction, NEXTDC induction, hospital-network template, etc.) so when a tradie joins a site, share-redeem prefills the right format
- **Slack / Teams / SMS notifications** — admin can route expiry alerts to a channel or to a person, not just an email
- **Bulk import** — paste a CSV of existing employee + licence data; AI maps the columns to the canonical schema (this is **EQ Import**, the desktop sibling product, but accessible from inside Cards' admin dashboard)
- **Audit trail** — every share, every export, every admin action logged with who-did-what-when
- **2-FA on admin accounts**
- **Custom branding** — the admin dashboard can be skinned with the customer's logo + colours (cosmetic; doesn't affect end-tradie wallet)

**Cost to us per user / month:** ~AUD $2.50 (richer notifications, more storage for audit logs, premium support).

**Margin:** ~$16 / user / month at full price.

---

## Tier 3 — Enterprise (30+ person team / data-centre / hospital scale)

**Audience:** SKS-scale customers. Principal contractors. Data-centre installers. Anyone where compliance bundles, client-portal exports, and audit packs are renewal-cycle-critical.

**Price:** Custom — annual contract, typically AUD $50-150 / user / month depending on integrations + SLA.

**Adds on top of Pro:**
- **SSO** — Microsoft Entra ID / Okta / Google Workspace. Per-domain auto-provisioning.
- **Job-management integrations** — bidirectional sync with SimPRO, AroFlo, Workbench, ServiceM8. (Per ARCHITECTURE §16 Q1 + EQ Intake doors.) When a tradie's licence expires, their job-mgt assignments auto-block.
- **Accounting integration** — read-only sync to Xero / MYOB / QuickBooks for cost-rate audit (timesheets and supplier invoices flow via EQ Import, not EQ Cards directly).
- **Client-portal exports** — the wallet can render and submit licence evidence in any client's required format. Equinix, NEXTDC, hospital networks, council bundles — set up once per principal, applied automatically thereafter.
- **Compliance bundles** — on-demand audit pack generation. "Last 12 months of SWMS / toolbox / licence currency" as a signed PDF.
- **Custom retention policies** — 7y default → 30y for legal/regulatory hold.
- **Data residency commitments** — Australian-only Supabase project, no overseas processors at the customer's request (means we offer an alternate OCR path that doesn't use Anthropic for these customers, e.g. AWS Textract in `ap-southeast-2`).
- **SLA** — 99.5% uptime, 4-hour incident response, named account manager.
- **Onboarding services** — we help migrate existing employee + licence data, set up site profiles, train the admin team. Fixed-fee implementation in the first month.

**Cost to us per user / month:** ~AUD $15-30 depending on integration scope.

**Margin:** ~50-70% at typical pricing. Enterprise sales cycle and onboarding cost is the gating constraint, not unit margin.

---

## What stays the same across tiers

- The wedge: tap-to-copy on every field, every screen, every tier
- Mobile OCR (free, on-device, no cost to us)
- Privacy-first defaults (EXIF stripping, signed photo URLs, RLS)
- The 3 design directions
- Inductions, SWMS, prestarts — never paywalled

---

## How tiers thread through EQ Solutions

EQ Cards is one product in a suite. The same tier framing applies to:

| Product | Free | Starter | Pro | Enterprise |
|---|---|---|---|---|
| **EQ Cards** (mobile wallet) | personal, ≤10 licences, OCR-capped | unlimited + team view | admin dashboard + integrations | SSO + custom exports |
| **EQ Import** (desktop intake) | 5 imports / month | unlimited + saved templates | bulk + scheduled imports | SSO + integration triggers |
| **EQ Capture** (vision intake) | 10 OCR calls / month | unlimited OCR | bulk paper-SWMS digitisation | + audit pack generation |
| **EQ Field** (mobile job mgmt) | view-only | basic scheduling | full scheduling + variations | + SimPRO/AroFlo bidirectional |
| **EQ Expenses** | personal expense tracker | + cost rate masking | + Xero sync | + accounting reconciliation rules |
| **EQ Quotes** | 5 quotes / month | unlimited quotes | + variation tracking | + client-portal submission |
| **EQ Ops** | — | — | dashboards | full ops command-centre |

Customers buy a **suite tier** (Starter / Pro / Enterprise) at the org level, and that grants the corresponding feature-set across whichever EQ products they've enabled. So a customer at Pro tier on Cards is also Pro on Import / Capture / Expenses by default — switching costs are inside one billing relationship.

This is the "starter → enterprise" framing Royce articulated. The EQ canonical schema spine (per `EQ-INTAKE-ARCHITECTURE.md`) is the technical realisation: every product feeds and reads from the same data, with role/tier flags gating which views and integrations a given user sees.

---

## What this means for EQ Cards' current pause-and-polish

**Nothing changes during the pause window.** Tiering is a v1.5+ concern — needs the canonical schema (multi-tenant, `tenant_id`, role columns) before any of it can be enforced. INTAKE Sprint-1 lays that groundwork.

The relevant Cards-side prep, all already done:
- ✅ Single-user wallet works end-to-end
- ✅ Wedge metric (`copy_field`) firing
- ✅ Web OCR with cost visibility (PostHog `licence_added` with `via_ocr`)
- ✅ Privacy / Terms / Settings infrastructure
- ✅ Design directions all shipping (cosmetic differentiation per tier later)

**Don't build:** any tier-specific gating, billing surface, or tenant-scoped views in Cards before INTAKE Sprint-1 lands.

---

## Open questions

1. **Pricing power.** $9 / $19 / $50+ are placeholders. Real numbers come from conversations with 3-5 trade subbies at each tier. The wedge usage data (`copy_field` ≥ 5/week/user) is the strongest evidence for value, but doesn't directly translate to willingness-to-pay.
2. **Free-tier limits.** 10 licences + 20 OCR/month: bumps for outliers without nudging real upgrades. May want to soften (20 licences, 50 OCR) once we see real usage distributions.
3. **Inductions paywalling.** Standing rule says no. Does that survive at scale where principal contractors require specific induction formats that cost us money to maintain (one new client-portal export per principal)? Likely yes — we eat the export-profile cost as customer acquisition. Re-test once 5+ principals are onboarded.
4. **Volume discount.** $14/user above 10 seats is illustrative. Real elasticity comes from the 5-30 segment.
5. **EQ Field bidirectional with SimPRO.** Per ARCHITECTURE §16 Q1 + EQ Intake §16 — first job-mgt integration is open. Pick the one with the most pain we can fix first; that becomes the leading Enterprise selling point.
6. **Customer-acquisition path.** Free → Starter is the funnel. Net acquisition cost matters more than tier prices in isolation. Currently no marketing site / paid acquisition; pure word-of-mouth from the SKS-side relationships.

---

## Decisions deferred

- Whether "Pro" includes EQ Capture's bulk-paper-SWMS digitisation by default or is a Pro+ add-on
- Whether SSO is Pro or only Enterprise
- White-label tier (Customer ships the suite under their own brand) — likely a separate "OEM" tier above Enterprise. Not v1 territory.

---

**This doc is a working draft. Update freely. Pricing numbers should reset after the first 5 real customer conversations.**
