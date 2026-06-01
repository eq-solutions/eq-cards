-- eq_cards_preview_invite: unauthenticated preview of a pending invite token.
-- Returns org name, worker name, credential count, and expiry so the claim
-- screen can show context before the worker signs in and consents.
-- SECURITY DEFINER: token possession is the authorization — no auth.uid() needed.
CREATE OR REPLACE FUNCTION public.eq_cards_preview_invite(p_token uuid)
RETURNS TABLE(
  org_name         text,
  worker_name      text,
  credential_count int,
  expires_at       timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    o.name,
    COALESCE(
      w.preferred_name,
      w.first_name || ' ' || w.last_name,
      wi.profile_data->>'first_name'
    ),
    COUNT(wc.id)::int,
    wi.expires_at
  FROM worker_invites wi
  LEFT JOIN organisations o  ON o.id = wi.org_id
  LEFT JOIN workers      w  ON w.id  = wi.worker_id
  LEFT JOIN worker_credentials wc
         ON wc.worker_id = w.id AND wc.deleted_at IS NULL
  WHERE wi.token       = p_token
    AND wi.claimed_at  IS NULL
    AND wi.expires_at  > now()
  GROUP BY
    o.name,
    w.preferred_name,
    w.first_name,
    w.last_name,
    wi.profile_data,
    wi.expires_at;
$$;
