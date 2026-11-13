// ===== 리소스 불러오기: 첫 화면 로딩 · 기기 캐시(sw.js) 등록 · 한가할 때 미리 받기 · 설정 '전체 리소스 받기 / 캐시 삭제' =====
// 기기 캐시 키: <경로>?h=<내용 해시> (asset-manifest.json). sw.js 와 같은 규칙.
(() => {
  const CACHE = 'vr-assets-v1', MANIFEST = '/asset-manifest.json';
  const $ = id => document.getElementById(id);
  const MB = n => n >= 1048576 * 10 ? Math.round(n / 1048576) : Math.max(0.1, +(n / 1048576).toFixed(1));
  const hasCache = 'caches' in window && window.isSecureContext;
  const swOff = (() => { try { return localStorage.getItem('vrNoSW') === '1'; } catch { return false; } })();

  // ---------- 1) 첫 화면 로딩 ----------
  // 화면에 바로 쓰는 그림(메인 UI·공통 UI)과 내 덱 카드 썸네일만 기다림. 최대 8초면 그냥 들어감.
  const boot = $('vr-boot'), bar = boot?.querySelector('.vb-bar i'), pctEl = boot?.querySelector('.vb-pct');
  const t0 = performance.now(); let loaded = document.readyState === 'complete', extras = [], extrasDone = 0, finished = false;
  function deckThumbs() {
    const ids = new Set();
    try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (!/^vrTcgPick:/.test(k)) continue; const v = JSON.parse(localStorage.getItem(k) || '[]'); (Array.isArray(v) ? v : []).forEach(x => { const id = typeof x === 'object' ? x?.id : x; if (/^\d{3,6}$/.test(String(id))) ids.add(String(id)); }); } } catch {}
    return [...ids].slice(0, 15).map(id => `img/thumb/${id}.webp`);
  }
  function preload(src) { return new Promise(r => { const im = new Image(); im.decoding = 'async'; im.onload = im.onerror = () => { extrasDone++; r(); }; im.src = src; }); }
  function eagerImgs() { return [...document.images].filter(i => i.loading !== 'lazy' && (i.getAttribute('src') || i.currentSrc)); }
  function finish(why) {
    if (finished) return; finished = true;
    window.VRBoot = { ms: Math.round(performance.now() - t0), why };
    if (!boot) return; if (bar) bar.style.width = '100%'; if (pctEl) pctEl.textContent = '100%';
    boot.classList.add('vb-out'); setTimeout(() => boot.remove(), 350);
    document.dispatchEvent(new CustomEvent('vr-boot-done', { detail: window.VRBoot }));
  }
  if (boot) {
    extras = deckThumbs(); Promise.all(extras.map(preload));
    addEventListener('load', () => { loaded = true; }, { once: true });
    const tick = () => {
      if (finished) return;
      const imgs = eagerImgs(), done = imgs.filter(i => i.complete).length;
      const total = imgs.length + extras.length || 1;
      let p = (done + extrasDone) / total; if (!loaded) p = Math.min(p, 0.92);
      const shown = Math.round(Math.max(p, Math.min(0.9, (performance.now() - t0) / 8000)) * 100);
      if (bar) bar.style.width = shown + '%'; if (pctEl) pctEl.textContent = shown + '%';
      if (loaded && extrasDone >= extras.length) return finish('ready');
      if (performance.now() - t0 > 8000) return finish('timeout');
      setTimeout(tick, 100);
    };
    tick();
  } else finish('none');

  // ---------- 2) 기기 캐시 등록 ----------
  async function registerSW() {
    if (!('serviceWorker' in navigator) || !window.isSecureContext) return null;
    try {
      if (swOff) { for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister(); return null; }
      return await navigator.serviceWorker.register('/sw.js', { scope: '/' });
    } catch { return null; }
  }

  // ---------- 자산 목록 · 캐시 상태 ----------
  let manP = null;
  function manifest(force) {
    if (!manP || force) manP = fetch(MANIFEST, { cache: 'no-cache' }).then(r => r.ok ? r.json() : null).catch(() => null);
    return manP;
  }
  const keyUrl = (p, h) => new URL(p, location.origin).pathname + '?h=' + h;
  async function cachedKeys() {
    if (!hasCache) return new Set();
    const c = await caches.open(CACHE), s = new Set();
    for (const r of await c.keys()) { const u = new URL(r.url); s.add(u.pathname + u.search); }
    return s;
  }
  async function status() {
    const m = await manifest(); if (!m) return null;
    const have = await cachedKeys(); let haveB = 0, needB = 0, need = [];
    for (const [p, [sz, h]] of Object.entries(m.files)) { if (have.has(keyUrl(p, h))) haveB += sz; else { needB += sz; need.push([p, sz, h]); } }
    return { m, total: m.total, haveB, needB, need };
  }
  // 한 파일 받아서 기기 캐시에 넣기 (HTTP 캐시의 옛 파일 말고 서버 확인 후)
  async function save(c, p, h, signal, prio) {
    const res = await fetch(p, { cache: 'no-cache', credentials: 'same-origin', signal, priority: prio });
    if (res.status !== 200) throw Error('HTTP ' + res.status);
    await c.put(keyUrl(p, h), res);
  }
  const waitVisible = () => document.hidden ? new Promise(r => document.addEventListener('visibilitychange', function f() { if (!document.hidden) { document.removeEventListener('visibilitychange', f); r(); } })) : null;
  const inBattle = () => { const g = $('game'); return !!g && !g.classList.contains('hidden') && g.getClientRects().length > 0; };
  const idle = () => new Promise(r => (window.requestIdleCallback || (f => setTimeout(f, 200)))(() => r(), { timeout: 3000 }));

  // ---------- 3) 한가할 때 조금씩 미리 받기 ----------
  const BG_ORDER = ['/img/ui/', '/css/', '/js/', '/img/effects/', '/data/event/', '/img/thumb/', '/img/bt_img/', '/data/fx/', '/img/battle/', '/data/voice/'];
  const BG_BUDGET = 80 * 1048576, BG_MAX_FILE = 6 * 1048576;
  let bgStop = false, fullRunning = null;
  function slowNet() { const c = navigator.connection; return !!c && (c.saveData || /(^|-)2g|3g/.test(c.effectiveType || '')); }
  async function background() {
    if (!hasCache || swOff || slowNet() || window.__VR_NO_PREFETCH) return;
    const st = await status(); if (!st) return;
    const rank = p => { const i = BG_ORDER.findIndex(x => p.startsWith(x)); return i < 0 ? 99 : i; };
    const list = st.need.filter(([p, sz]) => rank(p) < 99 && sz <= BG_MAX_FILE).sort((a, b) => rank(a[0]) - rank(b[0]) || a[0].localeCompare(b[0]));
    const c = await caches.open(CACHE); let used = 0, i = 0;
    const worker = async () => {
      while (!bgStop && i < list.length && used < BG_BUDGET) {
        if (fullRunning) return;
        await waitVisible(); while (inBattle() && !bgStop) await new Promise(r => setTimeout(r, 5000));
        if (slowNet()) return;
        await idle();
        const [p, sz, h] = list[i++]; used += sz;
        try { await save(c, p, h, undefined, 'low'); } catch {}
      }
    };
    await Promise.all([worker(), worker()]);   // 동시에 2개까지만
    window.VRAssets.bgDone = { files: i, bytes: used };
  }

  // ---------- 4) 전체 리소스 받기 ----------
  async function downloadAll(onProgress) {
    if (!hasCache) throw Error('이 브라우저는 저장을 지원하지 않아요');
    const st = await status(); if (!st) throw Error('목록을 못 불러왔어요');
    try { await navigator.storage?.persist?.(); } catch {}
    const ctl = new AbortController(), c = await caches.open(CACHE);
    const list = st.need.slice(); let doneB = 0, fail = 0, i = 0; const totalB = st.needB;
    const job = { cancel: () => ctl.abort(), signal: ctl.signal };
    fullRunning = job;
    const worker = async () => {
      while (i < list.length && !ctl.signal.aborted) {
        await waitVisible();
        const [p, sz, h] = list[i++];
        try { await save(c, p, h, ctl.signal); } catch (e) { if (ctl.signal.aborted) return; fail++; }
        doneB += sz; onProgress?.(doneB, totalB, i, list.length);
      }
    };
    job.done = Promise.all([0, 1, 2, 3].map(worker)).then(() => ({ cancelled: ctl.signal.aborted, fail, doneB, totalB })).finally(() => { fullRunning = null; });
    return job;
  }
  async function clear() { bgStop = true; fullRunning?.cancel(); if (hasCache) await caches.delete(CACHE); }

  // ---------- 설정 화면 ----------
  const toast = t => (window.VRGem?.toast || (x => console.log(x)))(t);
  const ask = (html, y, n) => window.VRConfirm ? window.VRConfirm(html, { y, n, cls: 'vc-guest' }) : Promise.resolve(confirm(html.replace(/<[^>]+>/g, ' ')));
  async function paint() {
    const sum = $('as-sum'), have = $('as-have'), dl = $('as-dl'); if (!sum) return;
    if (!hasCache) { sum.textContent = '이 브라우저에선 못 써요'; dl.disabled = true; $('as-clear').disabled = true; return; }
    const st = await status().catch(() => null);
    if (!st) { sum.textContent = '목록을 못 불러왔어요'; return; }
    sum.textContent = st.needB > 0 ? `약 ${MB(st.needB)}MB · 와이파이 권장` : '다 받았어요!';
    have.textContent = `기기에 약 ${MB(st.haveB)}MB 저장됨`;
    if (!fullRunning) dl.disabled = st.needB <= 0;
  }
  function bindSettings() {
    const dl = $('as-dl'), cancel = $('as-cancel'), prog = $('as-prog'); if (!dl) return;
    $('main-settings-open')?.addEventListener('click', () => setTimeout(paint, 0));
    dl.onclick = async () => {
      const st = await status().catch(() => null); if (!st || st.needB <= 0) return paint();
      const ok = await ask(`<b class="vc-guest-h">게임 리소스를 전부 받아 둘까요?</b><span class="vc-guest-s">약 ${MB(st.needB)}MB예요. 데이터가 많이 드니 와이파이에서 받는 걸 추천해요. 받는 중에도 게임은 할 수 있어요!</span>`, '받기', '다음에');
      if (!ok) return;
      dl.disabled = true; prog.hidden = false; const fill = prog.querySelector('.as-bar i'), txt = prog.querySelector('.as-txt');
      const job = await downloadAll((d, t, n, all) => { const p = t ? Math.min(100, Math.floor(d / t * 100)) : 100; fill.style.width = p + '%'; txt.textContent = `${p}% · ${MB(d)} / ${MB(t)}MB (${n}/${all})`; });
      cancel.onclick = () => job.cancel();
      const r = await job.done;
      prog.hidden = true; fill.style.width = '0%';
      toast(r.cancelled ? '받기를 멈췄어요. 받은 건 그대로 남아 있어요' : r.fail ? `거의 다 받았어요! (${r.fail}개는 다음에 다시 받을게요)` : '전부 받았어요! 이제 더 빨리 열려요');
      paint();
    };
    $('as-clear').onclick = async () => {
      if (!await ask('<b class="vc-guest-h">기기에 저장한 게임 리소스를 지울까요?</b><span class="vc-guest-s">게임 기록은 안 지워져요. 다음에 열 때 다시 받아요.</span>', '지우기', '그만두기')) return;
      await clear(); toast('캐시를 지웠어요'); paint();
    };
  }

  window.VRAssets = { status, downloadAll, clear, background, manifest, paint, CACHE, keyUrl, get running() { return !!fullRunning; } };
  const start = async () => {
    bindSettings();
    await registerSW();
    // 들어간 뒤 잠깐 쉬었다가, 한가할 때만 조금씩
    setTimeout(() => background().catch(() => {}), window.__VR_PREFETCH_DELAY ?? 6000);
  };
  const go = () => document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', start, { once: true }) : start();
  if (finished) go(); else document.addEventListener('vr-boot-done', go, { once: true });
})();
