// ===== 체력의 드링크 🥤 — 서버: supabase/trade_drink.sql =====
// 심연석 팝업 안에 보유량(거래 가능 · 귀속) + 사용 + 구매(유료 심연석만) 칸. 구매·사용 전 확인, 확인창 바깥 누르면 취소
// SQL 실행 전이거나 비로그인이면 칸이 안 보임
(() => {
  const IC = '🥤', NAME = '체력의 드링크';
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
  const ERR = { 'not enough paid gem': '🔮 유료 심연석이 부족해요 (무료분은 못 써요)', 'not enough drink': `${IC} 드링크가 부족해요`, 'stamina cap': '🔋 행동력이 너무 많아요. 조금 쓰고 마셔요', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const toast = t => window.VRGem?.toast?.(t);
  async function status() { if (off) return null; try { const r = await rpc('drink_status'); if (r?.ok) cache = r; } catch (e) { console.warn('[drink]', e?.message); } return cache; }
  function html() {
    const s = cache; if (!s) return '';
    return `<div class="drink-box"><div class="drink-top"><span class="drink-ic">${IC}</span><div><b>${NAME} ${n(s.total)}</b>
      <small>거래 가능 ${n(s.tradable - s.locked)} · 귀속 ${n(s.bound)}${s.locked ? ` · 🔒거래중 ${n(s.locked)}` : ''}</small></div>
      <button type="button" class="drink-use" data-drink-use ${s.total - s.locked > 0 ? '' : 'disabled'}>마시기 +${s.per}🔋</button></div>
      <div class="drink-shop">${(s.shop || []).map(k => `<button type="button" class="gem-buy" data-drink-buy="${k.sku}"><span class="gem-buy-get">${IC}<b>×${k.qty}</b></span><span class="gem-buy-p">🔮${n(k.price)}</span></button>`).join('')}</div>
      <div class="drink-how">유료 심연석 ${n(s.paid_gem)}개로만 살 수 있어요 · 산 드링크는 거래 가능, 이벤트 드링크는 귀속</div></div>`;
  }
  function ask(host, text) {
    return new Promise(res => {
      const a = document.createElement('div'); a.className = 'drink-ask';
      a.innerHTML = `<div class="drink-ask-box"><p>${text}</p><div><button type="button" data-no>취소</button><button type="button" data-yes>확인</button></div></div>`;
      a.addEventListener('click', e => { e.stopPropagation(); if (e.target === a || e.target.closest('[data-no]')) { a.remove(); res(false); } else if (e.target.closest('[data-yes]')) { a.remove(); res(true); } });
      host.appendChild(a);
    });
  }
  /** 심연석 팝업에 붙이기: 버튼 연결, 끝나면 redraw() */
  function bind(host, redraw) {
    host.querySelectorAll('[data-drink-buy]').forEach(b => b.onclick = async e => {
      e.stopPropagation(); const k = cache?.shop?.find(x => x.sku === b.dataset.drinkBuy); if (!k) return;
      if (!await ask(host.querySelector('.gem-panel') || host, `${IC} ${NAME} ${k.qty}개를<br>유료 심연석 🔮${n(k.price)}로 살까요?`)) return;
      b.disabled = true;
      try { const r = await rpc('drink_buy', { p_sku: k.sku }); if (r?.ok) { cache = r; toast(`${IC} ${NAME} +${r.bought}`); window.VRGem?.status?.(true); } }
      catch (er) { toast(errText(er)); }
      if (host.isConnected) redraw();
    });
    host.querySelectorAll('[data-drink-use]').forEach(b => b.onclick = async e => {
      e.stopPropagation(); if (!cache) return;
      if (!await ask(host.querySelector('.gem-panel') || host, `${IC} 1개를 마셔서 행동력 +${cache.per}?<br><small>귀속 드링크부터 써요</small>`)) return;
      b.disabled = true;
      try { const r = await rpc('drink_use', { p_n: 1 }); if (r?.ok) { cache = r; toast(`🔋 행동력 +${r.used * r.per} (지금 ${n(r.stamina)})`); window.VRPlayer?.status?.(true); } }
      catch (er) { toast(errText(er)); }
      if (host.isConnected) redraw();
    });
  }
  window.VRDrink = { IC, NAME, status, html, bind, get now() { return cache; } };
})();
