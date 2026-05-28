// GET /.netlify/functions/shell-verify
//
// Reads the eq_shell_session cookie, verifies its HMAC, and mints a
// short-lived Supabase JWT for the Cards Flutter app. The JWT is returned
// as JSON so Flutter can call setSession() without a JWT ever appearing in
// the URL hash or browser history.
//
// Same-origin request: the Cards iframe IS at cards.eq.solutions, and this
// function IS at cards.eq.solutions — so the browser sends eq_shell_session
// automatically (Domain=.eq.solutions, SameSite=Lax, allow-same-origin sandbox).
//
// 401 if cookie missing / bad sig / expired.
// 500 if EQ_SECRET_SALT or SUPABASE_JWT_SECRET not set.

import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';

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
  const secret = process.env.EQ_SECRET_SALT || '';
  if (!secret) return null;

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

  const expectedSig = createHmac('sha256', secret).update(jsonStr).digest('hex');
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
  const secret = process.env.SUPABASE_JWT_SECRET || '';
  if (!secret) throw new Error('SUPABASE_JWT_SECRET not set');

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
  const signature = base64UrlEncode(createHmac('sha256', secret).update(signingInput).digest());

  return { token: `${signingInput}.${signature}`, exp: claims.exp };
}

export default async function handler(req) {
  if (req.method !== 'GET') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  const secretSalt = process.env.EQ_SECRET_SALT || '';
  const jwtSecret = process.env.SUPABASE_JWT_SECRET || '';
  if (!secretSalt || !jwtSecret) {
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
