// ===== 전체 알림 📢 (UR·MR·LR 획득) — 서버: supabase/global_notice.sql =====
// 로그인·앱 시작, 홈이 다시 보일 때, 화면 이동 때, 탭이 다시 보이거나 창이 포커스될 때(60초에 한 번)만 새 소식을 확인.
// 안 본 소식이 있으면 나팔에 빨간 점. 창을 열면 점을 지우고 마지막 id를 localStorage에 기억.
// 일반 소식은 토스트를 띄우지 않음. SQL 전(함수 없음)이면 조용히 멈춤.
(() => {
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const SRC = { daily: '일일 영입', ticket: '영입권', merge: '합성', event: '이벤트', premium: '프리미엄 영입' };
  const SEEN_KEY = u => `vrGnSeen:${u}`;
  const FOCUS_GAP = 60000, NAV_GAP = 2000;
  let last = null, off = false, list = [], unseen = false, uid = null, seen = 0, lastPollAt = 0, inFlight = false, homeHooked = false;
  const cardName = id => (window.VRStory?.api?.card?.(id) || window.TCG?.cardById?.(id))?.name || '인재';
  const ago = t => { const s = Math.max(0, (Date.now() - new Date(t)) / 1000); return s < 60 ? '방금' : s < 3600 ? `${Math.floor(s / 60)}분 전` : s < 86400 ? `${Math.floor(s / 3600)}시간 전` : `${Math.floor(s / 86400)}일 전`; };
  const loadSeen = u => { try { return Math.max(0, +localStorage.getItem(SEEN_KEY(u)) || 0); } catch { return 0; } };
  const saveSeen = (u, id) => { try { if (u && id) localStorage.setItem(SEEN_KEY(u), String(id)); } catch {} };
  async function rpc(fn, args) {
    const mk = window.__NOTICE_MOCK; if (mk) return mk(fn, args);
    const sb = window.VRCloud?.sb; if (!sb || !window.VRCloud?.user) return null;
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) { if (/schema cache|Could not find the function|does not exist|PGRST202/.test(`${error.code} ${error.message}`)) off = true; return null; }
    return data;
  }
  const nameBtn = n => n.me ? `<b class="gn-nick me">${esc(n.nick)}</b>` : `<button class="gn-nick" data-gn-uid="${esc(n.uid)}" data-gn-nick="${esc(n.nick)}" title="지정 거래 제안">${esc(n.nick)}</button>`;
  const line = n => `${nameBtn(n)}님이 <em class="gn-g g-${esc(n.grade)}">${esc(n.grade)}</em> <b>${esc(cardName(n.card_id))}</b> 획득!`;
  function direct(id, nick) {
    document.querySelector('.gn-log')?.remove();
    if (!window.VRTrade?.direct) return;
    window.VRTrade.direct({ id, nick });
  }
  function bindNames(root) { root.querySelectorAll('[data-gn-uid]').forEach(b => b.onclick = e => { e.stopPropagation(); direct(b.dataset.gnUid, b.dataset.gnNick); }); }
  function badge() {
    const b = document.getElementById('gn-btn'); if (!b) return;
    b.removeAttribute('data-n');
    if (unseen) b.dataset.unread = '1'; else delete b.dataset.unread;
  }
  function markSeen() {
    unseen = false; badge();
    if (uid && last) { seen = last; saveSeen(uid, last); }
  }
  async function poll() {
    if (off || inFlight) return;
    if (!window.VRCloud?.user && !window.__NOTICE_MOCK) return;
    inFlight = true; lastPollAt = Date.now();
    try {
      const r = await rpc('global_notice_list', { p_limit: 50 }); if (!r?.notices) return;
      const fresh = r.notices;
      last = Math.max(last || 0, seen, ...fresh.map(x => x.id));
      const have = new Set(list.map(x => x.id));
      list = [...fresh.filter(x => !have.has(x.id)), ...list].slice(0, 50);
      unseen = list.some(x => !x.me && x.id > seen); badge();
    } finally { inFlight = false; }
  }
  function check(kind) {
    if (off) return;
    if ((kind === 'focus' || kind === 'visible') && document.hidden) return;
    const now = Date.now(), gap = (kind === 'focus' || kind === 'visible') ? FOCUS_GAP : (kind === 'start' || kind === 'gacha') ? 0 : NAV_GAP;
    if (gap && now - lastPollAt < gap) return;
    return poll();
  }
  function openLog() {
    document.querySelector('.gn-log')?.remove(); markSeen();
    const m = document.createElement('div'); m.className = 'gn-log';
    m.innerHTML = `<div class="gn-panel" role="dialog" aria-label="전체 소식"><div class="gn-head"><b>📢 전체 소식</b><small>UR↑ 획득</small><button class="gn-x" aria-label="닫기">✕</button></div>
      <div class="gn-list">${list.length ? list.map(n => `<div class="gn-row"><img src="${cardThumb(esc(n.card_id))}" alt="" loading="lazy"><div><span>${line(n)}</span><small>${esc(SRC[n.src] || n.src || '')} · ${ago(n.created_at)}</small></div></div>`).join('') : '<div class="gn-empty">ℹ️ 소식 없음</div>'}</div></div>`;
    m.onclick = e => { if (e.target === m || e.target.closest('.gn-x')) m.remove(); };
    bindNames(m); document.body.appendChild(m);
  }
  function mountBtn() {
    if (document.getElementById('gn-btn')) return;
    const b = document.createElement('button'); b.id = 'gn-btn'; b.type = 'button'; b.title = '전체 소식'; b.setAttribute('aria-label', '전체 소식'); b.textContent = '📢';
    b.onclick = openLog; document.body.appendChild(b);
  }
  function hookHome() {
    if (homeHooked) return;
    const scr = document.getElementById('start-screen'); if (!scr || typeof MutationObserver !== 'function') return;
    homeHooked = true;
    let was = !scr.classList.contains('hidden');
    new MutationObserver(() => {
      const vis = !scr.classList.contains('hidden');
      if (vis && !was) check('home');
      was = vis;
    }).observe(scr, { attributes: true, attributeFilter: ['class'] });
  }
  function start() {
    const u = window.VRCloud?.user?.id || (window.__NOTICE_MOCK ? 'mock' : null);
    if (u === uid) return; uid = u; last = null; list = []; unseen = false; lastPollAt = 0;
    if (!u) { document.getElementById('gn-btn')?.remove(); document.querySelector('.gn-log')?.remove(); return; }
    seen = loadSeen(u); hookHome(); mountBtn(); badge(); check('start');
  }
  window.addEventListener('vr:gacha', () => { check('gacha'); setTimeout(() => check('gacha'), 1500); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check('visible'); });
  window.addEventListener('focus', () => check('focus'));
  window.addEventListener('hashchange', () => check('nav'));
  window.addEventListener('vr:user', start); setTimeout(start, 2000);
  hookHome();
  window.VRNotice = { open: openLog, poll, check, start, _list: () => list, _unseen: () => unseen, _seen: () => seen, _lastPollAt: () => lastPollAt, _setLastPollAt: t => { lastPollAt = t; } };
})();
