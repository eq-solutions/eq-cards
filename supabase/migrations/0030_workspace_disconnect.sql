-- 0030_workspace_disconnect.sql
--
-- Phase 2b: let a worker disconnect from an employer they optionally joined.
-- This is the other half of the consent loop — Phase 2a let workers switch
-- between tenants; this lets them leave one.
--
-- Two changes:
--   1. eq_cards_list_my_tenants() gains an `is_home` column so the UI can tell
--      which tenant is the worker's home (users.tenant_id) — the home tenant
--      and the personal wallet are NOT disconnectable here.
--   2. eq_cards_revoke_org_access(uuid) — soft-deactivates an optional org
--      membership and falls the active context back to the home tenant.
--
-- Disconnect semantics (deliberately narrow):
--   • You can only disconnect an OPTIONAL membership — never your home tenant
--     (users.tenant_id) and never a personal wallet. Leaving your home tenant
--     is an account-level action (delete account / contact admin), not a
--     "disconnect from an employer you chose to connect to".
--   • Soft delete (active = false) — preserves audit and lets a re-join
--     reactivate the row. We never delete employer-held records from here;
--     the employer's HR record stays with the employer.

-- 1. List memberships, now flagging the home tenant.
-- DROP first: adding the is_home column changes the function's return type,
-- which CREATE OR REPLACE cannot do.
DROP FUNCTION IF EXISTS public.eq_cards_list_my_tenants();

CREATE OR REPLACE FUNCTION public.eq_cards_list_my_tenants()
RETURNS TABLE (
  tenant_id   uuid,
  name        text,
  slug        text,
  is_personal boolean,
  is_active   boolean,
  is_home     boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user shell_control.users%ROWTYPE;
BEGIN
  SELECT * INTO v_user FROM shell_control.users WHERE id = auth.uid();
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    t.id                                                               AS tenant_id,
    t.name,
    t.slug,
    t.is_personal,
    (t.id = COALESCE(v_user.last_active_tenant_id, v_user.tenant_id))  AS is_active,
    (t.id = v_user.tenant_id)                                          AS is_home
  FROM   shell_control.user_tenant_memberships utm
  JOIN   shell_control.tenants t ON t.id = utm.tenant_id
  WHERE  utm.user_id = auth.uid()
    AND  utm.active  = true
  ORDER  BY t.is_personal DESC, t.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.eq_cards_list_my_tenants() TO authenticated;


-- 2. Disconnect from an optional org membership.
-- Returns the tenant_id the active context now points at (the home tenant).
CREATE OR REPLACE FUNCTION public.eq_cards_revoke_org_access(p_org_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user        shell_control.users%ROWTYPE;
  v_is_personal boolean;
BEGIN
  SELECT * INTO v_user FROM shell_control.users WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Guard: never disconnect your home tenant — that's an account action.
  IF p_org_id = v_user.tenant_id THEN
    RAISE EXCEPTION 'cannot_revoke_home_tenant' USING ERRCODE = 'P0012';
  END IF;

  -- Guard: never disconnect a personal wallet.
  SELECT is_personal INTO v_is_personal
  FROM shell_control.tenants WHERE id = p_org_id;
  IF v_is_personal IS TRUE THEN
    RAISE EXCEPTION 'cannot_revoke_personal_tenant' USING ERRCODE = 'P0012';
  END IF;

  -- Guard: must actually be an active member.
  IF NOT EXISTS (
    SELECT 1 FROM shell_control.user_tenant_memberships
    WHERE user_id  = auth.uid()
      AND tenant_id = p_org_id
      AND active    = true
  ) THEN
    RAISE EXCEPTION 'not_a_member' USING ERRCODE = 'P0011';
  END IF;

  -- Soft-deactivate the membership.
  UPDATE shell_control.user_tenant_memberships
  SET    active = false
  WHERE  user_id  = auth.uid()
    AND  tenant_id = p_org_id;

  -- If the revoked org was the active context, fall back to the home tenant.
  IF v_user.last_active_tenant_id = p_org_id THEN
    UPDATE shell_control.users
    SET    last_active_tenant_id = v_user.tenant_id
    WHERE  id = auth.uid();
  END IF;

  RETURN v_user.tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.eq_cards_revoke_org_access(uuid) TO authenticated;
