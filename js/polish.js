// ===== 앱 같은 손맛: 팝업 열림·화면 전환 애니메이션 + 짧은 진동 (게임 로직 건드리지 않음 · css/polish.css) =====
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const HAP_KEY = 'vrHaptic';
  const hapOn = () => localStorage.getItem(HAP_KEY) !== '0';
  // --- 진동: 버튼 누를 때 8ms (지원 기기만 · 전투 화면 #game 안은 제외 · 설정에서 끔) ---
  document.addEventListener('pointerdown', e => {
    if (!hapOn() || !navigator.vibrate) return;
    const b = e.target.closest('button, [role="button"], .main-tile, [data-go]');
    if (!b || b.disabled || b.closest('#game')) return;
    try { navigator.vibrate(8); } catch {}
  }, { passive: true });
  const tg = document.getElementById('main-haptic');
  const paint = () => { if (!tg) return; const on = hapOn(); tg.textContent = on ? 'ON' : 'OFF'; tg.classList.toggle('on', on); tg.setAttribute('aria-checked', String(on)); };
  if (tg) { tg.onclick = () => { localStorage.setItem(HAP_KEY, hapOn() ? '0' : '1'); paint(); if (hapOn()) try { navigator.vibrate?.(15); } catch {} }; paint(); }
  if (reduce) return;
  const replay = (el, cls) => { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); setTimeout(() => el.classList.remove(cls), 260); };
  // --- 팝업: 숨김(hidden) → 보임 으로 바뀔 때만 (같은 팝업 다시 그리기는 애니메이션 없음) ---
  const POPS = ['story-pop', 'vr-confirm', 'main-menu-pop'];
  const watchPop = el => new MutationObserver(rs => {
    const wasHidden = String(rs[0].oldValue || '').split(/\s+/).includes('hidden');
    if (wasHidden && !el.classList.contains('hidden')) replay(el, 'ui-pop-in');
  }).observe(el, { attributes: true, attributeFilter: ['class'], attributeOldValue: true });
  const seen = new WeakSet();
  const hook = () => { for (const id of POPS) { const el = document.getElementById(id); if (el && !seen.has(el)) { seen.add(el); watchPop(el); } } };
  hook();
  // 새로 붙는 팝업 층 (PvP·조직 등 modal 을 새로 만드는 곳) + story-pop 첫 생성
  new MutationObserver(rs => { for (const r of rs) for (const n of r.addedNodes) {
    if (n.nodeType !== 1) continue;
    if (POPS.includes(n.id)) { hook(); if (!n.classList.contains('hidden')) replay(n, 'ui-pop-in'); }
    else if (n.matches?.('.pvp-modal, .gd-pop, .gd-ov, .mp-modal, .gal-modal')) replay(n, 'ui-pop-in');
  } }).observe(document.body, { childList: true });
  // --- 스토리 화면 전환: 제목이 바뀔 때만 살짝 페이드 (정렬·필터로 다시 그릴 땐 그대로) ---
  const sr = document.getElementById('story-screen');
  if (sr) { let last = ''; new MutationObserver(() => {
    const t = sr.querySelector('.story-top-title')?.textContent || sr.firstElementChild?.className || '';
    if (t === last) return; last = t; const w = sr.firstElementChild; if (w) replay(w, 'ui-screen-in');
  }).observe(sr, { childList: true }); }
})();
