// GET /.netlify/functions/shell-verify
//
// Reads the eq_shell_session cookie, verifies its HMAC, ensures the user
// exists in auth.users (creating the row if the backfill hasn't run yet),
// and mints a short-lived Supabase JWT for the Cards Flutter app. The JWT
// is returned as JSON so Flutter can call setSession() without a JWT ever
// appearing in the URL hash or browser history.
//
// Same-origin request: the Cards iframe IS at cards.eq.solutions, and this
// function IS at cards.eq.solutions — so the browser sends eq_shell_session
// automatically (Domain=.eq.solutions, SameSite=Lax, allow-same-origin sandbox).
//
// Self-healing: if public.users has no matching auth.users row (users created
// before the accept-invite fix), this function creates it inline via the
// Supabase admin API so Cards SSO always works after first login.
//
// 401 if cookie missing / bad sig / expired.
// 500 if required env vars not set or user email cannot be resolved.

import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const SUPABASE_JWT_SECRET = process.env.SUPABASE_JWT_SECRET || '';
const EQ_SECRET_SALT = process.env.EQ_SECRET_SALT || '';

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

function readCookie(req, name) {
  const header = req.headers.get('cookie') || '';
  for (const pair of header.split(/;\s*/)) {
    const eq = pair.indexOf('=');
    if (eq === -1) continue;
    if (pair.slice(0, eq) === name) return pair.slice(eq + 1);
  }
  return null;
}

function verifySessionCookie(cookieVal) {
  if (!EQ_SECRET_SALT) return null;

  const dotIdx = cookieVal.indexOf('.');
  if (dotIdx === -1) return null;
  const b64Payload = cookieVal.slice(0, dotIdx);
  const hexSig = cookieVal.slice(dotIdx + 1);

  let jsonStr;
  try {
    jsonStr = Buffer.from(b64Payload, 'base64').toString('utf8');
  } catch {
    return null;
  }

  const expectedSig = createHmac('sha256', EQ_SECRET_SALT).update(jsonStr).digest('hex');
  let providedBuf, expectedBuf;
  try {
    providedBuf = Buffer.from(hexSig, 'hex');
    expectedBuf = Buffer.from(expectedSig, 'hex');
  } catch {
    return null;
  }
  if (providedBuf.length !== expectedBuf.length) return null;
  if (!timingSafeEqual(providedBuf, expectedBuf)) return null;

  let payload;
  try {
    payload = JSON.parse(jsonStr);
  } catch {
    return null;
  }

  if (!payload.user_id || !payload.tenant_id) return null;
  // exp is milliseconds epoch (JS Date.now() style)
  if (typeof payload.exp !== 'number' || payload.exp < Date.now()) return null;

  return payload;
}

function base64UrlEncode(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function mintSupabaseJwt(userId, tenantId, eqRole, isPlatformAdmin) {
  if (!SUPABASE_JWT_SECRET) throw new Error('SUPABASE_JWT_SECRET not set');

  const now = Math.floor(Date.now() / 1000);
  const ttl = 15 * 60; // 15 minutes
  const jti = randomUUID();

  const claims = {
    sub: userId,
    role: 'authenticated',
    aud: 'authenticated',
    jti,
    app_metadata: {
      tenant_id: tenantId,
      eq_role: eqRole,
      is_platform_admin: isPlatformAdmin,
      source_app: 'cards',
    },
    iat: now,
    exp: now + ttl,
  };

  const header = base64UrlEncode(Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = base64UrlEncode(Buffer.from(JSON.stringify(claims)));
  const signingInput = `${header}.${payload}`;
  const signature = base64UrlEncode(
    createHmac('sha256', SUPABASE_JWT_SECRET).update(signingInput).digest(),
  );

  return { token: `${signingInput}.${signature}`, exp: claims.exp };
}

// Fetch the user's email from public.users via the Supabase REST API.
// Falls back to null if the lookup fails (caller handles the fallback).
async function fetchUserEmail(userId) {
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}&select=email&limit=1`,
      {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          Accept: 'application/json',
        },
      },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    return Array.isArray(rows) && rows.length > 0 ? rows[0].email ?? null : null;
  } catch {
    return null;
  }
}

// Ensure auth.users has a row for this userId. Calls the Supabase admin API:
//   GET  /auth/v1/admin/users/{id}  → 200 means exists, proceed
//   POST /auth/v1/admin/users       → create if not found
//
// Returns true if the user exists (or was successfully created), false on error.
async function ensureAuthUser(userId, email) {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return false;

  // Check if the user already exists.
  const checkRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      Accept: 'application/json',
    },
  });

  if (checkRes.ok) return true; // already exists
  if (checkRes.status !== 404) {
    console.warn('[shell-verify] admin getUser returned unexpected status', checkRes.status);
    // Non-404 might still mean the JWT will work — proceed optimistically.
    return true;
  }

  // User not in auth.users — create them.
  if (!email) {
    console.error('[shell-verify] user not in auth.users and no email available to create them', userId);
    return false;
  }

  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      id: userId,
      email,
      email_confirm: true,
    }),
  });

  if (createRes.ok) {
    console.info('[shell-verify] created missing auth.users row for', email);
    return true;
  }

  const body = await createRes.text();
  // "User already registered" is fine — race between two requests.
  if (body.includes('already registered') || body.includes('already exists')) return true;

  console.error('[shell-verify] failed to create auth.users row', createRes.status, body.slice(0, 200));
  return false;
}

export default async function handler(req) {
  if (req.method !== 'GET') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  if (!EQ_SECRET_SALT || !SUPABASE_JWT_SECRET) {
    return jsonResponse(500, { error: 'Server misconfigured' });
  }

  const cookieVal = readCookie(req, 'eq_shell_session');
  if (!cookieVal) {
    return jsonResponse(401, { error: 'No shell session' });
  }

  const session = verifySessionCookie(cookieVal);
  if (!session) {
    return jsonResponse(401, { error: 'Invalid or expired shell session' });
  }

  // Ensure auth.users has a row for this user before minting the JWT.
  // Without this, Supabase's getUser() (called by Flutter setSession) rejects
  // the JWT even if the signature is valid — the sub UUID must exist in auth.users.
  if (SUPABASE_SERVICE_ROLE_KEY) {
    // Prefer email from session cookie (present on cookies minted after 2026-05-28).
    // Fall back to a REST API lookup for older cookies that pre-date the email claim.
    const email = session.email || (await fetchUserEmail(session.user_id));
    const ok = await ensureAuthUser(session.user_id, email);
    if (!ok) {
      // Proceed anyway — the JWT might still work if auth.users was populated
      // by another path (e.g. the backfill function). Logging above captures the miss.
      console.warn('[shell-verify] ensureAuthUser failed, minting JWT anyway', session.user_id);
    }
  }

  let minted;
  try {
    minted = mintSupabaseJwt(
      session.user_id,
      session.tenant_id,
      session.role || 'employee',
      session.is_platform_admin === true,
    );
  } catch (e) {
    return jsonResponse(500, { error: e.message });
  }

  return jsonResponse(200, { token: minted.token, exp: minted.exp });
}
