// VR 기기 캐시 (서비스 워커). 같은 사이트의 정적 자산(js·css·data·img·audio·video)만 저장.
// - /asset-manifest.json 의 내용 해시로 버전 관리: 파일이 바뀌면 해시가 바뀌어 새로 받고, 옛것은 정리
// - 페이지(html)·로그인/OAuth 이동·Supabase/API·다른 사이트 요청·GET 아닌 요청은 건드리지 않음 (그냥 통과)
// - 목록을 못 받으면(없음·오프라인 첫 실행) 전부 통과
const CACHE = 'vr-assets-v1', META = 'vr-assets-meta', MANIFEST = '/asset-manifest.json';
const SCOPE = /^\/(js|css|data|img|audio|video)\//;
let man = null, manAt = 0, manP = null, cleanedV = null;

async function loadManifest(force) {
  if (!force && man && Date.now() - manAt < 30000) return man;
  if (manP) return manP;
  manP = (async () => {
    try {
      const r = await fetch(MANIFEST, { cache: 'no-cache', credentials: 'same-origin' });
      if (r.ok) {
        const m = await r.json();
        if (m && m.files) { man = m; manAt = Date.now(); (await caches.open(META)).put(MANIFEST, new Response(JSON.stringify(m), { headers: { 'content-type': 'application/json' } })).catch(() => {}); }
      } else if (r.status === 404) { man = null; manAt = Date.now(); }   // 목록이 없는 배포 → 캐시 안 씀
    } catch {
      if (!man) { try { const r = await (await caches.open(META)).match(MANIFEST); if (r) { man = await r.json(); manAt = Date.now() - 25000; } } catch {} }
    } finally { manP = null; }
    if (man && man.v !== cleanedV) { cleanedV = man.v; cleanup(man).catch(() => {}); }
    return man;
  })();
  return manP;
}
// 목록에 없거나 해시가 다른 캐시 항목 지우기
async function cleanup(m) {
  const c = await caches.open(CACHE);
  for (const req of await c.keys()) {
    const u = new URL(req.url); let p = u.pathname; try { p = decodeURIComponent(p); } catch {} const e = m.files[p] || m.files[u.pathname];
    if (!e || u.searchParams.get('h') !== e[1]) await c.delete(req);
  }
}
const keyOf = (path, h) => new Request(self.location.origin + path + '?h=' + h);

self.addEventListener('install', e => { self.skipWaiting(); e.waitUntil(loadManifest(true)); });
self.addEventListener('activate', e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k.startsWith('vr-assets') && k !== CACHE && k !== META) await caches.delete(k);   // 옛 버전 캐시
  await self.clients.claim();
})()));
self.addEventListener('message', e => { if (e.data === 'vr-refresh') e.waitUntil(loadManifest(true)); });

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;           // Supabase·Google·카드 원본 등 다른 곳은 통과
  if (req.mode === 'navigate') { e.waitUntil(loadManifest(true)); return; }   // 페이지·OAuth 이동은 그대로, 목록만 새로
  if (!SCOPE.test(url.pathname)) return;
  e.respondWith(handle(e, req, url));
});

async function handle(e, req, url) {
  let m = man;
  try { m = await Promise.race([loadManifest(false), new Promise(r => setTimeout(() => r(man), 2500))]); } catch {}
  let path; try { path = decodeURIComponent(url.pathname); } catch { return fetch(req); }
  const ent = m && (m.files[path] || m.files[url.pathname]);
  if (!ent) return fetch(req);
  const c = await caches.open(CACHE), key = keyOf(url.pathname, ent[1]);
  const range = req.headers.get('range');
  const hit = await c.match(key);
  if (hit) return range ? partial(hit, range) : hit;
  if (range) return fetch(req);                               // 영상 일부 요청은 통과 (전체를 받을 때 저장)
  let res;
  try { res = await fetch(url.href, { cache: 'no-cache', credentials: 'same-origin' }); }   // HTTP 캐시의 옛 파일을 새 해시로 저장하지 않게
  catch (err) { return fetch(req); }
  if (res.status === 200 && res.type === 'basic' && !res.headers.get('content-range')) e.waitUntil(c.put(key, res.clone()).catch(() => {}));
  return res;
}
async function partial(res, range) {
  const buf = await res.arrayBuffer(), size = buf.byteLength, m = /^bytes=(\d*)-(\d*)$/i.exec(range.trim());
  const type = res.headers.get('content-type') || 'application/octet-stream';
  if (!m || (!m[1] && !m[2])) return new Response(buf, { status: 200, headers: { 'content-type': type, 'accept-ranges': 'bytes', 'content-length': String(size) } });
  let s, end;
  if (!m[1]) { s = Math.max(0, size - Number(m[2])); end = size - 1; } else { s = Number(m[1]); end = m[2] ? Math.min(Number(m[2]), size - 1) : size - 1; }
  if (s >= size || end < s) return new Response(null, { status: 416, headers: { 'content-range': `bytes */${size}` } });
  return new Response(buf.slice(s, end + 1), { status: 206, headers: { 'content-type': type, 'accept-ranges': 'bytes', 'content-range': `bytes ${s}-${end}/${size}`, 'content-length': String(end - s + 1) } });
}
