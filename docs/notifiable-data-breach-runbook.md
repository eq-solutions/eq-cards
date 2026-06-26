# Notifiable Data Breach (NDB) Response Runbook — EQ Cards

**Owner:** Royce Milmlow / Emma Curth (directors, CDC Solutions Pty Ltd)
**Applies to:** EQ Cards (`cards.eq.solutions`) and its data in eq-canonical Supabase (`jvknxcmbtrfnxfrwfimn`).
**Legal basis:** Privacy Act 1988 (Cth) Part IIIC — Notifiable Data Breaches scheme.
**Status:** v1 (2026-06-26). Pairs with Privacy Policy §7. Review annually.

> Why this matters here: EQ Cards holds government IDs, Medicare numbers, and (per the
> credential types) WWCC, police-check, passport and right-to-work data. A breach of this
> class is very likely to cause "serious harm", so the NDB obligations will almost always apply.

---

## 0. The clock (memorise this)

Once you **suspect** an eligible breach, you have **30 days** to assess whether it is notifiable.
If it is, you must notify the OAIC **and** affected individuals **as soon as practicable**. Do not
sit on an assessment — start it the day you become aware.

| Phase | Target |
|---|---|
| Contain | Immediately (hours) |
| Assess (is it an "eligible data breach"?) | ≤ 30 days, faster if serious |
| Notify OAIC + individuals | As soon as practicable after assessing it as eligible |
| Post-incident review | Within 2 weeks of closure |

---

## 1. Detect — where a breach shows up

- **Sentry** (`eq-solutions` org) — spikes in auth errors, RLS-denied bursts, unexpected 200s on data endpoints.
- **Supabase logs / advisors** — run `get_advisors(type: security)` regularly; watch the Auth and PostgREST logs for anomalous `rpc/*` call volume or unfamiliar IPs.
- **Storage** — unexpected reads/listing of `licence-photos` or `certificates`.
- **Reports** — a worker or admin says "I can see someone else's documents" / "I got a code I didn't request".
- **Third-party processor notice** — Supabase, Twilio, Anthropic, PostHog, Sentry, or Netlify reports a breach on their side (their breach is your breach for your users).

Treat any credible signal of unauthorised **access to** or **disclosure/loss of** personal information as a *suspected* breach and open this runbook.

---

## 2. Contain (first hour)

1. **Stop the bleed** — depending on vector:
   - Leaked/over-broad RLS or RPC grant → apply a `REVOKE` / tightened policy migration immediately (see `supabase/migrations/0049_*`, `0050_*` for the pattern).
   - Compromised service-role / API key → rotate it in Supabase + Netlify env, redeploy. Revoke the old key.
   - Compromised user session → invalidate sessions (Supabase Auth → sign out user / rotate refresh tokens).
   - Public exposure of an endpoint → disable the edge function or feature flag it off.
2. **Preserve evidence** — snapshot the relevant Supabase logs, Sentry issues, and the offending migration/diff **before** you change anything irreversibly. Note timestamps (UTC).
3. **Open an incident record** — date/time discovered, who, what signal, first actions. Keep it in `eq-context` (private), not in the app repo.

---

## 3. Assess — is it an *eligible* data breach?

An eligible data breach = (a) unauthorised access/disclosure or loss of personal information, **and**
(b) a reasonable person would conclude it is **likely to result in serious harm** to any affected individual.

Work through:

1. **What data?** List the exact fields/tables/objects exposed. Rank by sensitivity:
   - *Highest:* `worker_credentials` (passport, WWCC, police check, right-to-work, Medicare), `licence-photos`/`certificates` storage objects, DOB + address.
   - *High:* names + licence numbers, emergency contacts, phone/email.
   - *Lower:* analytics events, opaque UUIDs.
2. **How many individuals**, and can you identify them? (Query the affected rows/paths.)
3. **Who got access** — internal mistake, single co-tenant worker, or open internet?
4. **Serious-harm test** — consider identity theft, fraud, physical safety (e.g. address + ID), or distress. Given the data class, default to "likely" unless you can show otherwise (e.g. data was encrypted/unreadable, or access was fleeting and remediated).
5. **Remediation exception** — if you acted before any serious harm was likely (e.g. revoked access before anyone read the data, and logs confirm no reads), the breach may **not** be notifiable. Document the evidence for this conclusion.

Record the decision and the reasoning. If unsure → treat as notifiable.

---

## 4. Notify (if eligible)

### 4.1 OAIC
- Use the OAIC **Notifiable Data Breach form**: https://www.oaic.gov.au/privacy/notifiable-data-breaches
- Include: your details (CDC Solutions Pty Ltd, ABN 40 651 962 935), description of the breach, the kinds of information involved, and recommended steps for individuals.

### 4.2 Affected individuals — "as soon as practicable"
- **Channel:** SMS and/or email to the affected workers (you already have verified mobiles). If you can't notify specific individuals, publish a notice and take reasonable steps to publicise it.
- **Content (plain English):** what happened, when, what information was involved, what you've done, **what they should do** (e.g. watch for scam calls/texts, consider replacing an exposed ID document, contact IDCARE 1800 595 160), and how to reach you (contact@eq.solutions).
- Template lives in `eq-context` (keep the wording pre-approved so you're not drafting under pressure).

---

## 5. Recover & review

- Confirm the fix holds (re-run `get_advisors`, re-test the RLS/grant, verify no further access in logs).
- **Post-incident review** within 2 weeks: root cause, why detection didn't catch it sooner, and a concrete prevention item (a migration, a test, an alert). Add a regression test where possible (e.g. assert anon cannot call a given RPC).
- Update this runbook with anything you learned.

---

## 6. Key contacts & resources

| | |
|---|---|
| Directors / decision-makers | Royce Milmlow, Emma Curth |
| Privacy contact | contact@eq.solutions |
| OAIC | 1300 363 992 · https://www.oaic.gov.au/ |
| IDCARE (identity-theft support for affected users) | 1800 595 160 · https://www.idcare.org |
| Supabase project | eq-canonical `jvknxcmbtrfnxfrwfimn` (region `ap-southeast-2`) |
| Error tracking | Sentry org `eq-solutions` |
| Processors who may report upstream | Supabase, Twilio (US), Anthropic (US), PostHog (EU), Sentry (EU), Netlify (US) |

---

**Reminder:** the 30-day assessment clock starts when you become *aware of grounds to suspect* a breach — not when you finish investigating. Start the assessment immediately.
