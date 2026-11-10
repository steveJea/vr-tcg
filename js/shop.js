// ===== 상점 (전용 페이지) — 서버: supabase/shop_bm_staging.sql · 심연석 결제는 payments_staging.sql · 드링크는 trade_drink.sql =====
// 상단 재화의 + 가 이 페이지를 연다. 탭: 충전 · 패키지 · 패스 · 소모품 · 스킨(비어 있음).
// KRW 심연석 팩은 테스트 결제가 켜져 있으면 기존 토스 주문을 쓰고, 아니면 shop_buy(테스트 지급).
// 소환권·레벨업 팩·시즌패스는 결제창을 새로 붙이지 않고 shop_buy. 드링크는 심연석(무료 우선).
(() => {
  const TABS = [['charge', '충전'], ['pack', '패키지'], ['pass', '패스'], ['consume', '소모품'], ['skin', '스킨']];
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist|shop unavailable/i.test(`${e?.code} ${e?.message}`);
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ERR = { 'not enough gem': '심연석이 부족해요', 'monthly limit': '이번 달 구매 횟수를 다 썼어요', 'rate limited': '잠시 후 다시 시도해 주세요', 'invalid item': '없는 상품이에요', 'login required': '로그인이 필요해요', 'shop unavailable': '이 서버에서는 상점을 열 수 없어요' };
  let tab = 'charge', cache = null, host = null;
  const toast = t => window.VRGem?.toast?.(t) || 0;
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : (missing(e) ? '상점 준비 중이에요' : m.slice(0, 80)); };
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
    pass_2: '즉시 소환권 10 + 매일 소환권 1 (30일 총 40) · 매일 행동력 150, 골드 10,000, 무료 심연석 50',
    pass_3: '즉시 소환권 30 + 유료 심연석 300 · 매일 소환권 1 (30일 총 60) · 매일 무료 심연석 100, 행동력 200, 골드·피·조각 10,000',
  };
  function card(p) {
    const used = p.month_used | 0, max = p.month_max, left = max == null ? null : Math.max(0, max - used);
    const limit = max == null ? '' : `<p>이번 달 ${used}/${max}</p>`;
    const payOn = !!(window.VRPayments?.enabled && p.tab === 'charge' && p.payment_sku);
    const label = left === 0 ? '이번 달 완료' : (payOn ? `${n(p.price_krw)}원 결제` : `${n(p.price_krw)}원 테스트 지급`);
    const blurb = PASS_BLURB[p.sku] || p.blurb || '';
    return `<article class="shop-card"><b>${esc(p.name)}</b><p>${esc(blurb)}</p><p class="shop-price">${n(p.price_krw)}원</p>${p.tab === 'charge' ? `<p class="shop-bonus">${esc(gemText(p))}</p>` : ''}${limit}<button type="button" class="shop-go ${payOn ? '' : 'test'}" data-sku="${esc(p.sku)}" ${left === 0 ? 'disabled' : ''}>${label}</button></article>`;
  }
  function passRows() {
    const rows = cache?.passes || [];
    if (!rows.length) return '';
    const label = { active: '진행 중', queued: '대기', ended: '종료' };
    return `<h3 class="shop-sub">내 패스</h3>` + rows.map(p => `<div class="shop-pass"><b>${esc(p.sku)}</b> <i>${label[p.state] || ''}</i><div>${esc(p.starts_on)} ~ ${esc(p.ends_on)}${p.claimed_today ? ' · 오늘 받음' : ''}</div></div>`).join('');
  }
  async function refresh(claim) {
    try {
      const r = claim ? await rpc('shop_pass_claim') : await rpc('shop_status');
      if (r?.ok) cache = r;
      if (claim && r?.claimed?.length) toast('시즌패스 오늘 보상을 받았어요');
      return r;
    } catch (e) { toast(errText(e)); return null; }
  }
  async function buy(sku) {
    const p = (cache?.products || []).find(x => x.sku === sku); if (!p) return;
    const payOn = !!(window.VRPayments?.enabled && p.tab === 'charge' && p.payment_sku);
    const hint = payOn ? `${p.name}을 ${n(p.price_krw)}원에 결제할까요?` : `${p.name}을 테스트 지급으로 받을까요? ${n(p.price_krw)}원`;
    if (!await ask(hint)) return;
    if (payOn) { await window.VRPayments.checkout({ id: p.payment_sku }); await refresh(false); return paint(); }
    try {
      const r = await rpc('shop_buy', { p_sku: sku });
      if (r?.ok) { cache = r; toast(r.first_bonus ? '첫 구매 2배로 지급했어요' : '지급했어요'); window.VRGem?.status?.(true); window.VRPlayer?.wallet?.(true); window.VRPlayer?.status?.(true); }
    } catch (e) { toast(errText(e)); }
    paint();
  }
  function paint() {
    if (!host) return;
    const list = (cache?.products || []).filter(p => p.tab === tab);
    const body = tab === 'skin' ? '<div class="shop-empty"><b>스킨 준비 중</b><p>스킨 상품은 아직 없어요. 나중에 이 탭에 추가됩니다.</p></div>'
      : !cache ? '<div class="shop-err">상점 정보를 불러오지 못했어요.</div>'
      : tab === 'consume' ? '<div data-consume></div>'
      : `<p class="shop-note">${tab === 'charge' ? '상품마다 첫 구매 한 번은 표기 수량과 같은 양을 한 번 더 드려요 (2배).' : tab === 'pass' ? '같은 패스를 다시 사면, 지금 패스가 끝난 다음 날부터 30일이 이어집니다.' : '스페셜 소환권은 지금 쓰는 소환권으로 들어와요. 픽업 소환은 아직 열리지 않았어요.'}</p><div class="shop-grid">${list.map(card).join('') || '<div class="shop-empty">상품이 없어요.</div>'}</div>${tab === 'pass' ? passRows() : ''}`;
    host.innerHTML = `<div class="shop" data-clarity-mask="true"><div class="shop-bal"><span>🔮 <b>${n(cache?.gem)}</b></span><small>무료 ${n(cache?.free)} · 유료 ${n(cache?.paid)}</small></div><div class="shop-tabs">${TABS.map(([id, name]) => `<button type="button" data-tab="${id}" class="${tab === id ? 'on' : ''}">${name}</button>`).join('')}</div>${body}</div>`;
    host.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; paint(); });
    host.querySelectorAll('[data-sku]').forEach(b => b.onclick = () => buy(b.dataset.sku));
    if (tab === 'consume') paintConsume(host.querySelector('[data-consume]'));
  }
  async function paintConsume(box) {
    if (!box) return;
    await Promise.all([window.VRGem?.status?.(true), window.VRDrink?.status?.()].map(p => Promise.resolve(p).catch(() => null)));
    // 소모품 탭은 드링크만. 행동력 충전·골드·소환권(gem shop)은 이 페이지 라인업이 아니라 각자 화면에서 산다.
    box.innerHTML = `<p class="shop-note">체력의 드링크는 심연석으로 사요. 무료 심연석을 먼저 쓰고, 모자라면 유료를 씁니다. 행동력 최대 충전과는 다른 상품이에요.</p>${window.VRDrink?.html?.() || ''}`;
    window.VRDrink?.bind?.(box, () => paintConsume(box));
  }
  function draw(body) { host = body; host.innerHTML = '<div class="shop" data-clarity-mask="true"><div class="shop-note">불러오는 중…</div></div>'; refresh(true).then(() => { if (host === body) paint(); }); }
  function open() {
    const logged = window.VRCloud?.user || window.__SHOP_MOCK || window.__GEM_MOCK;
    if (!logged) return toast('로그인이 필요해요');
    if (window.VRPages?.open) return window.VRPages.open('shop');
    const m = document.createElement('div'); m.className = 'gem-pop'; document.body.appendChild(m);
    const panel = document.createElement('div'); panel.className = 'gem-panel'; panel.setAttribute('data-clarity-mask', 'true'); m.appendChild(panel);
    m.addEventListener('click', e => { if (e.target === m) m.remove(); });
    draw(panel);
  }
  window.VRPages?.register?.('shop', { title: '상점', render: draw });
  window.VRShop = { open, refresh, get now() { return cache; } };
})();
