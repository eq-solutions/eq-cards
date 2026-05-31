# EQ Cards → canonical-api (`cards-api`) rewire — design & cutover plan

**Author:** Claude (cross-app audit, 2026-05-31)
**Branch:** `claude/cards-canonical-api-rewire`
**Status:** 🟢 **Rewire IMPLEMENTED behind an inert flag.** The repositories now
route through a `CardsDataSource` seam chosen by the `CARDS_DATA_TRANSPORT`
dart-define, which **defaults to `direct`** — so production behaviour is
byte-for-byte unchanged until someone builds with
`--dart-define=CARDS_DATA_TRANSPORT=gateway`. Flipping that flag on is still
**gated** on two *live* preconditions this task must not apply (a Supabase auth
hook and the EQ-tenant data migration); the hook SQL is staged for review under
`supabase/manual/`. The two smaller findings (auth error leak + CORS) are also
fixed here. **Nothing has been deployed.**

---

## 1. TL;DR for Royce

| Item | Asked | Done? | Why |
|---|---|---|---|
| Diagnose OTP vs handoff `tenant_id` | yes | ✅ diagnosed (§3) | — |
| Cleanest way to inject `tenant_id` for OTP | yes | ✅ designed (§5) | `custom_access_token_hook` on eq-canonical, sourced from `shell_control.users` |
| Re-wire repos → `CardsApi` | yes | 🟢 **Done behind a flag** (§7) | Repos call a `CardsDataSource` seam; transport chosen by `CARDS_DATA_TRANSPORT` (default `direct`). Direct RPCs kept as the default + rollback path, not deleted. |
| Flip the gateway on | — | ⛔ **NOT done** (gated, §6) | Blocked: the hook isn't live **and** EQ-tenant data isn't migrated. Flipping now would 401/empty-screen real users. |
| Confirm `cards-api` derives `tenant_id` for OTP tokens | yes | ✅ verified (§4) | `cards-api` is correct; it *401s* tokens with no `tenant_id`. The gap is upstream (at JWT mint), not in `cards-api`. |
| Fix `auth_flow_notifier` raw-error leak | yes | ✅ done (§9) | generic copy to user, raw → Sentry |
| Restrict `ocr-licence` / `share-licence` CORS | yes | ✅ done (§9) | `*` → `https://cards.eq.solutions` |

**The single sentence:** the rewire is one provider-wiring change away in the
Flutter code, but it is gated on **(A)** enabling a `custom_access_token_hook` on
eq-canonical and **(B)** migrating the EQ tenant's Cards data into its per-tenant
DB — both live, out-of-repo changes that only you should trigger.

---

## 2. Background: what `CardsApi` is and why it's dead code

`lib/core/cards_api/cards_api.dart` (`CardsApi` + `cardsApiProvider`) is a complete
Dio client for the Shell's `/.netlify/functions/cards-api` gateway. It has **zero
callers** — verified: the only matches for `CardsApi` in `lib/` are its own class,
constructor, and provider. Both repositories currently bypass it and call
`eq_cards_*` RPCs directly against eq-canonical:

- `lib/features/licences/data/licence_repository.dart:35,66,90` — `eq_cards_list_my_licences`, `eq_cards_upsert_my_licence`, `eq_cards_soft_delete_my_licence`
- `lib/features/profile/data/profile_repository.dart:31,47` — `eq_cards_current_staff`, `eq_cards_upsert_my_profile`

Both files carry the same rollback note (e.g. `licence_repository.dart:1-7`):

> The cards-api Shell proxy (Unit 5) was rolled back because it requires
> `app_metadata.tenant_id` in the JWT, which direct OTP sign-ins don't carry.

That note is **accurate and still true today.** This document is the plan to make
it false, safely.

---

## 3. Diagnosis (Goal 1): the three auth paths and where `tenant_id` comes from

Cards has three sign-in paths (`lib/features/auth/data/auth_repository.dart:1-8`).
Only one of them produces a JWT containing `app_metadata.tenant_id`:

| Path | How the session is minted | `app_metadata.tenant_id`? |
|---|---|---|
| **A. Shell handoff** (iframe at `core.eq.solutions/:tenant/cards`) | Shell sets the `eq_shell_session` cookie on `.eq.solutions`; Cards calls its own `netlify/functions/shell-verify.js`, which verifies the cookie HMAC and **mints a Supabase-compatible HS256 JWT** with `app_metadata.tenant_id` baked in. (A `postMessage` variant fetches the same token — `shell_session_refresh.dart`.) | ✅ **present** |
| **B. Email OTP** (standalone `cards.eq.solutions`) | `supabase.auth.signInWithOtp` / `verifyOTP` → Supabase mints a **native** JWT. No hook runs. | ❌ **absent** |
| **C. Google OAuth** (standalone) | `supabase.auth.signInWithOAuth(google)` → Supabase native mint. No hook runs. | ❌ **absent** |

Evidence the handoff path injects `tenant_id` and the direct paths do not — from
Cards' own SSO bridge, `netlify/functions/shell-verify.js`:

```js
// shell-verify.js:91-111  (mintSupabaseJwt)
const claims = {
  sub: userId, role: 'authenticated', aud: 'authenticated', jti,
  app_metadata: { tenant_id: tenantId, eq_role: eqRole, is_platform_admin, source_app: 'cards' },
  iat: now, exp: now + ttl,
};
```

…and the file's own header comment (paraphrased from the cookie/JWT design) plus
the gateway both confirm the OTP gap. The hook is documented as **planned, not
enabled** in three independent places:

- `supabase/config.toml:279-282` — `[auth.hook.custom_access_token]` is **commented out** (untouched template).
- `scripts/migrate-to-canonical.ts` STATUS: *"Until every tenant is migrated AND the auth hook injects tenant_id for OTP sessions, Cards stays pointed at eq-canonical via direct RPCs (the rollback)."*
- `ARCHITECTURE.md §17.3` (paraphrased): *"Custom access-token hook (PLANNED, NOT ENABLED). …would inject tenant_id … by looking up the user in `shell_control.users`. Until it's enabled, OTP/OAuth sessions have no tenant and cannot use the cards-api gateway."*

**Why the direct-RPC path works without `tenant_id`:** the `eq_cards_*` RPCs on
eq-canonical key off `auth.uid()`, not the tenant claim
(`supabase/migrations/0008_restore_eq_cards_rpcs.sql` — every function is
`where user_id = auth.uid()` / `id = auth.uid()`). So the rollback path is
self-sufficient; `tenant_id` is only needed to *route* a request to a per-tenant
DB, which is exactly what the gateway does.

---

## 4. `cards-api` verification (Goal 3): does it derive `tenant_id` correctly for OTP tokens?

**Verified against `C:/Projects/eq-shell/netlify/functions/cards-api.ts`.** The
gateway derives identity purely from the verified JWT:

```ts
// cards-api.ts:107-111
const jwt = verifySupabaseJwt(readBearerJwt(req));
if (!jwt) return json(401, { ok: false, error: 'not_signed_in' });
const tenantId = jwt.app_metadata.tenant_id;
const userId   = jwt.sub;
if (!tenantId || !userId) return json(401, { ok: false, error: 'jwt_missing_tenant_or_user' });
```

It then opens the tenant DB via `getTenantRpcClientById(tenantId)` (looks up
`shell_control.tenant_routing`, decrypts the service key, returns a
`public`-schema client) and calls each RPC passing **`p_tenant_id` + `p_user_id`
explicitly** (e.g. `cards-api.ts:188,196,208,222,236`), because the service-role
client has no `auth.uid()` context.

**Conclusion:** `cards-api` is **correct**. For a handoff token it routes properly;
for an **OTP/OAuth token it returns `401 jwt_missing_tenant_or_user`** because the
claim is genuinely absent. The fix must be made **upstream at mint time** (the
hook, §5) — *not* by adding a fallback in `cards-api`. (A `cards-api` fallback that
looked up the tenant by `user_id` server-side would technically work, but it would
fork tenant resolution into two code paths and is explicitly not the documented
design. Recommend against it.)

Two incidental notes from reading the gateway:

1. **`cards-api` is a superset of `CardsApi.dart`.** It also serves
   `upsert_my_profile` and control-plane ops (`list_licence_types`, `has_pin`,
   `set_pin`, `verify_pin`). The Flutter `CardsApi` only wires the five
   data ops. PIN currently runs via separate RPCs on eq-canonical
   (`pin_repository.dart`); moving PIN onto the gateway is **out of scope** here
   but worth a follow-up so PIN isn't left on the shared project after cutover.
2. **`cards-api` CORS** already allow-lists `https://cards.eq.solutions` plus
   `deploy-preview-*--eq-cards.netlify.app` (`cards-api.ts:71-72`). Good model;
   the §9 CORS fix mirrors it (minus previews — add them if you smoke-test OCR/share
   from preview URLs).

---

## 5. The fix for OTP/OAuth `tenant_id` (Goal 1): `custom_access_token_hook`

### 5.1 Recommendation

Add a **`custom_access_token_hook`** on **eq-canonical (`jvknxcmbtrfnxfrwfimn`)**
that injects `app_metadata.tenant_id` at mint time, sourcing the tenant from
**`shell_control.users`**.

Why this over a post-OTP server mint step:

- **Covers every native path at once** — OTP, OAuth, *and* token refresh all go
  through the access-token hook. A post-OTP mint would have to be re-run on every
  refresh and bolted onto the OAuth redirect too.
- **No client changes** — Cards keeps using `supabase.auth.*`; the token simply
  arrives with the claim. (A post-OTP mint needs new Flutter plumbing analogous to
  `shell-verify`/`setSession`.)
- **Single source of truth** — it reads the *same* table the Shell's handoff mint
  trusts, so a user's `tenant_id` is identical no matter how they sign in.
- It is the design `ARCHITECTURE.md §17.3` already commits to.

### 5.2 Critical design point: source from `shell_control.users`, NOT `org_memberships`

The `tenant_id` the gateway needs is the key into
`shell_control.tenant_routing` (`tenant-routing.ts` → `getTenantRpcClientById`).
That value lives in **`shell_control.users.tenant_id`** (eq-shell
`0001_shell_control.sql`):

```sql
create table shell_control.users (
  user_id           uuid primary key references auth.users(id),
  tenant_id         uuid not null references shell_control.tenants(id),
  eq_role           text not null default 'member',
  is_platform_admin boolean not null default false,
  ...
);
```

This repo *also* has a `public.org_memberships` table (`0006_org_layer.sql`) whose
`org_id` is conceptually a tenant. **Do not source the hook from `org_memberships`.**
If `org_memberships.org_id` ever diverged from `shell_control.users.tenant_id`, an
OTP user would route to a different (or non-existent) `tenant_routing` row than the
same user signing in via the Shell — a silent cross-tenant / empty-data bug. The
handoff path uses `shell_control.users`; the hook must match it exactly.

> **OPEN QUESTION 1 (Royce):** confirm `shell_control.users` is populated for every
> Cards user who can sign in via OTP/OAuth (not just Shell-provisioned users). If a
> tradie can self-serve OTP before being added to `shell_control.users`, the hook
> will emit no `tenant_id` and they'll 401 at the gateway. We need a rule for
> "OTP user with no shell_control.users row" (reject at gateway with a clear
> message, or auto-provision a tenant). See also the `link_pending_invites` /
> `org_memberships` invite flow in `0006_org_layer.sql:168-194` — clarify which of
> the two membership models is canonical for Cards.

### 5.3 Proposed hook SQL — ⚠️ DO NOT APPLY without Royce's go-ahead

This is a **live change to eq-canonical's auth behaviour.** Review, then apply via
the Supabase SQL editor / MCP against `jvknxcmbtrfnxfrwfimn`, and enable the hook
in **Auth → Hooks** (and/or uncomment the `config.toml` block). It is intentionally
**not** added as a numbered migration in this repo, to avoid `supabase db push`
auto-applying it.

```sql
-- PROPOSED — custom access token hook for eq-canonical (jvknxcmbtrfnxfrwfimn).
-- Injects app_metadata.tenant_id into Supabase-native JWTs (OTP/OAuth/refresh)
-- so they match the Shell-handoff token shape and can use the cards-api gateway.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer            -- owner must be able to read shell_control.users despite RLS
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_claims    jsonb;
begin
  select u.tenant_id
    into v_tenant_id
  from shell_control.users u
  where u.user_id = (event->>'user_id')::uuid;

  v_claims := coalesce(event->'claims', '{}'::jsonb);

  -- ensure app_metadata exists before writing into it
  if v_claims->'app_metadata' is null or jsonb_typeof(v_claims->'app_metadata') <> 'object' then
    v_claims := jsonb_set(v_claims, '{app_metadata}', '{}'::jsonb, true);
  end if;

  if v_tenant_id is not null then
    v_claims := jsonb_set(
      v_claims, '{app_metadata,tenant_id}', to_jsonb(v_tenant_id::text), true
    );
  end if;
  -- If v_tenant_id IS NULL we deliberately add nothing; the gateway then 401s
  -- with jwt_missing_tenant_or_user (see OPEN QUESTION 1 for the desired UX).

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

-- Supabase runs the hook as the supabase_auth_admin role.
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;
```

Notes / things to confirm before applying:

- **RLS on `shell_control.users`** is service-role-only (no policies). `security
  definer` (function owned by `postgres`) bypasses RLS so the lookup works. Confirm
  the function's owner is a role that bypasses RLS; if you'd rather not use
  `security definer`, instead `grant usage on schema shell_control` +
  `grant select on shell_control.users to supabase_auth_admin` **and** add a select
  policy for `supabase_auth_admin`.
- **`eq_role` / `is_platform_admin`:** the handoff token also carries these, but the
  current `shell-verify` mint and `verifySupabaseJwt` treat them as optional. Keep
  the hook minimal (`tenant_id` only) for parity with what the gateway *requires*;
  add `eq_role` later if/when a feature needs it.
- **`config.toml`:** for local/dev parity, the `[auth.hook.custom_access_token]`
  block at `config.toml:280-282` can be uncommented and pointed at
  `pg-functions://postgres/public/custom_access_token_hook`. Leave production
  enablement to the dashboard so it's an explicit, auditable action.

### 5.4 How to verify the hook (before trusting it)

1. Apply the function + enable the hook on eq-canonical.
2. Sign in via **OTP** on standalone `cards.eq.solutions`; decode the access token
   (jwt.io / `supabase.auth.currentSession`): assert `app_metadata.tenant_id` is
   present and equals the user's `shell_control.users.tenant_id`.
3. Repeat for **Google OAuth**.
4. Force a **token refresh** (wait out the TTL or call `refreshSession`) and
   re-check the claim survives.
5. Hit `cards-api?op=current_staff` with the OTP token → expect `200`, **not**
   `401 jwt_missing_tenant_or_user`.

Only when all five pass is precondition **A** met.

---

## 6. Blocking preconditions (the gates before any rewire)

The rewire (Goal 2) **must not** ship until **both** of these are true. Both are
documented in-repo as the exact conditions for ending the rollback
(`scripts/migrate-to-canonical.ts` STATUS line).

### A. Auth hook live & verified — §5.4
Without it, **every OTP/OAuth user** 401s at the gateway. (Handoff/iframe users
would still work.)

### B. EQ-tenant data migrated to its per-tenant DB
Per `migrate-to-canonical.ts` STATUS: the migration has been run **once, for the
SKS tenant only**; **the EQ tenant migration is pending.** Today all Cards data
lives on eq-canonical (`jvknxcmbtrfnxfrwfimn`). The gateway routes:

- EQ tenant → `zaapmfdkgedqupfjtchl`
- SKS tenant → `ehowgjardagevnrluult`

If we rewire while EQ data is still only on eq-canonical, **EQ-tenant users would
read an empty per-tenant DB** (apparent data loss) even with a valid `tenant_id`.
Before cutover, confirm on **each** per-tenant DB:

- the user's `profiles` + `licences` rows exist (migration applied), and
- the `eq_cards_*` RPCs exist (eq-shell `tenant-migrations/0006_cards_rpcs.sql`,
  `0007_cards_profile_rpc.sql`).

### Secondary (not strictly blocking reads, but resolve before GA): storage
`CardsApi`'s header says photo storage **intentionally stays on the shared
bucket** for now, but `licence_repository._withSignedUrls`
(`licence_repository.dart:107-123`) signs URLs via the **direct Supabase client**
(eq-canonical's `licence-photos` bucket). After cutover, licence *rows* come from
the per-tenant DB while photo *paths* may reference a different bucket
(`migrate-to-canonical.ts` rewrites photos to `tenant-{tenant_id}` buckets on the
destination project). Decide one of:

- keep signing against the shared bucket (works only while photos remain there), or
- add a gateway `op=sign_photo` / move signing to the tenant project.

This is the most likely subtle breakage and deserves an explicit decision.

> **OPEN QUESTION 2 (Royce):** is the EQ tenant ready to migrate, and do you want a
> single big-bang cutover or tenant-by-tenant (SKS first, since its data is already
> migrated)? A per-tenant flag would let SKS cut over now and EQ later.

---

## 7. The rewire itself (Goal 2) — recipe, for when A & B are green

The data-op contract already lines up (return shapes match the models), so the
Flutter side is small:

1. **Point repos at the gateway.** In `licenceRepository` /`profileRepository`
   providers, depend on `cardsApiProvider` instead of `supabaseClientProvider`,
   and replace each `_client.rpc('eq_cards_*')` with the matching `CardsApi`
   method:

   | Repo call | `CardsApi` method | Gateway op |
   |---|---|---|
   | `getAllForCurrentUser` | `listMyLicences()` | `list_my_licences` |
   | `upsert` | `upsertMyLicence(payload)` | `upsert_my_licence` |
   | `softDelete` | `softDeleteMyLicence(id)` | `soft_delete_my_licence` |
   | profile `getCurrent` | `currentStaff()` | `current_staff` |
   | profile `upsert` | `upsertMyProfile(payload)` | `upsert_my_profile` |

   The payload builders (`licenceToUpsertPayload`, `profileToUpsertPayload`) are
   unchanged — `CardsApi.upsert*` wraps them in `{ payload }`, which is what the
   gateway expects (`cards-api.ts:202-208,216-222`).

2. **Handle storage** per the §6 decision (keep `_withSignedUrls` only if photos
   stay on a bucket the active client can sign).

3. **Gate behind a flag** for instant rollback — e.g.
   `--dart-define=CARDS_DATA_TRANSPORT=gateway|direct` (default `direct` until
   you flip it), chosen in the repo providers. This avoids a code-revert-and-rebuild
   if something regresses in the field.

4. **Remove the dead direct path only after the flag has baked** — keep the
   `eq_cards_*` RPCs on eq-canonical (migration `0008`) through the rollback window;
   they're the fallback. Delete the direct repo code once `gateway` is the
   confirmed default.

5. `CardsApi` already proactively refreshes / re-mints the JWT near expiry
   (`cards_api.dart:144-170`), including the iframe `postMessage` re-mint, so the
   gateway path keeps the iframe session-refresh behaviour. No change needed there.

---

## 8. Cutover & rollback

```
0. (this branch) safe fixes only — auth error copy + CORS
1. Apply + enable custom_access_token_hook on eq-canonical        ← Royce (live)
2. Verify hook for OTP / OAuth / refresh (§5.4)                   ← gate A
3. Migrate EQ tenant data; verify rows + eq_cards_* RPCs per DB   ← Royce (live), gate B
4. Land rewire behind CARDS_DATA_TRANSPORT flag (default=direct)  ← code (this plan §7)
5. Flip flag to `gateway` for SKS; smoke-test; then EQ            ← runtime, reversible
6. Bake; then delete direct-RPC code + (later) retire 0008 RPCs   ← code
```

**Rollback at any point ≤5:** set the flag back to `direct` (or, pre-flag, revert
the wiring commit). The eq-canonical RPCs and data remain intact during the window,
so direct mode keeps working. **Auth changes (steps 1–2) require your explicit
approval before deployment** per the global non-negotiables.

---

## 9. What actually landed in this branch (safe fixes)

These are self-contained, carry no SSO risk, and are **not** deployed.

### 9.1 `auth_flow_notifier.dart` — stop leaking raw server errors
`lib/features/auth/presentation/notifiers/auth_flow_notifier.dart`

- The catch-all `ServerFailure(:final message) => message` showed raw server text
  to users. Replaced with a generic `'Something went wrong. Please try again.'`.
- Raw detail is now sent to **Sentry only** via a new `_reportOpaque(f)` (captures
  `ServerFailure`s without specific copy, and the underlying error of
  `UnknownFailure` — previously swallowed). `_message` stays a pure function so the
  mapping remains unit-testable; `_setError` ties reporting + mapping together.
- Rate-limit (429/401) and invalid-code (401) keep their specific friendly copy and
  are **not** captured (expected, not noise).

### 9.2 CORS lockdown on the two Edge Functions
- `supabase/functions/ocr-licence/index.ts` — `access-control-allow-origin: '*'` →
  `'https://cards.eq.solutions'`.
- `supabase/functions/share-licence/index.ts` — same.
- **Takes effect only on `supabase functions deploy`** (source-only change here).
- **Assumption to sanity-check:** the public licence-share page is served *from*
  `cards.eq.solutions` (so its browser fetch to `share-licence` is same-listed).
  Third-party verification works because the QR link opens that page (a top-level
  navigation, to which CORS doesn't apply) — not because some other origin fetches
  the function. If a non-`cards.eq.solutions` page is expected to `fetch()`
  `share-licence`, this lock would block it; tell me and I'll widen the allow-list.
- **Dev note:** local OCR testing that calls the *deployed* function from
  `localhost` will now be CORS-blocked. Mirror `cards-api`'s localhost/preview
  allow-list if you need that.

---

## 10. Open questions for Royce (consolidated)

1. **Tenant source of truth for OTP users** — confirm `shell_control.users` is
   populated for all OTP/OAuth-capable Cards users, and the desired UX for a user
   with no tenant row. Clarify `shell_control.users` vs `public.org_memberships`
   canonicality for Cards. (§5.2)
2. **EQ-tenant migration readiness & cutover shape** — big-bang vs per-tenant; is EQ
   data ready to migrate? (§6.B)
3. **Photo storage after cutover** — keep signing on the shared bucket, or move
   signing to the tenant project / gateway? (§6 secondary)
4. **PIN ops** — leave PIN RPCs on eq-canonical, or move onto the gateway so nothing
   Cards-related stays on the shared project post-cutover? (§4 note 1)
5. **`share-licence` CORS assumption** — confirm the share page is first-party on
   `cards.eq.solutions`. (§9.2)

Once 1–2 are resolved and the hook + migration are live and verified, the §7 rewire
is a small, flag-guarded change I can land on request.
