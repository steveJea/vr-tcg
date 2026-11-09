import { ENGINE_VERSION, verifySweep } from '../_shared/sweep-engine-v6.mjs';
const STAGING = 'https://cuyqchmdcnsgzkwyclji.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const exact = (o, keys) => o && typeof o === 'object' && !Array.isArray(o) && Object.keys(o).sort().join(',') === keys.sort().join(',');
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type', 'access-control-allow-methods': 'POST, OPTIONS' };
const reply = (status, value) => new Response(JSON.stringify(value), { status, headers: { ...cors, 'content-type': 'application/json', 'cache-control': 'no-store' } });
function key(env, plural, legacy) {
  let keys; try { keys = JSON.parse(env[plural] || '{}'); } catch { throw new Error('backend configuration'); }
  return keys.default || Object.values(keys)[0] || env[legacy];
}
const SAFE = ['battle session not found','submission conflict','sweep replay required','verifier unavailable','too fast','daily limit','floor locked','tower closed today','level too low','boss floor or invalid floor','invalid replay','reward verification pending','server settlement failed'];

export function createHandler(env, fetcher = fetch) {
  return async function handler(req) {
    const started = Date.now(), trace = crypto.randomUUID();
    let duplicate = false, operation = 'unknown';
    const respond = (status, value) => {
      console.info(JSON.stringify({ tag: 'story-tower-verify-v6', trace, operation, status, ms: Date.now() - started, duplicate, error: value.error || null }));
      return reply(status, { ...value, trace });
    };
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return respond(405, { error: 'POST required' });
    let body, user;
    try {
      if (env.SUPABASE_URL !== STAGING) return respond(503, { error: 'staging verifier unavailable' });
      if (!/application\/json/i.test(req.headers.get('content-type') || '')) return respond(400, { error: 'JSON required' });
      const reader = req.body?.getReader();
      if (!reader) return respond(400, { error: 'empty submission' });
      const chunks = []; let total = 0;
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > 4096) { await reader.cancel(); return respond(413, { error: 'submission too large' }); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(total); let at = 0;
      for (const c of chunks) { bytes.set(c, at); at += c.length; }
      body = JSON.parse(new TextDecoder().decode(bytes));
      operation = body?.op === 'sweep' || body?.op === 'status' ? body.op : 'unknown';
      if (body?.op === 'sweep') {
        if (!exact(body, ['op', 'id', 'version']) || typeof body.id !== 'string' || !UUID.test(body.id) || body.version !== ENGINE_VERSION) {
          if (body?.version && body.version !== ENGINE_VERSION && exact(body, ['op', 'id', 'version'])) return respond(409, { error: '새 전투 버전으로 새로고침해 주세요' });
          throw new Error('invalid sweep');
        }
      } else if (body?.op === 'status') {
        if (!exact(body, ['op', 'id']) || typeof body.id !== 'string' || !UUID.test(body.id)) throw new Error('invalid session');
      } else throw new Error('invalid operation');
      const token = req.headers.get('authorization');
      if (!token || !/^Bearer \S+$/i.test(token)) return respond(401, { error: 'login required' });
      const pub = key(env, 'SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
      const secret = key(env, 'SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
      if (!pub || !secret) return respond(503, { error: 'backend configuration' });
      const auth = await fetcher(STAGING + '/auth/v1/user', { headers: { authorization: token, apikey: pub } });
      if (!auth.ok) return respond(401, { error: 'login required' });
      user = await auth.json();
      if (!UUID.test(user.id || '')) return respond(401, { error: 'login required' });
      const rpc = async (name, args) => {
        const headers = { 'content-type': 'application/json', apikey: secret };
        if (!secret.startsWith('sb_secret_')) headers.authorization = 'Bearer ' + secret;
        const r = await fetcher(STAGING + '/rest/v1/rpc/' + name, { method: 'POST', headers, body: JSON.stringify(args) });
        if (!r.ok) {
          const e = await r.json().catch(() => ({}));
          throw new Error(SAFE.find(x => (e.message || '').includes(x)) || 'server settlement failed');
        }
        return r.json();
      };
      const s = await rpc('battle_sweep_session_v6', { p_uid: user.id, p_id: body.id });
      if (body.op === 'status') return respond(200, { ok: true, status: s.status, settlement: s.settlement || null });
      if (s.status === 'settled') duplicate = true;
      let result = null;
      if (s.status === 'issued' || s.status === 'settled') {
        try { result = verifySweep(s); }
        catch { return respond(422, { error: 'illegal or incomplete battle actions' }); }
      }
      const settled = await rpc('battle_sweep_settle_v6', { p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_result: result });
      return respond(200, settled);
    } catch (e) {
      return respond(user ? 409 : 400, { error: SAFE.includes(e.message) ? e.message : user ? 'server settlement failed' : 'invalid request' });
    }
  };
}
