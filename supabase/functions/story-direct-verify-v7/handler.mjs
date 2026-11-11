import { ENGINE_VERSION, verifyDirect } from './engine.mjs';
const STAGING = 'https://cuyqchmdcnsgzkwyclji.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const exact = (o, keys) => o && typeof o === 'object' && !Array.isArray(o) && Object.keys(o).sort().join(',') === keys.sort().join(',');
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type', 'access-control-allow-methods': 'POST, OPTIONS' };
const reply = (status, value) => new Response(JSON.stringify(value), { status, headers: { ...cors, 'content-type': 'application/json', 'cache-control': 'no-store' } });
function key(env, plural, legacy) {
  let keys; try { keys = JSON.parse(env[plural] || '{}'); } catch { throw new Error('backend configuration'); }
  return keys.default || Object.values(keys)[0] || env[legacy];
}
const SAFE = ['battle session not found', 'submission conflict', 'direct replay required', 'sweep replay required', 'verifier unavailable', 'too fast', 'daily limit', 'floor locked', 'tower closed today', 'level too low', 'boss floor or invalid floor', 'invalid replay', 'unsupported battle', 'reward verification pending', 'battle not started', 'completion rate limit', 'server settlement failed'];
const KO = {
  tampered: '전투 기록이 맞지 않아요. 다시 도전해 주세요.',
  'unsupported battle': '이 전투는 서버가 다시 계산할 수 없어요',
  'boss floor or invalid floor': '보스 층은 서버가 다시 계산할 수 없어요',
};
const ACT = new Set(['summon', 'atk', 'skill', 'end', 'reserve', 'buff', 'undo', 'giveup', 'swap']);
function actionsOk(list) {
  if (!Array.isArray(list) || list.length > 200) return false;
  return list.every(a => a && typeof a === 'object' && !Array.isArray(a) && ACT.has(a.k) && Number.isInteger(a.t) && a.t >= 0 && a.t <= 40
    && (a.i == null || (Number.isInteger(a.i) && a.i >= -1 && a.i <= 12))
    && (a.g == null || (Number.isInteger(a.g) && a.g >= -1 && a.g <= 12))
    && (a.id == null || (typeof a.id === 'string' && a.id.length <= 12))
    && (a.s == null || (typeof a.s === 'string' && a.s.length <= 40)));
}

function cardsOk(cards) {
  if (!Array.isArray(cards) || cards.length > 30) return false;
  return cards.every(c => c && typeof c === 'object' && !Array.isArray(c) && typeof c.uid === 'string' && c.uid.length > 0 && c.uid.length <= 80
    && Number.isInteger(c.kills) && c.kills >= 0 && c.kills <= 999
    && Number.isInteger(c.blocks) && c.blocks >= 0 && c.blocks <= 999);
}

export function createHandler(env, fetcher = fetch) {
  return async function handler(req) {
    const started = Date.now(), trace = crypto.randomUUID();
    let duplicate = false, operation = 'unknown';
    const respond = (status, value) => {
      console.info(JSON.stringify({ tag: 'story-direct-verify-v7', trace, operation, status, ms: Date.now() - started, duplicate, error: value.error || null }));
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
        if (total > 16384) { await reader.cancel(); return respond(413, { error: 'submission too large' }); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(total); let at = 0;
      for (const c of chunks) { bytes.set(c, at); at += c.length; }
      body = JSON.parse(new TextDecoder().decode(bytes));
      operation = body?.op === 'direct' || body?.op === 'status' ? body.op : 'unknown';
      if (body?.op === 'direct') {
        const claimed = Object.prototype.hasOwnProperty.call(body, 'win');
        if (!exact(body, claimed ? ['op', 'id', 'version', 'actions', 'cards', 'win'] : ['op', 'id', 'version', 'actions', 'cards']) || typeof body.id !== 'string' || !UUID.test(body.id) || (claimed && typeof body.win !== 'boolean') || !actionsOk(body.actions) || !cardsOk(body.cards)) {
          if (body?.version && body.version !== ENGINE_VERSION && typeof body.id === 'string' && UUID.test(body.id)) return respond(409, { error: '새 전투 버전으로 새로고침해 주세요' });
          throw new Error('invalid direct');
        }
        if (body.version !== ENGINE_VERSION) return respond(409, { error: '새 전투 버전으로 새로고침해 주세요' });
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
          const known = SAFE.find(x => (e.message || '').includes(x));
          throw new Error(known || 'server settlement failed');
        }
        return r.json();
      };
      const s = await rpc('battle_direct_session_v7', { p_uid: user.id, p_id: body.id });
      if (body.op === 'status') return respond(200, { ok: true, status: s.status, settlement: s.settlement || null });
      if (s.enabled !== true) return respond(503, { error: 'verifier unavailable' });
      if (s.status === 'settled') duplicate = true;
      let result = null;
      if (s.status === 'issued' || s.status === 'settled') {
        // body.cards is the story XP list (kills and blocks). The fight deck is session.snapshot.cards, saved at battle start. An empty cards array does not change the replay.
        try { result = verifyDirect(s, body.actions); }
        catch (e) {
          const message = String(e.message || '').startsWith('tampered') ? KO.tampered : (KO[e.message] || '전투 결과를 서버가 확인하지 못했어요');
          return respond(422, { error: message });
        }
        if (body.win === true && result?.win !== true) {
          const d = result?.debug;
          console.info(JSON.stringify({ tag: 'story-direct-verify-v7', event: 'replay-divergence', trace, session: body.id, reason: result?.reason || null, turn: d?.turn ?? null, action: d?.action ?? null, me: d?.me || null, ai: d?.ai || null }));
        }
        if (result && Object.prototype.hasOwnProperty.call(result, 'debug')) {
          result = { ...result };
          delete result.debug;
        }
      }
      const settled = await rpc('battle_direct_settle_v7', {
        p_uid: user.id, p_id: body.id, p_engine_hash: ENGINE_VERSION, p_result: result,
        p_client: { mana: body.mana, cards: body.cards },
      });
      return respond(200, settled);
    } catch (e) {
      const ko = KO[e.message];
      if (ko) return respond(422, { error: ko });
      return respond(user ? 409 : 400, { error: SAFE.includes(e.message) ? e.message : user ? '전투 결과를 서버가 확인하지 못했어요' : 'invalid request' });
    }
  };
}
