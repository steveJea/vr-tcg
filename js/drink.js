// ===== 체력의 드링크 🥤 — 서버: supabase/trade_drink.sql =====
// 심연석 팝업·소모품 탭: 보유량(거래 가능 · 귀속) + 사용 + 구매(무료분부터 차감). 구매·사용 전 확인, 확인창 바깥 누르면 취소
// SQL 실행 전이거나 비로그인이면 칸이 안 보임
(() => {
  const IC = '🥤', NAME = '체력의 드링크';
  const ICH = '<img class="ui-ic" src="img/ui/cur_drink.webp" alt="">', ST = '<img class="ui-ic" src="img/ui/stamina.webp" alt="">', GEM = '<img class="ui-ic" src="img/ui/guild/cur_gem.webp" alt="">';
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false;
  async function rpc(name, args) {
    const m = window.__DRINK_MOCK; if (m) return m(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const ERR = { 'not enough gem': '🔮 심연석이 부족해요', 'not enough paid gem': '🔮 심연석이 부족해요', 'not enough drink': `${IC} 드링크가 부족해요`, 'stamina cap': '🔋 행동력 가득', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const toast = t => window.VRGem?.toast?.(t);
  async function status() { if (off) return null; try { const r = await rpc('drink_status'); if (r?.ok) cache = r; } catch (e) { console.warn('[drink]', e?.message); } return cache; }
  function html() {
    const s = cache; if (!s) return '';
    return `<div class="drink-box"><div class="drink-top"><span class="drink-ic">${ICH}</span><div><b>${NAME} ${n(s.total)}</b>
      <small>거래 가능 ${n(s.tradable - s.locked)} · 귀속 ${n(s.bound)}${s.locked ? ` · 🔒거래중 ${n(s.locked)}` : ''}</small></div>
      <button type="button" class="drink-use" data-drink-use ${s.total - s.locked > 0 ? '' : 'disabled'}>마시기 +${s.per}${ST}</button></div>
      <div class="drink-shop">${(s.shop || []).map(k => `<button type="button" class="gem-buy" data-drink-buy="${k.sku}"><span class="gem-buy-get">${ICH}<b>×${k.qty}</b></span><span class="gem-buy-p">${GEM}${n(k.price)}</span></button>`).join('')}</div>
      <details class="vr-tip drink-how"><summary>ⓘ</summary><p>산 드링크는 거래 가능, 이벤트 드링크는 귀속</p></details></div>`;
  }
  function ask(host, text) {
    return new Promise(res => {
      const a = document.createElement('div'); a.className = 'drink-ask';
      a.innerHTML = `<div class="drink-ask-box" role="dialog">${text}<div class="drink-ask-acts"><button type="button" data-no>취소</button><button type="button" data-yes>확인</button></div></div>`;
      a.addEventListener('click', e => { e.stopPropagation(); if (e.target === a || e.target.closest('[data-no]')) { a.remove(); res(false); } else if (e.target.closest('[data-yes]')) { a.remove(); res(true); } });
      document.body.appendChild(a);
    });
  }
  /** 심연석 팝업에 붙이기: 버튼 연결, 끝나면 redraw() */
  function bind(host, redraw) {
    host.querySelectorAll('[data-drink-buy]').forEach(b => b.onclick = async e => {
      e.stopPropagation(); const k = cache?.shop?.find(x => x.sku === b.dataset.drinkBuy); if (!k) return;
      if (!await ask(host.querySelector('.gem-panel') || host, `<p>${ICH} ${NAME} ${k.qty}개를</p><p>심연석 ${n(k.price)}개로 살까요?</p><p class="drink-ask-note">무료 심연석을 먼저 써요</p>`)) return;
      b.disabled = true;
      try { const r = await rpc('drink_buy', { p_sku: k.sku }); if (r?.ok) { cache = r; toast(`${IC} ${NAME} +${r.bought}`); window.VRGem?.status?.(true); } }
      catch (er) { toast(errText(er)); }
      if (host.isConnected) redraw();
    });
    host.querySelectorAll('[data-drink-use]').forEach(b => b.onclick = async e => {
      e.stopPropagation(); if (!cache) return;
      if (!await ask(host.querySelector('.gem-panel') || host, `<p>${ICH} 1개를 마셔서</p><p>행동력 +${cache.per}?</p>`)) return;
      b.disabled = true;
      try { const r = await rpc('drink_use', { p_n: 1 }); if (r?.ok) { cache = r; toast(`🔋 행동력 +${r.used * r.per} (지금 ${n(r.stamina)})`); window.VRPlayer?.status?.(true); } }
      catch (er) { toast(errText(er)); }
      if (host.isConnected) redraw();
    });
  }
  /** 상단바 행동력 + : 드링크로 행동력 채우기. 서버 drink_use 가 귀속(무료) 드링크부터 씀 */
  async function quick() {
    if (document.querySelector('.drink-quick')) return;
    const a = document.createElement('div'); a.className = 'drink-ask drink-quick';
    const close = () => a.remove();
    const draw = (busy) => {
      const s = cache, P = window.VRPlayer?.now?.();
      if (!s) { a.innerHTML = `<div class="drink-ask-box" role="dialog"><p>${off ? '드링크를 쓸 수 없어요' : '불러오는 중…'}</p><div class="drink-ask-acts"><button type="button" data-no>닫기</button></div></div>`; return; }
      const free = s.bound | 0, other = Math.max(0, (s.tradable | 0) - (s.locked | 0)), have = free + other;
      const st = P?.stamina, capped = st != null && s.cap && st + s.per > s.cap;
      const why = !have ? '드링크가 없어요' : capped ? `행동력이 가득 찼어요 (최대 ${n(s.cap)})` : '';
      a.innerHTML = `<div class="drink-ask-box" role="dialog" aria-label="행동력 채우기">
        <p><b>${ST} 행동력 채우기</b></p>
        ${st != null ? `<p class="drink-q-now">지금 ${ST} <b>${n(st)}</b>/${n(P.stamina_max)}</p>` : ''}
        <div class="drink-q-cnt"><span>${ICH} 무료 드링크 <b>${n(free)}</b></span><span>${ICH} 일반 드링크 <b>${n(other)}</b>${s.locked ? ` <small>(🔒거래중 ${n(s.locked)})</small>` : ''}</span></div>
        <p class="drink-ask-note">${why || `1개 마시면 행동력 +${n(s.per)} · 무료 드링크부터 써요`}</p>
        <div class="drink-ask-acts"><button type="button" data-no>닫기</button>${have ? `<button type="button" data-yes data-q-use ${why || busy ? 'disabled' : ''}>마시기 +${n(s.per)}</button>` : '<button type="button" data-yes data-q-shop>상점 가기</button>'}</div></div>`;
    };
    a.addEventListener('click', async e => {
      e.stopPropagation();
      if (e.target === a || e.target.closest('[data-no]')) return close();
      if (e.target.closest('[data-q-shop]')) { close(); if (window.VRShop?.enabled && window.VRShop.open) window.VRShop.open('consume'); else window.VRGem?.open?.(); return; }
      const b = e.target.closest('[data-q-use]'); if (!b || b.disabled) return;
      draw(true);
      try { const r = await rpc('drink_use', { p_n: 1 }); if (r?.ok) { cache = r; toast(`🔋 행동력 +${r.used * r.per} (지금 ${n(r.stamina)})`); await window.VRPlayer?.status?.(true); } }
      catch (er) { toast(errText(er)); }
      if (a.isConnected) draw();
    });
    document.body.appendChild(a); draw();
    await status(); window.VRPlayer?.status?.(true)?.then?.(() => a.isConnected && draw());
    if (a.isConnected) draw();
  }
  window.VRDrink = { IC, NAME, status, html, bind, quick, get now() { return cache; } };
})();
