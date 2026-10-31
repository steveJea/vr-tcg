// ===== 심연석 🔮 (유료 재화) — 서버: supabase/gem.sql =====
// 화면: 상단 재화 칩(VRPlayer.chip 에 붙음) · 탭하면 팝업(잔액 · + 충전 준비 중 · 간단 상점) · 바깥 누르면 닫힘
// 사용처: 카드 뽑기(소환권 1장 150 / 10회 1500) · 행동력 충전 · PvP 추가 도전 · 골드 10,000 (가격은 서버 gem_shop 이 기준)
// SQL 실행 전이거나 비로그인이면 칩·버튼이 안 보임
(() => {
  const ICON = '🔮', NAME = '심연석';
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, at = 0, pending = null, off = false;
  async function rpc(name, args) {
    const m = window.__GEM_MOCK; if (m) return m(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const ERR = { 'not enough gem': `${ICON} ${NAME}이 부족해요`, 'daily limit': '오늘은 더 살 수 없어요', 'stamina full': '🔋 행동력이 가득해요', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const REASON = { chapter_clear: '챕터 첫 클리어', login_7: '7일 연속 접속', pvp_tier: 'PvP 시즌 보상', pvp_streak: 'PvP 10연승', admin: '운영 지급', iap: '충전', refund: '환불',
    'buy:ticket': '소환권 1장', 'buy:pull10': '소환권 10장', 'buy:stamina': '행동력 충전', 'buy:pvp_try': 'PvP 추가 도전', 'buy:gold10k': '골드 10,000' };
  const ITEM = { ticket: ['🎟️', '×1'], pull10: ['🎟️', '×10'], stamina: ['🔋', 'MAX'], pvp_try: ['⚔️', '+1'], gold10k: ['🪙', '10,000'] };
  function set(s) {
    if (!s || !s.ok) return cache;
    cache = s; at = Date.now();
    for (const g of s.granted || []) toast(`${ICON} +${g.gem} · ${g.reason === 'chapter_clear' ? `챕터 ${g.chapter} 첫 클리어` : g.reason === 'login_7' ? `${g.streak}일 연속 접속` : REASON[g.reason] || ''}`);
    paint(); return cache;
  }
  async function status(force = false) {
    if (off) return null;
    if (!force && cache && Date.now() - at < 60000) return cache;
    if (!pending) pending = rpc('gem_status').then(set).catch(e => { console.warn('[gem]', e?.message); return null; }).finally(() => { pending = null; });
    return pending;
  }
  const item = k => cache?.shop?.find(s => s.item === k) || null;
  /** 구매. 성공하면 서버 응답(잔액·지급 결과), 실패하면 토스트 후 null */
  async function buy(key, league, mode) {
    try { const r = await rpc('gem_buy', { p_item: key, p_league: league ?? null, p_mode: mode ?? null }); if (!r) throw new Error('offline'); set({ ...r, granted: [] });
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (r.stamina != null) window.VRPlayer?.status?.(true);
      return r; }
    catch (e) { toast(errText(e)); return null; }
  }
  /** 상단 칩 (값을 모르면 빈 문자열, 처음 호출 때 불러옴) */
  function chip() {
    if (!cache) { if (!pending && !off && window.VRCloud?.user || window.__GEM_MOCK) status(); return ''; }
    return `<button type="button" class="gem-chip" data-gem-open title="${NAME}" aria-label="${NAME} ${n(cache.gem)}"><span class="gem-ic">${ICON}</span><b>${n(cache.gem)}</b><i>+</i></button>`;
  }
  function paint() { document.querySelectorAll('[data-vr-gem]').forEach(e => { e.innerHTML = chip(); }); window.VRPlayer?.paint?.(); }
  /** 가격 버튼 HTML (상품 정보가 없으면 빈 문자열) */
  const priceBtn = (k, cls = '', label = '') => { const s = item(k); if (!s) return ''; const [ic, q] = ITEM[k] || ['', ''];
    return `<button type="button" class="gem-buy ${cls}" data-gem-buy="${k}" ${s.left === 0 ? 'disabled' : ''}><span class="gem-buy-get">${label || `${ic}<b>${q}</b>`}</span><span class="gem-buy-p">${ICON}${n(s.price)}</span>${s.left != null ? `<small>${s.left}</small>` : ''}</button>`; };
  function open() {
    document.querySelector('.gem-pop')?.remove();
    const m = document.createElement('div'); m.className = 'gem-pop';
    const draw = () => { m.innerHTML = `<div class="gem-panel" role="dialog" aria-label="${NAME}"><button class="gem-x" data-x aria-label="닫기">✕</button>
      <div class="gem-big"><span class="gem-orb">${ICON}</span><b>${n(cache?.gem)}</b></div>
      <div class="gem-split">무료 ${n(cache?.free)} · 유료 ${n(cache?.paid)}</div>
      <button type="button" class="gem-charge" data-charge>＋ 충전</button><div class="gem-soon" hidden>💳 충전은 준비 중이에요</div>
      <div class="gem-shop">${['stamina', 'gold10k', 'ticket'].map(k => priceBtn(k)).join('')}</div>
      ${window.VRDrink?.html?.() || ''}
      <div class="gem-how">🗺️ 챕터 첫 클리어 +50 · 📅 7일 연속 +30 · ⚔️ PvP 시즌 보상</div></div>`;
      m.querySelector('[data-charge]').onclick = () => { m.querySelector('.gem-soon').hidden = false; };
      m.querySelectorAll('[data-gem-buy]').forEach(b => b.onclick = async () => { b.disabled = true; const r = await buy(b.dataset.gemBuy); if (r) toast(`${ITEM[r.item]?.[0] || ''} ${REASON['buy:' + r.item] || ''} 완료`); if (m.isConnected) draw(); });
      window.VRDrink?.bind?.(m, draw);
    };
    draw();
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) m.remove(); });   // 바깥 누르면 닫힘
    document.body.appendChild(m);
    Promise.all([status(true), window.VRDrink?.status?.()]).then(() => { if (m.isConnected) draw(); });
  }
  document.addEventListener('click', e => { if (e.target.closest('[data-gem-open]')) { e.preventDefault(); e.stopPropagation(); open(); } }, true);
  /** 마이페이지: 잔액 + 최근 20건 */
  function section(s = cache) {
    if (!s) return '';
    const fmt = t => { const d = new Date(t); return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };
    return `<div class="gem-mp"><button type="button" class="gem-mp-top" data-gem-open><span class="gem-orb">${ICON}</span><b>${n(s.gem)}</b><small>무료 ${n(s.free)} · 유료 ${n(s.paid)}</small></button>
      </div>`;
  }
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  window.VRGem = { ICON, NAME, status, buy, chip, open, item, priceBtn, section, toast, get now() { return cache; }, _reset() { cache = null; at = 0; off = false; } };
})();
