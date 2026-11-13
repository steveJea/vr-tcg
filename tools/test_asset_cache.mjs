// 기기 캐시: sw.js (내용 해시 버전·옛것 정리·영상 Range·통과 규칙) + 자산 목록 빌더 + 화면 연결 검사
import assert from 'node:assert/strict';
import { readFile, mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os'; import path from 'node:path'; import vm from 'node:vm'; import { createHash } from 'node:crypto';
const H = b => createHash('sha256').update(b).digest('hex').slice(0, 8);
import { buildAssetManifest } from './build_asset_manifest.mjs';
const rd = p => readFile(new URL('../' + p, import.meta.url), 'utf8');
const ORIGIN = 'https://vr.test';

// ---- 자산 목록 빌더 ----
const dir = await mkdtemp(path.join(os.tmpdir(), 'vr-am-'));
await mkdir(path.join(dir, 'img/ui'), { recursive: true }); await mkdir(path.join(dir, 'js'), { recursive: true });
await writeFile(path.join(dir, 'img/ui/a.webp'), 'AAAA'); await writeFile(path.join(dir, 'js/x.js'), 'x'); await writeFile(path.join(dir, 'js/.hidden'), 'h'); await writeFile(path.join(dir, 'index.html'), '<html>');
const m1 = await buildAssetManifest(dir);
assert.deepEqual(Object.keys(m1.files).sort(), ['/img/ui/a.webp', '/js/x.js'], 'only asset dirs, no dotfiles/html');
assert.equal(m1.files['/img/ui/a.webp'][0], 4); assert.match(m1.files['/img/ui/a.webp'][1], /^[0-9a-f]{8}$/); assert.equal(m1.total, 5);
await writeFile(path.join(dir, 'img/ui/a.webp'), 'BBBB'); const m2 = await buildAssetManifest(dir);
assert.notEqual(m2.files['/img/ui/a.webp'][1], m1.files['/img/ui/a.webp'][1], 'content change → new hash'); assert.notEqual(m2.v, m1.v);
assert.equal(m2.files['/js/x.js'][1], m1.files['/js/x.js'][1]);
await rm(dir, { recursive: true, force: true });

// ---- sw.js ----
const sw = await rd('sw.js');
function makeEnv(manifest) {
  const net = { calls: [], files: { '/img/ui/a.webp': 'NEW', '/data/movie/1.mp4': '0123456789' }, manifest };
  class Store { constructor() { this.m = new Map(); } async match(r) { const u = typeof r === 'string' ? r : r.url; const v = this.m.get(u); return v ? v.clone() : undefined; } async put(r, res) { this.m.set(typeof r === 'string' ? r : r.url, res); } async keys() { return [...this.m.keys()].map(u => new Request(u)); } async delete(r) { return this.m.delete(typeof r === 'string' ? r : r.url); } }
  const stores = new Map();
  const caches = { async open(n) { if (!stores.has(n)) stores.set(n, new Store()); return stores.get(n); }, async keys() { return [...stores.keys()]; }, async delete(n) { return stores.delete(n); } };
  async function fetch(input, init = {}) {
    const url = new URL(typeof input === 'string' ? input : input.url, ORIGIN); net.calls.push([url.pathname, init.cache || (input.cache)]);
    if (url.pathname === '/asset-manifest.json' && net.manDelay) await new Promise(r => setTimeout(r, net.manDelay));
    if (url.pathname === '/asset-manifest.json') return net.manifest ? new Response(JSON.stringify(net.manifest), { status: 200 }) : new Response('nf', { status: 404 });
    const body = net.files[url.pathname]; if (body == null) return new Response('nf', { status: 404 });
    const r = new Response(body, { status: 200, headers: { 'content-type': 'image/webp' } }); Object.defineProperty(r, 'type', { value: 'basic' }); return r;
  }
  const L = {};
  const self = { location: new URL(ORIGIN + '/sw.js'), addEventListener: (t, f) => (L[t] = f), skipWaiting() {}, clients: { claim: async () => {} } };
  const ctx = vm.createContext({ self, caches, fetch, Request, Response, URL, Headers, setTimeout, Promise, crypto: globalThis.crypto, Uint8Array, JSON, Date, decodeURIComponent, String, Number, Math, console });
  vm.runInContext(sw, ctx);
  async function fire(url, { method = 'GET', mode = 'no-cors', headers = {} } = {}) {
    const request = new Request(new URL(url, ORIGIN), { method, headers }); Object.defineProperty(request, 'mode', { value: mode });
    let resp = null; const waits = [];
    L.fetch({ request, respondWith: p => (resp = p), waitUntil: p => waits.push(p) });
    const r = resp && await resp; await Promise.all(waits); await new Promise(r => setTimeout(r, 5)); return r;
  }
  return { fire, net, stores, caches, L };
}
const MAN = (body = 'NEW') => ({ v: 'v' + H(body), total: body.length + 10, files: { '/img/ui/a.webp': [body.length, H(body)], '/data/movie/1.mp4': [10, H('0123456789')] } });
{
  const E = makeEnv(MAN('NEW'));
  // 통과: GET 아님·다른 곳(Supabase 등)·범위 밖(html, auth)·페이지 이동
  assert.equal(await E.fire('/img/ui/a.webp', { method: 'POST' }), null);
  assert.equal(await E.fire('https://abc.supabase.co/rest/v1/x'), null);
  assert.equal(await E.fire('https://raw.githubusercontent.com/x/y.webp'), null);
  assert.equal(await E.fire('/index.html'), null); assert.equal(await E.fire('/auth/v1/callback'), null); assert.equal(await E.fire('/asset-manifest.json'), null);
  assert.equal(await E.fire('/?code=abc', { mode: 'navigate' }), null, 'OAuth redirect untouched');
  // 첫 요청: 원래 요청 그대로 (HTTP 캐시·우선순위 그대로, 강제 재확인 없음) → 내용 해시가 목록과 같을 때만 저장
  let r = await E.fire('/img/ui/a.webp?v=3'); assert.equal(await r.text(), 'NEW');
  assert(!E.net.calls.some(([p, c]) => p === '/img/ui/a.webp' && c === 'no-cache'), 'first fetch is the original request (no forced revalidation)');
  const store = await E.caches.open('vr-assets-v1'); assert((await store.keys()).map(k => k.url).includes(ORIGIN + '/img/ui/a.webp?h=' + H('NEW')));
  const n = E.net.calls.filter(([p]) => p === '/img/ui/a.webp').length;
  r = await E.fire('/img/ui/a.webp'); assert.equal(await r.text(), 'NEW'); assert.equal(E.net.calls.filter(([p]) => p === '/img/ui/a.webp').length, n, 'served from device cache');
  // 목록에 없는 파일은 저장 안 함
  E.net.files['/img/ui/new.webp'] = 'Z'; await E.fire('/img/ui/new.webp'); assert(!(await store.keys()).some(k => k.url.includes('new.webp')));
  // 배포로 파일이 바뀜 → 새 해시 → 페이지 이동 때 목록 새로 → 새로 받고 옛것 정리
  E.net.files['/img/ui/a.webp'] = 'NEWER'; E.net.manifest = MAN('NEWER');
  await E.fire('/', { mode: 'navigate' });
  r = await E.fire('/img/ui/a.webp'); assert.equal(await r.text(), 'NEWER', 'updated file refetched');
  await new Promise(r => setTimeout(r, 20));
  const keys = (await store.keys()).map(k => k.url); assert(keys.includes(ORIGIN + '/img/ui/a.webp?h=' + H('NEWER'))); assert(!keys.includes(ORIGIN + '/img/ui/a.webp?h=' + H('NEW')), 'stale hash cleaned');
  // 영상: 저장 전 Range 는 통과, 저장 후엔 206 조각
  r = await E.fire('/data/movie/1.mp4', { headers: { range: 'bytes=0-3' } }); assert.equal(await r.text(), '0123456789', 'uncached range → network');
  await E.fire('/data/movie/1.mp4');
  r = await E.fire('/data/movie/1.mp4', { headers: { range: 'bytes=2-5' } }); assert.equal(r.status, 206); assert.equal(await r.text(), '2345'); assert.equal(r.headers.get('content-range'), 'bytes 2-5/10');
  r = await E.fire('/data/movie/1.mp4', { headers: { range: 'bytes=-3' } }); assert.equal(await r.text(), '789');
  r = await E.fire('/data/movie/1.mp4', { headers: { range: 'bytes=50-' } }); assert.equal(r.status, 416);
  // 옛 버전 캐시 이름 정리
  await E.caches.open('vr-assets-v0'); const act = []; E.L.activate({ waitUntil: p => act.push(p) }); await Promise.all(act);
  assert(!(await E.caches.keys()).includes('vr-assets-v0')); assert((await E.caches.keys()).includes('vr-assets-v1'));
}
{ // 옛 내용(HTTP 캐시 등)이 오면 보여 주되 새 해시로 저장하지 않음 · 미리 받기 요청은 통과 · 목록 새로 받기를 기다리지 않음
  const E = makeEnv(MAN('NEW'));
  await E.fire('/', { mode: 'navigate' });
  E.net.files['/img/ui/a.webp'] = 'OLD';
  let r = await E.fire('/img/ui/a.webp'); assert.equal(await r.text(), 'OLD');
  const store = await E.caches.open('vr-assets-v1'); assert.equal((await store.keys()).length, 0, 'hash mismatch → not stored');
  assert.equal(await E.fire('/img/ui/a.webp', { headers: { 'x-vr-prefetch': '1' } }), null, 'prefetch bypasses SW');
  // 목록이 오래됨 + 서버가 목록을 늦게 줌 → 그림은 바로
  E.net.files['/img/ui/a.webp'] = 'NEW'; const realNow = Date.now; E.net.manDelay = 3000;
  Date.now = () => realNow() + 120000;
  const t0 = realNow(); const req = new Request(ORIGIN + '/img/ui/a.webp'); Object.defineProperty(req, 'mode', { value: 'no-cors' });
  let resp; E.L.fetch({ request: req, respondWith: p => (resp = p), waitUntil: () => {} });
  r = await resp; assert.equal(await r.text(), 'NEW'); assert(realNow() - t0 < 200, 'stale manifest never blocks');
  Date.now = realNow;
}
{ // 목록이 없는 배포(예: 운영 빌드에 목록이 없을 때) → 전부 통과, 저장 안 함
  const E = makeEnv(null);
  const r = await E.fire('/img/ui/a.webp'); assert.equal(await r.text(), 'NEW');
  assert.equal((await (await E.caches.open('vr-assets-v1')).keys()).length, 0);
}

// ---- 화면 연결 ----
const [html, js, build, priv] = await Promise.all(['index.html', 'js/asset-cache.js', 'tools/build_staging.mjs', 'privacy.html'].map(rd));
assert.match(html, /<body[^>]*>\n<!--[^\n]*-->\n<div id="vr-boot"/, 'loading screen first in body');
assert(html.indexOf('src="js/asset-cache.js"') < html.indexOf('src="js/id-alias.js"') || html.indexOf('src="js/asset-cache.js"') > 0);
for (const id of ['as-dl', 'as-sum', 'as-prog', 'as-cancel', 'as-clear', 'as-have']) assert.match(html, new RegExp(`id="${id}"`), id);
assert.match(js, /finish\('timeout'\)/); assert.match(js, /> 8000/, 'never blocks: 8s fallback');
assert.match(js, /saveData/); assert.match(js, /effectiveType/); assert.match(js, /document\.hidden/); assert.match(js, /x-vr-prefetch/); assert.match(js, /pendingImgs\(\)/); assert.match(js, /'yield'/); assert.match(js, /inBattle\(\)/); assert.match(js, /\[worker\(\), worker\(\)\]/, 'background concurrency 2');
assert.match(js, /CHUNK = 192 \* 1024/); assert.match(js, /range: `bytes=\$\{s\}-\$\{e\}`/); assert.match(js, /content-range/); assert.match(js, /new Uint8Array\(sz\)/); assert.match(js, /와이파이 권장/); assert.match(js, /그만|cancel/);
assert.match(build, /cp\(path\.join\(root, 'sw\.js'\)/); assert.match(build, /buildAssetManifest\(out\)/); assert.match(build, /\/asset-manifest\.json'\]\.map\(p => `\$\{p\}\\n  Cache-Control: no-cache/);
assert.match(priv, /게임 리소스\(그림·음성·영상 등\)를 기기에 저장해 더 빠르게 불러올 수 있어요/);
console.log('Asset cache: manifest hashes, SW passthrough (non-GET/cross-origin/navigate/auth), original-request first fetch + hash-checked store, prefetch bypass, stale manifest non-blocking, served from cache, update refetch + stale cleanup, Range 206, no-manifest passthrough, boot/settings/privacy wiring OK');
