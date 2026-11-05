// ===== 🎨 꾸미기 1차 (칭호·프레임) — 서버: supabase/cosmetics.sql =====
// 마이페이지 닉네임 옆 버튼 · 장착은 보유만 · 남 표시는 profiles.cosmo_* / lookup
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, tab = 'title';
  const TITLE_NAME = {};
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; return null; } throw error; }
    return data;
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'not owned': '아직 없어요', 'already owned': '이미 있어요', 'not for sale': '살 수 없어요', 'not enough gem': '심연석이 부족해요', 'login required': '로그인이 필요해요', 'invalid': '잘못된 요청이에요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  function set(s) {
    if (s?.ok) {
      cache = s;
      (s.titles || []).forEach(t => { TITLE_NAME[t.id] = t.name; });
    }
    return cache;
  }
  async function status(force) {
    if (off) return null;
    if (cache && !force) return cache;
    try { return set(await rpc('cosmetics_status')); } catch (e) { console.warn('[cosmo]', e?.message); return null; }
  }
  function titleName(id) { return TITLE_NAME[id] || cache?.titles?.find(t => t.id === id)?.name || id || ''; }
  function frameSrc(id) { return `img/ui/frame/${id || 'frame_basic'}.webp`; }
  /** 이름+칭호+프레임 칩. p: { name, title|title_name, frame, avatar } */
  function chip(p = {}, opt = {}) {
    const name = p.name || '플레이어';
    const tn = p.title_name || titleName(p.title) || '';
    const fr = p.frame || 'frame_basic';
    const av = p.avatar;
    const sm = opt.sm ? ' sm' : '';
    const avHtml = opt.noAv ? '' : `<span class="cosmo-av f-${fr}${sm}"><img src="${frameSrc(fr)}" alt="" class="cosmo-fr" onerror="this.classList.add('miss')">${av ? `<img src="${esc(av)}" alt="" class="cosmo-av-img" referrerpolicy="no-referrer" onerror="this.src='img/ui/profile.webp'">` : `<img src="img/ui/profile.webp" alt="" class="cosmo-av-img">`}</span>`;
    return `<span class="cosmo-chip${sm}">${avHtml}<span class="cosmo-tx"><b class="cosmo-nm">${esc(name)}</b>${tn ? `<i class="cosmo-ttl t-${esc(p.title || '')}">${esc(tn)}</i>` : ''}</span></span>`;
  }
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
  async function lookup(ids) {
    const list = [...new Set((ids || []).filter(Boolean))];
    if (!list.length || off) return {};
    try {
      const c = window.VRCloud?.sb; if (!c) return {};
      const { data, error } = await c.rpc('cosmetics_lookup', { p_ids: list });
      if (error) { if (missing(error)) { off = true; return {}; } throw error; }
      return data || {};
    } catch (e) { console.warn('[cosmo] lookup', e?.message); return {}; }
  }
  async function equip(title, frame) {
    const r = await rpc('cosmetics_equip', { p_title: title, p_frame: frame });
    if (r) set(r); return r;
  }
  async function buy(id) {
    const r = await rpc('cosmetics_buy', { p_kind: 'frame', p_id: id });
    if (r) { set(r); window.VRGem?.status?.(true); } return r;
  }
  function open() {
    document.querySelector('.cosmo-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop cosmo-pop';
    const draw = () => {
      const s = cache;
      if (!s) { pop.innerHTML = '<div class="gem-panel daily-panel cosmo-panel">불러오는 중...</div>'; return; }
      const eq = s.equipped || {};
      const list = tab === 'frame' ? (s.frames || []) : (s.titles || []);
      pop.innerHTML = `<div class="gem-panel daily-panel cosmo-panel" role="dialog" aria-label="꾸미기"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">🎨 꾸미기</h3>
        <div class="cosmo-preview">${chip({ name: window.VRCloud?.profile?.nickname || '나', title: eq.title, frame: eq.frame, title_name: titleName(eq.title), avatar: window.VRCloud?.user?.user_metadata?.avatar_url })}</div>
        <div class="ach-tabs cosmo-tabs">
          <button type="button" class="ach-tab ${tab === 'title' ? 'on' : ''}" data-tab="title">칭호</button>
          <button type="button" class="ach-tab ${tab === 'frame' ? 'on' : ''}" data-tab="frame">프레임</button>
        </div>
        <div class="cosmo-list">${list.map(it => {
          const owned = !!it.owned, on = !!it.equipped;
          const price = it.price != null && it.price !== '' ? +it.price : null;
          const canBuy = tab === 'frame' && !owned && price != null;
          return `<div class="cosmo-row ${owned ? '' : 'lock'} ${on ? 'on' : ''}">
            ${tab === 'frame' ? `<span class="cosmo-av f-${it.id}"><img src="${frameSrc(it.id)}" alt="" class="cosmo-fr" onerror="this.classList.add('miss')"><img src="img/ui/profile.webp" alt="" class="cosmo-av-img"></span>` : `<span class="cosmo-ttl-ic t-${it.id}">🏷️</span>`}
            <div class="cosmo-meta"><b>${esc(it.name)}</b><small>${esc(it.how || '')}</small></div>
            ${on ? '<span class="cosmo-st">장착</span>' : owned ? `<button class="fr-b" data-eq="${it.id}">장착</button>` : canBuy ? `<button class="fr-b" data-buy="${it.id}">🔮${price}</button>` : '<span class="cosmo-st dim">미보유</span>'}
          </div>`;
        }).join('')}</div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(); });
      pop.querySelectorAll('[data-eq]').forEach(b => b.onclick = async () => {
        try {
          const id = b.dataset.eq;
          const title = tab === 'title' ? id : eq.title;
          const frame = tab === 'frame' ? id : eq.frame;
          await equip(title, frame); toast('장착했어요'); draw();
        } catch (e) { toast(errText(e)); }
      });
      pop.querySelectorAll('[data-buy]').forEach(b => b.onclick = async () => {
        try { await buy(b.dataset.buy); toast('구매했어요'); draw(); } catch (e) { toast(errText(e)); }
      });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('cosmetics', '🎨 꾸미기', pop)) document.body.appendChild(pop);
    draw(); status(true).then(draw);
  }
  window.VRCosmo = { open, status, chip, lookup, titleName, frameSrc, get cache() { return cache; } };
  setTimeout(() => { status(); }, 2000);
})();
