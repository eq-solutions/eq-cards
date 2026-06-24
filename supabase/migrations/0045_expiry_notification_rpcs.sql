-- eq_get_licences_expiring_on
-- Returns all non-deleted, non-never-expiring licences for members of
-- p_org_id whose expiry_date is exactly p_target_date.
-- Trigger: scheduler calls with CURRENT_DATE + 30, then CURRENT_DATE + 7.
-- Each licence gets at most two emails (30-day and 7-day warning).
-- SECURITY DEFINER: scheduler service-role caller needs cross-table access.
CREATE OR REPLACE FUNCTION public.eq_get_licences_expiring_on(
  p_org_id    uuid,
  p_target_date date
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
    l.expiry_date = p_target_date
    AND l.deleted_at IS NULL
    AND (l.never_expires IS NULL OR l.never_expires = false)
    AND l.user_id IS NOT NULL
  ORDER BY w.last_name, w.first_name, l.expiry_date;
$$;

-- eq_get_licences_expiring_within
-- Returns all expiring licences for an org within a date window.
-- Used for the weekly admin digest — sends a summary of everything
-- expiring in the next p_days_ahead days.
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
  ORDER BY l.expiry_date, w.last_name, w.first_name;
$$;

-- eq_get_org_admins
-- Returns workers in admin role for a given org.
-- Used by the scheduler to know where to send the digest email.
CREATE OR REPLACE FUNCTION public.eq_get_org_admins(p_org_id uuid)
RETURNS TABLE (
  user_id    uuid,
  first_name text,
  last_name  text,
  email      text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    w.user_id,
    w.first_name,
    w.last_name,
    w.email
  FROM public.org_memberships om
  JOIN public.workers w ON w.user_id = om.user_id
  WHERE
    om.org_id  = p_org_id
    AND om.role   = 'admin'
    AND om.status = 'active'
    AND w.email IS NOT NULL;
$$;
