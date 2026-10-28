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
    'login required': '로그인이 필요해요', 'trade level': '계정 Lv.20부터 거래할 수 있어요', 'trade account age': '가입 7일 뒤부터 거래할 수 있어요',
    'nothing to trade': '올릴 인재나 장비를 골라 주세요', 'nothing to offer': '제안할 것을 하나 이상 넣어 주세요', 'too many items': '한쪽에 최대 5개까지예요',
    'too many listings': '열린 판매 글이 너무 많아요 (최대 5개)', 'too many offers': '대기 중인 제안이 너무 많아요', 'listing full': '이 글은 제안이 꽉 찼어요',
    'already offered': '이 글에는 이미 제안했어요. 고치려면 취소 후 다시', 'reoffer cooldown': '거절된 글에는 24시간 뒤에 다시 제안할 수 있어요',
    'own listing': '내 글에는 제안할 수 없어요', 'listing closed': '이미 끝난 글이에요', 'listing not found': '글을 찾을 수 없어요',
    'offer closed': '이미 끝난 제안이에요', 'offer not found': '제안을 찾을 수 없어요', 'gold not allowed': '🪙 SR 이상 인재·영웅 장비가 끼면 골드는 쓸 수 없어요',
    'price too high': '가격 범위보다 많아요', 'price too low': '가격 범위보다 적어요', 'escrow limit': '보관 한도를 넘어요 (드링크 20,000 · 골드 2,000,000)',
    'not enough drink': '🥤 거래 가능한 드링크가 부족해요 (귀속 드링크는 못 써요)', 'not enough gold': '🪙 골드가 부족해요',
    'card bound': '🔗 귀속 인재는 거래할 수 없어요', 'card locked': '🔒 잠긴 인재예요', 'cannot trade leader': '👑 리더는 올릴 수 없어요',
    'card not owned': '이 인재가 없어요', 'gear not owned': '이 장비가 없어요', 'gear locked': '🔒 잠긴 장비예요', 'gear equipped': '장착 중인 장비는 먼저 해제해 주세요',
    'gear not tradable': '전설·심연 장비는 거래할 수 없어요', 'resale cooldown': '거래로 받은 물건은 72시간 뒤에 다시 올릴 수 있어요',
    'daily trade limit': '오늘 거래 한도를 다 썼어요', 'same partner limit': '같은 상대와는 7일에 3번까지예요', 'no condition': '거절 조건을 넣어 주세요',
    'nothing to reject': '거절할 제안을 골라 주세요', 'duplicate card': '같은 인재를 두 번 골랐어요', 'duplicate gear': '같은 장비를 두 번 골랐어요', 'invalid amount': '수량을 확인해 주세요',
    'cancel limit': '오늘 제안 취소가 너무 많아요. 내일 다시 제안할 수 있어요', 'drink send limit': '🥤 오늘 보낼 수 있는 드링크 양을 넘어요 (하루 10,000)', 'drink recv limit': '🥤 오늘 받을 수 있는 드링크 양을 넘어요 (하루 10,000)'
  };
  const errText = m => { m = String(m || ''); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : /trade_|schema cache|Could not find/.test(m) ? '💱 거래 게시판은 준비 중이에요' : `⚠️ ${m.slice(0, 60)}`; };
  async function rpc(fn, args) {
    const mk = window.__TRADE_MOCK; if (mk) { try { return await mk(fn, args); } catch (e) { toast(errText(e.message)); return null; } }
    const sb = window.VRCloud?.sb; if (!sb || !window.VRCloud?.user) { toast(ERR['login required']); return null; }
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) { toast(errText(error.message)); return null; }
    if (data && data.ok === false) { toast(errText(data.reason)); return null; }
    return data;
  }
  // 팝업 (바깥 누르면 닫힘)
  function pop(html, cls = '') {
    const m = document.createElement('div'); m.className = 'tr-bg';
    m.innerHTML = `<div class="tr-pop ${cls}" role="dialog"><button class="tr-x" data-x aria-label="닫기">✕</button><div class="tr-in">${html}</div></div>`;
    let down = false;
    m.onpointerdown = e => { down = e.target === m; };
    m.onclick = e => { if ((down && e.target === m) || e.target.closest('[data-x]')) m.remove(); down = false; };
    document.body.appendChild(m); return m;
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
  const curTxt = (d, g) => [d ? `${I('cur_drink')}${n(d)}` : '', g ? `${I('cur_gold')}${n(g)}` : ''].filter(Boolean).join(' + ');

  // ---- 메인: 게시판 / 내 거래
  async function open(tab = 'board') {
    document.querySelector('.tr-bg.main')?.remove();
    const m = pop('<div class="tr-load">불러오는 중…</div>', 'wide'); m.classList.add('main');
    if (window.VRGear?.load) await window.VRGear.load().catch(() => {});
    if (!await loadCfg()) { m.remove(); return; }
    const draw = async t => {
      tab = t;
      body(m).innerHTML = `<div class="tr-head"><b>${I('trade')}거래 게시판</b><span><button class="tr-btn" data-help>${I('help')}도움말</button> <button class="tr-btn main" data-new>＋ 판매 글</button></span></div>
        <div class="tr-tabs"><button data-tab="board" class="${t === 'board' ? 'on' : ''}">게시판</button><button data-tab="my" class="${t === 'my' ? 'on' : ''}">내 거래</button></div><div class="tr-list"><div class="tr-load">불러오는 중…</div></div>`;
      body(m).querySelectorAll('[data-tab]').forEach(b => b.onclick = () => draw(b.dataset.tab));
      body(m).querySelector('[data-new]').onclick = () => createListing(() => draw('my'));
      body(m).querySelector('[data-help]').onclick = help;
      const L = body(m).querySelector('.tr-list');
      if (t === 'board') {
        const r = await rpc('trade_board', { p_limit: 50 }); if (!r) return;
        L.innerHTML = r.listings.length ? r.listings.map(l => `<button class="tr-row" data-l="${l.id}"><div class="tr-items">${itemsHTML(l.cards, l.gear)}</div>
          <div class="tr-meta">${l.want ? `<span class="tr-want">${I('trade_want')}${esc(l.want)}</span>` : ''}<span>${I('timer')}${left(l.expires_at)}</span><span>${I('trade_offer')}제안 ${l.offers}</span>${l.mine ? '<span class="tr-tag">내 글</span>' : l.my_offer ? '<span class="tr-tag">제안함</span>' : ''}</div></button>`).join('')
          : '<div class="tr-empty">아직 올라온 글이 없어요</div>';
        L.querySelectorAll('[data-l]').forEach(b => b.onclick = () => { const l = r.listings.find(x => x.id === +b.dataset.l); l.mine ? manage(l.id, () => draw(tab)) : detail(l, () => draw(tab)); });
      } else {
        const r = await rpc('trade_my'); if (!r) return;
        const ST = { open: '열림', done: '거래 완료', cancelled: '내림', expired: '만료', pending: '대기', accepted: '수락됨', rejected: '거절됨', refunded: '환불됨' };
        L.innerHTML = `<div class="tr-sec">내 판매 글</div>${r.listings.map(l => `<button class="tr-row" data-ml="${l.id}"><div class="tr-items">${itemsHTML(l.cards, l.gear)}</div>
            <div class="tr-meta"><span class="tr-tag s-${l.status}">${ST[l.status]}</span>${l.status === 'open' ? `<span>${I('timer')}${left(l.expires_at)}</span><span>${I('trade_offer')}제안 ${l.offers.filter(o => o.status === 'pending').length}</span>` : ''}</div></button>`).join('') || '<div class="tr-empty">판매 글이 없어요</div>'}
          <div class="tr-sec">내 제안</div>${r.offers.map(o => `<div class="tr-row"><div class="tr-items">${itemsHTML(o.cards, o.gear)}${curTxt(o.drinks, o.gold) ? `<div class="tr-cur">${curTxt(o.drinks, o.gold)}</div>` : ''}</div>
            <div class="tr-meta"><span class="tr-tag s-${o.status}">${ST[o.status]}</span>${o.reoffer_at && new Date(o.reoffer_at) > Date.now() ? `<span>다시 제안: ${left(o.reoffer_at)} 뒤</span>` : ''}${o.status === 'pending' ? `<button class="tr-btn" data-oc="${o.id}">제안 취소</button>` : ''}</div></div>`).join('') || '<div class="tr-empty">제안한 글이 없어요</div>'}`;
        L.querySelectorAll('[data-ml]').forEach(b => b.onclick = () => manage(+b.dataset.ml, () => draw(tab)));
        L.querySelectorAll('[data-oc]').forEach(b => b.onclick = async () => { if (!await ask('제안을 취소할까요?<br><small>보관된 인재·장비·재화가 바로 돌아와요</small>')) return;
          if (await rpc('trade_offer_cancel', { p_offer: +b.dataset.oc })) { toast('↩️ 제안을 취소했어요'); refreshMine(); draw(tab); } });
      }
    };
    draw(tab);
  }
  const refreshMine = () => { S()?.load?.(); window.VRGear?.load?.(true); window.VRDrink?.status?.(); window.VRPlayer?.wallet?.(true); };

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
      <p class="tr-note">이상한 거래는 운영자가 확인할 수 있어요.</p></div>`);
  }

  // ---- 글 상세 (남의 글)
  function detail(l, after) {
    const m = pop(`<div class="tr-head"><b>판매 글</b><span>${I('timer')}${left(l.expires_at)} · ${I('trade_offer')}제안 ${l.offers}</span></div>
      <div class="tr-items big">${itemsHTML(l.cards, l.gear)}</div>${l.want ? `<div class="tr-want">${I('trade_want')}${esc(l.want)}</div>` : ''}
      <div class="tr-note">다른 사람의 제안 내용은 보이지 않아요</div>
      <div class="tr-acts">${l.my_offer ? '<button class="tr-btn" data-c>내 제안 취소</button>' : '<button class="tr-btn main" data-o>제안하기</button>'}</div>`);
    m.querySelector('[data-o]')?.addEventListener('click', () => { m.remove(); makeOffer(l, after); });
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
        if (el.classList.contains('no')) return toast(`이 물건은 올릴 수 없어요: ${el.querySelector('i')?.textContent || ''}`);
        const isC = 'pc' in el.dataset, set = isC ? sel.cards : sel.gear, k = isC ? el.dataset.pc : +el.dataset.pg;
        if (set.has(k)) set.delete(k); else { if (count() >= max) return toast(`한쪽에 최대 ${max}개까지예요`); set.add(k); }
        el.classList.toggle('on', set.has(k)); onChange?.();
      });
    };
    draw();
    const keys = () => [...[...sel.cards].map(u => cardKey(save.owned.find(o => o.uid === u)?.id)), ...[...sel.gear].map(id => gearKey(defOf(gs.find(g => g.id === id)?.def)?.tier || 1))];
    return { sel, count, keys };
  }

  // ---- 판매 글 올리기
  async function createListing(after) {
    const m = pop(`<div class="tr-head"><b>＋ 판매 글 올리기</b><span class="tr-cnt">0 / ${cfg.max_items || 5}</span></div>
      <div class="tr-note">팔 인재·장비를 골라 주세요. 올리는 순간 보관되고 ${cfg.listing_hours || 72}시간 열려요. 흐린 것은 올릴 수 없어요.</div>
      <div class="tr-pickwrap"></div><input class="tr-input" maxlength="100" placeholder="희망 조건 (선택, 예: 드링크 2,000 이상)">
      <div class="tr-acts"><button class="tr-btn main" data-ok disabled>올리기</button></div>`, 'wide');
    const p = await picker(m.querySelector('.tr-pickwrap'), () => { m.querySelector('.tr-cnt').textContent = `${p.count()} / ${cfg.max_items || 5}`; m.querySelector('[data-ok]').disabled = !p.count(); });
    m.querySelector('[data-ok]').onclick = async () => {
      const deckN = [...p.sel.cards].filter(u => (S()?.save?.decks || []).some(d => (d?.uids || []).includes(u))).length;
      if (!await ask(`${p.count()}개를 올릴까요?<br><small>보관 중에는 쓸 수 없어요${deckN ? ` · 덱에 든 인재 ${deckN}명은 덱에서 빠져요` : ''}${p.sel.cards.size ? ' · 마지막 같은 인재면 장착 장비는 해제돼 내 가방에 남아요' : ''}</small>`)) return;
      const r = await rpc('trade_list', { p_cards: [...p.sel.cards], p_gear: [...p.sel.gear], p_want: m.querySelector('.tr-input').value.trim() });
      if (r) { toast('📤 판매 글을 올렸어요'); m.remove(); refreshMine(); after?.(); }
    };
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
  async function makeOffer(l, after) {
    const lKeys = [...(l.cards || []).map(c => c.gkey), ...(l.gear || []).map(g => g.gkey)];
    const dr = await window.VRDrink?.status?.(), gold = window.VRPlayer?.walletNow?.gold;
    const m = pop(`<div class="tr-head"><b>제안하기</b></div><div class="tr-items">${itemsHTML(l.cards, l.gear)}</div>
      <div class="tr-sec">내가 줄 것 (인재·장비는 선택)</div>
      <div class="tr-cur-in"><label>🥤 드링크 <input type="number" min="0" step="1" value="0" data-d><small>거래 가능 ${n((dr?.tradable || 0) - (dr?.locked || 0))}</small></label>
        <label>${I('cur_gold')}골드 <input type="number" min="0" step="100" value="0" data-g>${gold != null ? `<small>보유 ${n(gold)}</small>` : ''}</label></div>
      <div class="tr-info"></div><div class="tr-pickwrap"></div>
      <div class="tr-acts"><button class="tr-btn main" data-ok>제안 보내기</button></div>`, 'wide');
    const val = s => Math.max(0, Math.floor(+m.querySelector(s).value || 0));
    let p = null;
    const upd = () => { const i = priceInfo(lKeys, p ? p.keys() : [], val('[data-d]'), val('[data-g]')); m.querySelector('.tr-info').innerHTML = i.html; m.querySelector('[data-ok]').disabled = !!i.err; return i; };
    m.querySelectorAll('[data-d],[data-g]').forEach(x => x.oninput = upd); upd();
    p = await picker(m.querySelector('.tr-pickwrap'), upd); upd();
    m.querySelector('[data-ok]').onclick = async () => {
      const i = upd(); if (i.err) return toast(i.err);
      const d = val('[data-d]'), g = val('[data-g]');
      if (!await ask(`이 조건으로 제안할까요?<br><b>${[p.count() ? `물건 ${p.count()}개` : '', curTxt(d, g), i.fix ? `수수료 ${I('cur_gold')}${n(i.fix)}` : ''].filter(Boolean).join(' + ')}</b><br><small>보낸 것은 바로 보관되고, 거절·취소·만료되면 그대로 돌아와요</small>`)) return;
      const r = await rpc('trade_offer', { p_listing: l.id, p_cards: [...p.sel.cards], p_gear: [...p.sel.gear], p_drinks: d, p_gold: g });
      if (r) { toast('📨 제안을 보냈어요'); m.remove(); refreshMine(); after?.(); }
    };
  }

  // ---- 내 글 관리: 제안 목록 · 수락 · 거절 · 조건 거절 · 내리기
  async function manage(id, after) {
    const m = pop('<div class="tr-load">불러오는 중…</div>', 'wide');
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
          if (!await ask(`<b>${esc(o.nick || '익명')}</b>님의 제안을 수락할까요?<br>${offTxt(o)}<br><small>${recv ? `수수료 ${fee}% 뒤 ${recv} 받아요 · ` : '물건끼리: 받는 물건 등급별 골드 수수료 · '}나머지 제안은 모두 자동 환불돼요</small>`)) return;
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
  window.VRTrade = { open, _priceInfo: (l, o, d, g, c, b) => { cfg = c; bands = b; return priceInfo(l, o, d, g); }, _errText: errText, _cardBlock: (o, s) => { cfg = cfg || {}; return cardBlock(o, s); }, _sortCards: (list, k, desc) => { srt.c = { k, desc }; return sortCards(list); } };
})();
