-- 0044_notify_connection_request
--
-- AFTER INSERT trigger on org_access_requests that fires a pg_net HTTP POST to
-- the notify-connection-request edge function. Follows the same vault-backed
-- x-webhook-secret pattern as workers-canonical-sync.
--
-- Direction is inferred from the row:
--   worker_user_id = requested_by → worker self-applied via eq_cards_submit_access_request
--   otherwise                      → employer sent request via eq_cards_request_worker_access

-- 1. Webhook secret (same vault pattern as WORKERS_WEBHOOK_SECRET).
--    vault.create_secret() is required — direct INSERT INTO vault.secrets is
--    blocked for migration roles (pgsodium crypto permission denied).
SELECT vault.create_secret(
  gen_random_uuid()::text,
  'CONNECTION_NOTIFY_WEBHOOK_SECRET',
  'Webhook auth secret for notify-connection-request Edge Function'
)
WHERE NOT EXISTS (
  SELECT 1 FROM vault.secrets WHERE name = 'CONNECTION_NOTIFY_WEBHOOK_SECRET'
);

-- 2. Helper RPC: returns one row per email recipient. Admin lookup uses
--    public.org_memberships (role text='admin') — shell_control.user_tenant_memberships
--    uses eq_role enum which has no 'admin' value.
CREATE OR REPLACE FUNCTION public.eq_notify_connection_request_targets(
  p_request_id uuid
)
RETURNS TABLE (
  direction     text,
  org_name      text,
  sharing_scope text,
  worker_name   text,
  to_email      text,
  to_name       text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_req         public.org_access_requests;
  v_org_name    text;
  v_direction   text;
  v_worker_name text;
BEGIN
  SELECT * INTO v_req FROM public.org_access_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT o.name INTO v_org_name
  FROM public.organisations o WHERE o.id = v_req.org_id;

  v_direction := CASE
    WHEN v_req.worker_user_id IS NOT NULL
      AND v_req.worker_user_id = v_req.requested_by
    THEN 'worker'
    ELSE 'employer'
  END;

  IF v_direction = 'worker' THEN
    -- Worker applied — notify org admins via org_memberships (role is text 'admin')
    SELECT full_name INTO v_worker_name
    FROM public.profiles WHERE id = v_req.worker_user_id;

    RETURN QUERY
    SELECT
      v_direction,
      v_org_name,
      v_req.sharing_scope,
      COALESCE(v_worker_name, 'A worker'),
      p.email,
      p.full_name
    FROM public.org_memberships om
    JOIN public.profiles p ON p.id = om.user_id
    WHERE om.org_id = v_req.org_id
      AND om.role = 'admin'
      AND om.status = 'active'
      AND p.email IS NOT NULL;

  ELSE
    -- Employer sent request — notify the worker (only if registered + has email)
    IF v_req.worker_user_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
      v_direction,
      v_org_name,
      v_req.sharing_scope,
      COALESCE(p.full_name, ''),
      p.email,
      p.full_name
    FROM public.profiles p
    WHERE p.id = v_req.worker_user_id
      AND p.email IS NOT NULL;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.eq_notify_connection_request_targets(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eq_notify_connection_request_targets(uuid) TO service_role;

-- 3. Trigger function (vault-backed secret, same pattern as sync_worker_to_canonical)
CREATE OR REPLACE FUNCTION public.notify_connection_request()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'vault', 'public'
AS $$
DECLARE
  _secret    text;
  _direction text;
BEGIN
  SELECT decrypted_secret INTO _secret
  FROM vault.decrypted_secrets
  WHERE name = 'CONNECTION_NOTIFY_WEBHOOK_SECRET'
  LIMIT 1;

  IF _secret IS NULL THEN
    RAISE WARNING 'notify-connection-request: CONNECTION_NOTIFY_WEBHOOK_SECRET not in vault';
    RETURN NEW;
  END IF;

  _direction := CASE
    WHEN NEW.worker_user_id IS NOT NULL AND NEW.worker_user_id = NEW.requested_by
    THEN 'worker'
    ELSE 'employer'
  END;

  PERFORM net.http_post(
    url                  := 'https://jvknxcmbtrfnxfrwfimn.supabase.co/functions/v1/notify-connection-request',
    body                 := jsonb_build_object(
                              'request_id',     NEW.id,
                              'direction',      _direction
                            ),
    headers              := jsonb_build_object(
                              'Content-Type',     'application/json',
                              'x-webhook-secret', _secret
                            ),
    timeout_milliseconds := 10000
  );

  RETURN NEW;
END;
$$;

-- 4. AFTER INSERT trigger (non-transactional — pg_net is async)
DROP TRIGGER IF EXISTS tg_notify_connection_request ON public.org_access_requests;
CREATE TRIGGER tg_notify_connection_request
  AFTER INSERT ON public.org_access_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_connection_request();
