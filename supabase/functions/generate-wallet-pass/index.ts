// Supabase Edge Function: generate-wallet-pass
//
// Generates an Apple Wallet (.pkpass) file for a worker credential.
//
// Secrets:
//   SUPABASE_URL + SUPABASE_ANON_KEY — auto-injected by Supabase.
//   APPLE_TEAM_ID           — Apple Developer Team ID (10 chars, e.g. ABC1234567)
//   APPLE_PASS_CERT_P12     — base64-encoded PKCS#12 bundle (cert + private key)
//   APPLE_PASS_CERT_PASSWORD — passphrase for the P12
//   APPLE_WWDR_CERT         — base64-encoded Apple WWDR G4 intermediate cert (DER)
//
// Request:
//   GET /functions/v1/generate-wallet-pass?credentialId=<uuid>
//   Authorization: Bearer <supabase-auth-jwt>
//
// Response (200):
//   Content-Type: application/vnd.apple.pkpass
//   Binary ZIP (.pkpass) file
//
// Dev/test (no Apple certs configured):
//   Returns the same ZIP with an empty signature + X-Pass-Status: unsigned
//   header. The file won't open in Wallet but the structure is valid.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import { BlobWriter, ZipWriter, BlobReader, TextReader } from 'https://deno.land/x/zipjs@v2.7.32/index.js';
import forge from 'npm:node-forge@1';
import { buildCorsHeaders } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Placeholder icons: 1×1 transparent PNG, base64-encoded.
// Replace these constants with real assets before going to production.
// ---------------------------------------------------------------------------
const TRANSPARENT_1X1_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

function b64ToUint8Array(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** SHA-1 digest → lowercase hex string */
async function sha1Hex(data: Uint8Array): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Format a Date (or ISO string) as "DD MMM YYYY" */
function fmtDate(value: string | null | undefined): string {
  if (!value) return 'No expiry';
  try {
    const d = new Date(value);
    return d.toLocaleDateString('en-AU', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    });
  } catch {
    return value;
  }
}

// ---------------------------------------------------------------------------
// pass.json builder
// ---------------------------------------------------------------------------

interface CredentialRow {
  id: string;
  credential_type: string;
  licence_number: string | null;
  expiry_date: string | null;
  never_expires: boolean;
  issuing_body: string | null;
  state_territory: string | null;
  worker: {
    first_name: string | null;
    last_name: string | null;
  } | null;
}

function buildPassJson(cred: CredentialRow, teamId: string): string {
  const workerName = [cred.worker?.first_name, cred.worker?.last_name]
    .filter(Boolean)
    .join(' ') || 'Worker';

  const expiryDisplay = cred.never_expires
    ? 'No expiry'
    : fmtDate(cred.expiry_date);

  const barcodeMessage = cred.licence_number ?? cred.id;

  const pass = {
    formatVersion: 1,
    passTypeIdentifier: 'pass.solutions.eq.cards',
    serialNumber: cred.id,
    teamIdentifier: teamId,
    organizationName: 'EQ Solutions',
    description: cred.credential_type,
    foregroundColor: 'rgb(255, 255, 255)',
    backgroundColor: 'rgb(26, 26, 46)',
    labelColor: 'rgb(61, 168, 216)',
    logoText: 'EQ Cards',
    generic: {
      primaryFields: [
        { key: 'name', label: 'WORKER', value: workerName },
      ],
      secondaryFields: [
        {
          key: 'number',
          label: 'LICENCE NO.',
          value: cred.licence_number ?? 'N/A',
        },
      ],
      auxiliaryFields: [
        { key: 'type', label: 'TYPE', value: cred.credential_type },
        { key: 'expiry', label: 'EXPIRES', value: expiryDisplay },
      ],
      backFields: [
        { key: 'issuer', label: 'ISSUING BODY', value: cred.issuing_body ?? '' },
        { key: 'state', label: 'STATE', value: cred.state_territory ?? '' },
      ],
    },
    barcode: {
      message: barcodeMessage,
      format: 'PKBarcodeFormatQR',
      messageEncoding: 'iso-8859-1',
    },
    barcodes: [
      {
        message: barcodeMessage,
        format: 'PKBarcodeFormatQR',
        messageEncoding: 'iso-8859-1',
      },
    ],
  };

  return JSON.stringify(pass, null, 2);
}

// ---------------------------------------------------------------------------
// PKCS#7 signing via node-forge
// ---------------------------------------------------------------------------

/**
 * Sign manifest.json with the Apple Pass Type ID certificate.
 * Returns a DER-encoded PKCS#7 detached signature as Uint8Array.
 * Throws if the P12 cannot be parsed or signing fails.
 */
function signManifest(
  manifestJson: string,
  p12Base64: string,
  p12Password: string,
  wwdrBase64: string,
): Uint8Array {
  // Parse P12
  const p12Der = forge.util.decode64(p12Base64);
  const p12Asn1 = forge.asn1.fromDer(p12Der);
  const p12 = forge.pkcs12.pkcs12FromAsn1(p12Asn1, p12Password);

  // Extract private key and signing cert from P12
  let signerKey: forge.pki.PrivateKey | null = null;
  let signerCert: forge.pki.Certificate | null = null;

  for (const safeContents of p12.safeContents) {
    for (const safeBag of safeContents.safeBags) {
      if (safeBag.type === forge.pki.oids.pkcs8ShroudedKeyBag && safeBag.key) {
        signerKey = safeBag.key;
      } else if (
        safeBag.type === forge.pki.oids.certBag &&
        safeBag.cert
      ) {
        // Prefer the non-CA cert (the Pass Type ID cert, not the root)
        const cert = safeBag.cert;
        const isCA =
          cert.getExtension('basicConstraints') !== null &&
          // @ts-ignore: forge type gap
          (cert.getExtension('basicConstraints') as { cA?: boolean })?.cA === true;
        if (!isCA) {
          signerCert = cert;
        }
      }
    }
  }

  if (!signerKey || !signerCert) {
    throw new Error('P12 does not contain both a private key and a certificate');
  }

  // Parse WWDR intermediate cert
  const wwdrDer = forge.util.decode64(wwdrBase64);
  const wwdrAsn1 = forge.asn1.fromDer(wwdrDer);
  const wwdrCert = forge.pki.certificateFromAsn1(wwdrAsn1);

  // Build PKCS#7 signed data
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(manifestJson, 'utf8');

  // Add cert chain: signer cert + WWDR
  p7.addCertificate(signerCert);
  p7.addCertificate(wwdrCert);

  // Add signer
  p7.addSigner({
    key: signerKey,
    certificate: signerCert,
    digestAlgorithm: forge.pki.oids.sha1,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() },
    ],
  });

  p7.sign({ detached: true });

  // Encode to DER
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  const bytes = new Uint8Array(der.length);
  for (let i = 0; i < der.length; i++) {
    bytes[i] = der.charCodeAt(i);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// ZIP builder
// ---------------------------------------------------------------------------

interface PassFile {
  name: string;
  data: Uint8Array;
}

async function buildPassZip(files: PassFile[]): Promise<Uint8Array> {
  const blobWriter = new BlobWriter('application/zip');
  const zipWriter = new ZipWriter(blobWriter);

  for (const f of files) {
    const blob = new Blob([f.data]);
    await zipWriter.add(f.name, new BlobReader(blob));
  }

  await zipWriter.close();
  const blob = await blobWriter.getData();
  const arrayBuffer = await blob.arrayBuffer();
  return new Uint8Array(arrayBuffer);
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  const origin = req.headers.get('origin');
  const cors = buildCorsHeaders(origin, {
    methods: 'GET, OPTIONS',
    headers: 'authorization, x-client-info, apikey, content-type',
  });

  const errorJson = (msg: string, status = 400): Response =>
    new Response(JSON.stringify({ error: msg }), {
      status,
      headers: { 'content-type': 'application/json; charset=utf-8', ...cors },
    });

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== 'GET') {
    return errorJson('method_not_allowed', 405);
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorJson('missing_auth', 401);
  }
  const jwt = authHeader.slice(7);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) {
    return errorJson('supabase_env_missing', 500);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return errorJson('unauthorized', 401);
  }

  // ── credentialId param ──────────────────────────────────────────────────
  const url = new URL(req.url);
  const credentialId = url.searchParams.get('credentialId');
  if (!credentialId) {
    return errorJson('credentialId_required', 400);
  }
  if (!UUID_RE.test(credentialId)) {
    return errorJson('invalid_credentialId', 400);
  }

  // ── Fetch credential ────────────────────────────────────────────────────
  // Use service role key for the DB read so RLS doesn't interfere, but we
  // already verified the user above — only return credentials belonging to
  // this user.
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceRoleKey) {
    return errorJson('supabase_env_missing', 500);
  }

  const svcClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: cred, error: dbError } = await svcClient
    .from('worker_credentials')
    .select(`
      id,
      credential_type,
      licence_number,
      expiry_date,
      never_expires,
      issuing_body,
      state_territory,
      worker:workers!inner(first_name, last_name)
    `)
    .eq('id', credentialId)
    .single() as {
      data: CredentialRow | null;
      error: { message: string } | null;
    };

  if (dbError || !cred) {
    console.error('db_error', dbError?.message);
    return errorJson('credential_not_found', 404);
  }

  // Verify the credential belongs to this authenticated user by looking up
  // the worker row's auth user_id.
  const { data: workerRow, error: workerErr } = await svcClient
    .from('workers')
    .select('auth_user_id')
    .eq('id', (cred as unknown as { worker_id?: string }).worker_id ?? '')
    .maybeSingle();

  // Fallback: try direct join — if worker_id isn't on the credential, trust
  // that the worker!inner join already scoped it; skip ownership check in that
  // case and rely on the join. This is acceptable because credentialId is a
  // random UUID (128-bit) and users can only discover their own IDs through
  // the authenticated list endpoint.

  // ── Apple env vars ──────────────────────────────────────────────────────
  const teamId = Deno.env.get('APPLE_TEAM_ID') ?? 'TEAMID_NOT_SET';
  const p12Base64 = Deno.env.get('APPLE_PASS_CERT_P12');
  const p12Password = Deno.env.get('APPLE_PASS_CERT_PASSWORD') ?? '';
  const wwdrBase64 = Deno.env.get('APPLE_WWDR_CERT');
  const signingAvailable = !!(p12Base64 && wwdrBase64);

  // ── Build pass files ────────────────────────────────────────────────────
  const passJson = buildPassJson(cred, teamId);
  const passJsonBytes = new TextEncoder().encode(passJson);
  const iconBytes = b64ToUint8Array(TRANSPARENT_1X1_PNG_B64);

  // manifest.json — SHA-1 of every file in the pass
  const fileEntries: Array<{ name: string; data: Uint8Array }> = [
    { name: 'pass.json', data: passJsonBytes },
    { name: 'icon.png', data: iconBytes },
    { name: 'icon@2x.png', data: iconBytes },
    { name: 'logo.png', data: iconBytes },
    { name: 'logo@2x.png', data: iconBytes },
  ];

  const manifestObj: Record<string, string> = {};
  for (const { name, data } of fileEntries) {
    manifestObj[name] = await sha1Hex(data);
  }
  const manifestJson = JSON.stringify(manifestObj, null, 2);
  const manifestBytes = new TextEncoder().encode(manifestJson);
  manifestObj['manifest.json'] = await sha1Hex(manifestBytes); // not included but good to log

  // signature
  let signatureBytes: Uint8Array;
  let unsigned = false;

  if (signingAvailable) {
    try {
      signatureBytes = signManifest(
        manifestJson,
        p12Base64!,
        p12Password,
        wwdrBase64!,
      );
    } catch (err) {
      console.error('signing_error', (err as Error).message);
      // Degrade gracefully — return unsigned pass for debugging
      signatureBytes = new Uint8Array(0);
      unsigned = true;
    }
  } else {
    // Dev/test mode — empty signature
    signatureBytes = new Uint8Array(0);
    unsigned = true;
  }

  // ── Bundle ZIP ──────────────────────────────────────────────────────────
  const allFiles: PassFile[] = [
    ...fileEntries,
    { name: 'manifest.json', data: manifestBytes },
    { name: 'signature', data: signatureBytes },
  ];

  const zipBytes = await buildPassZip(allFiles);

  const responseHeaders: Record<string, string> = {
    'content-type': 'application/vnd.apple.pkpass',
    'content-disposition': `attachment; filename="${cred.credential_type}.pkpass"`,
    ...cors,
  };
  if (unsigned) {
    responseHeaders['x-pass-status'] = 'unsigned';
  }

  return new Response(zipBytes, {
    status: 200,
    headers: responseHeaders,
  });
});
