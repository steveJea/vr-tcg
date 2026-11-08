import { ENGINE_VERSION, verifyBattle, checkActions, arcadeOptions } from '../_shared/arcade-engine-v5.mjs';
const STAGING = 'https://cuyqchmdcnsgzkwyclji.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const exact = (o, keys) => o && typeof o === 'object' && !Array.isArray(o) && Object.keys(o).sort().join(',') === keys.sort().join(',');
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type', 'access-control-allow-methods': 'POST, OPTIONS' };
const reply = (status, value) => new Response(JSON.stringify(value), { status, headers: { ...cors, 'content-type': 'application/json', 'cache-control': 'no-store' } });
function key(env, plural, legacy) {
  let keys; try { keys = JSON.parse(env[plural] || '{}'); } catch { throw new Error('backend configuration'); }
  return keys.default || Object.values(keys)[0] || env[legacy];
}
// Explicit dependencies make Auth/REST failure and ACL behavior testable without a database/key.
export function createHandler(env, fetcher = fetch) {
  return async function handler(req) {
    const started=Date.now(), trace=crypto.randomUUID();let duplicate=false, operation='unknown';
    const respond=(status,value)=>{ console.info(JSON.stringify({tag:'arcade-verify-v5',trace,operation,status,ms:Date.now()-started,duplicate,error:value.error||null}));return reply(status,{...value,trace}); };
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return respond(405, { error: 'POST required' });
    let body, user;
    try {
      if (env.SUPABASE_URL !== STAGING) return respond(503, { error: 'staging verifier unavailable' });
      if (!/application\/json/i.test(req.headers.get('content-type') || '')) return respond(400, { error: 'JSON required' });
      if (Number(req.headers.get('content-length') || 0) > 524288) return respond(413, { error: 'submission too large' });
      // Streaming bound, also when Content-Length is missing or dishonest.
      const reader = req.body?.getReader(); if (!reader) return respond(400, { error: 'empty submission' });
      const chunks = []; let total = 0;
      for (;;) { const { value, done } = await reader.read(); if (done) break; total += value.length;
        if (total > 524288) { await reader.cancel(); return respond(413, { error: 'submission too large' }); } chunks.push(value); }
      const bytes = new Uint8Array(total); let at = 0; for (const c of chunks) { bytes.set(c, at); at += c.length; }
      body = JSON.parse(new TextDecoder().decode(bytes));
      operation=['start','finish','forfeit','status'].includes(body?.op)?body.op:'unknown';
      if (body.op === 'start') {
        if (!exact(body,['op','request','options','version'])||typeof body.request!=='string'||!UUID.test(body.request))throw Error('invalid start');
        arcadeOptions(body.options);
        if(body.version!==ENGINE_VERSION)return respond(409,{error:'새 전투 버전으로 새로고침해 주세요'});
      } else if (body.op === 'finish' || body.op === 'forfeit' || body.op === 'status') {
        if (!exact(body, body.op === 'finish' ? ['op','id','actions'] : ['op','id']) || typeof body.id !== 'string' || !/^[1-9][0-9]{0,18}$/.test(body.id) || BigInt(body.id) > 9223372036854775807n) throw new Error('invalid session');
        if (body.op === 'finish') checkActions(body.actions);
      } else throw new Error('invalid operation');
      const token = req.headers.get('authorization');
      if (!token || !/^Bearer \S+$/i.test(token)) return respond(401, { error: 'login required' });
      const pub = key(env,'SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY');
      const secret = key(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
      if (!pub || !secret) return respond(503, { error: 'backend configuration' });
      // Never decode/trust caller-supplied JWT claims. Auth validates signature, expiry and user.
      const auth = await fetcher(STAGING+'/auth/v1/user', { headers: { authorization: token, apikey: pub } });
      if (!auth.ok) return respond(401, { error: 'login required' });
      user = await auth.json(); if (!UUID.test(user.id || '')) return respond(401, { error: 'login required' });
      const rpc = async (name, args, trusted = true) => {
        const headers = { 'content-type': 'application/json', apikey: trusted ? secret : pub };
        if (!trusted) headers.authorization = token;
        else if (!secret.startsWith('sb_secret_')) headers.authorization = 'Bearer '+secret; // legacy service-role JWT
        const r = await fetcher(STAGING+'/rest/v1/rpc/'+name, { method: 'POST', headers, body: JSON.stringify(args) });
        if (!r.ok) {
          const e = await r.json().catch(() => ({}));
          // Only allow known game errors out; never reflect backend/auth/headers/SQL internals.
          const allowed = ['session not found','submission conflict','request conflict','no attempts left','rate limited','deck required','card not owned','duplicate card','guard grade','grade not allowed','cost over 150','verifier unavailable','no attempts','no attacks','not in guild','raid ended','no match','match ended','not battle time','target busy','defense first','already destroyed','deck dead','no attack deck','card not owned','invalid target','invalid deck','reward verification pending','active session','invalid arcade options'];
          throw new Error(allowed.find(x => (e.message || '').includes(x)) || 'server settlement failed');
        }
        return r.json();
      };
      if(body.op==='start')return respond(200,await rpc('arcade_start_v5',{p_request:body.request,p_options:arcadeOptions(body.options),p_engine_hash:ENGINE_VERSION},false));
      const s = await rpc('arcade_engine_session_v5', { p_uid: user.id, p_id: body.id });
      if (body.op === 'status') return respond(200, { ok: true, status: s.status, result: s.result });
      const submission = body.op === 'forfeit' ? { forfeit: true } : { actions: body.actions };
      if (s.status === 'settled') { duplicate=true;
        // SQL performs canonical JSONB comparison and returns the original receipt, not a second grant.
        return respond(200, await rpc('arcade_engine_settle_v5', { p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_submission: submission, p_result: null }));
      }
      if (body.op === 'forfeit') return respond(200, await rpc('arcade_engine_settle_v5', { p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_submission: submission, p_result: null }));
      if (s.engine_hash !== ENGINE_VERSION) {
        // NEVER replay an old transcript with new rules. SQL alone can close an
        // expired session as its already-reserved forfeit (or reject an active
        // old session). This also releases durable pending results after rollout.
        return respond(200, await rpc('arcade_engine_settle_v5', { p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_submission: submission, p_result: null }));
      }
      let result; try { result = verifyBattle(s, body.actions); } catch { return respond(422, { error: 'illegal or incomplete battle actions' }); }
      // No await inside engine execution: its scoped RNG/global skill state cannot interleave requests.
      return respond(200, await rpc('arcade_engine_settle_v5', { p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_submission: submission, p_result: result }));
    } catch (e) {
      const safe = ['session not found','submission conflict','request conflict','no attempts left','rate limited','deck required','card not owned','duplicate card','guard grade','grade not allowed','cost over 150','verifier unavailable','no attempts','no attacks','not in guild','raid ended','no match','match ended','not battle time','target busy','defense first','already destroyed','deck dead','no attack deck','card not owned','invalid target','invalid deck','reward verification pending','active session','invalid arcade options','server settlement failed'];
      return respond(user ? 409 : 400, { error: safe.includes(e.message) ? e.message : user ? 'server settlement failed' : 'invalid request' });
    }
  };
}
