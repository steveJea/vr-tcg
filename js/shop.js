// ===== 상점 (전용 페이지) — 서버: supabase/shop_bm_staging.sql · 심연석 결제는 payments_staging.sql · 드링크는 trade_drink.sql =====
// 상단 재화의 + 가 이 페이지를 연다. 탭: 충전 · 패키지 · 패스 · 소모품 · 스킨(비어 있음).
// KRW 심연석 팩은 테스트 결제가 켜져 있으면 기존 토스 주문을 쓰고, 아니면 shop_buy(테스트 지급).
// 시즌패스(31일)도 테스트 결제가 켜져 있고 payment_sku 가 있으면 토스 주문(seasonpass_31_staging.sql), 아니면 shop_buy.
// 소환권·레벨업 팩은 shop_buy. 드링크는 심연석(무료 우선). 패스 보상은 '오늘 보상 받기' 버튼으로만 받는다(KST 당일, 놓친 날 소급 없음).
(() => {
  const TABS = [['charge', '충전'], ['pack', '패키지'], ['pass', '패스'], ['consume', '소모품'], ['skin', '스킨']];
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist|shop unavailable/i.test(`${e?.code} ${e?.message}`);
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ERR = { 'not enough gem': '심연석이 부족해요', 'monthly limit': '이번 달 구매 횟수를 다 썼어요', 'rate limited': '잠시 후 다시 시도해 주세요', 'invalid item': '없는 상품이에요', 'login required': '로그인이 필요해요', 'shop unavailable': '이 서버에서는 상점을 열 수 없어요' };
  // 상점 BM(shop_bm_staging.sql)은 테스트 서버 전용. 운영에서는 상점 페이지를 열지 않고 예전 심연석 팝업을 쓴다.
  const on = () => !!(window.__SHOP_MOCK || window.VRCloud?.isStaging === true);
  let tab = 'charge', cache = null, host = null, cal = null;
  const toast = t => window.VRGem?.toast?.(t) || 0;
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : (missing(e) ? '🔒 상점' : m.slice(0, 80)); };
  async function rpc(name, args) {
    const m = window.__SHOP_MOCK; if (m) return m(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args || {});
    if (error) throw error;
    return data;
  }
  const ask = t => window.VRAsk ? window.VRAsk(t) : Promise.resolve(confirm(t));
  function gemText(p) {
    const g = p.grant || {}, paid = g.gem_paid | 0, free = g.gem_free | 0, total = paid + free;
    const base = free ? `유료 ${n(paid)} + 보너스 ${n(free)}` : `심연석 ${n(total)}`;
    return p.first_open ? `${base} · 첫 구매 ${n(total * 2)}` : base;
  }
  // 표시 문구만. 지급 내용(grant)은 서버 그대로.
  const PASS_BLURB = {
    pass_2: '즉시 소환권 10 + 매일 소환권 1 (31일 총 41) · 매일 행동력 150, 골드 10,000, 무료 심연석 50',
    pass_3: '즉시 소환권 30 + 유료 심연석 300 · 매일 소환권 1 (31일 총 61) · 매일 무료 심연석 100, 행동력 200, 골드·피·조각 10,000',
  };
  // 토스 테스트 결제: 심연석 충전 + 시즌패스(서버가 payment_sku 를 붙인 경우만). 그 외는 테스트 지급.
  const payable = p => !!(window.VRPayments?.enabled && p.payment_sku && (p.tab === 'charge' || p.tab === 'pass'));
  function card(p) {
    const used = p.month_used | 0, max = p.month_max, left = max == null ? null : Math.max(0, max - used);
    const limit = max == null ? '' : `<p>이번 달 ${used}/${max}</p>`;
    const payOn = payable(p);
    const label = left === 0 ? '이번 달 완료' : (payOn ? `${n(p.price_krw)}원 결제` : `${n(p.price_krw)}원 테스트 지급`);
    const blurb = PASS_BLURB[p.sku] || p.blurb || '';
    const x2 = p.tab === 'charge' && p.first_open ? '<span class="shop-x2">첫 구매 ×2</span>' : '';
    return `<article class="shop-card">${x2}<b>${esc(p.name)}</b><p>${esc(blurb)}</p><p class="shop-price">${n(p.price_krw)}원</p>${p.tab === 'charge' ? `<p class="shop-bonus">${esc(gemText(p))}</p>` : ''}${limit}<button type="button" class="shop-go ${payOn ? '' : 'test'}" data-sku="${esc(p.sku)}" ${left === 0 ? 'disabled' : ''}>${label}</button></article>`;
  }
  const STATE = { active: '진행 중', queued: '대기', ended: '종료' };
  const addDay = (d, k) => new Date(Date.parse(d + 'T00:00:00Z') + k * 864e5).toISOString().slice(0, 10);
  const kstToday = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  // 달력: 서버 shop_pass_days(). SQL 적용 전이면 shop_status 의 claimed_today 만으로 그린다.
  function passList() {
    if (cal?.passes) return { today: cal.today, list: cal.passes };
    const today = kstToday();
    return { today, list: (cache?.passes || []).map(p => ({ ...p, claimed: p.claimed_today ? [today] : [] })) };
  }
  function calendar(p, today) {
    const total = Math.max(1, Math.min(90, Math.round((Date.parse(p.ends_on) - Date.parse(p.starts_on)) / 864e5) + 1));
    const got = new Set(p.claimed || []);
    const cells = Array.from({ length: total }, (_, i) => {
      const d = addDay(p.starts_on, i), done = got.has(d);
      const cls = done ? 'done' : d === today ? 'today' : d < today ? 'miss' : 'future';
      const mark = done ? '✓' : d === today ? '오늘' : d < today ? '–' : '';
      return `<li class="shop-day ${cls}" title="${esc(d)}"><small>${i + 1}</small><span>${mark}</span></li>`;
    }).join('');
    return `<ol class="shop-cal" aria-label="${esc(p.name || p.sku)} ${total}일">${cells}</ol>`;
  }
  function passRows() {
    const { today, list } = passList();
    const rows = list.filter(p => p.state !== 'ended');
    if (!rows.length) return '';
    const names = Object.fromEntries((cache?.products || []).map(x => [x.sku, x.name]));
    const anyOpen = rows.some(p => p.state === 'active' && !(p.claimed || []).includes(today));
    const btn = `<button type="button" class="shop-go shop-claim" data-pass-claim ${anyOpen ? '' : 'disabled'}>${anyOpen ? '오늘 보상 받기' : '오늘 보상 받음'}</button>`;
    return `<h3 class="shop-sub">내 패스</h3>${btn}` + rows.map(p => {
      const got = (p.claimed || []).length, total = Math.round((Date.parse(p.ends_on) - Date.parse(p.starts_on)) / 864e5) + 1;
      return `<div class="shop-pass"><b>${esc(p.name || names[p.sku] || p.sku)}</b> <i>${STATE[p.state] || ''}</i><div>${esc(p.starts_on)} ~ ${esc(p.ends_on)} · ${got}/${total}일 받음</div>${calendar(p, today)}</div>`;
    }).join('') + '<p class="shop-note">✓ 받음 · 오늘 · – 지난 날(소급 지급 없음)</p>';
  }
  async function loadDays() {
    try { const r = await rpc('shop_pass_days'); cal = r?.passes ? r : null; } catch (e) { cal = null; }
  }
  async function refresh(claim) {
    try {
      const r = claim ? await rpc('shop_pass_claim') : await rpc('shop_status');
      if (r?.ok) cache = r;
      if (claim) toast(r?.claimed?.length ? '시즌패스 오늘 보상을 받았어요' : '오늘 받을 보상이 없어요');
      if (claim && r?.claimed?.length) { window.VRGem?.status?.(true); window.VRPlayer?.wallet?.(true); window.VRPlayer?.status?.(true); }
      return r;
    } catch (e) { toast(errText(e)); return null; }
  }
  async function buy(sku) {
    const p = (cache?.products || []).find(x => x.sku === sku); if (!p) return;
    const payOn = payable(p);
    const hint = payOn ? `${p.name}을 ${n(p.price_krw)}원에 결제할까요?` : `${p.name}을 테스트 지급으로 받을까요? ${n(p.price_krw)}원`;
    if (!await ask(hint)) return;
    if (payOn) { await window.VRPayments.checkout({ id: p.payment_sku }); await refresh(false); await loadDays(); return paint(); }
    try {
      const r = await rpc('shop_buy', { p_sku: sku });
      if (r?.ok && p.tab === 'pass') await loadDays();
      if (r?.ok) { cache = r; toast(r.first_bonus ? '첫 구매 2배로 지급했어요' : '지급했어요'); window.VRGem?.status?.(true); window.VRPlayer?.wallet?.(true); window.VRPlayer?.status?.(true); }
    } catch (e) { toast(errText(e)); }
    paint();
  }
  function paint() {
    if (!host) return;
    const list = (cache?.products || []).filter(p => p.tab === tab);
    const note = tab === 'pack' ? '<div class="shop-pack-head"><span class="shop-note">스페셜 소환권 1장 = 스페셜 소환 1회 (인재영입 › 스페셜)</span><button type="button" class="shop-rates" data-sp-rates>확률</button></div>'
      : tab === 'pass' ? '<details class="vr-tip shop-note"><summary>ⓘ 31일 · 재구매 시 +31일</summary><p>매일 아래 ‘오늘 보상 받기’로 받아요 (한국 시간 기준, 놓친 날은 소급되지 않아요). 같은 패스를 다시 사면, 지금 패스가 끝난 다음 날부터 31일이 이어져요.</p></details>' : '';
    const body = tab === 'skin' ? '<div class="shop-empty"><b>🔒 준비 중</b></div>'
      : !cache ? '<div class="shop-err">상점 정보를 불러오지 못했어요.</div>'
      : tab === 'consume' ? '<div data-consume></div>'
      : `${note}<div class="shop-grid">${list.map(card).join('') || '<div class="shop-empty">상품이 없어요.</div>'}</div>${tab === 'pass' ? passRows() : ''}`;
    host.innerHTML = `<div class="shop" data-clarity-mask="true"><div class="shop-bal"><span>🔮 <b>${n(cache?.gem)}</b></span><small>무료 ${n(cache?.free)} · 유료 ${n(cache?.paid)}</small></div><div class="shop-tabs">${TABS.map(([id, name]) => `<button type="button" data-tab="${id}" class="${tab === id ? 'on' : ''}">${name}</button>`).join('')}</div>${body}</div>`;
    host.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; paint(); });
    host.querySelectorAll('[data-sku]').forEach(b => b.onclick = () => buy(b.dataset.sku));
    host.querySelector('[data-pass-claim]')?.addEventListener('click', async e => { e.currentTarget.disabled = true; await refresh(true); await loadDays(); paint(); });
    host.querySelector('[data-sp-rates]')?.addEventListener('click', () => window.VRSpecial?.showRates());
    if (tab === 'consume') paintConsume(host.querySelector('[data-consume]'));
  }
  async function paintConsume(box) {
    if (!box) return;
    await Promise.all([window.VRGem?.status?.(true), window.VRDrink?.status?.()].map(p => Promise.resolve(p).catch(() => null)));
    // 소모품 탭은 드링크만. 행동력 충전·골드·소환권(gem shop)은 이 페이지 라인업이 아니라 각자 화면에서 산다.
    box.innerHTML = `${window.VRDrink?.html?.() || ''}`;
    window.VRDrink?.bind?.(box, () => paintConsume(box));
  }
  function draw(body) { host = body; host.innerHTML = '<div class="shop" data-clarity-mask="true"><div class="shop-note">불러오는 중…</div></div>'; Promise.all([refresh(false), loadDays()]).then(() => { if (host === body) paint(); }); }
  function open(next) {
    const logged = window.VRCloud?.user || window.__SHOP_MOCK || window.__GEM_MOCK;
    if (!on()) return null;
    if (!logged) return toast('로그인이 필요해요');
    if (TABS.some(([id]) => id === next)) tab = next;
    if (window.VRPages?.open) return window.VRPages.open('shop');
    const m = document.createElement('div'); m.className = 'gem-pop'; document.body.appendChild(m);
    const panel = document.createElement('div'); panel.className = 'gem-panel'; panel.setAttribute('data-clarity-mask', 'true'); m.appendChild(panel);
    m.addEventListener('click', e => { if (e.target === m) m.remove(); });
    draw(panel);
  }
  window.VRPages?.register?.('shop', { title: '상점', render: draw });
  window.VRShop = { open, refresh, get enabled() { return on(); }, get now() { return cache; } };
})();
