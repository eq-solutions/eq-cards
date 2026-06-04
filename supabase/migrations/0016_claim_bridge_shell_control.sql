-- 0016_claim_bridge_shell_control.sql
--
-- Phase 1 — low-friction onboarding (Cards-first portable identity).
-- Decision: eq-context ops/decisions.md 2026-06-04 +
--           eq/identity/onboarding-portable-identity-2026-06-04.md  ("bridge at claim").
--
-- PROBLEM this fixes
--   The claim flow (eq_cards_claim_invite) wrote ONLY the public.* app layer
--   (public.workers / org_memberships / licences), keyed on auth.uid(). But
--   phone-OTP LOGIN resolves a tenant by matching shell_control.users.phone
--   (via the Shell's shell-login-phone-otp exchange). The two layers were
--   disconnected, so a claimed worker had no shell_control identity and landed
--   on "not provisioned" after signing in. (Verified live 2026-06-04: of 38
--   pre-loaded workers, only the hand-seeded admin existed in shell_control.)
--
-- WHAT this does
--   1. Adds an EXPLICIT public.organisations.tenant_id FK (replaces the
--      implicit slug / field_org_id heuristic) so claim resolves the tenant
--      deterministically. Backfilled from the verified 1:1 mapping.
--   2. eq_cards_claim_invite now ALSO upserts shell_control.users +
--      user_tenant_memberships for auth.uid().
--
-- SECURITY
--   The shell_control.users.phone is set ONLY from the GoTrue-VERIFIED value
--   (auth.users.phone) — never the admin-entered invite mobile — because that
--   column is the phone-OTP login key. The claim token is the authorisation
--   event; the verified phone the claiming user controls becomes their key.
--   shell_control.users.email is UNIQUE, so a colliding email is dropped to
--   NULL rather than failing the claim.
--
-- SCOPE NOTE
--   This is the deliberate Phase-1 "bridge at claim". Long-term the Shell owns
--   shell_control writes; revisit when custom_access_token_hook lands (Phase 2),
--   at which point the per-method shell-exchange bridges retire. The fn is owned
--   by postgres (SECURITY DEFINER) so the cross-schema write is permitted.

-- 1. Explicit org -> tenant mapping -------------------------------------------
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES shell_control.tenants(id);

UPDATE public.organisations o
SET    tenant_id = t.id
FROM   shell_control.tenants t
WHERE  o.tenant_id IS NULL
  AND  (t.field_org_id = o.id OR t.slug = o.slug);

-- 2. Claim RPC with the shell_control bridge appended -------------------------
CREATE OR REPLACE FUNCTION public.eq_cards_claim_invite(p_token uuid)
RETURNS SETOF public.workers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_invite       public.worker_invites;
  v_worker       public.workers;
  v_cred         public.worker_credentials;
  v_existing_lic public.licences;
  v_licence_id   uuid;
  v_tenant_id    uuid;
  v_auth_phone   text;
  v_auth_email   text;
  v_email        text;
  v_name         text;
BEGIN
  SELECT * INTO v_invite FROM public.worker_invites WHERE token = p_token FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002'; END IF;
  IF v_invite.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'invite_already_claimed' USING ERRCODE = 'P0003'; END IF;
  IF v_invite.expires_at < now() THEN RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0004'; END IF;

  IF v_invite.worker_id IS NOT NULL THEN
    UPDATE public.workers SET user_id = auth.uid(), updated_at = now()
    WHERE id = v_invite.worker_id AND user_id IS NULL RETURNING * INTO v_worker;
    IF v_worker IS NULL THEN
      SELECT * INTO v_worker FROM public.workers WHERE id = v_invite.worker_id;
      IF v_worker IS NULL OR v_worker.user_id != auth.uid() THEN
        RAISE EXCEPTION 'worker_already_claimed_by_another_user' USING ERRCODE = 'P0005';
      END IF;
    END IF;
  ELSE
    INSERT INTO public.workers (
      user_id, first_name, last_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship
    ) VALUES (
      auth.uid(),
      v_invite.profile_data->>'first_name',
      COALESCE(v_invite.profile_data->>'last_name', v_invite.profile_data->>'full_name'),
      v_invite.profile_data->>'email', v_invite.profile_data->>'mobile',
      (v_invite.profile_data->>'date_of_birth')::date,
      v_invite.profile_data->>'address_street', v_invite.profile_data->>'address_suburb',
      v_invite.profile_data->>'address_state', v_invite.profile_data->>'address_postcode',
      v_invite.profile_data->>'emergency_contact_name', v_invite.profile_data->>'emergency_contact_mobile',
      v_invite.profile_data->>'emergency_contact_relationship'
    )
    ON CONFLICT DO NOTHING RETURNING * INTO v_worker;
  END IF;

  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_invite.org_id, auth.uid(), 'member', 'active', v_invite.created_by, now())
  ON CONFLICT (org_id, user_id) WHERE status != 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  IF v_worker IS NOT NULL THEN
    FOR v_cred IN
      SELECT * FROM public.worker_credentials
      WHERE worker_id = v_worker.id AND deleted_at IS NULL AND promoted_at IS NULL
    LOOP
      SELECT * INTO v_existing_lic
      FROM   public.licences
      WHERE  user_id      = auth.uid()
        AND  licence_type = v_cred.credential_type::text
        AND  deleted_at   IS NULL
        AND  CASE
               WHEN v_cred.licence_number IS NOT NULL THEN licence_number = v_cred.licence_number
               ELSE licence_number IS NULL
             END
      LIMIT 1;

      IF v_existing_lic IS NULL THEN
        INSERT INTO public.licences (
          user_id, licence_type, licence_number,
          issue_date, expiry_date, issuing_authority, state,
          notes, metadata, source_org_id, source_worker_cred_id
        ) VALUES (
          auth.uid(), v_cred.credential_type::text, v_cred.licence_number,
          v_cred.issue_date, v_cred.expiry_date, v_cred.issuing_body, v_cred.state_territory,
          v_cred.notes, COALESCE(v_cred.metadata, '{}'::jsonb), v_invite.org_id, v_cred.id
        ) RETURNING id INTO v_licence_id;
      ELSE
        v_licence_id := v_existing_lic.id;
        IF v_cred.expiry_date IS NOT NULL AND (
          v_existing_lic.expiry_date IS NULL OR v_cred.expiry_date > v_existing_lic.expiry_date
        ) THEN
          UPDATE public.licences SET expiry_date = v_cred.expiry_date, updated_at = now()
          WHERE id = v_existing_lic.id;
        END IF;
      END IF;

      UPDATE public.worker_credentials
      SET promoted_at = now(), promoted_licence_id = v_licence_id
      WHERE id = v_cred.id;
    END LOOP;
  END IF;

  -- ── Bridge to shell_control identity layer ─────────────────────────────────
  -- Makes a claimed worker resolvable by phone-OTP login. Runs only when the
  -- worker's org maps to a tenant. Phone comes ONLY from the GoTrue-verified
  -- value (never the unverified invite mobile); email is dropped to NULL on a
  -- uniqueness collision. Never clobbers an existing verified phone with NULL.
  SELECT tenant_id INTO v_tenant_id FROM public.organisations WHERE id = v_invite.org_id;

  IF v_tenant_id IS NOT NULL THEN
    SELECT phone, email INTO v_auth_phone, v_auth_email FROM auth.users WHERE id = auth.uid();

    v_name := COALESCE(
      NULLIF(TRIM(COALESCE(v_worker.first_name, '') || ' ' || COALESCE(v_worker.last_name, '')), ''),
      v_invite.profile_data->>'full_name'
    );

    v_email := COALESCE(v_auth_email, v_invite.profile_data->>'email');
    IF v_email IS NOT NULL AND EXISTS (
      SELECT 1 FROM shell_control.users WHERE email = v_email AND id <> auth.uid()
    ) THEN
      v_email := NULL;
    END IF;

    INSERT INTO shell_control.users (id, email, phone, name, role, tenant_id, last_active_tenant_id, active)
    VALUES (auth.uid(), v_email, v_auth_phone, v_name, 'employee', v_tenant_id, v_tenant_id, true)
    ON CONFLICT (id) DO UPDATE SET
      phone                 = COALESCE(EXCLUDED.phone, shell_control.users.phone),
      email                 = COALESCE(shell_control.users.email, EXCLUDED.email),
      name                  = COALESCE(shell_control.users.name, EXCLUDED.name),
      tenant_id             = COALESCE(shell_control.users.tenant_id, EXCLUDED.tenant_id),
      last_active_tenant_id = COALESCE(shell_control.users.last_active_tenant_id, EXCLUDED.last_active_tenant_id),
      active                = true;

    INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
    VALUES (auth.uid(), v_tenant_id, 'employee', true)
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;
  END IF;

  UPDATE public.worker_invites SET claimed_at = now(), claimed_by = auth.uid() WHERE id = v_invite.id;
  RETURN NEXT v_worker;
END;
$function$;
