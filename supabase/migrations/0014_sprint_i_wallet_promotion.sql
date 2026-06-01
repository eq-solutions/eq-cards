-- ─────────────────────────────────────────────────────────────────────────────
-- 0014 Sprint I: wallet promotion, source tracking, APP 12/17 RPCs
--
-- Goals:
--   1. Track which org contributed each licence (source_org_id)
--   2. Track promotion of worker_credentials → licences (promoted_at / _licence_id)
--   3. Rewrite eq_cards_claim_invite to promote staging credentials into the
--      worker's wallet at claim time, with dedup by (licence_type, licence_number)
--   4. Add eq_cards_get_worker_hr_record (APP 12 — access to own HR data)
--   5. Add eq_cards_delete_account (APP 17 — right to erasure of self-entered data)
--   6. Performance indexes
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Source tracking on licences ───────────────────────────────────────────

ALTER TABLE public.licences
  ADD COLUMN IF NOT EXISTS source_org_id         uuid REFERENCES public.organisations(id),
  ADD COLUMN IF NOT EXISTS source_worker_cred_id uuid REFERENCES public.worker_credentials(id);

COMMENT ON COLUMN public.licences.source_org_id IS
  'Org that contributed this licence via admin pre-load. NULL = self-entered by worker.';
COMMENT ON COLUMN public.licences.source_worker_cred_id IS
  'Staging worker_credentials row this was promoted from. NULL = self-entered.';

-- ── 2. Promotion tracking on worker_credentials ───────────────────────────────

ALTER TABLE public.worker_credentials
  ADD COLUMN IF NOT EXISTS promoted_at         timestamptz,
  ADD COLUMN IF NOT EXISTS promoted_licence_id uuid REFERENCES public.licences(id);

COMMENT ON COLUMN public.worker_credentials.promoted_at IS
  'When this staging record was promoted into the worker wallet (licences).';
COMMENT ON COLUMN public.worker_credentials.promoted_licence_id IS
  'The licences.id this staging record was merged into.';

-- ── 3. Performance indexes ────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_licences_user_type
  ON public.licences (user_id, licence_type)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_org_memberships_lookup
  ON public.org_memberships (org_id, user_id, status)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_worker_creds_unpromoted
  ON public.worker_credentials (worker_id)
  WHERE deleted_at IS NULL AND promoted_at IS NULL;

-- ── 4. Rewrite eq_cards_claim_invite ─────────────────────────────────────────
--
-- Changes from 0011:
--   • After linking worker + org_membership, iterates worker_credentials and
--     promotes each unpromoted, undeleted record into licences.
--   • Dedup key: (user_id, licence_type, licence_number). Singleton credential
--     types (no licence number) dedup by type only.
--   • Keeps higher expiry_date when a matching licence already exists.
--   • Marks each promoted staging row with promoted_at + promoted_licence_id.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.eq_cards_claim_invite(uuid);

CREATE OR REPLACE FUNCTION public.eq_cards_claim_invite(p_token uuid)
RETURNS SETOF public.workers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_invite       public.worker_invites;
  v_worker       public.workers;
  v_cred         public.worker_credentials;
  v_existing_lic public.licences;
  v_licence_id   uuid;
BEGIN
  -- ── Validate invite ────────────────────────────────────────────────────────
  SELECT * INTO v_invite
  FROM   public.worker_invites
  WHERE  token = p_token
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_invite.claimed_at IS NOT NULL THEN
    RAISE EXCEPTION 'invite_already_claimed' USING ERRCODE = 'P0003';
  END IF;
  IF v_invite.expires_at < now() THEN
    RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0004';
  END IF;

  -- ── Link worker ────────────────────────────────────────────────────────────
  IF v_invite.worker_id IS NOT NULL THEN
    UPDATE public.workers
    SET    user_id     = auth.uid(),
           updated_at  = now()
    WHERE  id          = v_invite.worker_id
      AND  user_id     IS NULL
    RETURNING * INTO v_worker;

    IF v_worker IS NULL THEN
      SELECT * INTO v_worker FROM public.workers WHERE id = v_invite.worker_id;
      IF v_worker IS NULL OR v_worker.user_id != auth.uid() THEN
        RAISE EXCEPTION 'worker_already_claimed_by_another_user' USING ERRCODE = 'P0005';
      END IF;
    END IF;
  ELSE
    -- Legacy path: build worker from profile_data JSONB
    INSERT INTO public.workers (
      user_id, first_name, last_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship
    ) VALUES (
      auth.uid(),
      v_invite.profile_data->>'first_name',
      COALESCE(v_invite.profile_data->>'last_name', v_invite.profile_data->>'full_name'),
      v_invite.profile_data->>'email',
      v_invite.profile_data->>'mobile',
      (v_invite.profile_data->>'date_of_birth')::date,
      v_invite.profile_data->>'address_street',
      v_invite.profile_data->>'address_suburb',
      v_invite.profile_data->>'address_state',
      v_invite.profile_data->>'address_postcode',
      v_invite.profile_data->>'emergency_contact_name',
      v_invite.profile_data->>'emergency_contact_mobile',
      v_invite.profile_data->>'emergency_contact_relationship'
    )
    ON CONFLICT DO NOTHING
    RETURNING * INTO v_worker;
  END IF;

  -- ── Create / reactivate org membership ────────────────────────────────────
  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_invite.org_id, auth.uid(), 'member', 'active', v_invite.created_by, now())
  ON CONFLICT (org_id, user_id)
    WHERE status != 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- ── Promote worker_credentials → licences ─────────────────────────────────
  IF v_worker IS NOT NULL THEN
    FOR v_cred IN
      SELECT *
      FROM   public.worker_credentials
      WHERE  worker_id   = v_worker.id
        AND  deleted_at  IS NULL
        AND  promoted_at IS NULL
    LOOP
      -- Dedup: match existing licence by (user_id, licence_type, licence_number).
      -- When licence_number is NULL the credential is a singleton per type
      -- (e.g. Manual Handling awareness) — match on type alone.
      SELECT * INTO v_existing_lic
      FROM   public.licences
      WHERE  user_id      = auth.uid()
        AND  licence_type = v_cred.credential_type::text
        AND  deleted_at   IS NULL
        AND  CASE
               WHEN v_cred.licence_number IS NOT NULL
               THEN licence_number = v_cred.licence_number
               ELSE licence_number IS NULL
             END
      LIMIT 1;

      IF v_existing_lic IS NULL THEN
        -- New to this wallet — insert
        INSERT INTO public.licences (
          user_id, licence_type, licence_number,
          issue_date, expiry_date, issuing_authority, state,
          notes, metadata,
          source_org_id, source_worker_cred_id
        ) VALUES (
          auth.uid(),
          v_cred.credential_type::text,
          v_cred.licence_number,
          v_cred.issue_date,
          v_cred.expiry_date,
          v_cred.issuing_body,
          v_cred.state_territory,
          v_cred.notes,
          COALESCE(v_cred.metadata, '{}'::jsonb),
          v_invite.org_id,
          v_cred.id
        )
        RETURNING id INTO v_licence_id;

      ELSE
        v_licence_id := v_existing_lic.id;
        -- Already in wallet — upgrade expiry if staging is more recent
        IF v_cred.expiry_date IS NOT NULL AND (
          v_existing_lic.expiry_date IS NULL OR
          v_cred.expiry_date > v_existing_lic.expiry_date
        ) THEN
          UPDATE public.licences
          SET    expiry_date = v_cred.expiry_date,
                 updated_at  = now()
          WHERE  id = v_existing_lic.id;
        END IF;
      END IF;

      -- Mark staging record as promoted
      UPDATE public.worker_credentials
      SET    promoted_at         = now(),
             promoted_licence_id = v_licence_id
      WHERE  id = v_cred.id;

    END LOOP;
  END IF;

  -- ── Mark invite claimed ────────────────────────────────────────────────────
  UPDATE public.worker_invites
  SET claimed_at = now(), claimed_by = auth.uid()
  WHERE id = v_invite.id;

  RETURN NEXT v_worker;
END;
$$;

-- ── 5. APP 12: worker reads their own HR record ───────────────────────────────
--
-- Returns the workers row linked to the calling user. If they've been
-- claimed by multiple orgs (multiple workers rows), returns the most recent.
-- Workers can see what the org holds about them but cannot edit it here —
-- corrections go to the admin for v1.

CREATE OR REPLACE FUNCTION public.eq_cards_get_worker_hr_record()
RETURNS SETOF public.workers
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT *
  FROM   public.workers
  WHERE  user_id = auth.uid()
  ORDER  BY created_at DESC
  LIMIT  1;
$$;

-- ── 6. APP 17: soft-delete of worker's own data (right to erasure) ────────────
--
-- Scope: only data the WORKER entered or that identifies them canonically.
--   • profiles — anonymised (worker's self-entered identity)
--   • licences — soft-deleted, PII fields nulled (credential types + expiry
--     kept for org compliance audit trails)
--   • org_memberships — revoked (removes org read access to wallet)
--
-- NOT in scope here (org is the data controller, not the worker):
--   • workers rows (org HR record — org must handle separately)
--   • worker_credentials staging rows (org-owned)
--
-- Hard deletion of auth.users is a manual ops step (Sprint K).

CREATE OR REPLACE FUNCTION public.eq_cards_delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Anonymise canonical identity
  UPDATE public.profiles
  SET    deleted_at                    = now(),
         full_name                     = '[deleted]',
         mobile                        = NULL,
         email                         = NULL,
         date_of_birth                 = NULL,
         address_street                = NULL,
         address_suburb                = NULL,
         address_state                 = NULL,
         address_postcode              = NULL,
         emergency_contact_name        = NULL,
         emergency_contact_relationship = NULL,
         emergency_contact_mobile      = NULL
  WHERE  id = auth.uid();

  -- Soft-delete licences; retain credential_type + expiry for org audit
  UPDATE public.licences
  SET    deleted_at     = now(),
         licence_number = NULL,
         notes          = NULL,
         metadata       = '{}'::jsonb
  WHERE  user_id    = auth.uid()
    AND  deleted_at IS NULL;

  -- Remove org access
  UPDATE public.org_memberships
  SET    status = 'revoked'
  WHERE  user_id = auth.uid()
    AND  status  != 'revoked';
END;
$$;
