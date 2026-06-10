-- 0023_lookup_invite_strip_spaces.sql
-- Extend phone normalisation in eq_cards_lookup_invite_by_phone to strip
-- internal whitespace before the prefix comparison. Fixes stored values like
-- "+61 482 976 483" that are otherwise valid but fail the 9-digit suffix match.
-- Also cleans the specific Sam Powell record in worker_invites.profile_data.

CREATE OR REPLACE FUNCTION eq_cards_lookup_invite_by_phone(
  p_phone  text,
  p_slug   text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id  uuid;
  v_token   uuid;
  -- Strip ALL whitespace first, then strip AU prefix to get 9-digit suffix.
  v_suffix  text := regexp_replace(
                      regexp_replace(p_phone, '\s', '', 'g'),
                      '^(\+61|61|0)', ''
                    );
BEGIN
  SELECT id INTO v_org_id
  FROM   public.tenants
  WHERE  slug   = lower(trim(p_slug))
    AND  status = 'active'
  LIMIT  1;

  IF v_org_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT wi.token INTO v_token
  FROM   public.worker_invites wi
  LEFT JOIN public.workers w ON w.id = wi.worker_id
  WHERE  wi.org_id    = v_org_id
    AND  wi.claimed_at IS NULL
    AND  wi.expires_at > now()
    AND (
      -- Strip spaces from stored values too before comparing
      regexp_replace(regexp_replace(coalesce(w.phone,                    ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(regexp_replace(coalesce(wi.profile_data->>'mobile', ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
      OR
      regexp_replace(regexp_replace(coalesce(wi.profile_data->>'phone',  ''), '\s', '', 'g'), '^(\+61|61|0)', '') = v_suffix
    )
  ORDER  BY wi.created_at DESC
  LIMIT  1;

  RETURN v_token;
END;
$$;

REVOKE ALL  ON FUNCTION eq_cards_lookup_invite_by_phone(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eq_cards_lookup_invite_by_phone(text, text) TO anon, authenticated;

-- Clean Sam Powell's stored mobile in profile_data while we're here.
UPDATE public.worker_invites
SET    profile_data = jsonb_set(
         profile_data,
         '{mobile}',
         to_jsonb(regexp_replace(profile_data->>'mobile', '\s', '', 'g'))
       )
WHERE  profile_data->>'mobile' ~ '\s'
  AND  org_id IN (
         SELECT o.id FROM public.organisations o
         JOIN   shell_control.tenants t ON t.id = o.tenant_id
         WHERE  t.slug = 'sks'
       );
