-- Pin search_path on eq_get_licences_expiring_within (SECURITY DEFINER hardening).
-- The function was introduced without SET search_path, leaving it vulnerable to
-- schema-search injection if a malicious schema precedes public in the path.
-- Also cleans up the redundant COALESCE on the NOT NULL is_private column.
CREATE OR REPLACE FUNCTION public.eq_get_licences_expiring_within(
  p_org_id     uuid,
  p_days_ahead int DEFAULT 30
)
RETURNS TABLE (
  licence_id        uuid,
  licence_type      text,
  licence_number    text,
  expiry_date       date,
  worker_user_id    uuid,
  worker_first_name text,
  worker_last_name  text,
  worker_email      text,
  worker_phone      text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    l.id,
    l.licence_type,
    l.licence_number,
    l.expiry_date,
    w.user_id,
    w.first_name,
    w.last_name,
    w.email,
    w.phone
  FROM public.licences l
  JOIN public.workers       w  ON w.user_id  = l.user_id
  JOIN public.org_memberships om ON om.user_id = w.user_id
                                  AND om.org_id  = p_org_id
                                  AND om.status  = 'active'
  WHERE
    l.expiry_date BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + p_days_ahead
    AND l.deleted_at IS NULL
    AND (l.never_expires IS NULL OR l.never_expires = false)
    AND l.user_id IS NOT NULL
    AND NOT l.is_private
  ORDER BY l.expiry_date, w.last_name, w.first_name;
$$;
