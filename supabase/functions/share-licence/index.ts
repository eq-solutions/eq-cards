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
//
// Error shapes:
//   { "error": "licence_not_found" }  — 404
//   { "error": "licence_id_required" } — 400

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

interface LicenceRow {
  licence_type: string;
  licence_number: string;
  state: string | null;
  issuing_authority: string | null;
  expiry_date: string;
  profiles: { full_name: string | null } | null;
}

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

  // Basic UUID shape check — avoids injecting arbitrary strings into the query.
  const UUID_RE =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_RE.test(licenceId)) {
    return jsonResponse({ error: 'invalid_licence_id' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'supabase_env_missing' }, 500);
  }

  // PostgREST embedded resource join: licences → profiles(full_name).
  // Service role bypasses RLS. deleted_at=is.null guards soft-deleted records.
  const apiUrl =
    `${supabaseUrl}/rest/v1/licences` +
    `?id=eq.${licenceId}` +
    `&deleted_at=is.null` +
    `&select=licence_type,licence_number,state,issuing_authority,expiry_date,profiles(full_name)` +
    `&limit=1`;

  const resp = await fetch(apiUrl, {
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': `Bearer ${serviceRoleKey}`,
      'Accept': 'application/json',
    },
  });

  if (!resp.ok) {
    const text = await resp.text().catch(() => '');
    console.error('supabase_rest_error', { status: resp.status, body: text });
    return jsonResponse({ error: 'database_error' }, 502);
  }

  const rows = (await resp.json()) as LicenceRow[];
  if (!rows.length) {
    return jsonResponse({ error: 'licence_not_found' }, 404);
  }

  const row = rows[0];
  return jsonResponse({
    licence_type: row.licence_type,
    licence_number: row.licence_number,
    state: row.state,
    issuing_authority: row.issuing_authority,
    expiry_date: row.expiry_date,
    holder_name: row.profiles?.full_name ?? null,
  });
});
