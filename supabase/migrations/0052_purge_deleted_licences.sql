-- 0052_purge_deleted_licences.sql
-- Privacy-policy §8: permanently erase soft-deleted licence rows and their
-- associated storage photos 30 days after deletion.
--
-- PREREQUISITE: pg_cron must be enabled on eq-canonical before applying.
--   Supabase Dashboard → Database → Extensions → pg_cron (toggle on)
-- The CREATE EXTENSION line is idempotent once the extension is available.
--
-- Storage note: deleting from storage.objects removes the metadata row and
-- revokes all API access immediately. Supabase's storage-api background worker
-- queues the underlying S3 object for deletion on the next cleanup cycle.

-- ── 1. Extension ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ── 2. Purge function ────────────────────────────────────────────────────────
-- Hard-deletes licences soft-deleted >30 days ago and their storage objects.
-- The pre-existing licences_audit trigger (migration 0001) writes a
-- 'licence.deleted' entry per row to audit_log — no extra audit code needed.
--
-- Storage path conventions both handled:
--   Pre-0050:  {user_id}/{licence_id}/{file}             → licence_id at pos 2
--   Post-0050: {tenant_id}/{user_id}/{licence_id}/{file} → licence_id at pos 3
CREATE OR REPLACE FUNCTION public.eq_purge_deleted_licences()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_licence_ids     uuid[];
  v_purged_licences int := 0;
  v_purged_objects  int := 0;
BEGIN
  SELECT ARRAY_AGG(id)
  INTO   v_licence_ids
  FROM   public.licences
  WHERE  deleted_at IS NOT NULL
    AND  deleted_at < NOW() - INTERVAL '30 days';

  IF v_licence_ids IS NULL THEN
    RETURN jsonb_build_object('purged_licences', 0, 'purged_storage_objects', 0);
  END IF;

  -- Remove storage objects before the licence rows so nothing is orphaned
  DELETE FROM storage.objects
  WHERE bucket_id = 'licence-photos'
    AND (
      split_part(name, '/', 2) = ANY(v_licence_ids::text[])
      OR split_part(name, '/', 3) = ANY(v_licence_ids::text[])
    );
  GET DIAGNOSTICS v_purged_objects = ROW_COUNT;

  -- Hard-delete; licences_audit trigger logs 'licence.deleted' per row
  DELETE FROM public.licences
  WHERE id = ANY(v_licence_ids);
  GET DIAGNOSTICS v_purged_licences = ROW_COUNT;

  RETURN jsonb_build_object(
    'purged_licences',        v_purged_licences,
    'purged_storage_objects', v_purged_objects
  );
END;
$$;

-- Only the service role (or postgres scheduler) may call this
REVOKE ALL ON FUNCTION public.eq_purge_deleted_licences() FROM PUBLIC, anon, authenticated;

-- ── 3. Daily pg_cron schedule ────────────────────────────────────────────────
-- 02:17 UTC — off-peak, avoids :00/:30 to spread scheduler load
SELECT cron.schedule(
  'purge-deleted-licences',
  '17 2 * * *',
  $$SELECT public.eq_purge_deleted_licences()$$
);
