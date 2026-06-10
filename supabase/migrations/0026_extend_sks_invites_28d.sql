-- 0026_extend_sks_invites_28d.sql
-- Extend all unclaimed SKS worker invites that expire 2026-06-15 by 28 days
-- (new expiry: 2026-07-13). Claimed and expired invites are left untouched.

UPDATE public.worker_invites
SET    expires_at = expires_at + interval '28 days'
WHERE  org_id IN (
         SELECT o.id
         FROM   public.organisations o
         JOIN   shell_control.tenants t ON t.id = o.tenant_id
         WHERE  t.slug = 'sks'
       )
  AND  claimed_at IS NULL
  AND  expires_at::date = '2026-06-15';
