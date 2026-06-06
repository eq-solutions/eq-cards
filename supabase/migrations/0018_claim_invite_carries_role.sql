-- 0018_claim_invite_carries_role.sql
--
-- Change: let an invite specify the eq_role the claimer is onboarded as, instead
-- of hardcoding 'employee'. The admin who pre-populates a worker profile sets the
-- role; claim respects it. Falls back to 'employee' when the invite omits a role
-- or supplies an unknown value.
--
-- Source of the role: worker_invites.profile_data->>'role' (no schema change —
-- worker_invites has no dedicated role column, and profile_data already carries
-- the admin-entered profile fields).
--
-- Safety: the value is validated against the eq_role enum's labels
-- (manager, supervisor, employee, apprentice, labour_hire) before use, so a bad
-- or absent value can never break the claim or inject an invalid enum cast.
--
-- This is the ONLY change vs 0017. The licence-promotion guard (v_worker.id IS
-- NOT NULL) and every other behaviour are copied verbatim. org_memberships.role
-- stays 'member' — that is the canonical org-layer vocabulary (text), not eq_role.

CREATE OR REPLACE FUNCTION public.eq_cards_claim_invite(p_token uuid)
 RETURNS SETOF workers LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_invite public.worker_invites; v_worker public.workers; v_cred public.worker_credentials;
  v_existing_lic public.licences; v_licence_id uuid; v_tenant_id uuid;
  v_auth_phone text; v_auth_email text; v_email text; v_name text;
  v_role text;
BEGIN
  SELECT * INTO v_invite FROM public.worker_invites WHERE token = p_token FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002'; END IF;
  IF v_invite.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'invite_already_claimed' USING ERRCODE = 'P0003'; END IF;
  IF v_invite.expires_at < now() THEN RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0004'; END IF;

  -- Derive the eq_role from the invite, validated against the enum's labels.
  -- Unknown / absent → 'employee' (the safe default for a self-claiming worker).
  v_role := lower(NULLIF(TRIM(COALESCE(v_invite.profile_data->>'role','')), ''));
  IF v_role IS NULL OR v_role NOT IN ('manager','supervisor','employee','apprentice','labour_hire') THEN
    v_role := 'employee';
  END IF;

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
    INSERT INTO public.workers (user_id, first_name, last_name, email, phone, date_of_birth,
      address_street, address_suburb, address_state, address_postcode,
      emergency_contact_name, emergency_contact_phone, emergency_contact_relationship)
    VALUES (auth.uid(), v_invite.profile_data->>'first_name',
      COALESCE(v_invite.profile_data->>'last_name', v_invite.profile_data->>'full_name'),
      v_invite.profile_data->>'email', v_invite.profile_data->>'mobile',
      (v_invite.profile_data->>'date_of_birth')::date,
      v_invite.profile_data->>'address_street', v_invite.profile_data->>'address_suburb',
      v_invite.profile_data->>'address_state', v_invite.profile_data->>'address_postcode',
      v_invite.profile_data->>'emergency_contact_name', v_invite.profile_data->>'emergency_contact_mobile',
      v_invite.profile_data->>'emergency_contact_relationship')
    ON CONFLICT DO NOTHING RETURNING * INTO v_worker;
  END IF;

  INSERT INTO public.org_memberships (org_id, user_id, role, status, invited_by, accepted_at)
  VALUES (v_invite.org_id, auth.uid(), 'member', 'active', v_invite.created_by, now())
  ON CONFLICT (org_id, user_id) WHERE status != 'revoked' AND user_id IS NOT NULL
  DO UPDATE SET status = 'active', accepted_at = now();

  -- FIX (0017): primary-key check, not row-wise `v_worker IS NOT NULL`.
  IF v_worker.id IS NOT NULL THEN
    FOR v_cred IN
      SELECT * FROM public.worker_credentials
      WHERE worker_id = v_worker.id AND deleted_at IS NULL AND promoted_at IS NULL
    LOOP
      SELECT * INTO v_existing_lic FROM public.licences
      WHERE user_id = auth.uid() AND licence_type = v_cred.credential_type::text AND deleted_at IS NULL
        AND CASE WHEN v_cred.licence_number IS NOT NULL THEN licence_number = v_cred.licence_number
                 ELSE licence_number IS NULL END
      LIMIT 1;
      IF v_existing_lic IS NULL THEN
        INSERT INTO public.licences (user_id, licence_type, licence_number, issue_date, expiry_date,
          issuing_authority, state, notes, metadata, source_org_id, source_worker_cred_id)
        VALUES (auth.uid(), v_cred.credential_type::text, v_cred.licence_number, v_cred.issue_date,
          v_cred.expiry_date, v_cred.issuing_body, v_cred.state_territory, v_cred.notes,
          COALESCE(v_cred.metadata, '{}'::jsonb), v_invite.org_id, v_cred.id) RETURNING id INTO v_licence_id;
      ELSE
        v_licence_id := v_existing_lic.id;
        IF v_cred.expiry_date IS NOT NULL AND (v_existing_lic.expiry_date IS NULL OR v_cred.expiry_date > v_existing_lic.expiry_date) THEN
          UPDATE public.licences SET expiry_date = v_cred.expiry_date, updated_at = now() WHERE id = v_existing_lic.id;
        END IF;
      END IF;
      UPDATE public.worker_credentials SET promoted_at = now(), promoted_licence_id = v_licence_id WHERE id = v_cred.id;
    END LOOP;
  END IF;

  SELECT tenant_id INTO v_tenant_id FROM public.organisations WHERE id = v_invite.org_id;
  IF v_tenant_id IS NOT NULL THEN
    SELECT phone, email INTO v_auth_phone, v_auth_email FROM auth.users WHERE id = auth.uid();
    IF v_auth_phone IS NULL OR v_auth_phone = '' THEN v_auth_phone := NULL;
    ELSIF left(v_auth_phone, 1) <> '+' THEN v_auth_phone := '+' || v_auth_phone; END IF;
    IF v_auth_phone IS NOT NULL AND EXISTS (SELECT 1 FROM shell_control.users WHERE phone = v_auth_phone AND id <> auth.uid()) THEN v_auth_phone := NULL; END IF;
    v_name := COALESCE(NULLIF(TRIM(COALESCE(v_worker.first_name,'')||' '||COALESCE(v_worker.last_name,'')),''), v_invite.profile_data->>'full_name');
    v_email := COALESCE(v_auth_email, v_invite.profile_data->>'email');
    IF v_email IS NOT NULL AND EXISTS (SELECT 1 FROM shell_control.users WHERE email = v_email AND id <> auth.uid()) THEN v_email := NULL; END IF;
    INSERT INTO shell_control.users (id, email, phone, name, role, tenant_id, last_active_tenant_id, active)
    VALUES (auth.uid(), v_email, v_auth_phone, v_name, v_role::eq_role, v_tenant_id, v_tenant_id, true)
    ON CONFLICT (id) DO UPDATE SET phone = COALESCE(EXCLUDED.phone, shell_control.users.phone),
      email = COALESCE(shell_control.users.email, EXCLUDED.email), name = COALESCE(shell_control.users.name, EXCLUDED.name),
      tenant_id = COALESCE(shell_control.users.tenant_id, EXCLUDED.tenant_id),
      last_active_tenant_id = COALESCE(shell_control.users.last_active_tenant_id, EXCLUDED.last_active_tenant_id), active = true;
    INSERT INTO shell_control.user_tenant_memberships (user_id, tenant_id, role, active)
    VALUES (auth.uid(), v_tenant_id, v_role::eq_role, true)
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET active = true;
  END IF;

  UPDATE public.worker_invites SET claimed_at = now(), claimed_by = auth.uid() WHERE id = v_invite.id;
  RETURN NEXT v_worker;
END;
$function$;
