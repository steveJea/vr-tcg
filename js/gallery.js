// ===== 카드 갤러리 =====
// 판이 끝나면(로그인 유저만) 승리: 필드에 남은 내 카드 전부 / 패배·무승부: MVP 1장을 갤러리에 등록.
// 저장은 Supabase gallery 테이블 + gallery_register RPC. 스킬 이미지는 절대 노출하지 않음(초상화만).
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };
  const LABEL = { N: '노멀', R: '레어', HR: '하이 레어', SR: '슈퍼 레어', UR: '울트라 레어', MR: '미식 레어' };
  const PENDING = 'vrGalleryPending.v1';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cloud = () => window.VRCloud;
  const logged = () => !!(cloud()?.sb && cloud()?.user);

  let cards = null, owned = new Map(), filter = 'ALL';
  async function loadCards() {
    if (cards) return cards;
    const txt = await (await fetch('data/cards.csv')).text();
    const [head, ...rows] = txt.trim().split(/\r?\n/);
    const h = head.split(',');
    cards = rows.map(r => { const v = r.split(','), o = {}; h.forEach((k, i) => o[k] = v[i]); return o; })
      .sort((a, b) => ORDER.indexOf(a.grade) - ORDER.indexOf(b.grade) || (+a.cost - +b.cost) || a.name.localeCompare(b.name, 'ko'));
    return cards;
  }
  const cardById = id => cards?.find(c => c.id === String(id));

  // --- 서버 통신 ---
  async function fetchOwned() {
    const { data, error } = await cloud().sb.from('gallery').select('card_id, count, mvp_count, first_at, last_at');
    if (error) throw error;
    owned = new Map(data.map(r => [r.card_id, r]));
  }
  async function register(ids, mvp) {
    const { data, error } = await cloud().sb.rpc('gallery_register', { p_cards: ids, p_mvp: mvp || null });
    if (error) throw error;
    return data || [];
  }
  const readPending = () => { try { return JSON.parse(localStorage.getItem(PENDING) || '[]'); } catch { return []; } };
  const writePending = a => localStorage.setItem(PENDING, JSON.stringify(a.slice(-10)));
  async function flushPending() {
    if (!logged()) return;
    const list = readPending(); if (!list.length) return;
    const rest = [];
    for (const p of list) {
      if (p.uid !== cloud().user.id) { rest.push(p); continue; }
      try { await register(p.ids, p.mvp); } catch { rest.push(p); }
    }
    writePending(rest);
  }

  // --- 종료 화면 ---
  function endBox() {
    let el = $('gal-end');
    if (!el) {
      el = document.createElement('div'); el.id = 'gal-end'; el.className = 'gal-end';
      const btn = $('restart-btn'); btn.parentNode.insertBefore(el, btn);
    }
    return el;
  }
  window.addEventListener('vr:match', async e => {
    const m = e.detail || {};
    const box = endBox();
    if (!logged()) {
      box.innerHTML = `<div class="gal-hint">🖼️ 로그인하면 카드가 갤러리에 수집돼요</div>`;
      return;
    }
    const ids = m.result === 'win' ? [...new Set((m.fieldIds || []).map(String))] : [];
    const mvp = m.mvpId ? String(m.mvpId) : null;
    if (m.result !== 'win' && mvp) ids.push(mvp);
    if (!ids.length) { box.innerHTML = `<div class="gal-hint">이번 판은 갤러리에 수집된 카드가 없어요</div>`; return; }
    box.innerHTML = `<div class="gal-hint">🖼️ 갤러리에 수집 중...</div>`;
    try {
      await loadCards();
      const res = await register(ids, mvp);
      res.forEach(r => owned.set(r.card_id, { ...(owned.get(r.card_id) || {}), ...r }));
      const items = ids.map(id => ({ c: cardById(id), r: res.find(x => x.card_id === id) })).filter(x => x.c);
      const nNew = items.filter(x => x.r?.is_new).length;
      box.innerHTML = `<div class="gal-end-title">🖼️ 갤러리 수집 ${items.length}장${nNew ? ` · <span class="gal-new-txt">NEW ${nNew}</span>` : ''}</div>
        <div class="gal-end-row">${items.map(({ c, r }) => `<div class="gal-end-card rar-${SHORT[c.grade]}">
          <img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" onerror="this.style.visibility='hidden'">
          ${r?.is_new ? '<span class="gal-new">NEW!</span>' : `<span class="gal-cnt">×${r?.count ?? ''}</span>`}
          <div class="gal-end-name">${esc(c.name)}</div></div>`).join('')}</div>`;
    } catch (err) {
      console.warn('[gallery] register failed', err);
      writePending([...readPending(), { uid: cloud().user.id, ids, mvp, at: Date.now() }]);
      box.innerHTML = `<div class="gal-hint">📡 지금은 갤러리에 저장하지 못했어요. 다음에 연결되면 자동으로 수집돼요</div>`;
    }
  });

  // --- 갤러리 화면 ---
  function ensureModal() {
    if ($('gal-modal')) return;
    const m = document.createElement('div');
    m.id = 'gal-modal'; m.className = 'gal-modal hidden';
    m.innerHTML = `<div class="gal-panel" role="dialog" aria-label="카드 갤러리">
      <div class="gal-head"><div><div class="gal-title">🖼️ 카드 갤러리</div><div id="gal-progress" class="gal-progress"></div></div>
        <button id="gal-close" class="gal-x" aria-label="닫기">✕</button></div>
      <div class="gal-bar"><div id="gal-bar-fill"></div></div>
      <div id="gal-filters" class="gal-filters"></div>
      <div id="gal-msg" class="gal-msg"></div>
      <div id="gal-grid" class="gal-grid"></div></div>
      <div id="gal-detail" class="gal-detail hidden"></div>`;
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m) close(); });
    $('gal-close').onclick = close;
    $('gal-detail').addEventListener('click', e => { if (e.target.id === 'gal-detail' || e.target.closest('.gal-x')) $('gal-detail').classList.add('hidden'); });
    $('gal-grid').addEventListener('click', e => { const t = e.target.closest('[data-cid]'); if (t) detail(t.dataset.cid); });
    $('gal-filters').addEventListener('click', e => { const b = e.target.closest('[data-f]'); if (b) { filter = b.dataset.f; draw(); } });
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && !m.classList.contains('hidden')) { $('gal-detail').classList.contains('hidden') ? close() : $('gal-detail').classList.add('hidden'); } });
  }
  function close() { $('gal-modal').classList.add('hidden'); document.body.classList.remove('gal-lock'); }

  async function open() {
    ensureModal();
    $('gal-modal').classList.remove('hidden'); document.body.classList.add('gal-lock');
    $('gal-detail').classList.add('hidden');
    $('gal-msg').textContent = '불러오는 중...'; $('gal-grid').innerHTML = '';
    try { await loadCards(); } catch { $('gal-msg').textContent = '카드 목록을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.'; return; }
    let msg = '';
    if (!logged()) { owned = new Map(); msg = cloud()?.sb ? '🔑 로그인하면 카드가 갤러리에 수집돼요' : '📡 지금은 서버에 연결할 수 없어요. 게스트로는 수집되지 않아요'; }
    else { try { await flushPending(); await fetchOwned(); } catch (e) { console.warn('[gallery] load failed', e); msg = '📡 갤러리를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'; } }
    $('gal-msg').innerHTML = msg ? (logged() || !cloud()?.sb ? esc(msg) : `${esc(msg)} <button id="gal-login" class="gal-login">로그인</button>`) : '';
    if ($('gal-login')) $('gal-login').onclick = () => cloud().login();
    draw();
  }

  function draw() {
    const total = cards.length, have = cards.filter(c => owned.has(c.id)).length;
    $('gal-progress').textContent = `${have}/${total} 수집 (${Math.floor(have / total * 100)}%)`;
    $('gal-bar-fill').style.width = `${have / total * 100}%`;
    const cnt = s => { const l = cards.filter(c => SHORT[c.grade] === s); return `${l.filter(c => owned.has(c.id)).length}/${l.length}`; };
    $('gal-filters').innerHTML = [['ALL', `전체 ${have}/${total}`], ...['N', 'R', 'HR', 'SR', 'UR', 'MR'].map(s => [s, `${s} ${cnt(s)}`])]
      .map(([f, t]) => `<button data-f="${f}" class="gal-f ${f !== 'ALL' ? 'rar-' + f : ''} ${filter === f ? 'on' : ''}">${t}</button>`).join('');
    const list = filter === 'ALL' ? cards : cards.filter(c => SHORT[c.grade] === filter);
    $('gal-grid').innerHTML = list.map(c => {
      const o = owned.get(c.id), s = SHORT[c.grade];
      if (!o) return `<div class="gal-card locked rar-${s}"><div class="gal-q">?</div><span class="gal-rar">${s}</span></div>`;
      return `<button class="gal-card rar-${s} ${o.mvp_count > 0 ? 'mvp' : ''}" data-cid="${c.id}">
        <img loading="lazy" src="${IMG}${c.id}.webp" alt="${esc(c.name)}" onerror="this.style.visibility='hidden'">
        <span class="gal-rar">${s}</span>${o.mvp_count > 0 ? '<span class="gal-crown">👑</span>' : ''}
        <div class="gal-name">${esc(c.name)}</div></button>`;
    }).join('');
  }

  function detail(id) {
    const c = cardById(id), o = owned.get(id); if (!c || !o) return;
    const s = SHORT[c.grade];
    const d = new Date(o.first_at), date = isNaN(d) ? '-' : d.toLocaleDateString('ko-KR', { year: 'numeric', month: 'long', day: 'numeric' });
    const row = (k, v) => `<div class="gal-row"><span>${k}</span><b>${v}</b></div>`;
    const el = $('gal-detail');
    el.innerHTML = `<div class="gal-dbox rar-${s} ${o.mvp_count > 0 ? 'mvp' : ''}">
      <button class="gal-x gal-dx" aria-label="닫기">✕</button>
      <div class="gal-dimg"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" onerror="this.style.visibility='hidden'">${o.mvp_count > 0 ? '<span class="gal-crown big">👑</span>' : ''}</div>
      <div class="gal-dname">${esc(c.name)}</div>
      <div class="gal-drar"><span class="gal-rar inline">${s}</span> ${LABEL[s]}</div>
      <div class="gal-rows">${row('수집 횟수', `${o.count}회`)}${row('MVP', o.mvp_count > 0 ? `👑 ${o.mvp_count}회` : '아직 없음')}${row('처음 수집', date)}${row('HP · ATK · DEF', `${c.HP} · ${c.ATK} · ${c.DEF}`)}</div></div>`;
    el.classList.remove('hidden');
  }

  // --- 타이틀 버튼 ---
  function addButton() {
    const howto = $('main-howto'); if (!howto || $('main-gallery')) return;
    const b = document.createElement('button');
    b.id = 'main-gallery'; b.className = 'main-btn main-btn-sub'; b.textContent = '🖼️ 갤러리';
    b.onclick = open;
    howto.parentNode.insertBefore(b, howto.nextSibling);
  }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', addButton) : addButton();
  setTimeout(flushPending, 4000);
  window.VRGallery = { open, close };
})();
