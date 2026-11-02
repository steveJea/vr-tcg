// ===== 페이지 시스템 (뼈대): 팝업 메뉴를 하나씩 "페이지"로 옮기기 위한 공용 틀 =====
// - VRPages.register(name, { title, render(body, params, page) }) · VRPages.open(name, params) · VRPages.back()
// - 주소 #/이름 + 브라우저 기록 → 폰 뒤로가기·← 버튼 = 이전 페이지. 로비에서 뒤로가기 = '나갈까요?'
// - 전투 중·영상 재생 중엔 뒤로가기 무시. 구글 로그인 복귀 주소(?code= · access_token)는 건드리지 않음
// - 공용 머리말: ← · 제목 · 재화 칩(행동력·심연석). 들어갈 때 오른쪽에서, 뒤로 갈 때 왼쪽으로 (css/pages.css · 동작 줄이기면 없음)
(() => {
  const REG = {}, stack = [];   // stack: 열린 페이지 [{ name, params }]
  let el = null, guardOn = false, shown = null;   // shown: 지금 그려진 페이지 (떠날 때 leave 호출)
  const reduce = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  const oauth = () => /[?&]code=|access_token=/.test(location.search + location.hash);
  const busy = () => { const g = document.getElementById('game'); return (g && !g.classList.contains('hidden')) || !!document.querySelector('.story-vcut, .story-ovp, #story-video') || !!window.__storyVideo?.el?.isConnected; };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

  function mount() {
    if (el?.isConnected) return el;
    el = document.createElement('div'); el.id = 'vr-page'; el.className = 'vr-page hidden'; el.setAttribute('role', 'dialog');
    el.innerHTML = `<header class="vr-page-head"><button type="button" class="vr-page-back" aria-label="뒤로">←</button><h2 class="vr-page-title"></h2><div class="vr-page-cur"><span data-vr-player></span><span class="vr-page-gem"></span></div></header><div class="vr-page-body"></div>`;
    el.querySelector('.vr-page-back').onclick = () => { if (!closeTopOverlay()) back(); };
    document.body.appendChild(el); return el;
  }
  function paintCur() { if (!el) return; try { window.VRPlayer?.paint?.(); } catch {} const g = el.querySelector('.vr-page-gem'); if (g) g.innerHTML = window.VRGem?.chip?.() || ''; }
  function draw(dir) {
    const top = stack[stack.length - 1];
    if (shown && el) { try { REG[shown.name]?.leave?.(el.querySelector('.vr-page-body'), shown.params || {}); } catch (e) { console.error('[pages] leave', e); } } shown = top || null;
    document.body.classList.toggle('vr-page-on', !!top);   // 페이지 위에 떠야 하는 팝업(카드 상세·확인창 등) 층 올림 (css/pages.css)
    if (!top) { if (el) { el.classList.add('hidden'); el.querySelector('.vr-page-body').innerHTML = ''; } return; }
    const p = REG[top.name], m = mount(), body = m.querySelector('.vr-page-body');
    m.querySelector('.vr-page-title').textContent = typeof p.title === 'function' ? p.title(top.params) : (p.title || '');
    body.innerHTML = ''; body.scrollTop = 0; m.classList.remove('hidden');
    try { p.render(body, top.params || {}, { close: back, open }); } catch (e) { console.error('[pages]', top.name, e); body.innerHTML = '<div class="vr-page-err">화면을 그리지 못했어요.</div>'; }
    paintCur();
    if (!reduce() && dir) { m.classList.remove('vr-in-r', 'vr-in-l'); void m.offsetWidth; m.classList.add(dir > 0 ? 'vr-in-r' : 'vr-in-l'); setTimeout(() => m.classList.remove('vr-in-r', 'vr-in-l'), 300); }
  }
  /** 페이지 열기: 기록에 한 칸 추가 (같은 페이지 다시 열기 = 내용만 바꿈) */
  function open(name, params = {}) {
    if (!REG[name]) return false;
    const top = stack[stack.length - 1];
    if (top?.name === name) { top.params = params; draw(0); return true; }
    stack.push({ name, params });
    if (!oauth()) history.pushState({ vrPage: name, depth: stack.length }, '', '#/' + name);
    draw(1); return true;
  }
  /** 뒤로: 기록을 한 칸 되돌림 → popstate 에서 화면 정리 */
  function back() { if (stack.length) history.back(); }
  /** 맨 위 작은 창 먼저 닫기 (뒤로가기·← 공통): Y/N 확인(= 아니오) → 확대 → 갤러리 상세 → 카드 상세 → 스토리 팝업 → 음료 확인 → 도움말 팝업. 닫았으면 true */
  const vis = q => { const e = document.querySelector(q); return e && !e.classList.contains('hidden') && getComputedStyle(e).display !== 'none' ? e : null; };
  function closeTopOverlay() {
    let e;
    if ((e = vis('#vr-confirm'))) { (e.querySelector('[data-yn=n]') || e).click(); if (!e.classList.contains('hidden')) e.classList.add('hidden'); return true; }
    if ((e = vis('.drink-ask'))) { (e.querySelector('[data-no]') || e).click(); return true; }
    if ((e = vis('.gal-zoom'))) { e.classList.add('hidden'); return true; }
    if ((e = vis('#detail'))) { e.classList.add('hidden'); e.classList.remove('flex'); e.style.zIndex = ''; return true; }
    if ((e = vis('.gal-detail'))) { e.classList.add('hidden'); return true; }
    if ((e = vis('#story-pop'))) { const x = e.querySelector('[data-close-pop]'); if (x) x.click(); else e.classList.add('hidden'); return true; }
    if ((e = vis('#vr-help'))) { e.remove(); return true; }
    { const g = [...document.querySelectorAll('.gear-pop-bg:not(.vr-in-page)')].pop(); if (g) { g.remove(); return true; } }   // 장비 작은 창 (아이템·문장·교환 등)
    return false;
  }
  /** 바로 닫기 (코드에서 닫을 때: 화면은 즉시 정리하고 기록은 뒤에서 한 칸 되돌림 → 그 popstate 는 무시) */
  let skipPop = 0;
  function closeNow() { if (!stack.length) return; stack.pop(); draw(-1); skipPop++; history.back(); }
  function closeAll() { const n = stack.length; if (n) history.go(-n); }

  // --- 로비 뒤로가기 가드: 로비 상태 위에 빈 칸 하나를 쌓아 두고, 뒤로가기로 그 칸이 빠지면 '나갈까요?' ---
  function armGuard() { if (oauth()) return; history.pushState({ vrGuard: 1 }, '', location.pathname + location.search); guardOn = true; }
  addEventListener('popstate', async e => {
    if (skipPop) { skipPop--; return; }
    const st = e.state || {};
    if (busy()) { history.go(1); return; }   // 전투·영상 중: 뒤로가기 무시 (방금 빠진 칸으로 다시 앞으로)
    const depth = st.vrPage ? (st.depth | 0) : 0;
    if (depth < stack.length && closeTopOverlay()) { const t = stack[stack.length - 1]; history.pushState({ vrPage: t.name, depth: stack.length }, '', '#/' + t.name); return; }   // 페이지 위 작은 창부터 닫고 페이지는 그대로
    if (depth < stack.length) { stack.length = depth; draw(-1); return; }   // 페이지에서 뒤로
    if (st.vrGuard) return;   // 다른 칸으로 이동(앞으로 가기 등)
    // 로비 칸까지 빠짐: 열린 로비 팝업이 있으면 그것만 닫고, 아니면 나갈지 물어봄
    if (closeTopOverlay()) { armGuard(); return; }   // 로비에서도 작은 창(확인창 등) 먼저
    const pops = [...document.querySelectorAll('.main-pop:not(.hidden), #main-menu-pop:not(.hidden)')];
    if (pops.length) { pops.forEach(p => p.classList.add('hidden')); armGuard(); return; }
    const ok = await (window.VRConfirm ? window.VRConfirm('<b>게임을 나갈까요?</b>') : Promise.resolve(confirm('게임을 나갈까요?')));
    if (ok) { guardOn = false; history.back(); } else armGuard();
  });
  // 처음 열 때: 주소에 #/페이지 가 남아 있으면 지움 (새로고침 시 빈 페이지 방지) → 가드 쌓기. 로그인 복귀 중이면 정리 끝난 뒤
  function boot(n = 0) {
    if (oauth()) return n < 40 && setTimeout(() => boot(n + 1), 250);
    if (/^#\//.test(location.hash)) history.replaceState(null, '', location.pathname + location.search);
    armGuard();
  }
  if (document.readyState === 'complete') boot(); else addEventListener('load', () => boot());
  /** 예전 팝업을 그대로 페이지 안에 담기: pop(바탕+판) 을 페이지 몸통으로 옮기고, pop.remove() = 뒤로가기. 실패하면 false → 예전 팝업 */
  function host(name, title, pop, leave) {   // leave: 페이지를 떠날 때 정리 (타이머 등)
    try {
      REG[name] = { title, render: body => { const p = REG[name]._pop; if (p) body.appendChild(p); }, leave };
      REG[name]._pop = pop; pop.classList.add('vr-in-page'); pop.onclick = null;
      const rm = pop.remove.bind(pop);
      pop.remove = () => { if (REG[name]._pop === pop && stack[stack.length - 1]?.name === name) closeNow(); else rm(); };
      return open(name);
    } catch (e) { console.error('[pages] host', e); return false; }
  }
  window.VRPages = { host, closeNow, register: (name, def) => { REG[name] = def; }, open, back, closeAll, get current() { return stack[stack.length - 1]?.name || null; }, get depth() { return stack.length; }, esc };
})();
