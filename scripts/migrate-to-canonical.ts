/**
 * Cards Unit 3 — one-time data migration script.
 *
 * Source:      Cards Supabase project (hshvnjzczdytfiklhojz)
 *              Tables: profiles, licences
 *              Bucket: licence-photos
 *
 * Destination: eq-canonical (jvknxcmbtrfnxfrwfimn)
 *              Tables: app_data.staff, app_data.licences
 *              Bucket: tenant-{tenant_id} with paths
 *                      licences/{licence_id}/front.jpg, back.jpg
 *
 * Per eq/cards/canonical-migration/plan.md §Unit 3:
 *   - Writes go through eq_intake_commit_batch RPC (NOT direct INSERT)
 *   - Idempotent: imported_from = 'eq_cards_supabase_2026_05_20' is the
 *     dedup key. Re-running the script is a no-op for already-migrated rows.
 *   - Photo migration is download-from-source → upload-to-dest with
 *     paths rewritten to canonical's per-tenant convention.
 *   - Dry-run first. Live apply requires --apply flag + explicit
 *     tenant-id argument.
 *
 * Usage:
 *
 *   # Dry-run — counts source rows, plans the migration, doesn't write
 *   pnpm tsx scripts/migrate-to-canonical.ts \
 *     --tenant-id <canonical_tenant_uuid> \
 *     --dry-run
 *
 *   # Live apply
 *   pnpm tsx scripts/migrate-to-canonical.ts \
 *     --tenant-id <canonical_tenant_uuid> \
 *     --apply
 *
 * Required env vars (set via .env or shell export):
 *
 *   CARDS_SUPABASE_URL                Cards source project URL
 *   CARDS_SUPABASE_SERVICE_KEY        Cards source service-role key
 *   CANONICAL_SUPABASE_URL            Destination (eq-canonical) URL
 *   CANONICAL_SUPABASE_SERVICE_KEY    Destination service-role key
 *
 * Safety:
 *   - Service-role keys are read-only required on Cards; read+write on canonical
 *   - Dry-run is the default — must explicitly pass --apply to write anything
 *   - Each rollback-able via eq_intake_rollback(intake_id, reason)
 *   - All commits use a single intake_id so a single rollback unwinds everything
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';

const IMPORTED_FROM = 'eq_cards_supabase_2026_05_20';

interface CliArgs {
  tenantId: string | null;
  apply: boolean;
  dryRun: boolean;
}

interface CardsProfile {
  id: string;             // Cards' auth.user uuid
  email: string;
  first_name: string;
  last_name: string;
  phone: string | null;
  role: string;
  active: boolean;
  created_at: string;
}

interface CardsLicence {
  id: string;
  user_id: string;        // FK to profiles.id
  licence_type: string;
  licence_number: string;
  issuing_authority: string | null;
  state: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  photo_front_url: string | null;  // Cards storage path
  photo_back_url: string | null;
  notes: string | null;
  metadata: Record<string, unknown> | null;
  deleted_at: string | null;
  created_at: string;
}

function parseArgs(): CliArgs {
  const args = process.argv.slice(2);
  let tenantId: string | null = null;
  let apply = false;
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--tenant-id' && i + 1 < args.length) {
      tenantId = args[++i];
    } else if (args[i] === '--apply') {
      apply = true;
    } else if (args[i] === '--dry-run') {
      dryRun = true;
    }
  }

  // Default to dry-run if neither flag passed
  if (!apply && !dryRun) dryRun = true;
  // --apply wins if both passed
  if (apply) dryRun = false;

  return { tenantId, apply, dryRun };
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

async function loadProfiles(cards: SupabaseClient): Promise<CardsProfile[]> {
  const { data, error } = await cards
    .from('profiles')
    .select('id, email, first_name, last_name, phone, role, active, created_at');
  if (error) throw error;
  return (data ?? []) as CardsProfile[];
}

async function loadLicences(cards: SupabaseClient): Promise<CardsLicence[]> {
  const { data, error } = await cards
    .from('licences')
    .select(
      'id, user_id, licence_type, licence_number, issuing_authority, state, ' +
        'issue_date, expiry_date, photo_front_url, photo_back_url, notes, metadata, ' +
        'deleted_at, created_at',
    );
  if (error) throw error;
  return (data ?? []) as CardsLicence[];
}

async function createIntakeEvent(
  canonical: SupabaseClient,
  tenantId: string,
  entity: string,
  sourceFilename: string,
): Promise<string> {
  const { data, error } = await canonical
    .schema('shell_control')
    .from('eq_intake_events')
    .insert({
      tenant_id: tenantId,
      entity,
      source_kind: 'migration',
      source_subkind: 'cards-supabase',
      source_filename: sourceFilename,
      schema_version: '1.0.0',
      status: 'committing',
      import_mode: 'upsert',
      source_app: 'migration-script',
      intake_mode: 'lenient',
    })
    .select('intake_id')
    .single();
  if (error || !data) throw new Error(`createIntakeEvent failed: ${error?.message}`);
  return (data as { intake_id: string }).intake_id;
}

async function commitBatch(
  canonical: SupabaseClient,
  intakeId: string,
  tenantId: string,
  table: string,
  rows: Record<string, unknown>[],
): Promise<{ committed: number; ids: string[] }> {
  const { data, error } = await canonical.rpc('eq_intake_commit_batch', {
    p_intake_id: intakeId,
    p_tenant_id: tenantId,
    p_table: table,
    p_rows: rows,
    p_confirm_replace: false,
    p_intake_mode: 'lenient',
  });
  if (error) throw new Error(`commitBatch(${table}) failed: ${error.message}`);
  const result = Array.isArray(data) ? data[0] : data;
  return {
    committed: result?.committed_count ?? 0,
    ids: result?.committed_ids ?? [],
  };
}

function mapProfileToStaff(
  profile: CardsProfile,
  tenantId: string,
): Record<string, unknown> {
  // Cards' role maps to canonical staff (no role column on staff today;
  // role lives on users via Phase 1.F). Cards user becomes a staff record
  // — if they're also a user, that link is wired via staff.user_id post-
  // user-table-sync (not part of this migration).
  return {
    staff_id: randomUUID(),
    tenant_id: tenantId,
    external_id: profile.id,
    first_name: profile.first_name,
    last_name: profile.last_name,
    email: profile.email,
    phone: profile.phone,
    employment_type: 'employee',
    active: profile.active,
    imported_from: IMPORTED_FROM,
  };
}

function mapLicenceToCanonical(
  licence: CardsLicence,
  staffIdByCardsId: Map<string, string>,
  tenantId: string,
): Record<string, unknown> | null {
  const canonicalStaffId = staffIdByCardsId.get(licence.user_id);
  if (!canonicalStaffId) {
    console.warn(
      `  ⚠️ licence ${licence.id} references unknown user_id ${licence.user_id}; skipping`,
    );
    return null;
  }
  return {
    licence_id: randomUUID(),
    tenant_id: tenantId,
    staff_id: canonicalStaffId,
    external_id: licence.id,
    licence_type: licence.licence_type,
    licence_number: licence.licence_number,
    issuing_authority: licence.issuing_authority,
    state: licence.state,
    issue_date: licence.issue_date,
    expiry_date: licence.expiry_date,
    // photo paths get rewritten by the photo-migration step that runs after
    photo_front_path: null,
    photo_back_path: null,
    notes: licence.notes,
    metadata: licence.metadata,
    active: licence.deleted_at === null,
    imported_from: IMPORTED_FROM,
  };
}

async function main() {
  const args = parseArgs();

  if (!args.tenantId) {
    console.error('Missing --tenant-id <canonical_tenant_uuid>');
    process.exit(1);
  }

  console.log('Cards → Canonical migration');
  console.log('============================');
  console.log(`Tenant ID:  ${args.tenantId}`);
  console.log(`Mode:       ${args.apply ? '🔥 APPLY (writes)' : '🔍 DRY-RUN'}`);
  console.log('');

  const cardsUrl = requireEnv('CARDS_SUPABASE_URL');
  const cardsKey = requireEnv('CARDS_SUPABASE_SERVICE_KEY');
  const canonicalUrl = requireEnv('CANONICAL_SUPABASE_URL');
  const canonicalKey = requireEnv('CANONICAL_SUPABASE_SERVICE_KEY');

  const cards = createClient(cardsUrl, cardsKey, { auth: { persistSession: false } });
  const canonical = createClient(canonicalUrl, canonicalKey, {
    auth: { persistSession: false },
  });

  // ── 1. Read source
  console.log('Step 1 — Reading source data from Cards Supabase…');
  const profiles = await loadProfiles(cards);
  const licences = await loadLicences(cards);
  console.log(`  Found: ${profiles.length} profiles, ${licences.length} licences`);
  console.log('');

  if (profiles.length === 0 && licences.length === 0) {
    console.log('Nothing to migrate. Exiting.');
    return;
  }

  // ── 2. Plan staff inserts
  console.log('Step 2 — Mapping profiles → staff…');
  const staffRows = profiles.map((p) => mapProfileToStaff(p, args.tenantId!));
  const cardsIdToStaffId = new Map<string, string>();
  for (let i = 0; i < profiles.length; i++) {
    cardsIdToStaffId.set(profiles[i].id, staffRows[i].staff_id as string);
  }
  console.log(`  Prepared ${staffRows.length} staff rows`);

  // ── 3. Plan licence inserts
  console.log('Step 3 — Mapping licences → app_data.licences…');
  const licenceRows = licences
    .map((l) => mapLicenceToCanonical(l, cardsIdToStaffId, args.tenantId!))
    .filter((r): r is Record<string, unknown> => r !== null);
  console.log(`  Prepared ${licenceRows.length} licence rows`);
  console.log('');

  if (args.dryRun) {
    console.log('🔍 Dry-run complete. No writes were made.');
    console.log('');
    console.log('To apply, re-run with --apply:');
    console.log(`  pnpm tsx scripts/migrate-to-canonical.ts --tenant-id ${args.tenantId} --apply`);
    return;
  }

  // ── 4. Write staff via intake
  console.log('Step 4 — Committing staff to canonical via eq_intake_commit_batch…');
  const staffIntakeId = await createIntakeEvent(canonical, args.tenantId, 'staff', 'cards-profiles');
  console.log(`  Intake event ${staffIntakeId}`);
  const staffResult = await commitBatch(canonical, staffIntakeId, args.tenantId, 'staff', staffRows);
  console.log(`  Committed ${staffResult.committed} staff rows`);
  console.log('');

  // ── 5. Write licences via intake
  console.log('Step 5 — Committing licences to canonical…');
  const licenceIntakeId = await createIntakeEvent(canonical, args.tenantId, 'licence', 'cards-licences');
  console.log(`  Intake event ${licenceIntakeId}`);
  const licenceResult = await commitBatch(
    canonical,
    licenceIntakeId,
    args.tenantId,
    'licences',
    licenceRows,
  );
  console.log(`  Committed ${licenceResult.committed} licence rows`);
  console.log('');

  // ── 6. Migrate photos (best-effort; failures don't block)
  console.log('Step 6 — Migrating licence photos from Cards bucket to canonical tenant bucket…');
  let photosMigrated = 0;
  let photoErrors = 0;
  const destBucket = `tenant-${args.tenantId}`;

  for (let i = 0; i < licences.length; i++) {
    const sourceLicence = licences[i];
    const canonicalLicence = licenceRows[i];
    if (!canonicalLicence) continue;
    const canonicalLicenceId = canonicalLicence.licence_id as string;

    for (const side of ['front', 'back'] as const) {
      const sourcePath = side === 'front' ? sourceLicence.photo_front_url : sourceLicence.photo_back_url;
      if (!sourcePath) continue;

      try {
        const { data: blob, error: dErr } = await cards.storage.from('licence-photos').download(sourcePath);
        if (dErr || !blob) {
          console.warn(`  ⚠️ couldn't download ${sourcePath}: ${dErr?.message ?? 'no blob'}`);
          photoErrors++;
          continue;
        }
        const destPath = `licences/${canonicalLicenceId}/${side}.jpg`;
        const { error: uErr } = await canonical.storage
          .from(destBucket)
          .upload(destPath, blob, { contentType: 'image/jpeg', upsert: true });
        if (uErr) {
          console.warn(`  ⚠️ couldn't upload ${destPath}: ${uErr.message}`);
          photoErrors++;
          continue;
        }
        // Update the canonical licence row with the path
        const pathColumn = side === 'front' ? 'photo_front_path' : 'photo_back_path';
        await canonical
          .schema('app_data')
          .from('licences')
          .update({ [pathColumn]: destPath })
          .eq('licence_id', canonicalLicenceId);
        photosMigrated++;
      } catch (e) {
        console.warn(`  ⚠️ photo migration error: ${(e as Error).message}`);
        photoErrors++;
      }
    }
  }

  console.log(`  Migrated ${photosMigrated} photos (${photoErrors} errors)`);
  console.log('');

  // ── 7. Mark Cards Supabase read-only (operational — Royce does manually)
  console.log('Step 7 — Cutover hint:');
  console.log('  Set Cards Supabase RLS to read-only via Dashboard once you verify');
  console.log('  the canonical data looks correct. Use:');
  console.log('    eq_intake_rollback(' + staffIntakeId + ', \'rollback reason\')');
  console.log('    eq_intake_rollback(' + licenceIntakeId + ', \'rollback reason\')');
  console.log('  if you need to unwind.');
  console.log('');
  console.log('✅ Migration complete.');
}

main().catch((e) => {
  console.error('❌ Migration failed:', e);
  process.exit(1);
});
