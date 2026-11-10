// Durable per-account protocol. Browser outcomes are presentation only.
import { GUILDBATTLE_ENGINE_VERSION as version } from './guildbattle-engine-version.js';
function cloud(owner) {
  const c = window.VRCloud;
  if (!c?.sb || !c.user) throw Error('login required');
  if (owner && owner !== c.user.id) throw Object.assign(Error('로그인 계정이 바뀌었어요'), { code: 'account-changed' });
  return c;
}
function store(kind, value, owner) {
  const key = 'vrGuildBattle.pendingV4:' + owner + ':' + kind;
  if (value === undefined) return JSON.parse(localStorage.getItem(key) || 'null');
  if (value === null) localStorage.removeItem(key);
  else localStorage.setItem(key, JSON.stringify(value));
  return value;
}
export async function verifyRpc(body, owner = cloud().user.id) {
  let last;
  for (let i = 0; i < 2; i++) {
    const c = cloud(owner);
    try {
      const { data, error } = await c.sb.functions.invoke('guildbattle-verify-v4', { body });
      cloud(owner);
      if (error) {
        let detail; try { detail = await error.context?.json(); } catch {}
        throw Error(detail?.error || error.message);
      }
      if (!data?.ok) throw Error(data?.error || 'server settlement failed');
      return data;
    } catch (e) { cloud(owner); last = e; }
  }
  throw last;
}
async function finishBody(body, owner) {
  try { return await verifyRpc(body, owner); }
  catch (e) {
    const s = await verifyRpc({ op: 'status', id: body.id }, owner).catch(() => null);
    if (s?.status === 'settled') return s;
    throw e;
  }
}
export async function recoverVerified(kind) {
  const owner = cloud().user.id;
  let p = store(kind, undefined, owner); if (!p) return null;
  if (p.phase === 'start') {
    // Lost START response: look up its UUID, never issue another ticket/seed.
    const { data, error } = await cloud(owner).sb.rpc('guildbattle_lookup_v4', { p_kind: kind, p_request: p.body.request });
    cloud(owner); if (error) throw Error(error.message);
    if (!data) { store(kind, null, owner); return null; }
    p = store(kind, { phase: 'active', session: data }, owner);
  }
  if (p.phase === 'active') {
    const s = await verifyRpc({ op: 'status', id: p.session.id }, owner);
    if (s.status === 'settled') { store(kind, null, owner); return s.result; }
    cloud(owner);
    p = store(kind, { phase: 'finish', body: { op: 'forfeit', id: p.session.id } }, owner);
  }
  const r = await finishBody(p.body, owner);
  store(kind, null, owner); return r.result;
}
export async function startVerified(kind, payload, control) {
  const owner = cloud().user.id;
  if (store(kind, undefined, owner)) throw Error('이전 전투 확인 필요');
  const body = { op: 'start', kind, payload, request: crypto.randomUUID(), control, version };
  store(kind, { phase: 'start', body }, owner);
  const s = { ...await verifyRpc(body, owner), _owner: owner };
  store(kind, { phase: 'active', session: s }, owner); return s;
}
export async function forfeitVerified(kind, s) {
  const owner = s._owner || cloud().user.id; cloud(owner);
  const body = { op: 'forfeit', id: s.id };
  store(kind, { phase: 'finish', body }, owner);
  const r = await finishBody(body, owner);
  store(kind, null, owner); return r.result;
}
export async function finishVerified(kind, s, actions) {
  const owner = s._owner || cloud().user.id; cloud(owner);
  const body = { op: 'finish', id: s.id, actions };
  store(kind, { phase: 'finish', body }, owner);
  const r = await finishBody(body, owner);
  store(kind, null, owner); return r.result;
}
export async function sweepVerified(rpc) {
  const owner = cloud().user.id, kind = 'raid-sweep';
  let p = store(kind, undefined, owner);
  if (!p) p = store(kind, { request: crypto.randomUUID() }, owner);
  const r = await rpc('raid_sweep_v4', { p_request: p.request });
  cloud(owner); store(kind, null, owner); return r;
}
export async function recoverSweepVerified(rpc) {
  return store('raid-sweep', undefined, cloud().user.id) ? sweepVerified(rpc) : null;
}
