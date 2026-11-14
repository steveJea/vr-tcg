// Staging-only PortOne V2 identity verification. Secret comes from env, never source.
export const STAGING = 'https://cuyqchmdcnsgzkwyclji.supabase.co';
const HOST = 'https://vr-tcg-staging.notcold.workers.dev';
const VID = /^identity-verification-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UUID = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const STORE_ID = /^store-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RPC_ERRORS = ['identity already used', 'identity mismatch', 'profile required', 'invalid verify', 'age verify unavailable'];

export function isAtLeast19(birthDate, now = new Date()) {
  if (typeof birthDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) return false;
  const [y, m, d] = birthDate.split('-').map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2100) return false;
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  const num = t => Number(parts.find(p => p.type === t).value);
  const Y = num('year'), M = num('month'), D = num('day');
  let age = Y - y;
  if (M < m || (M === m && D < d)) age -= 1;
  return age >= 19;
}

export async function sha256hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

function envKey(env, plural, legacy) {
  let keys;
  try { keys = JSON.parse(env[plural] || '{}'); } catch { return null; }
  return keys.default || Object.values(keys)[0] || env[legacy];
}

export function createHandler(env, fetcher = fetch, timeoutMs = 9000) {
  return async req => {
    const origin = req.headers.get('origin');
    const cors = { 'access-control-allow-origin': HOST, 'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info', 'access-control-allow-methods': 'POST, OPTIONS', 'vary': 'Origin' };
    const reply = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'content-type': 'application/json', 'cache-control': 'no-store' } });
    if (origin && origin !== HOST) return reply(403, { error: 'origin not allowed' });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return reply(405, { error: 'POST required' });
    const controller = new AbortController();
    let timer, stage = 'request';
    const work = async () => {
      if (env.SUPABASE_URL !== STAGING) return reply(503, { error: 'staging only' });
      const secret = env.PORTONE_API_SECRET;
      if (typeof secret !== 'string' || secret.length < 20 || secret.length > 200 || /[\u0000-\u001f\u007f]/.test(secret)) return reply(503, { error: 'age verification configuration required' });
      const storeId = typeof env.PORTONE_STORE_ID === 'string' ? env.PORTONE_STORE_ID.trim() : '';
      if (storeId && !STORE_ID.test(storeId)) return reply(503, { error: 'age verification configuration required' });
      const pub = envKey(env, 'SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY'), service = envKey(env, 'SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
      if (!pub || !service) return reply(503, { error: 'backend configuration' });
      if (!/^application\/json(?:;|$)/i.test(req.headers.get('content-type') || '')) return reply(400, { error: 'invalid request' });
      const reader = req.body?.getReader();
      if (!reader) return reply(400, { error: 'invalid request' });
      let size = 0, parts = [];
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 4096) { await reader.cancel(); return reply(400, { error: 'invalid request' }); }
        parts.push(value);
      }
      const bytes = new Uint8Array(size);
      let at = 0;
      for (const p of parts) { bytes.set(p, at); at += p.length; }
      let b;
      try { b = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reply(400, { error: 'invalid request' }); }
      if (!b || typeof b !== 'object' || Array.isArray(b) || Object.keys(b).sort().join(',') !== 'identityVerificationId' || !VID.test(b.identityVerificationId || '')) return reply(400, { error: 'invalid request' });
      const token = req.headers.get('authorization');
      if (!/^Bearer \S+$/i.test(token || '')) return reply(401, { error: 'login required' });
      const request = (url, opts = {}) => fetcher(url, { ...opts, signal: controller.signal });
      stage = 'auth';
      const auth = await request(STAGING + '/auth/v1/user', { headers: { authorization: token, apikey: pub } });
      if (!auth.ok) return reply(401, { error: 'login required' });
      const user = await auth.json();
      if (typeof user.id !== 'string' || !UUID.test(user.id)) return reply(401, { error: 'login required' });
      stage = 'portone';
      const url = 'https://api.portone.io/identity-verifications/' + encodeURIComponent(b.identityVerificationId) + (storeId ? '?storeId=' + encodeURIComponent(storeId) : '');
      const pr = await request(url, { headers: { Authorization: 'PortOne ' + secret } });
      const body = await pr.json().catch(() => null);
      if (pr.status === 401 || pr.status === 403) return reply(503, { error: 'age verification configuration required' });
      if (!pr.ok || !body || typeof body !== 'object') return reply(409, { error: 'verification not completed' });
      if (body.status !== 'VERIFIED' || body.id !== b.identityVerificationId) return reply(409, { error: 'verification not completed' });
      const customer = body.verifiedCustomer;
      if (!customer || typeof customer !== 'object') return reply(409, { error: 'verification not completed' });
      if (!isAtLeast19(customer.birthDate)) return reply(403, { error: 'underage' });
      if (typeof customer.ci !== 'string' || customer.ci.length < 20 || customer.ci.length > 200) return reply(409, { error: 'identity incomplete' });
      const ciHash = await sha256hex(customer.ci);
      const rpc = async (name, args) => {
        const headers = { 'content-type': 'application/json', apikey: service };
        if (!service.startsWith('sb_secret_')) headers.authorization = 'Bearer ' + service;
        const r = await request(STAGING + '/rest/v1/rpc/' + name, { method: 'POST', headers, body: JSON.stringify(args) });
        if (!r.ok) {
          const e = await r.json().catch(() => ({}));
          const known = RPC_ERRORS.find(s => String(e.message).includes(s));
          const code = known || (['PGRST202', '42P01', '42883', '42703'].includes(e.code) ? 'age verify sql required' : 'verification not completed');
          console.warn(JSON.stringify({ tag: 'age-verify-v1', stage, status: r.status, dbCode: /^[A-Z0-9_]{3,24}$/.test(e.code || '') ? e.code : null, code }));
          throw Error(code);
        }
        return r.json();
      };
      stage = 'apply';
      const applied = await rpc('age_verify_apply', { p_uid: user.id, p_vid: b.identityVerificationId, p_ci_hash: ciHash });
      return reply(200, { ok: true, verified: true, idempotent: !!applied?.idempotent });
    };
    try {
      return await Promise.race([
        work(),
        new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(reply(504, { error: 'verification pending', stage })); }, timeoutMs); }),
      ]);
    } catch (e) {
      const allowed = [...RPC_ERRORS, 'age verify sql required'];
      const error = allowed.includes(e.message) ? e.message : 'verification pending';
      return reply(error === 'identity already used' || error === 'identity mismatch' ? 409 : error.startsWith('age verify') || error === 'profile required' ? 503 : 409, { error, stage });
    } finally { clearTimeout(timer); }
  };
}
