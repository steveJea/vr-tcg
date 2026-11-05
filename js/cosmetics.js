// ===== 🎨 꾸미기 (칭호·프레임·보드·테두리) — 서버: cosmetics.sql · cosmetics2.sql =====
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, tab = 'title';
  const TITLE_NAME = {};
  const TABS = [
    ['title', '칭호'], ['frame', '프레임'], ['board', '보드'], ['border', '테두리'],
  ];
  const LIST_KEY = { title: 'titles', frame: 'frames', board: 'boards', border: 'borders' };
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
      try { localStorage.setItem('vrCosmoEq', JSON.stringify(s.equipped || {})); } catch {}
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
  function boardSrc(id, wide) {
    if (!id || id === 'board_basic') return null;
    const k = id.replace(/^board_/, '');
    return `img/battle/bg/cosmo_${k}_${wide ? 'pc' : 'm'}.webp`;
  }
  function borderSrc(id) {
    if (!id || id === 'border_basic') return null;
    return `img/ui/border/${id}.webp`;
  }
  function equipped() {
    if (cache?.equipped) return cache.equipped;
    try { const v = JSON.parse(localStorage.getItem('vrCosmoEq') || 'null'); if (v) return { title: 'recruit', frame: 'frame_basic', board: 'board_basic', border: 'border_basic', ...v }; } catch {}
    return { title: 'recruit', frame: 'frame_basic', board: 'board_basic', border: 'border_basic' };
  }
  function boardKey() {
    const b = equipped().board;
    if (!b || b === 'board_basic') return null;
    return 'cosmo_' + b.replace(/^board_/, '');
  }
  function borderId() {
    try {
      if (document.documentElement.classList.contains('ios')) return null;
      const b = equipped().border;
      return (!b || b === 'border_basic') ? null : b;
    } catch { return null; }
  }
  /** 내 리더 카드 얼굴(썸네일). 없으면 null → 호출측에서 기본 프로필로 폴백 */
  function leaderAvatar() {
    try {
      const sv = window.VRStory?.save;
      const lo = sv?.owned?.find(o => o.uid === sv.leader) || sv?.owned?.[0];
      const id = lo?.id;
      if (!id) return null;
      return (window.cardThumb || (x => 'img/thumb/' + x + '.webp'))(id);
    } catch { return null; }
  }
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
  async function equipAll(patch) {
    const eq = { ...equipped(), ...patch };
    const r = await rpc('cosmetics_equip', { p_title: eq.title, p_frame: eq.frame, p_board: eq.board, p_border: eq.border });
    if (r) set(r); return r;
  }
  async function buy(kind, id) {
    const r = await rpc('cosmetics_buy', { p_kind: kind, p_id: id });
    if (r) { set(r); window.VRGem?.status?.(true); } return r;
  }
  function thumb(it) {
    if (tab === 'frame') return `<span class="cosmo-av f-${it.id}"><img src="${frameSrc(it.id)}" alt="" class="cosmo-fr" onerror="this.classList.add('miss')"><img src="${esc(leaderAvatar() || 'img/ui/profile.webp')}" alt="" class="cosmo-av-img" onerror="this.src='img/ui/profile.webp'"></span>`;
    if (tab === 'board') {
      const src = boardSrc(it.id, false);
      return src ? `<span class="cosmo-board-th"><img src="${src}" alt="" onerror="this.parentNode.classList.add('miss')"></span>` : `<span class="cosmo-board-th miss">기본</span>`;
    }
    if (tab === 'border') {
      const src = borderSrc(it.id);
      return src ? `<span class="cosmo-border-th"><img src="${src}" alt="" onerror="this.parentNode.classList.add('miss')"></span>` : `<span class="cosmo-border-th miss">기본</span>`;
    }
    return `<span class="cosmo-ttl-ic t-${it.id}">🏷️</span>`;
  }
  function open() {
    document.querySelector('.cosmo-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop cosmo-pop';
    const draw = () => {
      const s = cache;
      if (!s) { pop.innerHTML = '<div class="gem-panel daily-panel cosmo-panel">불러오는 중...</div>'; return; }
      const eq = s.equipped || equipped();
      const list = s[LIST_KEY[tab]] || [];
      const previewBoard = boardSrc(eq.board, false);
      pop.innerHTML = `<div class="gem-panel daily-panel cosmo-panel" role="dialog" aria-label="꾸미기"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">🎨 꾸미기</h3>
        <div class="cosmo-preview ${previewBoard ? 'has-board' : ''}" ${previewBoard ? `style="background-image:url(${previewBoard})"` : ''}>${chip({ name: window.VRCloud?.profile?.nickname || '나', title: eq.title, frame: eq.frame, title_name: titleName(eq.title), avatar: leaderAvatar() || window.VRCloud?.user?.user_metadata?.avatar_url })}</div>
        <div class="ach-tabs cosmo-tabs">${TABS.filter(([k]) => k === 'title' || k === 'frame' || (s[LIST_KEY[k]] && s[LIST_KEY[k]].length)).map(([k, l]) => `<button type="button" class="ach-tab ${tab === k ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>
        <div class="cosmo-list">${list.map(it => {
          const owned = !!it.owned, on = !!it.equipped;
          const price = it.price != null && it.price !== '' ? +it.price : null;
          const canBuy = !owned && price != null;
          return `<div class="cosmo-row ${owned ? '' : 'lock'} ${on ? 'on' : ''}">
            ${thumb(it)}
            <div class="cosmo-meta"><b>${esc(it.name)}</b><small>${esc(it.how || '')}</small></div>
            ${on ? '<span class="cosmo-st">장착</span>' : owned ? `<button class="fr-b" data-eq="${it.id}">장착</button>` : canBuy ? `<button class="fr-b" data-buy="${it.id}">🔮${price}</button>` : '<span class="cosmo-st dim">미보유</span>'}
          </div>`;
        }).join('')}</div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(); });
      pop.querySelectorAll('[data-eq]').forEach(b => b.onclick = async () => {
        try {
          const id = b.dataset.eq;
          const patch = { [tab]: id };
          await equipAll(patch); toast('장착했어요'); draw();
        } catch (e) { toast(errText(e)); }
      });
      pop.querySelectorAll('[data-buy]').forEach(b => b.onclick = async () => {
        try { await buy(tab, b.dataset.buy); toast('구매했어요'); draw(); } catch (e) { toast(errText(e)); }
      });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('cosmetics', '🎨 꾸미기', pop)) document.body.appendChild(pop);
    draw(); status(true).then(draw);
  }
  window.VRCosmo = { open, status, chip, leaderAvatar, lookup, titleName, frameSrc, boardSrc, borderSrc, boardKey, borderId, equipped, get cache() { return cache; } };
  setTimeout(() => { status(); }, 2000);
})();
