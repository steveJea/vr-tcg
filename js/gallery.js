// ===== 카드 갤러리 =====
// 판이 끝나면(로그인 유저만) 승리: 필드에 남은 내 카드 전부 / 패배·무승부: MVP 1장을 갤러리에 등록.
// 저장은 Supabase gallery 테이블 + gallery_register RPC. 스킬 이미지는 VIP 왕관 등급으로 개방된 것만 노출.
(() => {
  const IC = n => window.VRIcon?.icon(n) || '';   // js/icons.js
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
  const LABEL = { N: '노멀', R: '레어', HR: '하이 레어', SR: '슈퍼 레어', UR: '울트라 레어', MR: '미식 레어' };
  const PENDING = 'vrGalleryPending.v1';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cloud = () => window.VRCloud;
  const logged = () => !!(cloud()?.sb && cloud()?.user);

  // --- VIP 왕관 등급 (mvp_count) ---
  const TIERS = [null,
    { k: 'blue', e: '🔵', n: '파란 왕관' }, { k: 'purple', e: '🟣', n: '보라 왕관' },
    { k: 'yellow', e: '🟡', n: '노란 왕관' }, { k: 'red', e: '🔴', n: '붉은 왕관' }];
  const TE = t => (window.VRIcon?.icon(`crown_${TIERS[t].k}`, { alt: TIERS[t].n }) || TIERS[t].e);
  const tierOf = m => Math.min(4, Math.max(0, +m || 0));
  const crownHtml = (t, big) => t ? `<span class="gal-crown vip-${TIERS[t].k}${big ? ' big' : ''}" title="${TIERS[t].n}">${TE(t)}</span>` : '';
  // 등급 t의 보상: 스킬 t가 있으면 스킬 개방, 없으면 꾸미기 보상 (2=금테, 3=특별 배경, 4=붉은 반짝 테두리는 항상)
  const rewardText = (t, nSkill) => t <= nSkill ? `스킬 ${t} 개방` : ({ 1: '', 2: '금테 프레임', 3: '특별 배경', 4: '붉은 반짝 테두리' }[t] || '') + (t === 4 && nSkill >= 4 ? ' + 붉은 반짝 테두리' : '');
  let skills = null, voices = null;
  async function loadSkills() {
    if (skills) return;
    try { skills = await (await fetch('data/skills.json')).json(); } catch { skills = {}; }
    try { voices = new Set(await (await fetch('data/voice/index.json')).json()); } catch { voices = new Set(); }
  }
  const skillsOf = id => (skills && skills[id]) || [];
  let voiceAudio = null;
  function playVoice(key) {
    try {
      voiceAudio?.pause();
      const a = voiceAudio = new Audio(`data/voice/${key}.mp3`);
      a.addEventListener('playing', () => window.VRSound?.duck?.(true));
      const off = () => setTimeout(() => { if (voiceAudio === a || a.paused) window.VRSound?.duck?.(false); }, 60);
      a.addEventListener('ended', off); a.addEventListener('pause', off); a.addEventListener('error', off);
      a.play().catch(off);
    } catch {}
  }

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
      box.innerHTML = `<div class="gal-hint">${IC('gallery')} 로그인하면 카드가 갤러리에 수집돼요</div>`;
      return;
    }
    const ids = m.result === 'win' ? [...new Set((m.fieldIds || []).map(String))] : [];
    const mvp = m.mvpId ? String(m.mvpId) : null;
    if (m.result !== 'win' && mvp) ids.push(mvp);
    if (!ids.length) { box.innerHTML = `<div class="gal-hint">이번 판은 갤러리에 수집된 카드가 없어요</div>`; return; }
    box.innerHTML = `<div class="gal-hint">${IC('gallery')} 갤러리에 수집 중...</div>`;
    try {
      await loadCards();
      const res = await register(ids, mvp);
      await loadSkills();
      res.forEach(r => owned.set(r.card_id, { ...(owned.get(r.card_id) || {}), ...r }));
      const items = ids.map(id => ({ c: cardById(id), r: res.find(x => x.card_id === id) })).filter(x => x.c);
      const nNew = items.filter(x => x.r?.is_new).length;
      box.innerHTML = `<div class="gal-end-title">${IC('gallery')} 갤러리 수집 ${items.length}장${nNew ? ` · <span class="gal-new-txt">NEW ${nNew}</span>` : ''}</div>
        <div class="gal-end-row">${items.map(({ c, r }) => `<div class="gal-end-card rar-${SHORT[c.grade]}">
          <img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" onerror="this.style.visibility='hidden'">
          ${r?.is_new ? '<span class="gal-new">NEW!</span>' : `<span class="gal-cnt">×${r?.count ?? ''}</span>`}
          ${crownHtml(crownTier(r))}
          <div class="gal-end-name">${esc(c.name)}</div></div>`).join('')}</div>${promoNote(items, mvp)}`;
    } catch (err) {
      console.warn('[gallery] register failed', err);
      writePending([...readPending(), { uid: cloud().user.id, ids, mvp, at: Date.now() }]);
      box.innerHTML = `<div class="gal-hint">📡 지금은 갤러리에 저장하지 못했어요. 다음에 연결되면 자동으로 수집돼요</div>`;
    }
  });

  function promoNote(items, mvp) {
    const it = items.find(x => x.c.id === mvp && x.r); if (!it) return '';
    const now = tierOf(it.r.mvp_count), before = tierOf(it.r.mvp_count - 1);
    if (now <= before) return '';
    const rw = rewardText(now, skillsOf(it.c.id).length);
    return `<div class="gal-promo vip-${TIERS[now].k}">${IC('crown')} ${esc(it.c.name)} ${before ? TE(before) : '✨'}→${TE(now)} ${now === 1 ? 'VIP 등극!' : '승급!'}${rw ? ` ${rw}` : ''}${now === 4 ? ' (최종)' : ''}</div>`;
  }

  // --- 크게 보기 (갤러리 전용) ---
  function zoom(src, title, sub, grade) {
    let z = $('gal-zoom');
    if (!z) {
      z = document.createElement('div'); z.id = 'gal-zoom'; z.className = 'gal-zoom hidden'; document.body.appendChild(z);
      z.addEventListener('click', e => { if (!e.target.closest('.gal-zimg') || e.target.closest('.gal-zx')) z.classList.add('hidden'); });
    }
    z.innerHTML = `<button class="gal-x gal-zx" aria-label="닫기">✕</button>${grade ? (window.rarityStars?.(grade, 'base', 'rstars-lg') || '') : ''}<img class="gal-zimg" src="${src}" alt="${esc(title)}"><div class="gal-zcap"><b>${esc(title)}</b>${sub ? `<div>${esc(sub)}</div>` : ''}</div>`;
    z.classList.remove('hidden');
  }

  // --- 갤러리 화면 ---
  function ensureModal() {
    if ($('gal-modal')) return;
    const m = document.createElement('div');
    m.id = 'gal-modal'; m.className = 'gal-modal hidden';
    m.innerHTML = `<div class="gal-panel" role="dialog" aria-label="카드 갤러리">
      <div class="gal-head"><div><div class="gal-title">${IC('gallery')} 카드 갤러리</div><div id="gal-progress" class="gal-progress"></div></div>
        <button id="gal-close" class="gal-x" aria-label="닫기">✕</button></div>
      <div class="gal-bar"><div id="gal-bar-fill"></div></div>
      <div id="gal-filters" class="gal-filters"></div>
      <div id="gal-msg" class="gal-msg"></div>
      <div id="gal-grid" class="gal-grid"></div></div>
      <div id="gal-detail" class="gal-detail hidden"></div>`;
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m) close(); });
    $('gal-close').onclick = close;
    $('gal-detail').addEventListener('click', e => {
      const zb = e.target.closest('[data-zsrc]'); if (zb) { zoom(zb.dataset.zsrc, zb.dataset.ztitle, zb.dataset.zsub, zb.dataset.zgrade); return; }
      const sb2 = e.target.closest('[data-share]'); if (sb2) { shareCard(sb2.dataset.share, sb2); return; }
      const kb = e.target.closest('[data-kshare]'); if (kb) { kakaoCard(kb.dataset.kshare, kb); return; }
      const vb = e.target.closest('[data-voice]'); if (vb) { playVoice(vb.dataset.voice); return; }
      if (e.target.id === 'gal-detail' || e.target.closest('.gal-x')) $('gal-detail').classList.add('hidden'); });
    $('gal-grid').addEventListener('click', e => { const t = e.target.closest('[data-cid]'); if (t) detail(t.dataset.cid); });
    $('gal-filters').addEventListener('click', e => { const b = e.target.closest('[data-f]'); if (b) { filter = b.dataset.f; draw(); } });
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && $('gal-zoom') && !$('gal-zoom').classList.contains('hidden')) { $('gal-zoom').classList.add('hidden'); return; }
      if (e.key === 'Escape' && !m.classList.contains('hidden')) { $('gal-detail').classList.contains('hidden') ? close() : $('gal-detail').classList.add('hidden'); } });
  }
  function close() { if (prevTrack !== null) { const t = prevTrack; prevTrack = null; if (t) try { window.VRSound?.setTrack?.(t); } catch {} } $('gal-modal').classList.add('hidden'); document.body.classList.remove('gal-lock'); }

  let prevTrack = null;   // 열 때 mypage BGM, 닫으면 이전 트랙 복귀
  async function open() {
    if (prevTrack === null) { prevTrack = window.VRSound?.track || ''; try { window.VRSound?.setTrack?.('audio/mypage.mp3'); } catch {} }
    ensureModal();
    $('gal-modal').classList.remove('hidden'); document.body.classList.add('gal-lock');
    $('gal-detail').classList.add('hidden');
    $('gal-msg').textContent = '불러오는 중...'; $('gal-grid').innerHTML = '';
    try { await loadCards(); await loadSkills(); } catch { $('gal-msg').textContent = '카드 목록을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.'; return; }
    let msg = '';
    if (!logged()) { owned = new Map(); msg = cloud()?.sb ? '🔑 로그인하면 카드가 갤러리에 수집돼요' : '📡 지금은 서버에 연결할 수 없어요. 게스트로는 수집되지 않아요'; }
    else { try { await flushPending(); await fetchOwned(); } catch (e) { console.warn('[gallery] load failed', e); msg = '📡 갤러리를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'; } }
    $('gal-msg').innerHTML = msg ? (logged() || !cloud()?.sb ? esc(msg) : `${window.VRIcon ? VRIcon.swap(esc(msg)) : esc(msg)} <button id="gal-login" class="gal-login">로그인</button>`) : '';
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
      const t = crownTier(o);
      return `<button class="gal-card rar-${s} ${t ? 'vip vip-' + TIERS[t].k : ''}" data-cid="${c.id}">
        <img loading="lazy" src="${IMG}${c.id}.webp" alt="${esc(c.name)}" onerror="this.style.visibility='hidden'">
        <span class="gal-rar">${s}</span>${crownHtml(t)}
        <div class="gal-name">${esc(c.name)}</div></button>`;
    }).join('');
  }

  // 왕관 등급 훅: 지금은 MVP 횟수 기준. 나중에 EX 합성 레벨 도입 시 exTier(o) 를 채워 max(MVP 등급, EX 등급) 으로 올림
  const exTier = o => 0;   // TODO(EX): o.ex_level 등 → 0~4
  const crownTier = o => Math.max(tierOf(o?.mvp_count || 0), exTier(o));
  function detail(id) {
    const c = cardById(id), o = owned.get(id); if (!c || !o) return;
    const s = SHORT[c.grade], t = crownTier(o), sk = skillsOf(c.id);
    const d = new Date(o.first_at), date = isNaN(d) ? '-' : d.toLocaleDateString('ko-KR');
    const row = (k, v) => `<div class="gal-row"><span>${k}</span><b>${v}</b></div>`;
    const deco = [t ? 'vip vip-' + TIERS[t].k : '', t >= 2 && sk.length < 2 ? 'deco-gold' : '', t >= 3 && sk.length < 3 ? 'deco-bg' : ''].join(' ');
    const portrait = `${IMG}${c.id}.webp`;
    // 스킬 목록: 개방된 스킬만 이미지 경로를 HTML에 넣음 (잠긴 스킬 이미지는 절대 노출 안 함)
    const skHtml = sk.slice(0, 4).map((k, i) => {
      const n = i + 1, key = `${c.id}_${n}`;
      if (t < n) return `<div class="gal-sk locked"><div class="gal-sk-lock">🔒</div><div class="gal-sk-txt"><b>${n}. ${esc(k.name)}</b><span>${TE(n)} ${TIERS[n].n}에서 개방</span></div></div>`;
      const fx = k.fx ? `data/fx/${k.fx}` : '';
      const img = fx ? `<button class="gal-sk-img" data-zsrc="${fx}" data-ztitle="${esc(c.name)} · ${esc(k.name)}" data-zsub="스킬 ${n}" aria-label="스킬 이미지 크게 보기"><img src="${fx}" alt="${esc(k.name)}" loading="lazy" onerror="this.parentNode.remove()"></button>` : '';
      const vo = voices?.has(key) ? `<button class="gal-voice" data-voice="${key}" aria-label="음성 듣기">${IC('sound_on')} 듣기</button>` : '';
      return `<div class="gal-sk open">${img}<div class="gal-sk-txt"><b>${n}. ${esc(k.name)}</b><span>${TE(n)} 개방됨</span></div>${vo}</div>`;
    }).join('');
    const extra = [2, 3, 4].filter(n => n > sk.length).map(n => `<div class="gal-perk ${t >= n ? 'on' : ''}">${t >= n ? TE(n) : (IC('lock') || '🔒')} ${rewardText(n, sk.length)}${t >= n ? '' : ` · ${TIERS[n].n}`}</div>`);
    if (sk.length >= 4) extra.push(`<div class="gal-perk ${t >= 4 ? 'on' : ''}">${t >= 4 ? '🔴' : '🔒'} 붉은 반짝 테두리${t >= 4 ? '' : ' · 붉은 왕관'}</div>`);
    const nextTxt = t >= 4 ? '🔴 최종 등급 달성!' : `다음: ${TE(t + 1)} ${TIERS[t + 1].n} (MVP ${t + 1}회)`;
    const el = $('gal-detail');
    el.innerHTML = `<div class="gal-dbox rar-${s} ${deco}">
      <button class="gal-x gal-dx" aria-label="닫기">✕</button><button class="gal-share" data-share="${c.id}" aria-label="이미지로 공유">📤 공유</button><button class="gal-share gal-kakao" data-kshare="${c.id}" aria-label="카카오톡으로 공유">💬 카카오톡</button>
      <div class="gal-dimg"><img src="${portrait}" alt="${esc(c.name)}" data-zsrc="${portrait}" data-ztitle="${esc(c.name)}" data-zsub="${LABEL[s]}" data-zgrade="${s}" onerror="this.style.visibility='hidden'">${window.rarityStars?.(s, 'base', 'rstars-over') || ''}${crownHtml(t, true)}
        <button class="gal-zbtn" data-zsrc="${portrait}" data-ztitle="${esc(c.name)}" data-zsub="${LABEL[s]}" data-zgrade="${s}" aria-label="크게 보기">🔍</button></div>
      <div class="gal-dname">${window.TCG?.cardTitle ? TCG.cardTitle(c) : esc(c.name)}</div>
      <div class="gal-drar">${window.TCG?.cardTags ? TCG.cardTags(c, t ? [`<span class="gal-tname vip-${TIERS[t].k}">${TE(t)}</span>`] : []) : `<span class="gal-rar inline">${s}</span>`}</div>
      ${window.TCG?.cardStats?.(c) || ''}
      <div class="ci-tags gal-minor"><span class="ci-tag" title="${o.count ? '수집 횟수' : '보유로 등록 (아케이드 수집 0회)'}">🗂️${o.count}</span><span class="ci-tag" title="MVP">${IC('crown') || '👑'}${o.mvp_count}</span><span class="ci-tag" title="처음 수집">📅${esc(date)}</span><span class="ci-tag" title="전투력">⚡${Number(c.power || 0).toLocaleString('ko-KR')}</span></div>
      <div class="gal-vip"><div class="gal-vip-h">${IC('crown')} VIP 보상 <span>${nextTxt}</span></div>${skHtml}${extra.join('')}</div></div>`;
    el.classList.remove('hidden');
  }

  // --- 이미지 공유 (js/share-card.js). 스킬 이미지는 넣지 않음: 프로필 + 이름·등급·스탯만 ---
  function shareInfo(id) {
    const c = cardById(id), o = owned.get(id); if (!c || !o) return null;
    const s = SHORT[c.grade], t = crownTier(o), d = new Date(o.first_at);
    return { name: c.name, short: s, label: LABEL[s], portrait: `${IMG}${c.id}.webp`, hp: c.HP, atk: c.ATK, def: c.DEF, power: c.power,
      count: o.count, mvp: o.mvp_count, crown: t ? { e: TIERS[t].e, n: TIERS[t].n } : null,
      first: isNaN(d) ? '' : d.toLocaleDateString('ko-KR'), site: location.hostname || 'tcg.mbbs.kr' };
  }
  function galToast(t) { const el = document.createElement('div'); el.className = 'story-toast'; el.style.zIndex = '120'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 3200); }
  async function shareCard(id, btn) {
    const info = shareInfo(id); if (!info || !window.VRShareCard) return;
    const old = btn?.textContent; if (btn) { btn.disabled = true; btn.textContent = '만드는 중...'; }
    try {
      const cv = await VRShareCard.render(info);
      const { r, copied } = await VRShareCard.share(cv, `vr-abyss-gate_${id}.png`, `${info.name} (${info.short}) · VR: Abyss Gate`);
      if (btn && r === 'downloaded') { btn.textContent = '✅ 저장됨'; setTimeout(() => { btn.textContent = old; }, 1600); }
      else if (btn) btn.textContent = old;
      if (r === 'downloaded') galToast(copied ? '이미지를 저장하고 게임 링크를 복사했어요' : `이미지를 저장했어요 · 게임 링크: ${VRShareCard.GAME_URL}`);
      else if (r === 'shared' && copied) galToast('게임 링크도 복사해 뒀어요 · 링크가 빠졌다면 붙여넣기 하세요');
    } catch (e) { console.warn('[gallery] share failed', e); if (btn) btn.textContent = old; alert('이미지를 만들지 못했어요. 잠시 후 다시 시도해 주세요.'); }
    finally { if (btn) btn.disabled = false; }
  }
  // 카카오톡 공유 (js/kakao-share.js): 공유 이미지를 카카오에 올려 피드로. SDK·업로드 실패 시 기존 공유(파일 공유·저장)로
  async function kakaoCard(id, btn) {
    const info = shareInfo(id); if (!info || !window.VRShareCard) return;
    const old = btn?.textContent; if (btn) { btn.disabled = true; btn.textContent = '준비 중...'; }
    try {
      if (!window.VRKakaoShare) throw new Error('no kakao');
      const cv = await VRShareCard.render(info), file = await VRShareCard.toFile(cv, `vr-abyss-gate_${id}.png`);
      await VRKakaoShare.share({ title: info.name, description: `${info.short} · VR: Abyss Gate`, file });
    } catch (e) {
      console.warn('[gallery] kakao share failed', e, (() => { try { return JSON.stringify(e); } catch { return ''; } })());
      const why = window.VRKakaoShare?.describe?.(e);
      galToast(`카카오톡 공유를 열지 못했어요${why ? ` (${why})` : ''} · 다른 방법으로 공유할게요`);
      if (btn) btn.textContent = old;
      return shareCard(id, null);
    } finally { if (btn) { btn.disabled = false; btn.textContent = old; } }
  }
  /** 마이페이지용 수집률 { have, total, logged } */
  async function collection() {
    await loadCards();
    if (logged()) { try { await fetchOwned(); } catch {} }
    const have = logged() ? cards.filter(c => owned.has(c.id)).length : 0;
    return { have, total: cards.length, logged: logged() };
  }

  // --- 타이틀 버튼 ---
  function addButton() {
    const ex = $('main-gallery'); if (ex) { ex.onclick = open; return; }   // 메인 메달 버튼(index.html)
    const howto = $('main-howto'); if (!howto) return;
    const b = document.createElement('button');
    b.id = 'main-gallery'; b.className = 'main-btn main-btn-sub'; b.innerHTML = `${IC('gallery')} 갤러리`;
    b.onclick = open;
    howto.parentNode.insertBefore(b, howto.nextSibling);
  }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', addButton) : addButton();
  setTimeout(flushPending, 4000);
  window.VRGallery = { open, close, collection, shareCard, _test: { shareInfo, setOwned: m => { owned = m; }, detail, draw, promoNote, loadCards, loadSkills, cardById } };
})();
