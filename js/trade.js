// ===== 거래 게시판 💱 (화면) — 서버: supabase/trade_board.sql =====
// 게시판 목록 · 글 상세 · 판매 글 올리기 · 제안(인재·장비·드링크·골드) · 내 글(수락·거절·조건 거절·내리기) · 내 제안(취소)
// 팝업은 바깥 누르면 닫힘, 돈·물건이 움직이는 동작은 모두 확인 후. SQL 없으면 "준비 중"
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const TIER = ['', '낡은', '일반', '고급', '희귀', '영웅', '전설', '심연'];
  const GRADE = { NORMAL: 'N', RARE: 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const I = f => `<img class="tr-ic" src="img/ui/${f}.webp" alt="">`;   // 아이콘 (img/ui)
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const toast = t => (window.VRGem?.toast || window.alert)(t);
  const ERR = {
    'no buy price': '즉시 구매가가 없는 글이에요', 'price changed': '가격이 바뀌었어요. 글을 다시 열어 주세요', 'buy one currency': '즉시 구매가는 드링크나 골드 중 하나만 정할 수 있어요',
    'login required': '로그인이 필요해요', 'trade level': '계정 Lv.20부터 거래할 수 있어요', 'trade account age': '가입 7일 뒤부터 거래할 수 있어요',
    'nothing to trade': '올릴 인재나 장비를 골라 주세요', 'nothing to offer': '제안할 것을 하나 이상 넣어 주세요', 'too many items': '한쪽에 최대 5개까지예요',
    'too many listings': '열린 판매 글이 너무 많아요 (최대 5개)', 'too many offers': '대기 중인 제안이 너무 많아요', 'listing full': '이 글은 제안이 꽉 찼어요',
    'already offered': '이 글에는 이미 제안했어요. 고치려면 취소 후 다시', 'reoffer cooldown': '거절된 글에는 24시간 뒤에 다시 제안할 수 있어요',
    'own listing': '내 글에는 제안할 수 없어요', 'listing closed': '이미 끝난 글이에요', 'listing not found': '글을 찾을 수 없어요',
    'offer closed': '이미 끝난 제안이에요', 'offer not found': '제안을 찾을 수 없어요', 'gold not allowed': '🪙 SR 이상 인재·영웅 장비가 끼면 골드는 쓸 수 없어요',
    'price too high': '가격 범위보다 많아요', 'price too low': '가격 범위보다 적어요', 'escrow limit': '보관 한도를 넘어요',
    'not enough drink': '🥤 거래 가능한 드링크가 부족해요 (귀속 드링크는 못 써요)', 'not enough gold': '🪙 골드가 부족해요',
    'card bound': '🔗 귀속 인재는 거래할 수 없어요', 'card locked': '🔒 잠긴 인재예요', 'cannot trade leader': '👑 리더는 올릴 수 없어요',
    'card not owned': '이 인재가 없어요', 'gear not owned': '이 장비가 없어요', 'gear locked': '🔒 잠긴 장비예요', 'gear equipped': '장착 중인 장비는 먼저 해제해 주세요',
    'gear not tradable': '전설·심연 장비는 거래할 수 없어요', 'resale cooldown': '거래로 받은 물건은 72시간 뒤에 다시 올릴 수 있어요',
    'daily trade limit': '오늘 거래 한도를 다 썼어요', 'same partner limit': '같은 상대와는 7일에 3번까지예요', 'no condition': '거절 조건을 넣어 주세요',
    'nothing to reject': '거절할 제안을 골라 주세요', 'duplicate card': '같은 인재를 두 번 골랐어요', 'duplicate gear': '같은 장비를 두 번 골랐어요', 'invalid amount': '수량을 확인해 주세요', 'too many wants': '원하는 물건은 5개까지예요', 'direct only': '🤝 지정 거래는 받는 사람만 응할 수 있어요', 'target cannot trade': '상대가 아직 거래할 수 없어요 (Lv.20 · 가입 7일)', 'invalid target': '거래 상대를 다시 골라 주세요', 'too many direct': '같은 상대에게 열린 지정 거래는 3개까지예요', 'want required': '드링크만 보낼 땐 원하는 물건을 하나 이상 골라 주세요', 'invalid want': '원하는 물건을 다시 골라 주세요',
    'cancel limit': '오늘 제안 취소가 너무 많아요. 내일 다시 제안할 수 있어요', 'drink send limit': '🥤 오늘 보낼 수 있는 드링크 양을 넘어요', 'drink recv limit': '🥤 오늘 받을 수 있는 드링크 양을 넘어요 (하루 10,000)'
  };
  const errText = m => { m = String(m || ''); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : /trade_|schema cache|Could not find/.test(m) ? '💱 거래 게시판은 준비 중이에요' : `⚠️ ${m.slice(0, 60)}`; };
  const MISSING = /schema cache|Could not find the function|does not exist|PGRST202/;
  async function rpc(fn, args, quiet) {   // quiet: 서버에 함수가 없으면(SQL 실행 전) 토스트 없이 'missing'
    const mk = window.__TRADE_MOCK; if (mk) { try { return await mk(fn, args); } catch (e) { if (quiet && MISSING.test(e.message)) return 'missing'; toast(errText(e.message)); return null; } }
    const sb = window.VRCloud?.sb; if (!sb || !window.VRCloud?.user) { toast(ERR['login required']); return null; }
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) { if (quiet && MISSING.test(`${error.code} ${error.message}`)) return 'missing'; toast(errText(error.message)); return null; }
    if (data && data.ok === false) { toast(errText(data.reason)); return null; }
    return data;
  }
  // 팝업 (바깥 누르면 닫힘)
  // page: [이름, 제목] 이면 페이지(#/이름)로 띄움 (js/pages.js). 페이지 시스템이 없거나 실패하면 예전 팝업
  function pop(html, cls = '', page = null) {
    const m = document.createElement('div'); m.className = 'tr-bg';
    m.innerHTML = `<div class="tr-pop ${cls}" role="dialog"><button class="tr-x" data-x aria-label="닫기">✕</button><div class="tr-in">${html}</div></div>`;
    let down = false;
    m.onpointerdown = e => { down = e.target === m; };
    m.onclick = e => { if ((down && e.target === m) || e.target.closest('[data-x]')) m.remove(); down = false; };
    document.body.appendChild(m);
    if (page && window.VRPages?.host) { m.classList.add('tr-page'); window.VRPages.host(page[0], page[1], m, null, null, page[2] || null); }
    return m;
  }
  const body = m => m.querySelector('.tr-in');
  function ask(html, danger) {
    return new Promise(res => { let done = false; const fin = v => { if (done) return; done = true; o.disconnect(); m.remove(); res(v); };
      const m = pop(`<div class="tr-ask">${html}</div><div class="tr-acts"><button class="tr-btn" data-n>취소</button><button class="tr-btn main ${danger ? 'danger' : ''}" data-y>확인</button></div>`, 'small');
      const o = new MutationObserver(() => { if (!m.isConnected) fin(false); }); o.observe(document.body, { childList: true });
      m.querySelector('[data-y]').onclick = () => fin(true); m.querySelector('[data-n]').onclick = () => fin(false); });
  }

  // ---- 데이터
  let cfg = null, bands = null;
  const S = () => window.VRStory?.api;
  const cardOf = id => S()?.card?.(id) || window.TCG?.cardById?.(id) || null;
  const gradeOf = id => GRADE[cardOf(id)?.grade] || '?';
  const defOf = id => window.VRGear?._defs?.()?.[id] || null;
  const gearIcon = d => d ? `img/gear/${d.slot === 'acc' ? 'accessory' : d.slot}_${d.tier}_${d.id.split('_')[2]}.webp` : '';
  const cardKey = id => ({ N: 'card_nr', R: 'card_nr', HR: 'card_hr', SR: 'card_sr', UR: 'card_ur' })[gradeOf(id)] || 'card_mlr';
  const gearKey = t => t <= 3 ? 'gear_low' : t === 4 ? 'gear_rare' : t === 5 ? 'gear_hero' : null;
  async function loadCfg() { if (cfg) return true; const r = await rpc('trade_my'); if (!r) return false; cfg = r.config || {}; bands = Object.fromEntries((r.bands || []).map(b => [b.gkey, b])); return r; }

  // 물건 타일 (인재: 그림·등급·레벨 / 장비: 아이콘·등급·+강화)
  const cardTile = (c, extra = '') => { const m = cardOf(c.id); return `<div class="tr-it card g-${gradeOf(c.id)}" ${extra}><img src="${IMG}${c.id}.webp" alt="" loading="lazy"><b>${esc(m?.name || c.id)}</b><small>${gradeOf(c.id)} · Lv.${c.level || 1}</small></div>`; };
  const gearTile = (g, extra = '') => { const d = defOf(g.def_id || g.def); return `<div class="tr-it gear t-${d?.tier || 0}" ${extra}><img src="${gearIcon(d)}" alt="" loading="lazy" onerror="this.style.visibility='hidden'"><b>${esc(d?.name || '장비')}${g.plus ? ` +${g.plus}` : ''}</b><small>${TIER[d?.tier] || ''}</small></div>`; };
  const itemsHTML = (cards, gear) => (cards || []).map(x => cardTile(x.card || x)).join('') + (gear || []).map(x => gearTile(x.row || x)).join('');
  const left = t => { const s = Math.max(0, (new Date(t) - Date.now()) / 1000); return s >= 3600 ? `${Math.floor(s / 3600)}시간` : `${Math.ceil(s / 60)}분`; };
  const cfRow = (label, items, cur) => `<div class="tr-cf-row"><div class="tr-cf-l">${label}</div><div class="tr-items tr-cf-items">${items || ''}${cur ? `<div class="tr-cur">${cur}</div>` : ''}${!items && !cur ? '<span class="tr-cf-none">없음</span>' : ''}</div></div>`;
  const buyTxt = l => l.buy_drinks ? `${I('cur_drink')}${n(l.buy_drinks)}` : l.buy_gold ? `${I('cur_gold')}${n(l.buy_gold)}` : '';
  const curTxt = (d, g) => [d ? `${I('cur_drink')}${n(d)}` : '', g ? `${I('cur_gold')}${n(g)}` : ''].filter(Boolean).join(' + ');

  // ---- 메인: 게시판 / 내 거래
  let myView = 'live', mSort = 'new', mF = { type: 'all', gr: new Set(), q: '', buy: false, want: false }, srvSearch = null;   // mF: 마켓 필터 (화면 안에서 유지)   // mSort: 마켓 정렬
  const GO = ['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'];   // 내 거래: 진행중 / 종료 탭
  async function open(tab = 'board') {
    if (window.VRPages?.current?.startsWith('exchange') && window.VRPages.current !== 'exchange') while (window.VRPages.current?.startsWith('exchange-')) window.VRPages.closeNow();
    document.querySelector('.tr-bg.main')?.remove();
    const m = pop('<div class="tr-load">불러오는 중…</div>', 'wide', ['exchange', '💱 거래소']); m.classList.add('main');
    if (window.VRGear?.load) await window.VRGear.load().catch(() => {});
    if (!await loadCfg()) { m.remove(); return; }
    const draw = async t => {
      tab = t;
      body(m).innerHTML = `<div class="tr-head"><b>${I('trade')}거래 게시판</b><span><button class="tr-btn" data-help>${I('help')}도움말</button> <button class="tr-btn" data-direct>🤝 지정 거래</button> <button class="tr-btn" data-gnlog>📢 소식</button> <button class="tr-btn main" data-new>＋ 판매 글</button></span></div>
        <div class="tr-tabs"><button data-tab="board" class="${t === 'board' ? 'on' : ''}">게시판</button><button data-tab="price" class="${t === 'price' ? 'on' : ''}">📈 시세</button><button data-tab="my" class="${t === 'my' ? 'on' : ''}">내 거래</button></div><div class="tr-list"><div class="tr-load">불러오는 중…</div></div>`;
      body(m).querySelectorAll('[data-tab]').forEach(b => b.onclick = () => draw(b.dataset.tab));
      body(m).querySelector('[data-new]').onclick = () => createListing(() => draw('my'));
      body(m).querySelector('[data-help]').onclick = help;
      body(m).querySelector('[data-gnlog]').onclick = () => window.VRNotice?.open?.();
      body(m).querySelector('[data-direct]').onclick = () => directCreate(null, () => draw('my'));
      const L = body(m).querySelector('.tr-list');
      if (t === 'board') {
        // 마켓 (PR2): 카드 격자 · 정렬(최신/마감 임박/제안 많은) · 더 보기(p_before) · 빈/불러오는 중. 정렬은 불러온 글 안에서
        const PAGE = 30, SORT = { new: ['최신', (a, b) => b.id - a.id], end: ['마감 임박', (a, b) => new Date(a.expires_at) - new Date(b.expires_at)], hot: ['제안 많은', (a, b) => b.offers - a.offers || b.id - a.id], price: ['낮은 가격', (a, b) => (bp(a) ?? Infinity) - (bp(b) ?? Infinity) || b.id - a.id] };
        const bp = l => l.buy_drinks ?? (l.buy_gold != null ? l.buy_gold / 100 : null);   // 즉시 구매가 비교 (골드 100 ≈ 드링크 1, 서버와 같음)
        let all = [], more = true, busy = false, qT = 0;   // srvSearch: 서버 검색(trade_search) 쓸 수 있으면 true, SQL 전이면 false → 불러온 글 안에서 거름
        L.className = 'tr-list tr-market';
        L.innerHTML = `<div class="tr-filter"><input type="search" class="tr-input tr-q" placeholder="🔍 이름으로 찾기" value="${esc(mF.q)}" aria-label="이름 검색">
            <div class="tr-fchips" role="group" aria-label="종류">${[['all', '전체'], ['card', '인재'], ['gear', '장비']].map(([k, lb]) => `<button data-ftype="${k}" class="${mF.type === k ? 'on' : ''}">${lb}</button>`).join('')}</div>
            <div class="tr-fchips tr-fgr" role="group" aria-label="등급">${['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'].map(g => `<button data-fgr="${g}" class="g-${g} ${mF.gr.has(g) ? 'on' : ''}">${g}</button>`).join('')}</div>
            <div class="tr-fchips"><button data-fbuy class="tr-fbuy ${mF.buy ? 'on' : ''}">⚡ 즉시 구매만</button><button data-fwant class="tr-fbuy ${mF.want ? 'on' : ''}">🎯 내 물건을 원하는 글</button></div></div>
          <div class="tr-sort" role="group" aria-label="정렬">${Object.entries(SORT).map(([k, [lb]]) => `<button data-sort="${k}" class="${k === mSort ? 'on' : ''}">${lb}</button>`).join('')}</div>
          <div class="tr-grid">${'<div class="tr-gc ui-skel"></div>'.repeat(4)}</div><div class="tr-more-w"></div>`;
        const G = L.querySelector('.tr-grid'), M = L.querySelector('.tr-more-w'); let mineSet = myIds();
        const gIdx = l => Math.max(0, ...(l.cards || []).map(c => GO.indexOf(gradeOf(c.id))), ...(l.gear || []).map(g => (defOf(g.def_id || g.def)?.tier || 0) - 2));
        const cardHTML = l => { const c0 = (l.cards || [])[0], g0 = !c0 && (l.gear || [])[0], d = g0 && defOf(g0.def_id || g0.def), m0 = c0 && cardOf(c0.id), cnt = (l.cards?.length || 0) + (l.gear?.length || 0);
          const secs = (new Date(l.expires_at) - Date.now()) / 1000, gr = GO[Math.min(GO.length - 1, gIdx(l))];
          return `<button class="tr-gc g-${gr}" data-l="${l.id}"><span class="tr-gc-img">${c0 ? `<img src="${IMG}${c0.id}.webp" alt="" loading="lazy">` : d ? `<img class="gear" src="${gearIcon(d)}" alt="" loading="lazy">` : ''}
            <i class="tr-gc-gr">${c0 ? gradeOf(c0.id) : d ? TIER[d.tier] : ''}</i>${cnt > 1 ? `<i class="tr-gc-n">+${cnt - 1}</i>` : ''}${l.to_me ? '<i class="tr-gc-tag dir">🤝 나에게</i>' : l.mine ? `<i class="tr-gc-tag">${l.direct ? `🤝 ${esc(l.target_name || '지정')}` : '내 글'}</i>` : l.my_offer ? '<i class="tr-gc-tag">제안함</i>' : ''}</span>
            <b>${esc(m0?.name || d?.name || '판매 글')}${c0?.level ? ` <small>Lv.${c0.level}</small>` : ''}</b>${(l.want_ids || []).length ? `<span class="tr-gc-wid ${l.want_ids.some(w => mineSet.has(String(w.id))) ? 'have' : ''}">🎯 ${esc(itemName(l.want_ids[0].k, l.want_ids[0].id))}${l.want_ids.length > 1 ? ` 외 ${l.want_ids.length - 1}` : ''}</span>` : ''}${l.want ? `<span class="tr-gc-want">${esc(l.want)}</span>` : '<span class="tr-gc-want dim">희망 조건 없음</span>'}
            ${buyTxt(l) ? `<span class="tr-gc-buy">⚡ ${buyTxt(l)}</span>` : ''}<span class="tr-gc-meta"><span class="${secs < 3 * 3600 ? 'soon' : ''}">${I('timer')}${left(l.expires_at)}</span><span>${I('trade_offer')}${l.offers}</span></span></button>`; };
        // 필터 (PR4): 불러온 글 안에서만 — 종류(인재/장비 포함)·등급(글 안 물건 중 하나라도)·이름(물건 이름 일부)
        const itemGr = l => [...(l.cards || []).map(c => gradeOf(c.id)), ...(l.gear || []).map(g => GO[Math.max(0, Math.min(6, (defOf(g.def_id || g.def)?.tier || 0) - 2))])];
        const names = l => [...(l.cards || []).map(c => cardOf(c.id)?.name || ''), ...(l.gear || []).map(g => defOf(g.def_id || g.def)?.name || '')].join(' ').toLowerCase();
        const pass = l => srvSearch ? true : (!mF.buy || bp(l) != null) && (mF.type === 'all' || (mF.type === 'card' ? l.cards?.length : l.gear?.length)) && (!mF.gr.size || itemGr(l).some(g => mF.gr.has(g))) && (!mF.q || names(l).includes(mF.q.trim().toLowerCase())) && (!mF.want || (l.want_ids || []).some(w => mineSet.has(String(w.id))));
        const fOn = () => mF.type !== 'all' || mF.gr.size || mF.q.trim() || mF.buy || mF.want;
        const paintG = () => { const list = srvSearch ? all.slice() : all.filter(pass).sort(SORT[mSort][1]);
          G.innerHTML = list.length ? list.map(cardHTML).join('') : all.length && fOn() ? `<div class="tr-empty"><b>조건에 맞는 글이 없어요</b><small>${srvSearch ? '게시판 전체에서 찾았어요' : `불러온 ${all.length}개 중에서 찾았어요${more ? ' · 더 보기로 더 불러올 수 있어요' : ''}`}</small><button class="tr-btn" data-freset>필터 지우기</button></div>` : `<div class="tr-empty">${I('trade')}<b>아직 올라온 글이 없어요</b><small>첫 판매 글을 올려 보세요</small><button class="tr-btn main" data-new2>＋ 판매 글</button></div>`;
          G.querySelector('[data-freset]')?.addEventListener('click', () => { mF.type = 'all'; mF.gr.clear(); mF.q = ''; mF.buy = false; mF.want = false; L.querySelector('[data-fbuy]').classList.remove('on'); L.querySelector('[data-fwant]').classList.remove('on'); L.querySelector('.tr-q').value = ''; L.querySelectorAll('[data-ftype]').forEach(x => x.classList.toggle('on', x.dataset.ftype === 'all')); L.querySelectorAll('[data-fgr]').forEach(x => x.classList.remove('on')); refilter(); });
          L.querySelector('.tr-fcount')?.remove(); if (fOn() && list.length && !srvSearch) G.insertAdjacentHTML('beforebegin', `<div class="tr-fcount">${list.length} / ${all.length}개</div>`);
          G.querySelector('[data-new2]')?.addEventListener('click', () => createListing(() => draw('my')));
          G.querySelectorAll('[data-l]').forEach(b => b.onclick = () => { const l = all.find(x => x.id === +b.dataset.l); l.mine ? manage(l.id, () => draw(tab)) : detail(l, () => draw(tab)); });
          M.innerHTML = more && all.length ? '<button class="tr-btn tr-more">더 보기</button>' : all.length ? '<div class="tr-end">마지막 글이에요</div>' : '';
          M.querySelector('.tr-more')?.addEventListener('click', load); };
        // 서버 검색 인자: 인재 이름 → id (이름은 화면 데이터에만 있음), 등급 칩 → trade_band 키 (장비: N·R=낮은, HR=희귀, SR=영웅)
        const GK = { N: ['card_nr', 'gear_low'], R: ['card_nr', 'gear_low'], HR: ['card_hr', 'gear_rare'], SR: ['card_sr', 'gear_hero'], UR: ['card_ur'], MR: ['card_mlr'], LR: ['card_mlr'] };
        const searchArgs = () => { const q = mF.q.trim(), pool = window.TCG?.POOL || [];
          const ids = q ? [...new Set(pool.filter(c => (c.name || '').toLowerCase().includes(q.toLowerCase())).map(c => String(c.id)))].slice(0, 200) : null;
          return { p_q: q, p_card_ids: ids, p_type: mF.type, p_gkeys: mF.gr.size ? [...new Set([...mF.gr].flatMap(g => GK[g]))] : null, p_buy_only: mF.buy, p_sort: mSort, p_limit: PAGE, p_offset: all.length }; };
        async function load() { if (busy || !more) return; busy = true; const b = M.querySelector('.tr-more'); if (b) { b.disabled = true; b.textContent = '불러오는 중…'; }
          let r = null, got;
          if (srvSearch !== false && mF.want) { r = await rpc('trade_search2', { ...searchArgs(), p_want_in: [...mineSet].slice(0, 500) }, true); if (r === 'missing') { r = null; mF.want = false; L.querySelector('[data-fwant]').classList.remove('on'); toast('🎯 원하는 물건 검색은 서버 준비 중이에요'); } else if (r) srvSearch = true; }
          if (srvSearch !== false && !r) { r = await rpc('trade_search', searchArgs(), true); if (r === 'missing') { srvSearch = false; r = null; } else if (r) srvSearch = true; }
          if (srvSearch === false) { const before = all.length ? Math.min(...all.map(x => x.id)) : null; r = await rpc('trade_board', { p_limit: PAGE, ...(before ? { p_before: before } : {}) }); }
          busy = false;
          if (!r) { if (!all.length) G.innerHTML = '<div class="tr-empty"><b>불러오지 못했어요</b></div>'; else paintG(); return; }
          got = r.listings || []; const seen = new Set(all.map(x => x.id)); all = all.concat(got.filter(x => !seen.has(x.id))); more = srvSearch ? !!r.more : got.length >= PAGE; paintG(); }
        const refilter = () => { if (!srvSearch) { if (!busy) paintG(); return; } all = []; more = true; G.innerHTML = '<div class="tr-gc ui-skel"></div>'.repeat(4); M.innerHTML = ''; if (busy) setTimeout(refilter, 150); else load(); };
        L.querySelector('.tr-q').oninput = e => { mF.q = e.target.value; clearTimeout(qT); qT = setTimeout(refilter, srvSearch ? 350 : 0); };
        L.querySelector('[data-fwant]').onclick = e => { mF.want = !mF.want; mineSet = myIds(); e.currentTarget.classList.toggle('on', mF.want); refilter(); };
        L.querySelector('[data-fbuy]').onclick = e => { mF.buy = !mF.buy; e.currentTarget.classList.toggle('on', mF.buy); refilter(); };
        L.querySelectorAll('[data-ftype]').forEach(b => b.onclick = () => { mF.type = b.dataset.ftype; L.querySelectorAll('[data-ftype]').forEach(x => x.classList.toggle('on', x === b)); refilter(); });
        L.querySelectorAll('[data-fgr]').forEach(b => b.onclick = () => { const g = b.dataset.fgr; mF.gr.has(g) ? mF.gr.delete(g) : mF.gr.add(g); b.classList.toggle('on', mF.gr.has(g)); refilter(); });
        L.querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { mSort = b.dataset.sort; L.querySelectorAll('[data-sort]').forEach(x => x.classList.toggle('on', x === b)); refilter(); });
        await load();
      } else if (t === 'price') { await priceTab(L);
      } else {
        const r = await rpc('trade_my'); if (!r) return;
        const ib = await rpc('trade_direct_inbox', {}, true), inbox = ib && ib !== 'missing' ? ib.listings || [] : [];
        const ST = { open: '열림', done: '거래 완료', cancelled: '내림', expired: '만료', pending: '대기', accepted: '수락됨', rejected: '거절됨', refunded: '환불됨' };
        // 진행중 = 판매 글 열림 · 제안 대기 / 종료 = 그 밖 (거래 완료·내림·만료·수락됨·거절됨·환불됨) → 회색
        const liveL = l => l.status === 'open', liveO = o => o.status === 'pending', end = myView === 'end';
        const Ls = r.listings.filter(l => liveL(l) !== end), Os = r.offers.filter(o => liveO(o) !== end);
        const nEnd = r.listings.filter(l => !liveL(l)).length + r.offers.filter(o => !liveO(o)).length, nLive = r.listings.length + r.offers.length - nEnd;
        L.innerHTML = `<div class="tr-tabs tr-subtabs"><button data-mv="live" class="${end ? '' : 'on'}">진행중 ${nLive}</button><button data-mv="end" class="${end ? 'on' : ''}">종료 ${nEnd}</button></div>
          ${inbox.length && !end ? `<div class="tr-sec">🤝 받은 지정 거래 ${inbox.length}</div>${inbox.map(l => `<button class="tr-row tr-dirrow" data-dl="${l.id}"><div class="tr-items">${itemsHTML(l.cards, l.gear)}${l.give_drinks ? `<div class="tr-cur">${curTxt(l.give_drinks, 0)}</div>` : ''}</div>
            <div class="tr-meta"><span class="tr-tag s-open">${esc(l.seller_name || '플레이어')}님</span><span>${I('timer')}${left(l.expires_at)}</span><span class="tr-btn main">확인</span></div></button>`).join('')}` : ''}
          <div class="tr-sec">내 판매 글</div>${Ls.map(l => `<button class="tr-row ${liveL(l) ? '' : 'tr-ended'}" data-ml="${l.id}"><div class="tr-items">${itemsHTML(l.cards, l.gear)}</div>
            <div class="tr-meta"><span class="tr-tag s-${l.status}">${ST[l.status]}</span>${l.status === 'open' ? `<span>${I('timer')}${left(l.expires_at)}</span><span>${I('trade_offer')}제안 ${l.offers.filter(o => o.status === 'pending').length}</span>` : ''}</div></button>`).join('') || `<div class="tr-empty">${end ? '끝난 판매 글이 없어요' : '진행 중인 판매 글이 없어요'}</div>`}
          <div class="tr-sec">내 제안</div>${Os.map(o => `<div class="tr-row ${liveO(o) ? '' : 'tr-ended'}"><div class="tr-items">${itemsHTML(o.cards, o.gear)}${curTxt(o.drinks, o.gold) ? `<div class="tr-cur">${curTxt(o.drinks, o.gold)}</div>` : ''}</div>
            <div class="tr-meta"><span class="tr-tag s-${o.status}">${ST[o.status]}</span>${o.reoffer_at && new Date(o.reoffer_at) > Date.now() ? `<span>다시 제안: ${left(o.reoffer_at)} 뒤</span>` : ''}${o.status === 'pending' ? `<button class="tr-btn" data-oc="${o.id}">제안 취소</button>` : ''}</div></div>`).join('') || `<div class="tr-empty">${end ? '끝난 제안이 없어요' : '진행 중인 제안이 없어요'}</div>`}`;
        L.querySelectorAll('[data-mv]').forEach(b => b.onclick = () => { myView = b.dataset.mv; draw(tab); });
        L.querySelectorAll('[data-ml]').forEach(b => b.onclick = () => manage(+b.dataset.ml, () => draw(tab)));
        L.querySelectorAll('[data-dl]').forEach(b => b.onclick = () => detail(inbox.find(x => x.id === +b.dataset.dl), () => draw(tab)));
        L.querySelectorAll('[data-oc]').forEach(b => b.onclick = async () => { if (!await ask('제안을 취소할까요?<br><small>보관된 인재·장비·재화가 바로 돌아와요</small>')) return;
          if (await rpc('trade_offer_cancel', { p_offer: +b.dataset.oc })) { toast('↩️ 제안을 취소했어요'); refreshMine(); draw(tab); } });
      }
    };
    draw(tab);
  }
  const refreshMine = () => { S()?.load?.(); window.VRGear?.load?.(true); window.VRDrink?.status?.(); window.VRPlayer?.wallet?.(true); };

  // ---- 📈 시세 (PR6): trade_price_board / trade_price_history — 한 가지 물건을 재화로만 판 거래만, 판매자·구매자 정보 없음
  let pDays = 7, pKind = 'all';
  const itemName = (k, id) => k === 'card' ? (cardOf(id)?.name || '인재') : (defOf(id)?.name || '장비');
  const itemImg = (k, id) => k === 'card' ? `<img src="${IMG}${id}.webp" alt="" loading="lazy">` : defOf(id) ? `<img class="gear" src="${gearIcon(defOf(id))}" alt="" loading="lazy">` : '';
  const statTxt = st => [st?.drink && `${I('cur_drink')}${n(st.drink.median)}`, st?.gold && `${I('cur_gold')}${n(st.gold.median)}`].filter(Boolean).join(' · ');
  const PSOON = '<div class="tr-empty">📈<b>시세는 곧 열려요</b><small>서버 준비가 끝나면 최근 거래 가격을 볼 수 있어요</small></div>';
  function spark(daily, f) { const v = (daily || []).map(d => d[f]).filter(x => x != null); if (v.length < 2) return '';
    const lo = Math.min(...v), hi = Math.max(...v), W = 100, H = 24, pts = v.map((x, i) => `${(i / (v.length - 1) * W).toFixed(1)},${(H - 2 - (hi === lo ? 0.5 : (x - lo) / (hi - lo)) * (H - 4)).toFixed(1)}`).join(' ');
    return `<svg class="tr-spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}"/></svg>`; }
  async function priceTab(L) {
    L.className = 'tr-list tr-prices';
    L.innerHTML = `<div class="tr-filter"><div class="tr-fchips" role="group" aria-label="기간">${[7, 30].map(d => `<button data-pd="${d}" class="${pDays === d ? 'on' : ''}">${d}일</button>`).join('')}</div>
      <div class="tr-fchips" role="group" aria-label="종류">${[['all', '전체'], ['card', '인재'], ['gear', '장비']].map(([k, lb]) => `<button data-pk="${k}" class="${pKind === k ? 'on' : ''}">${lb}</button>`).join('')}</div></div>
      <div class="tr-note">한 가지 물건을 드링크나 골드로만 판 거래의 중앙값이에요. 누가 사고팔았는지는 보이지 않아요.</div><div class="tr-plist">${'<div class="tr-prow ui-skel"></div>'.repeat(3)}</div>`;
    L.querySelectorAll('[data-pd]').forEach(b => b.onclick = () => { pDays = +b.dataset.pd; priceTab(L); });
    L.querySelectorAll('[data-pk]').forEach(b => b.onclick = () => { pKind = b.dataset.pk; priceTab(L); });
    const P = L.querySelector('.tr-plist'), r = await rpc('trade_price_board', { p_days: pDays, p_kind: pKind, p_limit: 30 }, true);
    if (r === 'missing') { P.innerHTML = PSOON; return; }
    if (!r) { P.innerHTML = '<div class="tr-empty"><b>불러오지 못했어요</b></div>'; return; }
    const it = r.items || [];
    if (!it.length) { P.innerHTML = `<div class="tr-empty">🌱<b>아직 거래가 거의 없어요</b><small>최근 ${pDays}일 동안 시세를 낼 만한 거래가 없어요.${pDays === 7 ? ' 30일로 넓혀 보세요.' : ''} 거래가 쌓이면 여기에 가격이 보여요</small></div>`; return; }
    P.innerHTML = (r.total < 5 ? `<div class="tr-fcount">최근 ${pDays}일 거래 ${r.total}건 · 아직 적어서 참고용이에요</div>` : '') + it.map(x => `<button class="tr-prow" data-pi="${x.kind}:${esc(x.id)}"><span class="tr-pimg">${itemImg(x.kind, x.id)}</span>
      <span class="tr-pmain"><b>${esc(itemName(x.kind, x.id))}</b><small>${x.n}건${x.buy_now ? ` · ⚡ ${x.buy_now}` : ''} · ${left0(x.last_at)}</small></span><span class="tr-pval">${statTxt(x) || '-'}</span></button>`).join('');
    P.querySelectorAll('[data-pi]').forEach(b => b.onclick = () => { const [k, ...id] = b.dataset.pi.split(':'); priceHistory(k, id.join(':')); });
  }
  const left0 = t => { const h = Math.floor((Date.now() - new Date(t)) / 3600e3); return h < 1 ? '방금' : h < 24 ? `${h}시간 전` : `${Math.floor(h / 24)}일 전`; };
  async function priceHistory(k, id) {
    const m = pop('<div class="tr-load">불러오는 중…</div>', '', ['exchange-price', '📈 시세']);
    const r = await rpc('trade_price_history', { p_kind: k, p_id: id }, true), B = body(m);
    if (r === 'missing') { B.innerHTML = PSOON; return; } if (!r) { m.remove(); return; }
    const box = (lb, st) => `<div class="tr-pbox"><b>${lb}</b>${st?.n ? `<span>${st.n}건 (⚡${st.buy_now} · 제안 ${st.offer})</span>${['drink', 'gold'].filter(f => st[f]).map(f => `<div class="tr-prng">${I('cur_' + f)}중앙 <b>${n(st[f].median)}</b> <small>${n(st[f].min)}~${n(st[f].max)}</small></div>`).join('')}` : '<span class="dim">거래 없음</span>'}</div>`;
    B.innerHTML = `<div class="tr-phead"><span class="tr-pimg">${itemImg(k, id)}</span><b>${esc(itemName(k, id))}</b></div>
      ${r.d30?.n ? `<div class="tr-pgrid">${box('7일', r.d7)}${box('30일', r.d30)}</div>${spark(r.daily, 'drink') || spark(r.daily, 'gold')}
      <div class="tr-sec">최근 거래</div>${r.recent.map(x => `<div class="tr-prec"><span>${left0(x.at)}</span><span>${x.buy_now ? '⚡ 즉시 구매' : '제안 수락'}</span><b>${curTxt(x.drinks, x.gold)}</b></div>`).join('')}`
        : '<div class="tr-empty">🌱<b>아직 거래 기록이 없어요</b><small>30일 안에 이 물건만 재화로 판 거래가 없어요</small></div>'}`;
  }
  async function trendLine(el, k, id) {   // 글 상세·판매 3단계 한 줄 요약 (조용히: SQL 전·거래 없음이면 숨김)
    if (!el || !id) return; const r = await rpc('trade_price_history', { p_kind: k, p_id: String(id) }, true);
    if (!r || r === 'missing' || !el.isConnected) return; const st = r.d7?.n ? r.d7 : r.d30, d = r.d7?.n ? 7 : 30;
    el.innerHTML = st?.n ? `<button class="tr-trend" type="button">📈 최근 ${d}일 ${st.n}건 · 중앙 ${statTxt(st)}${spark(r.daily, st.drink ? 'drink' : 'gold')}<i>›</i></button>` : '<div class="tr-trend dim">📈 최근 30일 시세 기록이 아직 없어요</div>';
    el.querySelector('button')?.addEventListener('click', () => priceHistory(k, String(id)));
  }

  // ---- 도움말 (규칙 요약, 값은 서버 조절표 기준)
  function help() {
    const c = cfg || {}, B = bands || {}, rng = k => B[k] ? `${I('cur_drink')}${n(B[k].d_min)}~${n(B[k].d_max)}${B[k].g_max != null ? ` · ${I('cur_gold')}${n(B[k].g_min)}~${n(B[k].g_max)}` : ` · ${I('cur_gold')}불가`}` : '-';
    pop(`<div class="tr-head"><b>${I('help')}거래 도움말</b></div><div class="tr-help">
      <p><b>흐름</b> 판매 글에 인재·장비(최대 ${c.max_items || 5}개)를 올리면 바로 보관돼요. 다른 사람은 인재·장비·🥤드링크·🪙골드를 섞어 제안하고, 판매자가 하나를 수락하면 한 번에 교환돼요. 나머지 제안은 자동으로 돌려받아요.</p>
      <p><b>보관</b> 올리거나 제안한 물건·재화는 끝날 때까지 쓸 수 없어요. 거절·취소·글 내리기·${c.listing_hours || 72}시간 만료 때 즉시 돌아와요 (장비는 가방이 꽉 차면 📬 우편함).</p>
      <p><b>수수료</b> 받는 재화의 ${c.fee_pct || 10}%가 사라져요. 물건끼리만 바꾸면 받는 물건 등급별로 골드 수수료를 내요.</p>
      <p><b>골드</b> HR 이하 인재·희귀 이하 장비만 있을 때 쓸 수 있어요. SR 이상 인재나 영웅 장비가 끼면 드링크만 돼요.</p>
      <p><b>거래할 수 없는 것</b> 🔗 스토리 보상 인재, 👑 리더, 🔒 잠근 인재·장비, 장착 중인 장비, 전설·심연 장비, 이벤트·보상으로 받은 🥤 드링크.</p>
      <p><b>함께 넘어가는 것</b> 인재의 레벨·성장, 그리고 그 인재가 내 마지막 사본이면 💠 증표. 장착 장비는 해제돼 내 가방에 남아요. 덱에 든 인재는 덱에서 빠져요.</p>
      <p><b>한도</b> Lv.${c.min_level || 20}·가입 ${c.min_account_days || 7}일부터 · 열린 글 ${c.max_open_listings || 5}개 · 대기 제안 ${c.max_open_offers || 10}개 · 하루 거래 ${c.daily_trades || 5}번 · 같은 상대 7일 ${c.same_partner_7d || 3}번 · 드링크 하루 보내기·받기 각각 ${n(c.daily_drink_send || 10000)} · 거절된 글엔 ${c.reoffer_cooldown_hours || 24}시간 뒤 다시 제안 · 받은 물건은 ${c.resale_hours || 72}시간 뒤 다시 올리기</p>
      <p><b>1개당 가격 범위</b><br>인재 N·R ${rng('card_nr')}<br>인재 HR ${rng('card_hr')}<br>인재 SR ${rng('card_sr')}<br>인재 UR ${rng('card_ur')}<br>인재 MR·LR ${rng('card_mlr')}<br>장비 낡은~고급 ${rng('gear_low')}<br>장비 희귀 ${rng('gear_rare')}<br>장비 영웅 ${rng('gear_hero')}</p>
      <p class="tr-note">이상한 거래는 운영자가 확인할 수 있어요.</p></div>`, '', ['exchange-help', '❓ 거래 도움말']);
  }

  // ---- 글 상세 (남의 글)
  // ---- 원하는 물건 (want_ids: [{k:'card'|'gear', id}])
  const myIds = () => new Set([...(S()?.save?.owned || []).map(o => String(o.id)), ...(window.VRGear?.myGear?.() || []).map(g => String(g.def))]);
  const wantChip = (w, mine) => `<span class="tr-wchip ${mine?.has(String(w.id)) ? 'have' : ''}">${itemImg(w.k, w.id)}<b>${esc(itemName(w.k, w.id))}</b>${w.k === 'card' ? `<i>${gradeOf(w.id)}</i>` : `<i>${TIER[defOf(w.id)?.tier] || ''}</i>`}</span>`;
  const wantsHTML = (ws, mine) => (ws || []).length ? `<div class="tr-wants">${I('trade_want')}<span>원하는 물건</span>${ws.map(w => wantChip(w, mine)).join('')}</div>` : '';
  function wantPicker(cur, max = 5) {
    return new Promise(res => {
      const sel = (cur || []).map(w => ({ ...w })); let tab = 'card', gr = 'UR', q = '';
      const m = pop('', 'wide tr-wpick'); const B = body(m);
      const seen = new Set(), pool = (window.TCG?.POOL || []).filter(c => { const k = String(c.id); if (seen.has(k)) return false; seen.add(k); return true; });
      const gears = Object.values(window.VRGear?._defs?.() || {}).filter(d => (d.tier || 0) <= 5);
      const has = (k, id) => sel.some(w => w.k === k && String(w.id) === String(id));
      const paint = () => {
        const ql = q.trim().toLowerCase();
        const list = tab === 'card' ? pool.filter(c => (ql ? (c.name || '').toLowerCase().includes(ql) : GRADE[c.grade] === gr)).slice(0, 120).map(c => ({ k: 'card', id: String(c.id) }))
          : gears.filter(d => (ql ? (d.name || '').toLowerCase().includes(ql) : String(d.tier) === gr)).slice(0, 120).map(d => ({ k: 'gear', id: d.id }));
        const chips = tab === 'card' ? ['LR', 'MR', 'UR', 'SR', 'HR', 'R', 'N'] : ['5', '4', '3', '2', '1'];
        if (!chips.includes(gr)) gr = chips[0];
        B.innerHTML = `<div class="tr-head"><b>🎯 원하는 물건 고르기</b><span>${sel.length} / ${max}</span></div>
          <div class="tr-wsel">${sel.length ? sel.map((w, i) => `<button class="tr-wchip on" data-rm="${i}">${itemImg(w.k, w.id)}<b>${esc(itemName(w.k, w.id))}</b><i>✕</i></button>`).join('') : '<small class="tr-cf-none">아직 없어요 · 아래에서 눌러 고르세요</small>'}</div>
          <div class="tr-tabs tr-subtabs"><button data-wt="card" class="${tab === 'card' ? 'on' : ''}">인재</button><button data-wt="gear" class="${tab === 'gear' ? 'on' : ''}">장비</button></div>
          <input type="search" class="tr-input tr-wq" placeholder="🔍 이름으로 찾기" value="${esc(q)}">
          <div class="tr-fchips">${chips.map(g => `<button data-wg="${g}" class="${tab === 'card' ? `g-${g}` : ''} ${gr === g && !ql ? 'on' : ''}">${tab === 'card' ? g : TIER[g]}</button>`).join('')}</div>
          <div class="tr-wgrid">${list.map(w => `<button class="tr-wit ${has(w.k, w.id) ? 'on' : ''}" data-wk="${w.k}" data-wid="${esc(w.id)}">${itemImg(w.k, w.id)}<b>${esc(itemName(w.k, w.id))}</b></button>`).join('') || '<div class="tr-empty">없어요</div>'}</div>
          <div class="tr-acts"><button class="tr-btn" data-wc>취소</button><button class="tr-btn main" data-wok>고르기 끝 (${sel.length})</button></div>`;
        B.querySelectorAll('[data-wt]').forEach(b => b.onclick = () => { tab = b.dataset.wt; gr = ''; q = ''; paint(); });
        B.querySelectorAll('[data-wg]').forEach(b => b.onclick = () => { gr = b.dataset.wg; q = ''; paint(); });
        B.querySelectorAll('[data-rm]').forEach(b => b.onclick = () => { sel.splice(+b.dataset.rm, 1); paint(); });
        B.querySelectorAll('[data-wid]').forEach(b => b.onclick = () => { const k = b.dataset.wk, id = b.dataset.wid, i = sel.findIndex(w => w.k === k && String(w.id) === id);
          if (i >= 0) sel.splice(i, 1); else if (sel.length >= max) return toast(`원하는 물건은 ${max}개까지예요`); else sel.push({ k, id }); paint(); });
        const qi = B.querySelector('.tr-wq'); qi.oninput = () => { q = qi.value; const pos = qi.selectionStart; paint(); const n2 = B.querySelector('.tr-wq'); n2.focus(); n2.setSelectionRange(pos, pos); };
        B.querySelector('[data-wc]').onclick = () => { done = true; m.remove(); res(null); };
        B.querySelector('[data-wok]').onclick = () => { done = true; m.remove(); res(sel); };
      };
      let done = false; const o = new MutationObserver(() => { if (!m.isConnected) { o.disconnect(); if (!done) res(null); } }); o.observe(document.body, { childList: true });
      paint();
    });
  }

  // ---- 글 상세: 물건마다 강화·능력치·옵션을 한 줄씩 (서버가 보관한 그대로: 인재 level·ex, 장비 plus·opts)
  const PMUL = [1, 1.10, 1.20, 1.35, 1.50, 1.70];   // gear-core.js PLUS_MULT 와 같음
  const exStars = (ex, max) => max ? `<span class="tr-ex">${'★'.repeat(Math.min(ex, max))}<i>${'☆'.repeat(Math.max(0, max - ex))}</i></span>` : '';
  function cardRow(c) {
    const m = cardOf(c.id), b = S()?.statsOf?.(c), g = gradeOf(c.id), ex = Math.max(0, c.ex | 0);
    const st = b ? `<div class="tr-dstat"><span><i>전투력</i>${n(b.power)}</span><span><i>ATK</i>${n(b.ATK)}</span><span><i>HP</i>${n(b.HP)}</span><span><i>DEF</i>${n(b.DEF)}</span></div>` : '';
    return `<div class="tr-det card g-${g}"><img src="${IMG}${c.id}.webp" alt="" loading="lazy"><div class="tr-dinfo">
      <b><em class="tr-gr g-${g}">${g}</em>${esc(m?.name || c.id)}</b>
      <div class="tr-dsub">Lv.${c.level || 1}${b?.cap ? `<i>/${b.cap}</i>` : ''} · 강화 EX ${ex}${b?.maxEx ? `/${b.maxEx}` : ''} ${exStars(ex, b?.maxEx)}</div>${st}
      <small class="tr-dnote">장비는 함께 오지 않아요 · 능력치는 장비 빼고</small></div></div>`;
  }
  function gearRow(r) {
    const d = defOf(r.def_id || r.def), T = window.VRGear?.txt, p = r.plus | 0;
    const main = d ? `${T?.main?.(d) || ''}${p ? ` → <b>+${Math.round(+d.main_pct * (PMUL[p] || 1) * 10) / 10}%</b>` : ''}` : '';
    const opts = (r.opts || []).map(o => `<span class="tr-opt">${esc(T?.opt?.(o) || `${o.opt} +${o.v}`)}</span>`).join('');
    return `<div class="tr-det gear t-${d?.tier || 0}"><img src="${gearIcon(d)}" alt="" loading="lazy" onerror="this.style.visibility='hidden'"><div class="tr-dinfo">
      <b><em class="tr-gr t-${d?.tier || 0}">${TIER[d?.tier] || ''}</em>${esc(d?.name || '장비')}${p ? ` <span class="tr-plus">+${p}</span>` : ''}</b>
      <div class="tr-dsub">강화 +${p}/5${d?.slot ? ` · ${({ weapon: '무기', armor: '방어구', acc: '장신구' })[d.slot] || d.slot}` : ''}</div>
      ${main ? `<div class="tr-dmain">주 능력 ${main}</div>` : ''}${opts ? `<div class="tr-opts">${opts}</div>` : '<small class="tr-dnote">추가 옵션 없음</small>'}</div></div>`;
  }
  const detRows = (cards, gear) => (cards || []).map(x => cardRow(x.card || x)).join('') + (gear || []).map(x => gearRow(x.row || x)).join('');

  function detail(l, after) {
    if (l.direct && l.to_me) return directDetail(l, after);
    const m = pop(`<div class="tr-head"><b>${l.direct ? `🤝 지정 거래${l.target_name ? ` → ${esc(l.target_name)}` : ''}` : '판매 글'}</b><span>${I('timer')}${left(l.expires_at)} · ${I('trade_offer')}제안 ${l.offers}</span></div>
      <div class="tr-dets">${detRows(l.cards, l.gear)}</div>${wantsHTML(l.want_ids, myIds())}${l.want ? `<div class="tr-want">${I('trade_want')}${esc(l.want)}</div>` : ''}<div class="tr-trend-w"></div>
      <div class="tr-note">다른 사람의 제안 내용은 보이지 않아요</div>
      <div class="tr-acts">${l.my_offer ? '<button class="tr-btn" data-c>내 제안 취소</button>' : '<button class="tr-btn main" data-o>제안하기</button>'}</div>`.replace('<div class="tr-acts">', buyTxt(l) && !l.my_offer ? `<div class="tr-buybox"><div><b>⚡ 즉시 구매</b><span>${buyTxt(l)}</span></div><small>이 가격으로 바로 거래돼요. 판매자는 ${cfg.fee_pct || 10}% 수수료를 뺀 만큼 받아요</small><button class="tr-btn main tr-buy" data-buy>⚡ ${buyTxt(l)}에 바로 사기</button></div><div class="tr-acts">` : '<div class="tr-acts">'), '', ['exchange-post', '판매 글']);
    if ((l.cards?.length || 0) + (l.gear?.length || 0) === 1) trendLine(m.querySelector('.tr-trend-w'), l.cards?.length ? 'card' : 'gear', l.cards?.length ? l.cards[0].id : (l.gear[0].def_id || l.gear[0].def));
    m.querySelector('[data-buy]')?.addEventListener('click', async e => {
      if (!await ask(`<b>⚡ 즉시 구매</b><div class="tr-cf">${cfRow('받을 물건', itemsHTML(l.cards, l.gear))}${cfRow('낼 재화', '', buyTxt(l))}</div><small>확인하면 바로 거래가 끝나요 (되돌릴 수 없어요)</small>`)) return;
      e.target.disabled = true;
      const r = await rpc('trade_buy', { p_listing: l.id, p_drinks: l.buy_drinks || 0, p_gold: l.buy_gold || 0 });
      if (r) { toast(`🤝 구매 완료!${r.mailed_buyer ? ' 장비 일부는 우편함으로 갔어요' : ''}`); refreshMine(); m.remove(); after?.(); } else e.target.disabled = false;
    });
    m.querySelector('[data-o]')?.addEventListener('click', () => { const inPage = m.classList.contains('vr-in-page'); if (!inPage) m.remove(); makeOffer(l, inPage ? () => { if (m.isConnected) m.remove(); after?.(); } : after); });   // 페이지: 제안 화면 뒤로 = 글 상세
    m.querySelector('[data-c]')?.addEventListener('click', async () => { if (!await ask('제안을 취소할까요?')) return; if (await rpc('trade_offer_cancel', { p_offer: l.my_offer })) { toast('↩️ 제안을 취소했어요'); m.remove(); refreshMine(); after?.(); } });
  }

  // ---- 고르기 목록: 못 올리는 이유 표시
  function cardBlock(o, save) {
    if (o.uid === save.leader) return I('leader_crown') + '리더';
    if (o.bound !== false) return I('bound') + '귀속';
    if (o.locked && !o.dlk) return I('lock') + '잠금';
    if (o.traded_at && o.traded_at * 1000 > Date.now() - (cfg.resale_hours || 72) * 3600e3) return I('timer') + '재판매 대기';
    return '';
  }
  function gearBlock(g) {
    const d = defOf(g.def);
    if (g.card) return '장착 중'; if (g.locked) return I('lock') + '잠금'; if ((d?.tier || 0) > 5) return '거래 불가 등급';
    return '';
  }
  // 못 올리는 이유 (자세히)
  function whyLong(x, isCard, save) {
    if (!x) return '이 물건은 올릴 수 없어요';
    if (isCard) {
      if (x.uid === save?.leader) return '👑 리더는 올릴 수 없어요. 마이에서 리더를 바꾸면 올릴 수 있어요';
      if (x.bound !== false) return '🔗 스토리 보상으로 받은 인재는 거래할 수 없어요';
      if (x.locked && !x.dlk) return '🔒 잠긴 인재예요. 잠금을 풀면 올릴 수 있어요';
      if (x.traded_at) { const h = Math.ceil((x.traded_at * 1000 + (cfg.resale_hours || 72) * 3600e3 - Date.now()) / 3600e3); if (h > 0) return `⏳ 거래로 받은 인재는 ${cfg.resale_hours || 72}시간 뒤에 다시 올릴 수 있어요 (약 ${h}시간 남음)`; }
    } else {
      if (x.card) return '장착 중인 장비예요. 먼저 해제해 주세요';
      if (x.locked) return '🔒 잠긴 장비예요. 잠금을 풀면 올릴 수 있어요';
      if ((defOf(x.def)?.tier || 0) > 5) return '전설·심연 장비는 거래할 수 없어요';
      if (x.traded_at) return `⏳ 거래로 받은 장비는 ${cfg.resale_hours || 72}시간 뒤에 다시 올릴 수 있어요`;
    }
    return '이 물건은 올릴 수 없어요';
  }
  // ---- 정렬 (인재: 등급·레벨·이름·획득 / 장비: 등급·강화·이름). 같은 버튼 다시 누르면 ▼▲ 전환, 기억함. 못 올리는 것도 제자리(흐리게)
  const G_ORD = ['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'];
  const CSORT = { grade: '등급', level: '레벨', name: '이름', new: '획득' }, GSORT = { tier: '등급', plus: '강화', name: '이름' };
  const SK = 'vr-trade-sort';
  let srt = (() => { try { const v = JSON.parse(localStorage.getItem(SK)); if (v?.c && CSORT[v.c.k] && v?.g && GSORT[v.g.k]) return v; } catch {} return { c: { k: 'grade', desc: true }, g: { k: 'tier', desc: true } }; })();
  const setSrt = (w, k) => { srt[w] = srt[w].k === k ? { k, desc: !srt[w].desc } : { k, desc: true }; try { localStorage.setItem(SK, JSON.stringify(srt)); } catch {} };
  const cmpName = (a, b) => String(a || '').localeCompare(String(b || ''), 'ko');
  function sortCards(list) {
    const { k, desc } = srt.c, d = desc ? -1 : 1;
    const gi = o => G_ORD.indexOf(gradeOf(o.id)), nm = o => cardOf(o.id)?.name || o.id;
    return list.slice().sort((A, B) => { const a = A.o, b = B.o;
      const v = k === 'grade' ? gi(a) - gi(b) : k === 'level' ? (a.level | 0) - (b.level | 0) : k === 'name' ? cmpName(nm(a), nm(b)) : A.i - B.i;
      return v * d || (gi(b) - gi(a)) || ((b.level | 0) - (a.level | 0)) || cmpName(nm(a), nm(b)) || (B.i - A.i); });
  }
  function sortGear(list) {
    const { k, desc } = srt.g, d = desc ? -1 : 1;
    const t = g => defOf(g.def)?.tier || 0, nm = g => defOf(g.def)?.name || '';
    return list.slice().sort((A, B) => { const a = A.g, b = B.g;
      const v = k === 'tier' ? t(a) - t(b) : k === 'plus' ? (a.plus | 0) - (b.plus | 0) : cmpName(nm(a), nm(b));
      return v * d || (t(b) - t(a)) || ((b.plus | 0) - (a.plus | 0)) || cmpName(nm(a), nm(b)) || (b.id - a.id); });
  }
  const sortBar = (w, opts) => `<div class="tr-sortbar">${Object.entries(opts).map(([k, l]) => `<button type="button" class="story-chip tr-chip ${srt[w].k === k ? 'on' : ''}" data-srt="${w}:${k}" aria-pressed="${srt[w].k === k}">${l}${srt[w].k === k ? (srt[w].desc ? ' ▼' : ' ▲') : ''}</button>`).join('')}</div>`;

  async function picker(host, onChange) {
    await S()?.load?.(); const save = S()?.save; const gs = (await window.VRGear?.load?.(true))?.gear || [];
    const inDeck = new Set((save?.decks || []).flatMap(d => d?.uids || []));
    const sel = { cards: new Set(), gear: new Set() }, max = cfg.max_items || 5;
    const cards = (save?.owned || []).map((o, i) => ({ o, i, why: cardBlock(o, save) }));
    const gear = gs.map(g => ({ g, why: gearBlock(g) }));
    const count = () => sel.cards.size + sel.gear.size;
    const draw = () => {
      host.innerHTML = `<div class="tr-sec-row"><div class="tr-sec">인재</div>${sortBar('c', CSORT)}</div><div class="tr-pick">${sortCards(cards).map(({ o, why }) => `<div class="tr-pk ${why ? 'no' : ''} ${sel.cards.has(o.uid) ? 'on' : ''}" data-pc="${esc(o.uid)}">${cardTile(o)}${why ? `<i>${why}</i>` : inDeck.has(o.uid) ? '<i class="soft">덱에서 빠짐</i>' : ''}</div>`).join('') || '<div class="tr-empty">인재가 없어요</div>'}</div>
        <div class="tr-sec-row"><div class="tr-sec">장비</div>${gear.length > 1 ? sortBar('g', GSORT) : ''}</div><div class="tr-pick">${sortGear(gear).map(({ g, why }) => `<div class="tr-pk ${why ? 'no' : ''} ${sel.gear.has(g.id) ? 'on' : ''}" data-pg="${g.id}">${gearTile(g)}${why ? `<i>${why}</i>` : ''}</div>`).join('') || '<div class="tr-empty">장비가 없어요</div>'}</div>`;
      host.querySelectorAll('[data-srt]').forEach(b => b.onclick = () => { const [w, k] = b.dataset.srt.split(':'); setSrt(w, k); draw(); });
      host.querySelectorAll('[data-pc],[data-pg]').forEach(el => el.onclick = () => {
        if (el.classList.contains('no')) { const k = 'pc' in el.dataset ? save.owned.find(o => o.uid === el.dataset.pc) : gs.find(g => g.id === +el.dataset.pg); return toast(whyLong(k, 'pc' in el.dataset, save)); }
        const isC = 'pc' in el.dataset, set = isC ? sel.cards : sel.gear, k = isC ? el.dataset.pc : +el.dataset.pg;
        if (set.has(k)) set.delete(k); else { if (count() >= max) return toast(`한쪽에 최대 ${max}개까지예요`); set.add(k); }
        el.classList.toggle('on', set.has(k)); onChange?.();
      });
    };
    draw();
    const keys = () => [...[...sel.cards].map(u => cardKey(save.owned.find(o => o.uid === u)?.id)), ...[...sel.gear].map(id => gearKey(defOf(gs.find(g => g.id === id)?.def)?.tier || 1))];
    const tiles = () => [...sel.cards].map(u => save.owned.find(o => o.uid === u)).filter(Boolean).map(cardTile).join('') + [...sel.gear].map(id => gs.find(g => g.id === id)).filter(Boolean).map(gearTile).join('');
    return { sel, count, keys, tiles, defOf: id => gs.find(g => g.id === id)?.def };
  }

  // ---- 판매 글 올리기 (PR3: 단계식) 1 물건 고르기 → 2 희망 조건 → 3 미리보기(가격 범위·수수료) · 뒤로 = 한 단계씩
  function gateMsg(myOpen) {   // 서버 규칙을 미리 안내 (최종 판단은 서버)
    const c = cfg || {}, st = window.VRPlayer?.now?.(), u = window.VRCloud?.user, out = [];
    if (st?.level != null && st.level < (c.min_level || 20)) out.push(`계정 Lv.${c.min_level || 20}부터 거래할 수 있어요 (지금 Lv.${st.level})`);
    if (u?.created_at) { const d = Math.ceil((new Date(u.created_at).getTime() + (c.min_account_days || 7) * 864e5 - Date.now()) / 864e5); if (d > 0) out.push(`가입 ${c.min_account_days || 7}일 뒤부터 거래할 수 있어요 (${d}일 남음)`); }
    if (myOpen >= (c.max_open_listings || 5)) out.push(`열린 판매 글이 ${myOpen}개예요. 최대 ${c.max_open_listings || 5}개까지라 하나를 내리거나 끝나야 올릴 수 있어요`);
    return out;
  }
  function bandRows(keys) {
    const pct = cfg.fee_pct || 10, cnt = {}; keys.forEach(k => { cnt[k] = (cnt[k] || 0) + 1; });
    const rows = Object.entries(cnt).map(([k, c]) => { const b = bands[k] || {};
      return `<tr><td>${esc(b.label || k)}${c > 1 ? ` ×${c}` : ''}</td><td>${I('cur_drink')}${n(b.d_min * c)}~${n(b.d_max * c)}</td><td>${b.g_max != null ? `${I('cur_gold')}${n(b.g_min * c)}~${n(b.g_max * c)}` : '<span class="dim">골드 불가</span>'}</td></tr>`; }).join('');
    const B = k => bands[k] || {}, sum = f => keys.reduce((a, k) => a + (+B(k)[f] || 0), 0), goldOk = keys.every(k => B(k).g_max != null);
    return `<table class="tr-band"><thead><tr><th>물건</th><th>드링크</th><th>골드</th></tr></thead><tbody>${rows}</tbody>
      <tfoot><tr><td>합계</td><td>${I('cur_drink')}${n(sum('d_min'))}~${n(sum('d_max'))}</td><td>${goldOk ? `${I('cur_gold')}${n(sum('g_min'))}~${n(sum('g_max'))}` : '<span class="dim">골드 불가</span>'}</td></tr></tfoot></table>
      <div class="tr-fee"><b>예상 수수료</b><ul><li>재화(드링크·골드)를 받으면 받는 양의 ${pct}%가 사라져요 (올림). 예: ${I('cur_drink')}${n(sum('d_max'))} → 실제 ${n(sum('d_max') - Math.ceil(sum('d_max') * pct / 100))}</li>
      <li>물건만 받고 바꾸면 받는 물건 등급별로 고정 골드 수수료를 내요</li>${goldOk ? '' : '<li>SR 이상 인재·영웅 장비가 있어 골드 제안은 받을 수 없어요 (드링크만)</li>'}</ul></div>`;
  }
  async function createListing(after) {
    const max = cfg.max_items || 5, H = cfg.listing_hours || 72;
    let step = 1, want = '', p = null, wantIds = [];
    const m = pop('<div class="tr-load">불러오는 중…</div>', 'wide', ['exchange-new', '＋ 판매 글 올리기', () => { if (step > 1) { go(step - 1); return true; } return false; }]);
    const mine = await rpc('trade_my'); const myOpen = (mine?.listings || []).filter(l => l.status === 'open').length;
    const gates = gateMsg(myOpen);
    const B = body(m);
    B.innerHTML = `<div class="tr-steps">${['물건 고르기', '희망 조건', '확인'].map((t, i) => `<span data-st="${i + 1}"><i>${i + 1}</i>${t}</span>`).join('')}</div>
      ${gates.length ? `<div class="tr-gate">${gates.map(g => `<p>⛔ ${esc(g)}</p>`).join('')}</div>` : ''}
      <section data-step="1"><div class="tr-note">팔 인재·장비를 골라 주세요 (최대 ${max}개). 흐린 것은 눌러 보면 이유가 나와요.</div><div class="tr-pickwrap"></div></section>
      <section data-step="2" hidden><div class="tr-note">원하는 조건을 적어 주세요 (선택, 100자). 다른 사람이 제안할 때 참고해요.</div>
        <div class="tr-items tr-sel2"></div><div class="tr-wbox"><button type="button" class="tr-btn" data-wpick>🎯 원하는 물건 고르기 <small>(선택 · 최대 5)</small></button><div class="tr-wcur"></div></div><textarea class="tr-input tr-want-in" maxlength="100" rows="3" placeholder="예: 드링크 2,000 이상 · SR 인재와 교환"></textarea><small class="tr-wc">0 / 100</small></section>
      <section data-step="3" hidden><div class="tr-cf"></div></section>
      <div class="tr-acts tr-step-acts"><button class="tr-btn" data-prev>이전</button><span class="tr-cnt">0 / ${max}</span><button class="tr-btn main" data-next disabled>다음</button></div>`;
    const next = B.querySelector('[data-next]'), prev = B.querySelector('[data-prev]'), cnt = B.querySelector('.tr-cnt'), ta = B.querySelector('.tr-want-in');
    function go(k) {
      step = k; B.querySelectorAll('[data-step]').forEach(x => { x.hidden = +x.dataset.step !== k; });
      B.querySelectorAll('[data-st]').forEach(x => { x.classList.toggle('on', +x.dataset.st === k); x.classList.toggle('done', +x.dataset.st < k); });
      prev.style.visibility = k > 1 ? 'visible' : 'hidden'; cnt.hidden = k !== 1;
      next.textContent = k === 3 ? '📤 올리기' : '다음'; next.disabled = !p?.count() || (k === 3 && gates.length > 0);
      if (k === 2) B.querySelector('.tr-sel2').innerHTML = p.tiles();
      if (k === 3) { want = ta.value.trim();
        B.querySelector('[data-step="3"] .tr-cf').innerHTML = `${cfRow('올릴 물건', p.tiles())}<div class="tr-cf-row"><div class="tr-cf-l">희망 조건</div><div>${want ? esc(want) : '<span class="tr-cf-none">없음</span>'}</div></div>${wantIds.length ? `<div class="tr-cf-row"><div class="tr-cf-l">원하는 물건</div><div class="tr-wants">${wantIds.map(w => wantChip(w)).join('')}</div></div>` : ''}
          <div class="tr-trend-w"></div><div class="tr-sec">허용 가격 범위 (등급별 · 서버 기준)</div>${bandRows(p.keys())}
          <div class="tr-buyset"><label class="tr-buy-on"><input type="checkbox" data-buyon ${buy.on ? 'checked' : ''}> ⚡ 즉시 구매가 정하기 <small>(선택)</small></label>
            <div class="tr-buy-in" ${buy.on ? '' : 'hidden'}>${goldOk() ? `<div class="tr-fchips"><button type="button" data-bcur="d" class="${buy.cur === 'd' ? 'on' : ''}">🥤 드링크</button><button type="button" data-bcur="g" class="${buy.cur === 'g' ? 'on' : ''}">🪙 골드</button></div>` : ''}
            <input type="number" inputmode="numeric" min="1" step="1" class="tr-input" data-bamt value="${buy.amt || ''}" placeholder="가격"><small class="tr-buy-hint"></small></div></div>
          <div class="tr-note">올리는 순간 보관돼 게임에서 쓸 수 없고, ${H}시간 뒤 팔리지 않으면 돌아와요.${deckN() ? ` 덱에 든 인재 ${deckN()}명은 덱에서 빠져요.` : ''}${p.sel.cards.size ? ' 마지막 같은 인재면 장착 장비는 해제돼 내 가방에 남아요.' : ''}</div>
          ${gates.length ? `<div class="tr-gate">${gates.map(g => `<p>⛔ ${esc(g)}</p>`).join('')}</div>` : ''}`; }
      if (k === 3) { bindBuy(); if (p.count() === 1) { const u = [...p.sel.cards][0], g = [...p.sel.gear][0]; trendLine(B.querySelector('[data-step="3"] .tr-trend-w'), u ? 'card' : 'gear', u ? S()?.save?.owned?.find(o => o.uid === u)?.id : p.defOf(g)); } }
      B.closest('.vr-page-body, .tr-pop')?.scrollTo?.(0, 0);
    }
    const buy = { on: false, cur: 'd', amt: 0 };
    const rng = () => { const ks = p.keys(), sum = f => ks.reduce((a, k) => a + (+(bands[k] || {})[f] || 0), 0); return buy.cur === 'g' ? [sum('g_min'), sum('g_max')] : [sum('d_min'), sum('d_max')]; };
    const goldOk = () => p.keys().every(k => (bands[k] || {}).g_max != null);
    const buyErr = () => { if (!buy.on) return ''; const [lo, hi] = rng(); if (!buy.amt) return '가격을 넣어 주세요'; if (buy.amt < lo) return `범위보다 적어요 (최소 ${n(lo)})`; if (buy.amt > hi) return `범위보다 많아요 (최대 ${n(hi)})`; return ''; };
    function bindBuy() {
      const S3 = B.querySelector('[data-step="3"]'), box = S3.querySelector('.tr-buy-in'), hint = S3.querySelector('.tr-buy-hint'), amt = S3.querySelector('[data-bamt]');
      if (!goldOk()) buy.cur = 'd';
      const upd = () => { const [lo, hi] = rng(), e = buyErr(), pct = cfg.fee_pct || 10;
        hint.innerHTML = e ? `<span class="bad">${e}</span>` : buy.on ? `범위 ${n(lo)}~${n(hi)} · 팔리면 ${n(buy.amt - Math.ceil(buy.amt * pct / 100))} 받음 (${pct}% 소각)` : '';
        hint.classList.toggle('bad', !!e); next.disabled = !p.count() || gates.length > 0 || !!e; };
      S3.querySelector('[data-buyon]').onchange = ev => { buy.on = ev.target.checked; box.hidden = !buy.on; upd(); };
      S3.querySelectorAll('[data-bcur]').forEach(b => b.onclick = () => { buy.cur = b.dataset.bcur; S3.querySelectorAll('[data-bcur]').forEach(x => x.classList.toggle('on', x === b)); upd(); });
      amt.oninput = () => { buy.amt = Math.max(0, Math.floor(+amt.value || 0)); upd(); };
      upd();
    }
    const deckN = () => [...p.sel.cards].filter(u => (S()?.save?.decks || []).some(d => (d?.uids || []).includes(u))).length;
    const paintW = () => { B.querySelector('.tr-wcur').innerHTML = wantIds.length ? `<div class="tr-wants">${wantIds.map(w => wantChip(w)).join('')}</div>` : ''; };
    B.querySelector('[data-wpick]').onclick = async () => { const r = await wantPicker(wantIds); if (r) { wantIds = r; paintW(); } };
    ta.oninput = () => { B.querySelector('.tr-wc').textContent = `${ta.value.length} / 100`; };
    prev.onclick = () => go(step - 1);
    next.onclick = async () => {
      if (step < 3) return go(step + 1);
      next.disabled = true;
      const base = { p_cards: [...p.sel.cards], p_gear: [...p.sel.gear], p_want: want };
      let r;
      if (wantIds.length) { r = await rpc('trade_list3', { ...base, p_buy_drinks: buy.on && buy.cur === 'd' ? buy.amt : null, p_buy_gold: buy.on && buy.cur === 'g' ? buy.amt : null, p_want_ids: wantIds }, true); if (r === 'missing') { r = null; toast('🎯 원하는 물건 지정은 서버 준비 중이에요. 빼고 올려 주세요'); } }
      else if (buy.on) { r = await rpc('trade_list2', { ...base, p_buy_drinks: buy.cur === 'd' ? buy.amt : null, p_buy_gold: buy.cur === 'g' ? buy.amt : null }, true); if (r === 'missing') { r = null; toast('⚡ 즉시 구매는 서버 준비 중이에요. 가격 없이 올리려면 체크를 꺼 주세요'); } }
      else r = await rpc('trade_list', base);
      if (r) { toast('📤 판매 글을 올렸어요'); m.remove(); refreshMine(); after?.(); } else next.disabled = false;
    };
    p = await picker(B.querySelector('.tr-pickwrap'), () => { cnt.textContent = `${p.count()} / ${max}`; next.disabled = !p.count(); });
    go(1);
  }

  // ---- 가격·골드 미리보기
  function priceInfo(lKeys, oKeys, drinks, gold) {
    const B = k => bands[k] || {}, sum = (ks, f) => ks.reduce((a, k) => a + (+B(k)[f] || 0), 0);
    const goldOk = [...lKeys, ...oKeys].every(k => B(k).g_max != null);
    const dmin = sum(lKeys, 'd_min'), dmax = sum(lKeys, 'd_max'), gmin = sum(lKeys, 'g_min'), gmax = sum(lKeys, 'g_max');
    const pct = cfg.fee_pct || 10, onlyItems = !drinks && !gold;
    let err = '';
    if (gold > 0 && !goldOk) err = ERR['gold not allowed'];
    else if (drinks > dmax || gold > (goldOk ? gmax : 0)) err = ERR['price too high'];
    else if (!oKeys.length && (drinks || gold) && drinks / Math.max(dmin, 1) + (goldOk && gmin ? gold / gmin : 0) < 1) err = ERR['price too low'];
    else if (!oKeys.length && onlyItems) err = ERR['nothing to offer'];
    const fix = onlyItems ? lKeys.reduce((a, k) => a + (+B(k).fix_fee || 0), 0) : 0;
    const html = `<div class="tr-rule"><div>${I('cur_drink')}드링크 ${oKeys.length ? `최대 ${n(dmax)}` : `${n(dmin)} ~ ${n(dmax)}`}</div>
      <div>${I('cur_gold')}골드 ${goldOk ? (oKeys.length ? `최대 ${n(gmax)}` : `${n(gmin)} ~ ${n(gmax)}`) : '<b class="no">불가</b> (SR 이상 인재·영웅 장비 포함)'}</div>
      <div>${I('fee_burn')}${onlyItems ? `물건끼리: 수수료 골드 ${n(fix)} (제안할 때 보관)` : `판매자는 ${pct}% 수수료 뒤 ${curTxt(drinks - Math.ceil(drinks * pct / 100), gold - Math.ceil(gold * pct / 100))} 받아요`}</div>
      ${err ? `<div class="tr-err">${err}</div>` : ''}</div>`;
    return { html, err, fix };
  }

  // ---- 제안하기
  async function makeOffer(l, after, direct) {
    const lKeys = [...(l.cards || []).map(c => c.gkey), ...(l.gear || []).map(g => g.gkey)];
    const dr = await window.VRDrink?.status?.(), gold = window.VRPlayer?.walletNow?.gold;
    const m = pop(`<div class="tr-head"><b>${direct ? '🤝 지정 거래 수락' : '제안하기'}</b></div><div class="tr-items">${itemsHTML(l.cards, l.gear)}${l.give_drinks ? `<div class="tr-cur">${curTxt(l.give_drinks, 0)}</div>` : ''}</div>${direct ? wantsHTML(l.want_ids, myIds()) : ''}
      <div class="tr-sec">내가 줄 것 (인재·장비는 선택)</div>
      <div class="tr-cur-in"><label>🥤 드링크 <input type="number" min="0" step="1" value="0" data-d><small>거래 가능 ${n((dr?.tradable || 0) - (dr?.locked || 0))}</small></label>
        <label>${I('cur_gold')}골드 <input type="number" min="0" step="100" value="0" data-g>${gold != null ? `<small>보유 ${n(gold)}</small>` : ''}</label></div>
      <div class="tr-info"></div><div class="tr-pickwrap"></div>
      <div class="tr-acts"><button class="tr-btn main" data-ok>${direct ? '🤝 수락하고 거래 끝내기' : '제안 보내기'}</button></div>`, 'wide', ['exchange-offer', direct ? '🤝 지정 거래 수락' : '📨 제안하기']);
    const val = s => Math.max(0, Math.floor(+m.querySelector(s).value || 0));
    let p = null;
    const upd = () => { const i = priceInfo(lKeys, p ? p.keys() : [], val('[data-d]'), val('[data-g]')); m.querySelector('.tr-info').innerHTML = i.html; m.querySelector('[data-ok]').disabled = !!i.err; return i; };
    m.querySelectorAll('[data-d],[data-g]').forEach(x => x.oninput = upd); upd();
    p = await picker(m.querySelector('.tr-pickwrap'), upd); upd();
    m.querySelector('[data-ok]').onclick = async () => {
      const i = upd(); if (i.err) return toast(i.err);
      const d = val('[data-d]'), g = val('[data-g]');
      if (!await ask(`${direct ? '이 조건으로 수락할까요? <small>(바로 거래가 끝나요, 되돌릴 수 없어요)</small>' : '이 조건으로 제안할까요?'}<div class="tr-cf">${cfRow('내가 주는 것', p.tiles(), curTxt(d, g))}${cfRow('상대가 주는 것', itemsHTML(l.cards, l.gear), l.give_drinks ? curTxt(l.give_drinks, 0) : '')}</div>${i.fix ? `<b>수수료 ${I('cur_gold')}${n(i.fix)}</b>` : ''}`)) return;
      const r = await rpc(direct ? 'trade_direct_accept' : 'trade_offer', { p_listing: l.id, p_cards: [...p.sel.cards], p_gear: [...p.sel.gear], p_drinks: d, p_gold: g });
      if (r) { toast(direct ? `🤝 거래 완료!${r.got_drinks ? ` 드링크 ${n(r.got_drinks)} 받음` : ''}${r.mailed_buyer ? ' 장비 일부는 우편함으로 갔어요' : ''}` : '📨 제안을 보냈어요'); m.remove(); refreshMine(); after?.(); }
    };
  }

  // ---- 지정 거래 (PR3): 받은 사람 화면 · 보내기
  function directDetail(l, after) {
    const pct = cfg?.fee_pct || 10;
    const m = pop(`<div class="tr-head"><b>🤝 ${esc(l.seller_name || '플레이어')}님의 지정 거래</b><span>${I('timer')}${left(l.expires_at)}</span></div>
      <div class="tr-sec">받을 것</div><div class="tr-dets">${detRows(l.cards, l.gear)}</div>
      ${l.give_drinks ? `<div class="tr-dgive">🥤 드링크 <b>${n(l.give_drinks)}</b> <small>(받을 때 ${pct}% 소각 → ${n(l.give_drinks - Math.ceil(l.give_drinks * pct / 100))})</small></div>` : ''}
      ${wantsHTML(l.want_ids, myIds())}${l.want ? `<div class="tr-want">${I('trade_want')}${esc(l.want)}</div>` : ''}
      <div class="tr-note">수락하면 원하는 물건을 내고 바로 거래가 끝나요. 거래 규칙(Lv.20 · 가입 7일 · 하루 5번 · 같은 상대 7일 3번)은 똑같이 적용돼요.</div>
      <div class="tr-acts"><button class="tr-btn danger" data-dec>거절</button><button class="tr-btn main" data-acc>수락하기</button></div>`, 'wide', ['exchange-detail', '🤝 지정 거래']);
    m.querySelector('[data-acc]').onclick = () => { const inPage = m.classList.contains('vr-in-page'); if (!inPage) m.remove(); makeOffer(l, inPage ? () => { if (m.isConnected) m.remove(); after?.(); } : after, true); };
    m.querySelector('[data-dec]').onclick = async () => { if (!await ask('지정 거래를 거절할까요?<br><small>보낸 사람에게 물건이 돌아가고 우편으로 알려요</small>', true)) return;
      if (await rpc('trade_direct_decline', { p_listing: l.id })) { toast('🙅 거절했어요'); m.remove(); after?.(); } };
    return m;
  }
  async function directCreate(target, after) {
    const max = cfg?.max_items || 5; let who = target || null, wantIds = [], p = null, qT = 0;
    const dr = await window.VRDrink?.status?.();
    const m = pop('', 'wide', ['exchange-direct', '🤝 지정 거래']); const B = body(m);
    B.innerHTML = `<div class="tr-head"><b>🤝 지정 거래 보내기</b></div>
      <div class="tr-sec">1. 받는 사람</div><div class="tr-dwho"></div>
      <div class="tr-sec">2. 내가 줄 것 (인재·장비 최대 ${max}개 · 드링크 · 드링크만도 가능)</div>
      <div class="tr-cur-in"><label>🥤 드링크 <input type="number" min="0" step="1" value="0" data-d><small>거래 가능 ${n((dr?.tradable || 0) - (dr?.locked || 0))}</small></label></div>
      <div class="tr-pickwrap"></div>
      <div class="tr-sec">3. 원하는 것</div><div class="tr-wbox"><button type="button" class="tr-btn" data-wpick>🎯 원하는 물건 고르기 <small>(최대 5)</small></button><div class="tr-wcur"></div></div>
      <div class="tr-sec">4. 메시지 (우편으로 가요)</div><textarea class="tr-input tr-dmsg" maxlength="200" rows="2" placeholder="예: 김성진이랑 바꿔요! UR 5장 + 드링크 드릴게요"></textarea>
      <div class="tr-note">보내면 물건·드링크가 보관되고, 상대가 수락하면 바로 거래가 끝나요. 거절·만료되면 그대로 돌아와요. 받는 사람도 똑같은 거래 규칙이 적용돼요.</div>
      <div class="tr-acts"><button class="tr-btn main" data-send disabled>🤝 보내기</button></div>`;
    const send = B.querySelector('[data-send]'), dIn = B.querySelector('[data-d]');
    const dv = () => Math.max(0, Math.floor(+dIn.value || 0));
    const ok = () => { const items = p?.count() || 0; send.disabled = !who || (!items && !(dv() > 0 && wantIds.length)); const h = B.querySelector('.tr-dhint'); if (h) h.textContent = !items && dv() > 0 && !wantIds.length ? '드링크만 보낼 땐 원하는 물건을 하나 이상 골라 주세요' : ''; };
    const paintWho = () => { const W = B.querySelector('.tr-dwho');
      if (who) { W.innerHTML = `<div class="tr-dsel"><b>${esc(who.nick)}</b><button class="tr-btn" data-chg>바꾸기</button></div>`; W.querySelector('[data-chg]').onclick = () => { who = null; paintWho(); ok(); }; return; }
      W.innerHTML = `<input type="search" class="tr-input tr-dq" placeholder="🔍 닉네임으로 찾기"><div class="tr-dres"></div>`;
      const q = W.querySelector('.tr-dq'), R = W.querySelector('.tr-dres'); q.focus();
      q.oninput = () => { clearTimeout(qT); qT = setTimeout(async () => { const v = q.value.trim(); if (!v) { R.innerHTML = ''; return; }
        const r = await rpc('trade_user_find', { p_q: v }, true); if (r === 'missing') { R.innerHTML = '<small>🤝 지정 거래는 서버 준비 중이에요</small>'; return; }
        const us = r?.users || []; R.innerHTML = us.length ? us.map(u => `<button class="tr-wchip on" data-uid="${esc(u.id)}">${esc(u.nick)}</button>`).join('') : '<small class="tr-cf-none">찾는 사람이 없어요</small>';
        R.querySelectorAll('[data-uid]').forEach(b => b.onclick = () => { who = us.find(u => u.id === b.dataset.uid); paintWho(); ok(); }); }, 300); };
    };
    paintWho();
    const paintW = () => { B.querySelector('.tr-wcur').innerHTML = wantIds.length ? `<div class="tr-wants">${wantIds.map(w => wantChip(w)).join('')}</div>` : ''; };
    B.querySelector('[data-wpick]').onclick = async () => { const r = await wantPicker(wantIds); if (r) { wantIds = r; paintW(); ok(); } };
    dIn.oninput = ok; B.querySelector('[data-send]').insertAdjacentHTML('beforebegin', '<small class="tr-dhint bad"></small>');
    p = await picker(B.querySelector('.tr-pickwrap'), ok); ok();
    send.onclick = async () => {
      const d = Math.max(0, Math.floor(+dIn.value || 0)), msg = B.querySelector('.tr-dmsg').value.trim();
      if (!await ask(`<b>${esc(who.nick)}</b>님에게 지정 거래를 보낼까요?<div class="tr-cf">${cfRow('내가 주는 것', p.tiles(), curTxt(d, 0))}${cfRow('원하는 것', wantIds.map(w => wantChip(w)).join(''))}</div>`)) return;
      send.disabled = true;
      const r = await rpc('trade_direct_list', { p_target: who.id, p_cards: [...p.sel.cards], p_gear: [...p.sel.gear], p_drinks: d, p_want: '', p_want_ids: wantIds, p_msg: msg }, true);
      if (r === 'missing') { toast('🤝 지정 거래는 서버 준비 중이에요'); send.disabled = false; return; }
      if (r) { toast(`🤝 ${who.nick}님에게 보냈어요 (우편으로 알렸어요)`); m.remove(); refreshMine(); after?.(); } else send.disabled = false;
    };
    return m;
  }

  // ---- 내 글 관리: 제안 목록 · 수락 · 거절 · 조건 거절 · 내리기
  async function manage(id, after) {
    const m = pop('<div class="tr-load">불러오는 중…</div>', 'wide', ['exchange-mine', '📦 내 판매 글']);
    const draw = async () => {
      const r = await rpc('trade_my'); if (!r) return m.remove();
      const l = r.listings.find(x => x.id === id); if (!l) { m.remove(); return toast(ERR['listing not found']); }
      const offs = l.offers.filter(o => o.status === 'pending'), sel = new Set();
      let sort = 'cur';
      const list = () => offs.slice().sort((a, b) => sort === 'new' ? b.id - a.id : (b.drinks - a.drinks) || (b.gold - a.gold));
      const row = o => `<div class="tr-off" data-of="${o.id}"><label class="tr-chk"><input type="checkbox" data-sel="${o.id}"></label>
        <div class="tr-off-b"><div class="tr-nick">${esc(o.nick || '익명')}</div><div class="tr-items">${itemsHTML(o.cards, o.gear)}${curTxt(o.drinks, o.gold) ? `<div class="tr-cur">${curTxt(o.drinks, o.gold)}</div>` : ''}</div></div>
        <div class="tr-off-a"><button class="tr-btn main" data-ac="${o.id}">수락</button><button class="tr-btn" data-rj="${o.id}">거절</button></div></div>`;
      body(m).innerHTML = `<div class="tr-head"><b>내 판매 글</b>${l.status === 'open' ? `<span>${I('timer')}${left(l.expires_at)}</span>` : ''}</div>
        <div class="tr-items big">${itemsHTML(l.cards, l.gear)}</div>
        ${l.status !== 'open' ? '<div class="tr-note">끝난 글이에요</div>' : `
        <div class="tr-head sm"><b>📨 제안 ${offs.length}개</b><span><button class="tr-btn ${sort === 'cur' ? 'on' : ''}" data-sort="cur">재화 많은 순</button><button class="tr-btn" data-sort="new">새 순</button></span></div>
        <div class="tr-offs">${list().map(row).join('') || '<div class="tr-empty">아직 제안이 없어요</div>'}</div>
        ${offs.length ? `<div class="tr-bulk"><button class="tr-btn" data-rsel>선택 거절</button>
          <span>조건 아래 전부 거절: ${I('cur_drink')}<input type="number" min="0" data-md placeholder="최소"> ${I('cur_gold')}<input type="number" min="0" data-mg placeholder="최소"> <label><input type="checkbox" data-ni> 물건 없는 제안</label></span><button class="tr-btn" data-rbelow>거절</button></div>` : ''}
        <div class="tr-acts"><button class="tr-btn danger" data-down>글 내리기</button></div>`}`;
      const offTxt = o => [o.cards.length + o.gear.length ? `물건 ${o.cards.length + o.gear.length}개` : '', curTxt(o.drinks, o.gold)].filter(Boolean).join(' + ');
      body(m).querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { sort = b.dataset.sort; body(m).querySelector('.tr-offs').innerHTML = list().map(row).join(''); bindRows(); });
      const bindRows = () => {
        body(m).querySelectorAll('[data-sel]').forEach(c => c.onchange = () => c.checked ? sel.add(+c.dataset.sel) : sel.delete(+c.dataset.sel));
        body(m).querySelectorAll('[data-ac]').forEach(b => b.onclick = async () => { const o = offs.find(x => x.id === +b.dataset.ac);
          const fee = cfg.fee_pct || 10, recv = curTxt(o.drinks - Math.ceil(o.drinks * fee / 100), o.gold - Math.ceil(o.gold * fee / 100));
          if (!await ask(`<b>${esc(o.nick || '익명')}</b>님의 제안을 수락할까요?<div class="tr-cf">${cfRow('받는 것', itemsHTML(o.cards, o.gear), curTxt(o.drinks, o.gold))}</div><small>${recv ? `수수료 ${fee}% 뒤 ${recv} 받아요 · ` : '물건끼리: 받는 물건 등급별 골드 수수료 · '}나머지 제안은 모두 자동 환불돼요</small>`)) return;
          const r2 = await rpc('trade_accept', { p_listing: id, p_offer: o.id }); if (r2) { toast(`🤝 거래 완료!${r2.mailed ? ' 장비 일부는 우편함으로 갔어요' : ''}`); refreshMine(); m.remove(); after?.(); } });
        body(m).querySelectorAll('[data-rj]').forEach(b => b.onclick = async () => { if (!await ask('이 제안을 거절할까요?<br><small>제안자에게 바로 돌려줘요</small>')) return;
          if (await rpc('trade_reject', { p_listing: id, p_offers: [+b.dataset.rj] })) { toast('🙅 거절했어요'); draw(); } });
      };
      bindRows();
      body(m).querySelector('[data-rsel]')?.addEventListener('click', async () => { if (!sel.size) return toast(ERR['nothing to reject']);
        if (!await ask(`고른 제안 ${sel.size}개를 거절할까요?`)) return; const r2 = await rpc('trade_reject', { p_listing: id, p_offers: [...sel] }); if (r2) { toast(`🙅 ${r2.rejected}개 거절했어요`); draw(); } });
      body(m).querySelector('[data-rbelow]')?.addEventListener('click', async () => {
        const v = s => { const x = body(m).querySelector(s).value; return x === '' ? null : Math.max(0, Math.floor(+x)); };
        const md = v('[data-md]'), mg = v('[data-mg]'), ni = body(m).querySelector('[data-ni]').checked;
        if (md == null && mg == null && !ni) return toast(ERR['no condition']);
        const hit = offs.filter(o => (md != null && o.drinks < md) || (mg != null && o.gold < mg) || (ni && !o.cards.length && !o.gear.length)).length;
        if (!hit) return toast('조건에 맞는 제안이 없어요');
        if (!await ask(`조건에 맞는 제안 ${hit}개를 거절할까요?`)) return;
        const r2 = await rpc('trade_reject_below', { p_listing: id, p_min_drinks: md, p_min_gold: mg, p_no_items: ni }); if (r2) { toast(`🙅 ${r2.rejected}개 거절했어요`); draw(); } });
      body(m).querySelector('[data-down]')?.addEventListener('click', async () => {
        if (!await ask(`글을 내릴까요?<br><small>내 물건이 돌아오고, 제안 ${offs.length}개도 모두 환불돼요</small>`, true)) return;
        if (await rpc('trade_cancel', { p_listing: id })) { toast('📥 글을 내렸어요'); refreshMine(); m.remove(); after?.(); } });
    };
    draw();
  }

  // 메인 거래소 타일 (게스트는 main-menu.js 가 로그인 확인 먼저)
  const mount = () => document.getElementById('main-trade')?.addEventListener('click', () => { if (window.VRCloud?.user || window.__TRADE_MOCK) open(); });
  if (typeof document !== 'undefined' && document.addEventListener) { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount(); }
  window.VRTrade = { open, direct: async t => { await open('my'); return directCreate(t || null, () => open('my')); }, _wantPicker: (c, m) => wantPicker(c, m), _priceInfo: (l, o, d, g, c, b) => { cfg = c; bands = b; return priceInfo(l, o, d, g); }, _errText: errText, _cardBlock: (o, s) => { cfg = cfg || {}; return cardBlock(o, s); }, _sortCards: (list, k, desc) => { srt.c = { k, desc }; return sortCards(list); } };
})();
