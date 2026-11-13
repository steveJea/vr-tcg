// VR 기기 캐시 (서비스 워커). 같은 사이트의 정적 자산(js·css·data·img·audio·video)만 저장.
// - /asset-manifest.json 의 내용 해시로 버전 관리: 파일이 바뀌면 해시가 바뀌어 새로 받고, 옛것은 정리
// - 페이지(html)·로그인/OAuth 이동·Supabase/API·다른 사이트 요청·GET 아닌 요청은 건드리지 않음 (그냥 통과)
// - 목록을 못 받으면(없음·오프라인 첫 실행) 전부 통과
const CACHE = 'vr-assets-v1', META = 'vr-assets-meta', MANIFEST = '/asset-manifest.json';
const SCOPE = /^\/(js|css|data|img|audio|video)\//;
let man = null, manAt = 0, manP = null, cleanedV = null;

// 목록 새로 받기 (뒤에서). 그림 요청은 이걸 기다리지 않음.
async function loadManifest(force) {
  if (!force && Date.now() - manAt < 60000) return man;
  if (manP) return manP;
  manP = (async () => {
    try {
      const r = await fetch(MANIFEST, { cache: 'no-cache', credentials: 'same-origin' });
      if (r.ok) {
        const m = await r.json();
        if (m && m.files) { man = m; manAt = Date.now(); (await caches.open(META)).put(MANIFEST, new Response(JSON.stringify(m), { headers: { 'content-type': 'application/json' } })).catch(() => {}); }
      } else if (r.status === 404) { man = null; manAt = Date.now(); }   // 목록이 없는 배포 → 캐시 안 씀
    } catch { manAt = Math.max(manAt, Date.now() - 45000); } finally { manP = null; }   // 오프라인: 15초 뒤 다시
    if (man && man.v !== cleanedV) { cleanedV = man.v; cleanup(man).catch(() => {}); }
    return man;
  })();
  return manP;
}
// 그림 요청용 목록: 있는 것(메모리 → 기기에 저장한 사본)을 바로 쓰고, 오래됐으면 뒤에서만 새로.
// 서비스 워커가 막 다시 켜졌을 때도 네트워크를 기다리지 않음 (사본도 없으면 이번 요청은 그냥 통과).
// 예외: 페이지를 막 연 순간(새 배포일 수 있음)엔 새 목록을 최대 1.5초 기다림 → 새 html 에 옛 js 가 섞이지 않게. 전투 중엔 해당 없음.
let metaP = null, navP = null;
async function manifestNow(e) {
  if (navP) await Promise.race([navP, new Promise(r => setTimeout(r, 1500))]).catch(() => {});
  if (!man && !manAt) {
    metaP = metaP || (async () => { try { const r = await (await caches.open(META)).match(MANIFEST); if (r && !man) { man = await r.json(); manAt = 1; } } catch {} })();
    await metaP;
  }
  if (Date.now() - manAt > 60000) { const p = loadManifest(false).catch(() => {}); try { e.waitUntil(p); } catch {} }
  return man;
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
  if (req.mode === 'navigate') { const p = navP = loadManifest(true).finally(() => { if (navP === p) navP = null; }); e.waitUntil(p); return; }   // 페이지·OAuth 이동은 그대로, 목록만 새로   // 페이지·OAuth 이동은 그대로, 목록만 새로
  if (!SCOPE.test(url.pathname)) return;
  if (req.headers.get('x-vr-prefetch')) return;            // 화면 쪽 미리 받기: 직접 기기 캐시에 넣으니 여기선 통과
  e.respondWith(handle(e, req, url));
});

// 기기 캐시에 있으면 바로. 없으면 원래 요청 그대로(브라우저 HTTP 캐시·우선순위 그대로) 보내고,
// 받은 내용의 해시가 목록과 같을 때만 뒤에서 저장 (HTTP 캐시의 옛 파일이 새 해시로 저장되지 않게). 첫 요청을 절대 늦추지 않음.
async function handle(e, req, url) {
  const m = await manifestNow(e);
  let path; try { path = decodeURIComponent(url.pathname); } catch { return fetch(req); }
  const ent = m && (m.files[path] || m.files[url.pathname]);
  if (!ent) return fetch(req);
  const key = keyOf(url.pathname, ent[1]), range = req.headers.get('range');
  let hit; try { hit = await (await caches.open(CACHE)).match(key); } catch {}
  if (hit) return range ? partial(hit, range) : hit;
  const res = await fetch(req);
  if (!range && res.status === 200 && res.type === 'basic' && !res.headers.get('content-range')) e.waitUntil(store(key, res.clone(), ent).catch(() => {}));
  return res;
}
async function store(key, res, ent) {
  const buf = await res.arrayBuffer();
  if (buf.byteLength !== ent[0]) return;
  const h = [...new Uint8Array(await crypto.subtle.digest('SHA-256', buf))].slice(0, 4).map(b => b.toString(16).padStart(2, '0')).join('');
  if (h !== ent[1]) return;
  await (await caches.open(CACHE)).put(key, new Response(buf, { status: 200, headers: res.headers }));
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
