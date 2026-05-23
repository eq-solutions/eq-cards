// Supabase Edge Function: share-licence
//
// Public endpoint — no JWT required. Returns the non-sensitive public fields
// of a licence so a third party can verify a tradie's card by scanning a QR
// code. Licence IDs are UUIDs (128-bit random) so enumeration is infeasible.
//
// Secrets:
//   SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase.
//   Service role bypasses RLS so we can read any non-deleted licence.
//
// Request:
//   GET /functions/v1/share-licence?licence_id={uuid}
//
// Response (200):
//   {
//     "licence_type": string,
//     "licence_number": string,
//     "state": string | null,
//     "issuing_authority": string | null,
//     "expiry_date": string,      // YYYY-MM-DD
//     "holder_name": string | null
//   }

const CORS_HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'content-type',
  'access-control-allow-methods': 'GET, OPTIONS',
} as const;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...CORS_HEADERS,
    },
  });
}

const REST_HEADERS = (key: string) => ({
  'apikey': key,
  'Authorization': `Bearer ${key}`,
  'Accept': 'application/json',
});

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'GET') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  const url = new URL(req.url);
  const licenceId = url.searchParams.get('licence_id');
  if (!licenceId) {
    return jsonResponse({ error: 'licence_id_required' }, 400);
  }
  if (!UUID_RE.test(licenceId)) {
    return jsonResponse({ error: 'invalid_licence_id' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'supabase_env_missing' }, 500);
  }

  const headers = REST_HEADERS(serviceRoleKey);

  // Query 1 — licence row. licences.user_id has no direct FK to profiles
  // (both reference auth.users), so embedded resource join isn't available;
  // two separate queries is the clean path.
  const licenceResp = await fetch(
    `${supabaseUrl}/rest/v1/licences` +
      `?id=eq.${licenceId}&deleted_at=is.null` +
      `&select=licence_type,licence_number,state,issuing_authority,expiry_date,user_id` +
      `&limit=1`,
    { headers },
  );
  if (!licenceResp.ok) {
    const text = await licenceResp.text().catch(() => '');
    console.error('supabase_licence_error', { status: licenceResp.status, body: text });
    return jsonResponse({ error: 'database_error' }, 502);
  }
  const licenceRows = (await licenceResp.json()) as Array<{
    licence_type: string;
    licence_number: string;
    state: string | null;
    issuing_authority: string | null;
    expiry_date: string;
    user_id: string;
  }>;

  if (!licenceRows.length) {
    return jsonResponse({ error: 'licence_not_found' }, 404);
  }
  const licence = licenceRows[0];

  // Query 2 — holder's display name from profiles.
  const profileResp = await fetch(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${licence.user_id}&select=full_name&limit=1`,
    { headers },
  );
  let holderName: string | null = null;
  if (profileResp.ok) {
    const profileRows = (await profileResp.json()) as Array<{ full_name: string | null }>;
    holderName = profileRows[0]?.full_name ?? null;
  }

  return jsonResponse({
    licence_type: licence.licence_type,
    licence_number: licence.licence_number,
    state: licence.state,
    issuing_authority: licence.issuing_authority,
    expiry_date: licence.expiry_date,
    holder_name: holderName,
  });
});
