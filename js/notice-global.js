// ===== 전체 알림 📢 (UR·MR·LR 획득) — 서버: supabase/global_notice.sql =====
// 5초마다(탭 보일 때) + 뽑기 직후 바로(vr:gacha) 새 알림만 받아 위쪽 토스트 · 📢 버튼/토스트 누르면 소식 창(최근 3일 50개) · 이름 누르면 지정 거래(거래소)
// SQL 전(함수 없음)이면 조용히 멈춤. 전투 중엔 토스트 대신 쌓아 두었다가 소식 창에서 보기
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const SRC = { daily: '일일 영입', ticket: '영입권', merge: '합성', event: '이벤트', premium: '프리미엄 영입' };
  let last = null, off = false, timer = 0, list = [], unseen = 0, uid = null;
  const cardName = id => (window.VRStory?.api?.card?.(id) || window.TCG?.cardById?.(id))?.name || '인재';
  const ago = t => { const s = Math.max(0, (Date.now() - new Date(t)) / 1000); return s < 60 ? '방금' : s < 3600 ? `${Math.floor(s / 60)}분 전` : s < 86400 ? `${Math.floor(s / 3600)}시간 전` : `${Math.floor(s / 86400)}일 전`; };
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
  const busy = () => !!document.querySelector('#game:not(.hidden)') || !!document.getElementById('story-dlg');
  const RANK = { LR: 3, MR: 2, UR: 1 };
  function toast(ns) {
    ns = [].concat(ns); const n = ns.reduce((a, b) => (RANK[b.grade] || 0) > (RANK[a.grade] || 0) ? b : a);
    let host = document.getElementById('gn-toasts');
    if (!host) { host = document.createElement('div'); host.id = 'gn-toasts'; document.body.appendChild(host); }
    const t = document.createElement('div'); t.className = 'gn-toast';
    t.innerHTML = `<img src="${cardThumb(esc(n.card_id))}" alt=""><span>📢 ${ns.length > 1 ? `${nameBtn(n)}님이 ${ns.map(x => `<em class="gn-g g-${esc(x.grade)}">${esc(x.grade)}</em> <b>${esc(cardName(x.card_id))}</b>`).join(', ')} 획득!` : line(n)}</span>`;
    bindNames(t); t.onclick = () => { t.remove(); openLog(); };
    host.appendChild(t); while (host.children.length > 2) host.firstChild.remove();
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 400); }, 6000);
  }
  function badge() { const b = document.getElementById('gn-btn'); if (b) b.dataset.n = unseen > 0 ? (unseen > 9 ? '9+' : unseen) : ''; }
  async function poll() {
    if (off || !window.VRCloud?.user && !window.__NOTICE_MOCK) return;
    const first = last == null;
    const r = await rpc('global_notice_list', { p_after: last, p_limit: 50 }); if (!r?.notices) return;
    const fresh = r.notices; if (!fresh.length) return;
    last = Math.max(last || 0, ...fresh.map(x => x.id));
    const seen = new Set(list.map(x => x.id)); list = [...fresh.filter(x => !seen.has(x.id)), ...list].slice(0, 50);
    if (first) return;   // 처음엔 기록만 (예전 것 토스트 안 함)
    unseen += fresh.filter(x => !x.me).length; badge();
    if (busy()) return;
    // 같은 사람 알림은 한 토스트로 묶기 (10연차 UR 2장 → 1개)
    const g = new Map(); for (const n of [...fresh].reverse()) { const k = n.uid || n.nick; g.has(k) ? g.get(k).push(n) : g.set(k, [n]); }
    [...g.values()].slice(-2).forEach(toast);
  }
  function openLog() {
    document.querySelector('.gn-log')?.remove(); unseen = 0; badge();
    const m = document.createElement('div'); m.className = 'gn-log';
    m.innerHTML = `<div class="gn-panel" role="dialog" aria-label="전체 소식"><div class="gn-head"><b>📢 전체 소식</b><small>UR 이상 획득 · 이름을 누르면 지정 거래</small><button class="gn-x" aria-label="닫기">✕</button></div>
      <div class="gn-list">${list.length ? list.map(n => `<div class="gn-row"><img src="${cardThumb(esc(n.card_id))}" alt="" loading="lazy"><div><span>${line(n)}</span><small>${esc(SRC[n.src] || n.src || '')} · ${ago(n.created_at)}</small></div></div>`).join('') : '<div class="gn-empty">아직 소식이 없어요</div>'}</div></div>`;
    m.onclick = e => { if (e.target === m || e.target.closest('.gn-x')) m.remove(); };
    bindNames(m); document.body.appendChild(m);
  }
  function mountBtn() {
    if (document.getElementById('gn-btn')) return;
    const b = document.createElement('button'); b.id = 'gn-btn'; b.type = 'button'; b.title = '전체 소식'; b.setAttribute('aria-label', '전체 소식'); b.textContent = '📢';
    b.onclick = openLog; document.body.appendChild(b);
  }
  function start() {
    const u = window.VRCloud?.user?.id || (window.__NOTICE_MOCK ? 'mock' : null);
    if (u === uid) return; uid = u; last = null; list = []; unseen = 0; clearInterval(timer);
    if (!u) { document.getElementById('gn-btn')?.remove(); return; }
    mountBtn(); badge(); poll(); timer = setInterval(() => { if (!document.hidden) poll(); }, 5000);
  }
  window.addEventListener('vr:gacha', () => { poll(); setTimeout(poll, 1500); });   // 뽑기 결과 직후 바로 확인
  document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
  window.addEventListener('vr:user', start); setTimeout(start, 2000);
  window.VRNotice = { open: openLog, poll, start, _list: () => list };
})();
