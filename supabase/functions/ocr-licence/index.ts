// Supabase Edge Function: ocr-licence
//
// Receives a base64-encoded licence photo and returns structured fields
// extracted by Anthropic's Claude Vision. This is the web path of the OCR
// pipeline — mobile uses on-device ML Kit (architecture §16 Q3, revised
// 2026-04-28: web fallback added via Claude Vision).
//
// Auth: gateway-level JWT verification is OFF (verify_jwt = false in
// config.toml under [functions.ocr-licence]) so the browser's preflight
// OPTIONS request — which carries no Authorization header — can reach this
// function and receive its CORS headers. JWT is verified manually below
// using the SUPABASE_URL + SUPABASE_ANON_KEY pair via auth.getUser().
//
// Secrets:
//   ANTHROPIC_API_KEY — Anthropic Console → API keys.
//   SUPABASE_URL + SUPABASE_ANON_KEY — auto-injected by Supabase.
//
// Request body:
//   { "image_base64": "<base64 image>", "mime_type": "image/jpeg" }
//
// Response (200):
//   {
//     "licence_number": string|null,
//     "licence_type": string|null,        // matches seeded codes when possible
//     "issuing_authority": string|null,
//     "issue_date": "YYYY-MM-DD"|null,
//     "expiry_date": "YYYY-MM-DD"|null,
//     "raw_text": string,
//     "confidence": "low"|"medium"|"high"
//   }

// deno-lint-ignore-file no-explicit-any

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_MODEL = 'claude-sonnet-4-6';

// Seeded licence type codes from migration 0002_seed_licence_types.sql.
// Claude is asked to pick from this list when it recognises the document.
const LICENCE_TYPES = [
  'white_card',
  'driver_licence',
  'first_aid',
  'cpr',
  'working_at_heights',
  'confined_space',
  'ewp',
  'forklift_hrwl',
  'test_and_tag',
  'electrical_licence',
  'medicare',
  'asbestos_awareness',
  'traffic_control',
];

const EXTRACT_TOOL = {
  name: 'extract_licence',
  description:
    'Return structured fields extracted from an Australian tradie licence photo.',
  input_schema: {
    type: 'object',
    properties: {
      licence_number: {
        type: ['string', 'null'],
        description:
          'The licence/card number printed on the document. For HLTAID first-aid certificates this is the unit code (e.g. HLTAID011). Return null if not visible.',
      },
      licence_type: {
        type: ['string', 'null'],
        enum: [...LICENCE_TYPES, null],
        description:
          'Best-match code from the seeded list. Return null if the document does not match any of these.',
      },
      issuing_authority: {
        type: ['string', 'null'],
        description:
          'The issuing body printed on the card (e.g. "Service NSW", "VicRoads", "Department of Transport WA", "St John Ambulance", an RTO name). Null if not visible.',
      },
      state: {
        type: ['string', 'null'],
        enum: ['NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'NT', 'ACT', null],
        description:
          'Australian state/territory printed anywhere on the card (in headers, addresses, or the issuer name). Return the standard 2-3 letter code. Null if no Australian state is visible.',
      },
      issue_date: {
        type: ['string', 'null'],
        description:
          'ISO date YYYY-MM-DD if an issue/start date is visible. Null otherwise.',
      },
      expiry_date: {
        type: ['string', 'null'],
        description:
          'ISO date YYYY-MM-DD if an expiry/valid-until date is visible. Null otherwise. White Cards do not expire — return null.',
      },
      raw_text: {
        type: 'string',
        description:
          'All text legible on the card, line-separated, in the order it appears.',
      },
      confidence: {
        type: 'string',
        enum: ['low', 'medium', 'high'],
        description:
          'Self-rated confidence in the extraction. "low" if the photo is blurry or fields are guesses; "high" if every field is clearly readable.',
      },
    },
    required: ['raw_text', 'confidence'],
  },
};

const SYSTEM_PROMPT =
  'You are extracting structured fields from a photo of an Australian tradie licence or certificate ' +
  '(White Card, HLTAID first-aid certificate, driver licence, forklift HRWL, electrical licence, etc.). ' +
  'Return ONLY via the extract_licence tool. ' +
  'Be assertive when there are clear visual cues: a card with a photo, "while licence is valid" text, ' +
  'or a state transport branding is a driver_licence; a White Card style construction-induction card ' +
  'with an 8-digit number is a white_card; an HLTAID code is first_aid (HLTAID011) or cpr (HLTAID009); ' +
  'a card showing "NSW" / "VIC" / "QLD" etc. anywhere on it has that state. ' +
  'For licence_number and dates ONLY: return null if not clearly readable. ' +
  'For licence_type, state, and issuing_authority: infer confidently when the document type is unambiguous. ' +
  'Dates must be ISO YYYY-MM-DD. Card numbers are returned as printed (preserve case for letters).';

interface OcrRequest {
  image_base64?: string;
  mime_type?: string;
}

const CORS_HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers':
    'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
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

Deno.serve(async (req) => {
  // 204 No Content per HTTP spec — body MUST be empty. Deno's HTTP server
  // throws if you set a body on a 204 (which jsonResponse({}, 204) would do).
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  // Manual JWT verification (gateway verify_jwt is off so preflight can pass).
  // Plain fetch to /auth/v1/user — avoids pulling in the supabase-js module on
  // every cold start.
  const authHeader = req.headers.get('Authorization') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: 'supabase_env_missing' }, 500);
  }
  const userResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      'Authorization': authHeader,
      'apikey': supabaseAnonKey,
    },
  });
  if (!userResp.ok) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  // Per-user rate-limit check (atomic in Postgres via SECURITY DEFINER RPC).
  // 20 OCRs/hour/user. Returns true if allowed (and records the call);
  // false if the user is over the limit. See migration 0005_ocr_rate_limit.
  //
  // We do this BEFORE the Anthropic call so a rate-limited user incurs zero
  // upstream cost. If the RPC itself fails (network, etc.), fail-open with
  // a warning — preferring user UX over strict cost protection on a degraded
  // backend is the right trade for a 5-tester pilot.
  try {
    const rpcResp = await fetch(
      `${supabaseUrl}/rest/v1/rpc/check_and_record_ocr_usage`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'authorization': authHeader,
          'apikey': supabaseAnonKey,
        },
        body: JSON.stringify({ p_limit: 20, p_window: '1 hour' }),
      },
    );
    if (rpcResp.ok) {
      const allowed = await rpcResp.json();
      if (allowed === false) {
        return jsonResponse(
          {
            error: 'rate_limit_exceeded',
            message:
              "You've used your 20 magic-scans for this hour. Try again later, or add the licence manually.",
            retry_after_seconds: 3600,
          },
          429,
        );
      }
    } else {
      console.warn('rate_limit_rpc_unreachable', {
        status: rpcResp.status,
        body: await rpcResp.text().catch(() => ''),
      });
    }
  } catch (e) {
    console.warn('rate_limit_rpc_error', { error: String(e) });
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) {
    return jsonResponse({ error: 'anthropic_api_key_missing' }, 500);
  }

  let body: OcrRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const { image_base64, mime_type } = body;
  if (!image_base64 || typeof image_base64 !== 'string') {
    return jsonResponse({ error: 'image_base64_required' }, 400);
  }
  const mediaType = mime_type ?? 'image/jpeg';
  if (!/^image\/(jpeg|png|webp|gif)$/.test(mediaType)) {
    return jsonResponse({ error: 'unsupported_mime_type' }, 400);
  }

  const anthropicRequest = {
    model: ANTHROPIC_MODEL,
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    tools: [EXTRACT_TOOL],
    tool_choice: { type: 'tool', name: 'extract_licence' },
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: mediaType,
              data: image_base64,
            },
          },
          {
            type: 'text',
            text: 'Extract the licence fields from this image.',
          },
        ],
      },
    ],
  };

  const upstream = await fetch(ANTHROPIC_API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(anthropicRequest),
  });

  if (!upstream.ok) {
    // Log full upstream body to Edge Function logs only — never leak Anthropic
    // request signatures, prompt details, or WAF fingerprints back to the
    // browser. The 7-iteration debug chain in CHANGELOG benefited from
    // returning the body; production should not.
    const text = await upstream.text();
    console.error('anthropic_upstream', {
      status: upstream.status,
      body: text,
    });
    return jsonResponse(
      { error: 'anthropic_upstream_error', status: upstream.status },
      502,
    );
  }

  const data = await upstream.json() as any;
  // Find the tool_use block — there should be exactly one.
  const toolUse = (data.content ?? []).find(
    (b: any) => b.type === 'tool_use' && b.name === 'extract_licence',
  );
  if (!toolUse) {
    return jsonResponse(
      { error: 'no_tool_use_block', anthropic_response: data },
      502,
    );
  }

  return jsonResponse(toolUse.input);
});
