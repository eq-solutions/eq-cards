-- 0029_workspace_context_switching.sql
--
-- Phase 2a: workspace connection management.
-- Workers can list their tenant memberships and switch active context.
-- The hook (updated in 0028) reads last_active_tenant_id, so switching
-- only requires updating that column + calling refreshSession() in Flutter.
--
-- Functions:
--   eq_cards_list_my_tenants()           — all active memberships for the caller
--   eq_cards_set_active_tenant(uuid)     — switch last_active_tenant_id + return it

-- List all active tenant memberships for the calling user.
-- Returns personal wallet first, then orgs alphabetically.
-- is_active = true on whichever tenant the hook would currently inject.
CREATE OR REPLACE FUNCTION public.eq_cards_list_my_tenants()
RETURNS TABLE (
  tenant_id   uuid,
  name        text,
  slug        text,
  is_personal boolean,
  is_active   boolean
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
    t.id                                                                  AS tenant_id,
    t.name,
    t.slug,
    t.is_personal,
    (t.id = COALESCE(v_user.last_active_tenant_id, v_user.tenant_id))    AS is_active
  FROM   shell_control.user_tenant_memberships utm
  JOIN   shell_control.tenants t ON t.id = utm.tenant_id
  WHERE  utm.user_id = auth.uid()
    AND  utm.active  = true
  ORDER  BY t.is_personal DESC, t.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.eq_cards_list_my_tenants() TO authenticated;


-- Switch the caller's active tenant context.
-- Validates membership, updates last_active_tenant_id.
-- Flutter calls refreshSession() after this so the hook injects the new
-- tenant_id into the JWT and the router re-evaluates.
CREATE OR REPLACE FUNCTION public.eq_cards_set_active_tenant(p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: caller must be an active member of the target tenant.
  IF NOT EXISTS (
    SELECT 1 FROM shell_control.user_tenant_memberships
    WHERE user_id  = auth.uid()
      AND tenant_id = p_tenant_id
      AND active    = true
  ) THEN
    RAISE EXCEPTION 'tenant_not_found_or_not_member' USING ERRCODE = 'P0011';
  END IF;

  UPDATE shell_control.users
  SET    last_active_tenant_id = p_tenant_id
  WHERE  id = auth.uid();

  RETURN p_tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.eq_cards_set_active_tenant(uuid) TO authenticated;
