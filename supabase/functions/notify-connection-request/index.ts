// Supabase Edge Function: notify-connection-request
//
// Fires on every INSERT into public.org_access_requests via a pg_net trigger.
//
//   direction=worker   → emails org admin(s): a worker applied to connect
//   direction=employer → emails the worker: an employer sent them a request
//
// Security: validates x-webhook-secret header against CONNECTION_NOTIFY_WEBHOOK_SECRET.
//
// Edge Function Secrets (Supabase dashboard → Settings → Edge Function Secrets):
//   SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY  auto-injected by Supabase
//   CONNECTION_NOTIFY_WEBHOOK_SECRET          copy from vault after running migration 0044:
//                                             SELECT decrypted_secret FROM vault.decrypted_secrets
//                                             WHERE name = 'CONNECTION_NOTIFY_WEBHOOK_SECRET';
//   RESEND_API_KEY                            from resend.com dashboard

const FROM_EMAIL = 'EQ Solutions <contact@eq.solutions>';
const SHELL_URL  = 'https://core.eq.solutions';
const CARDS_URL  = 'https://cards.eq.solutions';

interface Payload {
  request_id: string;
  direction: 'worker' | 'employer';
}

interface Target {
  direction: string;
  org_name: string;
  sharing_scope: string | null;
  worker_name: string;
  to_email: string;
  to_name: string | null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const webhookSecret = Deno.env.get('CONNECTION_NOTIFY_WEBHOOK_SECRET');
  if (!webhookSecret || req.headers.get('x-webhook-secret') !== webhookSecret) {
    return json({ error: 'unauthorized' }, 401);
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.error('RESEND_API_KEY not configured');
    return json({ error: 'email_not_configured' }, 500);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const { request_id, direction }: Payload = await req.json();

  // One RPC round-trip: fetches org info + all recipient rows from shell_control
  const rpcRes = await fetch(
    `${supabaseUrl}/rest/v1/rpc/eq_notify_connection_request_targets`,
    {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_request_id: request_id }),
    },
  );

  if (!rpcRes.ok) {
    const text = await rpcRes.text().catch(() => '');
    console.error('rpc failed', { status: rpcRes.status, body: text });
    return json({ error: 'rpc_error' }, 502);
  }

  const targets: Target[] = await rpcRes.json();

  if (!targets.length) {
    // No recipients: org has no admin emails, or worker has no email, or not yet registered
    console.log('no notification targets', { request_id, direction });
    return json({ ok: true, sent: 0 });
  }

  const { org_name, sharing_scope, worker_name } = targets[0];
  const scopeLabel = sharing_scope === 'basic' ? 'basic profile' : 'full profile + credentials';
  const isWorker   = direction === 'worker';

  const results = await Promise.allSettled(
    targets.map((t) =>
      sendEmail(resendKey, {
        to:      t.to_email,
        subject: isWorker
          ? `New connection request — ${org_name}`
          : `${org_name} wants to connect with you on EQ Cards`,
        html: buildEmail(
          isWorker
            ? {
                greeting:   `Hi${t.to_name ? ` ${firstName(t.to_name)}` : ''},`,
                paragraphs: [
                  `<strong>${esc(worker_name)}</strong> has applied to connect their EQ Cards wallet to <strong>${esc(org_name)}</strong>.`,
                  `They've chosen to share their <strong>${scopeLabel}</strong>.`,
                ],
                cta:    { label: 'Review in EQ Shell', href: SHELL_URL },
                footer: `You're receiving this because you're an admin of ${esc(org_name)}.`,
              }
            : {
                greeting:   `Hi ${t.to_name ? firstName(t.to_name) : 'there'},`,
                paragraphs: [
                  `<strong>${esc(org_name)}</strong> has sent you a connection request on EQ Cards.`,
                  `Open the app to review and accept or decline — it only takes a moment.`,
                ],
                cta:    { label: 'Open EQ Cards', href: CARDS_URL },
                footer: 'You can manage your connection requests in the EQ Cards app.',
              },
        ),
      }),
    ),
  );

  const sent = results.filter((r) => r.status === 'fulfilled').length;
  results
    .filter((r): r is PromiseRejectedResult => r.status === 'rejected')
    .forEach((r) => console.error('send failed', r.reason));

  console.log('notifications sent', { sent, total: targets.length, direction, request_id });
  return json({ ok: true, sent });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function firstName(name: string): string {
  return name.split(' ')[0];
}

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function sendEmail(
  apiKey: string,
  opts: { to: string; subject: string; html: string },
): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to:   [opts.to],
      subject: opts.subject,
      html: opts.html,
    }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`resend_${res.status}: ${text}`);
  }
}

function buildEmail(opts: {
  greeting:   string;
  paragraphs: string[];
  cta:        { label: string; href: string };
  footer:     string;
}): string {
  const { greeting, paragraphs, cta, footer } = opts;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
</head>
<body style="margin:0;padding:0;background:#f4f4f5;font-family:'Plus Jakarta Sans',system-ui,sans-serif;color:#1A1A2E">
<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:40px 16px">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%">
  <tr><td style="background:#3DA8D8;padding:24px 32px;border-radius:8px 8px 0 0">
    <span style="color:#fff;font-size:18px;font-weight:700;letter-spacing:-0.3px">EQ Solutions</span>
  </td></tr>
  <tr><td style="background:#fff;padding:32px;border-radius:0 0 8px 8px">
    <p style="margin:0 0 16px;line-height:1.6">${greeting}</p>
    ${paragraphs.map((p) => `<p style="margin:0 0 16px;line-height:1.6">${p}</p>`).join('\n    ')}
    <p style="margin:24px 0">
      <a href="${cta.href}" style="display:inline-block;background:#3DA8D8;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;font-weight:600">${cta.label}</a>
    </p>
    <p style="margin:24px 0 0;color:#888;font-size:12px;border-top:1px solid #EAF5FB;padding-top:16px">${footer}</p>
  </td></tr>
</table>
</td></tr></table>
</body>
</html>`;
}
