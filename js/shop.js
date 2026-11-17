// ===== 상점 (전용 페이지) — 서버: supabase/shop_v2_staging.sql (디버그 시트 68 상점 구성안) =====
// 상단 재화의 + 가 이 페이지를 연다. 탭: 시즌패스 · 심연석 패키지 · 아이템 패키지 · 심연석 상점 · 인재 소환(소환 화면으로 이동) · 팝업스토어. 스킨 상점 없음.
// 구매한 것은 전부 📮 우편함으로 온다 (상점이 지갑에 바로 넣지 않음). 시즌패스·팝업스토어의 날짜별 보상도 그날 우편으로 온다.
// 원화(KRW) 상품: 실결제(PG) 연결 전이라 테스트 서버에서만 '테스트 지급'(shop_buy). 운영은 상점 페이지 자체가 꺼져 있음.
// 심연석 상점: shop_gem_buy(수량) · 장비 9칸 shop_gear_buy (매일 00시 KST 교체, 칸당 하루 1회). 무료 심연석부터 씀.
(() => {
  const TABS = [['pass', '시즌패스'], ['charge', '심연석 패키지'], ['pack', '아이템 패키지'], ['gem', '심연석 상점'], ['summon', '인재 소환'], ['popup', '팝업스토어']];
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist|shop unavailable/i.test(`${e?.code} ${e?.message}`);
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ERR = { 'not enough gem': '심연석이 부족해요', 'monthly limit': '이번 달 구매 횟수를 다 썼어요', 'account limit': '계정당 1번만 살 수 있어요', 'pass active': '이 패스는 이용 중이에요. 끝난 뒤 다시 살 수 있어요',
    'sold out': '오늘은 이미 산 칸이에요', 'invalid qty': '수량을 확인해 주세요', 'payment not ready': '결제 준비 중이에요', 'rate limited': '잠시 후 다시 시도해 주세요', 'invalid item': '없는 상품이에요', 'login required': '로그인이 필요해요', 'shop unavailable': '이 서버에서는 상점을 열 수 없어요' };
  // 상점은 테스트 서버 전용. 운영에서는 상점 페이지를 열지 않고 예전 심연석 팝업을 쓴다.
  const on = () => !!(window.__SHOP_MOCK || window.VRCloud?.isStaging === true);
  const GEM = '<img class="ui-ic" src="img/ui/guild/cur_gem.webp" alt="">', TK = '<img class="ui-ic" src="img/ui/ticket.webp" alt="">', SPT = '<img class="ui-ic" src="img/ui/ticket_special.webp" alt="" onerror="this.onerror=null;this.src=\'img/ui/ticket.webp\'">';
  const DRK = '<img class="ui-ic drk-ic paid" src="img/ui/cur_drink_paid.webp" alt="유료 드링크">', DRF = '<img class="ui-ic drk-ic free" src="img/ui/cur_drink_free.webp" alt="무료 드링크">';   // 유료 = 금색 · 무료 = 초록
  const drk = h => h.replace(/유료 드링크/g, `${DRK}<span class="drk-name paid">유료 드링크</span>`).replace(/무료 드링크/g, `${DRF}<span class="drk-name free">무료 드링크</span>`);
  const BANNER = { pass: 'img/ui/shop/pass_banner.webp', popup: 'img/ui/shop/popup_banner.webp' };   // 그림순이 최종본 (1080×360)
  const GRADE = { HR: 'HIGH RARE', SR: 'SUPER RARE', UR: 'ULTRA RARE' };
  let tab = 'charge', cache = null, host = null, cal = null, busy = false;
  const qty = {};
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
  const gearIcon = g => `img/gear/${g.slot === 'acc' ? 'accessory' : g.slot}_${g.tier}_${String(g.def_id).split('_')[2] || 1}.webp`;
  function gemText(p) {
    const g = p.grant || {}, total = (g.gem_paid | 0) + (g.gem_free | 0);
    return p.first_open ? `첫 구매 시 ${n(total * 2)}개` : `심연석 ${n(total)}개`;
  }
  function limitText(p) {
    if (p.acct_max) return `<p class="shop-lim">계정당 ${p.acct_max}회${p.acct_used ? ' · 구매 완료' : ''}</p>`;
    if (p.month_max) return `<p class="shop-lim">이번 달 ${p.month_used | 0}/${p.month_max}</p>`;
    if (p.pass_until) return `<p class="shop-lim on">이용 중 · ${esc(p.pass_until)}까지</p>`;
    return '';
  }
  function soldOut(p) {
    if (p.acct_max && (p.acct_used | 0) >= p.acct_max) return '구매 완료';
    if (p.month_max && (p.month_used | 0) >= p.month_max) return '이번 달 완료';
    if (p.pass_until) return '이용 중';
    return '';
  }
  function card(p) {
    const done = soldOut(p), test = cache?.krw_test !== false;
    const label = done || (test ? `${n(p.price_krw)}원 · 테스트 지급` : '결제 준비 중');
    const x2 = p.tab === 'charge' && p.first_open ? '<span class="shop-x2">첫 구매 ×2</span>' : '';
    const ui = f => `<img class="ui-ic" src="img/ui/${f}.webp" alt="">`;
    const ic = p.tab === 'charge' ? GEM : p.tab === 'pass' ? ui('star') : p.tab === 'popup' ? ui('reward') : p.grant?.special_tickets ? SPT : p.grant?.tickets ? TK : ui('level_up');
    return `<article class="shop-card shop-${esc(p.tab)}">${x2}<div class="shop-card-h"><span class="shop-ic">${ic}</span><b>${esc(p.name)}</b></div>
      ${p.tab === 'charge' ? `<p class="shop-bonus">${esc(gemText(p))}</p>` : `<p>${drk(esc(p.blurb))}</p>`}
      <p class="shop-price">${n(p.price_krw)}원</p>${limitText(p)}
      <button type="button" class="shop-go ${done ? '' : 'test'}" data-sku="${esc(p.sku)}" ${done || !test ? 'disabled' : ''}>${label}</button></article>`;
  }
  const STATE = { active: '진행 중', queued: '대기', ended: '종료' };
  const addDay = (d, k) => new Date(Date.parse(d + 'T00:00:00Z') + k * 864e5).toISOString().slice(0, 10);
  const kstToday = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  function passList() {
    if (cal?.passes) return { today: cal.today, list: cal.passes };
    const today = kstToday();
    return { today, list: (cache?.passes || []).map(p => ({ ...p, claimed: p.claimed_today ? [today] : [] })) };
  }
  function calendar(p, today) {
    const total = Math.max(1, Math.min(90, Math.round((Date.parse(p.ends_on) - Date.parse(p.starts_on)) / 864e5) + 1));
    const got = new Set(p.claimed || []), sent = new Set(p.sent || []);
    const cells = Array.from({ length: total }, (_, i) => {
      const d = addDay(p.starts_on, i), done = got.has(d), mailed = sent.has(d), now = d === today, stopped = p.revoked_on && d >= p.revoked_on;
      const cls = (done ? 'done' : mailed ? 'sent' : stopped ? 'past' : now ? 'today' : d > today ? 'future' : 'past') + (now ? ' is-today' : '');
      const mark = done ? '✓' : mailed ? '📮' : stopped ? '중단' : now ? '오늘' : d > today ? '예정' : '';
      return `<li class="shop-day ${cls}" title="${esc(d)}"><small>${i + 1}</small><span>${mark}</span></li>`;
    }).join('');
    return `<ol class="shop-cal" aria-label="${esc(p.name || p.sku)} ${total}일">${cells}</ol>`;
  }
  function passRows() {
    const { today, list } = passList();
    if (!list.length) return '';
    const names = Object.fromEntries((cache?.products || []).map(x => [x.sku, x.name]));
    const pending = cal?.mail_pending | 0;
    return `<h3 class="shop-sub">내 패스</h3><button type="button" class="shop-go shop-claim" data-mail>📮 우편함 가기${pending ? ` (${pending})` : ''}</button>` + list.map(p => {
      const got = (p.claimed || []).length, total = Math.round((Date.parse(p.ends_on) - Date.parse(p.starts_on)) / 864e5) + 1;
      return `<div class="shop-pass"><b>${esc(names[p.sku] || p.name || p.sku)}</b> <i>${STATE[p.state] || ''}</i><div>${esc(p.starts_on)} ~ ${esc(p.ends_on)} · ${got}/${total}일 받음</div>${calendar(p, today)}</div>`;
    }).join('') + '<p class="shop-note">✓ 받음 · 📮 우편함에 있음 · 오늘 · 예정 — 매일 보상은 우편함으로 와요 (보관 기한 없음, 접속 안 한 날도 쌓여요).</p>';
  }
  function gemTab() {
    const items = cache?.gem_items || [], gear = cache?.gear || [], R = cache?.gear_rates || {};
    const icOf = g => g.grant?.special_tickets ? SPT : g.grant?.tickets ? TK : g.grant?.drink ? DRK : GEM;
    const rows = items.map(g => { const k = qty[g.sku] || 1;
      return `<div class="shop-qrow"><span class="shop-ic">${icOf(g)}</span><div class="shop-qmeta"><b>${g.grant?.drink ? `<span class="drk-name paid">${esc(g.name)}</span>` : esc(g.name)}</b><small>${GEM}${n(g.price)} / 1개</small></div>
        <div class="shop-qty"><button type="button" data-q="${esc(g.sku)}" data-d="-1" aria-label="빼기">−</button><input type="number" inputmode="numeric" min="1" max="${g.max_qty | 0}" value="${k}" data-qi="${esc(g.sku)}" aria-label="${esc(g.name)} 수량"><button type="button" data-q="${esc(g.sku)}" data-d="1" aria-label="더하기">＋</button></div>
        <button type="button" class="shop-go" data-gem-item="${esc(g.sku)}">${GEM}${n(g.price * k)}</button></div>`; }).join('');
    const cells = gear.map(g => `<button type="button" class="shop-gear g-${esc(g.grade)} ${g.bought ? 'sold' : ''}" data-gear="${g.slot_no | 0}" ${g.bought ? 'disabled' : ''}>
        <span class="shop-gear-g">${esc(g.grade)}</span><img src="${gearIcon(g)}" alt="" loading="lazy" onerror="this.style.visibility='hidden'"><b>${esc(g.name)}</b>
        <small>${g.bought ? '구매 완료' : `${GEM}${n(g.price)}`}</small></button>`).join('');
    const wt = ['HR', 'SR', 'UR'].reduce((t, k) => t + (R[k]?.weight | 0), 0);
    const rate = wt ? ['HR', 'SR', 'UR'].filter(k => R[k]).map(k => `${k} ${Number(((R[k].weight | 0) / wt * 100).toFixed(2))}%`).join(' · ') : '';   // 가중치 합 1000 → 95 · 4.9 · 0.1
    return `<p class="shop-note">무료 심연석을 먼저 써요 · 원하는 수량을 골라 사세요.</p><div class="shop-qlist">${rows}</div>
      <h3 class="shop-sub">오늘의 장비 <small>매일 00시(한국 시간) 바뀌어요 · 칸마다 하루 1번${rate ? ` · ${rate}` : ''}</small></h3>
      <div class="shop-gears">${cells || '<div class="shop-empty">장비를 불러오지 못했어요.</div>'}</div>`;
  }
  function body() {
    if (!cache) return '<div class="shop-err">상점 정보를 불러오지 못했어요.</div>';
    if (tab === 'gem') return gemTab();
    const list = (cache.products || []).filter(p => p.tab === tab);
    const banner = BANNER[tab] ? `<div class="shop-banner shop-banner-${tab}"><img src="${BANNER[tab]}" alt="" onerror="this.parentNode.classList.add('miss')"></div>` : '';
    const note = tab === 'pack' ? '<div class="shop-pack-head"><span class="shop-note">프리미엄 소환권 = 프리미엄 소환 · 스페셜 소환권 = 스페셜(픽업) 소환</span><button type="button" class="shop-rates" data-sp-rates>확률</button></div>'
      : tab === 'pass' ? '<p class="shop-note">30일 · 같은 패스는 기간이 끝난 뒤 다시 살 수 있어요 · 서로 다른 패스는 함께 쓸 수 있어요.</p>'
      : tab === 'popup' ? '<p class="shop-note">계정당 1번 · 1일차 보상은 바로, 2·3일차 보상은 그날 우편함으로 와요.</p>'
      : tab === 'charge' ? '<p class="shop-note">상품마다 첫 구매는 2배로 받아요.</p>' : '';
    return `${banner}${note}<div class="shop-grid">${list.map(card).join('') || '<div class="shop-empty">상품이 없어요.</div>'}</div>${tab === 'pass' ? passRows() : ''}`;
  }
  async function loadDays() { try { const r = await rpc('shop_pass_days'); cal = r?.passes ? r : null; } catch { cal = null; } }
  async function refresh() {
    try { const r = await rpc('shop_status'); if (r?.ok) cache = r; return r; } catch (e) { toast(errText(e)); return null; }
  }
  const after = r => { if (r?.ok) cache = r; window.VRGem?.status?.(true); window.VRGear?.unread?.(); };
  const MAILED = '📮 우편함으로 보냈어요';
  async function buy(sku) {
    const p = (cache?.products || []).find(x => x.sku === sku); if (!p || busy) return;
    if (!await ask(`${p.name}을(를) 테스트 지급으로 받을까요? (${n(p.price_krw)}원 · 실제 결제 없음)\n받은 상품은 우편함으로 와요.`)) return;
    busy = true;
    try { const r = await rpc('shop_buy', { p_sku: sku }); after(r); if (p.tab === 'pass') await loadDays(); toast(r?.first_bonus ? `첫 구매 2배 · ${MAILED}` : MAILED); }
    catch (e) { toast(errText(e)); } finally { busy = false; }
    paint();
  }
  async function buyGem(sku) {
    const g = (cache?.gem_items || []).find(x => x.sku === sku); if (!g || busy) return;
    const k = Math.max(1, Math.min(g.max_qty | 0 || 99, qty[sku] || 1));
    if (!await ask(`${g.name} ${k}개를 심연석 ${n(g.price * k)}개로 살까요?\n무료 심연석을 먼저 써요.`)) return;
    busy = true;
    try { after(await rpc('shop_gem_buy', { p_sku: sku, p_qty: k })); qty[sku] = 1; toast(MAILED); } catch (e) { toast(errText(e)); } finally { busy = false; }
    paint();
  }
  async function buyGear(slot) {
    const g = (cache?.gear || []).find(x => (x.slot_no | 0) === slot); if (!g || g.bought || busy) return;
    if (!await ask(`${g.grade} ${g.name}을(를) 심연석 ${n(g.price)}개로 살까요?\n장비는 우편함으로 와요 (가방이 꽉 차면 우편함에 남아요).`)) return;
    busy = true;
    try { after(await rpc('shop_gear_buy', { p_slot: slot })); toast(MAILED); } catch (e) { toast(errText(e)); } finally { busy = false; }
    paint();
  }
  function openMail() {
    const G = window.VRGear; if (G && !G.off) G.mailbox({ back: () => { Promise.all([refresh(), loadDays()]).then(paint); } }); else toast('📮 우편함을 불러올 수 없어요');
  }
  function goSummon() {
    const b = document.querySelector('[data-gnb="summon"]');
    if (b) b.click(); else window.VRStory?.openShop?.();
  }
  function paint() {
    if (!host) return;
    const c = cache || {};
    host.innerHTML = `<div class="shop" data-clarity-mask="true"><div class="shop-bal"><span>${GEM}<b>${n(c.gem)}</b><small>무료 ${n(c.free)} · 유료 ${n(c.paid)}</small></span>
      <span class="shop-tk">${TK}${n(c.tickets)} ${SPT}${n(c.special_tickets)}</span><button type="button" class="shop-mailbtn" data-mail aria-label="우편함">📮</button></div>
      <p class="shop-mailnote">구매한 상품은 모두 📮 우편함으로 와요.</p>
      <div class="shop-tabs" role="tablist">${TABS.map(([id, name]) => `<button type="button" role="tab" data-tab="${id}" class="${tab === id ? 'on' : ''} ${id === 'summon' ? 'out' : ''}">${name}${id === 'summon' ? ' ↗' : ''}</button>`).join('')}</div>${body()}</div>`;
    host.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { if (b.dataset.tab === 'summon') return goSummon(); tab = b.dataset.tab; paint(); });
    host.querySelectorAll('[data-sku]').forEach(b => b.onclick = () => buy(b.dataset.sku));
    host.querySelectorAll('[data-gem-item]').forEach(b => b.onclick = () => buyGem(b.dataset.gemItem));
    host.querySelectorAll('[data-gear]').forEach(b => b.onclick = () => buyGear(+b.dataset.gear));
    host.querySelectorAll('[data-q]').forEach(b => b.onclick = () => { const g = (cache?.gem_items || []).find(x => x.sku === b.dataset.q); if (!g) return; qty[g.sku] = Math.max(1, Math.min(g.max_qty | 0 || 99, (qty[g.sku] || 1) + (+b.dataset.d))); paint(); });
    host.querySelectorAll('[data-qi]').forEach(i => i.onchange = () => { const g = (cache?.gem_items || []).find(x => x.sku === i.dataset.qi); if (!g) return; qty[g.sku] = Math.max(1, Math.min(g.max_qty | 0 || 99, Math.floor(+i.value) || 1)); paint(); });
    host.querySelectorAll('[data-mail]').forEach(b => b.onclick = openMail);
    host.querySelector('[data-sp-rates]')?.addEventListener('click', () => window.VRSpecial?.showRates());
  }
  function draw(b) { host = b; host.innerHTML = '<div class="shop" data-clarity-mask="true"><div class="shop-note">불러오는 중…</div></div>'; Promise.all([refresh(), loadDays()]).then(() => { if (host === b) paint(); }); }
  function open(next) {
    const logged = window.VRCloud?.user || window.__SHOP_MOCK || window.__GEM_MOCK;
    if (!on()) return null;
    if (!logged) return toast('로그인이 필요해요');
    if (next === 'consume') next = 'gem';
    if (TABS.some(([id]) => id === next) && next !== 'summon') tab = next;
    if (window.VRPages?.open) return window.VRPages.open('shop');
    const m = document.createElement('div'); m.className = 'gem-pop'; document.body.appendChild(m);
    const panel = document.createElement('div'); panel.className = 'gem-panel'; panel.setAttribute('data-clarity-mask', 'true'); m.appendChild(panel);
    m.addEventListener('click', e => { if (e.target === m) m.remove(); });
    draw(panel);
  }
  window.VRPages?.register?.('shop', { title: '상점', render: draw });
  window.VRShop = { open, refresh, TABS, get enabled() { return on(); }, get now() { return cache; } };
})();
