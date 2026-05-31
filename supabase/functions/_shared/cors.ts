// Shared CORS policy for EQ Cards Supabase Edge Functions.
//
// First-party browser callers only. Production is https://cards.eq.solutions;
// localhost and Netlify deploy-previews are allow-listed so `flutter run -d
// chrome` and preview builds can still reach the functions during development.
// Native iOS/Android builds send no Origin header and are unaffected (CORS is
// a browser concept).
//
// The allow-origin value is echoed from the request Origin when it matches the
// allow-list, so `Vary: Origin` is always set — without it a shared/CDN cache
// could serve one origin's allow-origin header to a request from another.

const ALLOWED_ORIGIN_EXACT = new Set<string>([
  'https://cards.eq.solutions',
  'https://core.eq.solutions', // EQ Shell iframe embedding
]);

const ALLOWED_ORIGIN_PATTERNS: RegExp[] = [
  // Netlify deploy previews for the eq-cards site.
  /^https:\/\/deploy-preview-\d+--eq-cards\.netlify\.app$/,
  // Local web development (`flutter run -d chrome` picks a random port).
  /^http:\/\/localhost:\d+$/,
  /^http:\/\/127\.0\.0\.1:\d+$/,
];

export function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return false;
  return (
    ALLOWED_ORIGIN_EXACT.has(origin) ||
    ALLOWED_ORIGIN_PATTERNS.some((re) => re.test(origin))
  );
}

/**
 * Builds CORS response headers for [origin]. When the origin is not
 * allow-listed, `access-control-allow-origin` is omitted entirely so the
 * browser blocks the response (fail-closed). `methods` is the value for
 * `access-control-allow-methods`; `headers` overrides the default
 * allow-headers list.
 */
export function buildCorsHeaders(
  origin: string | null,
  opts: { methods: string; headers?: string },
): Record<string, string> {
  const headers: Record<string, string> = {
    'access-control-allow-methods': opts.methods,
    'access-control-allow-headers':
      opts.headers ?? 'authorization, x-client-info, apikey, content-type',
    'vary': 'Origin',
  };
  if (isAllowedOrigin(origin)) {
    headers['access-control-allow-origin'] = origin as string;
  }
  return headers;
}
