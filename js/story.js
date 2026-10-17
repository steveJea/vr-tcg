// ===== 스토리 모드 (로그인 전용) =====
// 저장: Supabase story_progress(user_id, data jsonb) + localStorage 백업. 테이블이 없으면 브라우저에만 저장.
(() => {
  const D = window.STORY_DATA;
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = n => Number(n).toLocaleString('ko-KR');
  const STATS = ['ATK', 'HP', 'DEF'];
  const STAT_LABEL = { ATK: '⚔ ATK', HP: '♥ HP', DEF: '🛡 DEF' };
  const RAR = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };

  const user = () => (window.__STORY_MOCK_CLOUD || window.VRCloud)?.user || window.__STORY_MOCK_USER || null;
  const pool = () => window.TCG?.POOL || [];
  const card = id => pool().find(c => String(c.id) === String(id));
  let save = null, cloudOk = true, serverMode = false;
  const cloud = () => window.__STORY_MOCK_CLOUD || window.VRCloud;

  // ----- 저장 -----
  const KEY = () => `vrTcgStory.v1:${user()?.id || 'guest'}`;
  const fresh = () => ({ v: 1, openingSeen: false, starter: null, owned: [], points: 0, cleared: {}, updatedAt: 0 });
  function loadLocal() { try { return JSON.parse(localStorage.getItem(KEY())) || null; } catch { return null; } }
  async function load() {
    let local = loadLocal(), cdata = null;
    const sb = cloud()?.sb, u = cloud()?.user;
    if (sb && u) {
      try { const { data, error } = await sb.from('story_progress').select('data').eq('user_id', u.id).maybeSingle(); if (error) throw error; cdata = data?.data || {}; serverMode = true; cloudOk = true; }
      catch (e) { cloudOk = false; serverMode = false; console.warn('[story] 클라우드 불러오기 실패 → 브라우저 저장 사용', e?.message || e); }
    }
    // 서버 모드: 서버 기록이 기준 (브라우저 저장은 캐시). 테이블이 없을 때만 브라우저 저장으로 진행
    save = clampPoints({ ...fresh(), ...(serverMode ? cdata : local || {}) });
    if (serverMode) cacheLocal();
  }
  // 반복 클리어 악용 방지: (보유 + 분배한) 포인트는 첫 클리어로 얻을 수 있는 총량을 넘을 수 없음
  function earnedPoints(sv) {
    let n = 0;
    for (const ch of D.chapters) for (const no of sv.cleared?.[ch.id] || []) { const ph = ch.phases.find(p => p.no === no); if (ph) n += D.statPoints[ph.type] || 0; }
    return n;
  }
  function clampPoints(sv) {
    const used = (sv.owned || []).reduce((a, o) => a + Object.values(o.boost || {}).reduce((x, y) => x + (+y || 0), 0) - (o.spentCard | 0), 0);   // 카드 전용 포인트로 쓴 양은 제외
    sv.points = Math.max(0, Math.min(sv.points | 0, earnedPoints(sv) - used));
    return sv;
  }
  function cacheLocal() { try { localStorage.setItem(KEY(), JSON.stringify(save)); } catch {} }
  // 브라우저 저장 (테이블이 없을 때만 쓰는 대체 경로)
  async function persist() { save.updatedAt = Date.now(); cacheLocal(); }
  const missingFn = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  /** 서버 쓰기: 서버 함수(rpc) 호출 후 서버가 돌려준 data 로 교체. 서버 함수가 없으면 local() 로 브라우저 저장 */
  async function act(rpc, args, local, pick = r => r) {
    if (serverMode) {
      const { data, error } = await cloud().sb.rpc(rpc, args);
      if (!error) { const r = data || {}; save = clampPoints({ ...fresh(), ...(pick(r) || {}) }); cacheLocal(); return { ok: true, r }; }
      if (!missingFn(error)) { console.warn('[story] 서버 거부', rpc, error.message); toast(`⚠️ 저장 실패: ${error.message}`); return { ok: false, error }; }
      serverMode = false; cloudOk = false; console.warn('[story] 서버 함수 없음 → 브라우저 저장', rpc);
    }
    const r = await local?.(); await persist(); return { ok: true, r, local: true };
  }
  async function reload() { if (!serverMode) return; try { const u = cloud().user; const { data } = await cloud().sb.from('story_progress').select('data').eq('user_id', u.id).maybeSingle(); if (data?.data) { save = clampPoints({ ...fresh(), ...data.data }); cacheLocal(); } } catch {} }


  // ----- 카드 계산 -----
  // 최종 스탯 = 기본 스탯 × 레벨 배율(반올림) + 스탯 포인트 강화. 레벨 배율 = 1 + 등급별 비율 × (레벨 − 1)
  const LV_RATE = { 'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06 };
  const lvPct = o => { const c = card(o.id); return c ? Math.round((LV_RATE[c.grade] || 0.01) * (Math.max(1, o.level | 0 || 1) - 1) * 100) : 0; };
  function boosted(o) {
    const c = card(o.id); if (!c) return null;
    const b = o.boost || {}, k = D.statPerPoint, m = 1 + lvPct(o) / 100;
    return { ...c, ATK: Math.round(c.ATK * m) + (b.ATK || 0) * k.ATK, HP: Math.round(c.HP * m) + (b.HP || 0) * k.HP, DEF: Math.round(c.DEF * m) + (b.DEF || 0) * k.DEF };
  }

  // ----- 카드 레벨 (서버 story_levels.sql 과 같은 규칙. 브라우저 저장 대체 경로·미리보기용) -----
  // 다음 레벨 EXP = 레벨×100 · 최대 레벨 N20 R30 HR40 SR50 UR60 MR70 (+ex 합성 1회당 +10, 추후 EX 합성용) · 레벨당 기본 스탯 +N1% R2% HR3% SR4% UR5% MR6% (레벨업 포인트 지급은 없음, 예전에 받은 카드 전용 포인트는 그대로 사용 가능)
  const LV_CAP = { 'NORMAL': 20, 'RARE': 30, 'HIGH RARE': 40, 'SUPER RARE': 50, 'ULTRA RARE': 60, 'MYTHIC RARE': 70 };
  const FEED_EXP = { 'NORMAL': 50, 'RARE': 150, 'HIGH RARE': 400, 'SUPER RARE': 1000, 'ULTRA RARE': 3000, 'MYTHIC RARE': 6000 };
  const lvCap = o => (LV_CAP[card(o.id)?.grade] || 20) + 10 * Math.max(0, o.ex | 0);
  const norm = o => Object.assign(o, { count: Math.max(1, o.count | 0 || 1), boost: o.boost || {}, level: Math.max(1, o.level | 0 || 1), exp: Math.max(0, o.exp | 0), totalExp: Math.max(0, o.totalExp | 0), cpts: Math.max(0, o.cpts | 0), spentCard: Math.max(0, o.spentCard | 0) });
  /** EXP 적용 결과 (원본 변경 없음): { level, exp, totalExp, cpts, wasted } */
  function gainCalc(o, amt) {
    const n = norm({ ...o }), cap = lvCap(n); let { level, exp, totalExp, cpts } = n, wasted = 0;
    if (level >= cap) return { level, exp: 0, totalExp, cpts, wasted: amt };
    exp += amt;
    while (level < cap && exp >= level * 100) { exp -= level * 100; level++; }
    if (level >= cap) { wasted = exp; totalExp += amt - exp; exp = 0; } else totalExp += amt;
    return { level, exp, totalExp, cpts, wasted };
  }
  function feedCalc(src, tgt) {
    const a = card(src.id), b = card(tgt.id), whole = (src.count || 1) <= 1;
    let amt = FEED_EXP[a?.grade] || 50;
    if (a && b && a.name === b.name) amt = Math.floor(amt * 1.5);
    if (whole) amt += Math.floor((src.totalExp | 0) * 0.5);
    const refund = whole ? Math.max(0, Object.values(src.boost || {}).reduce((x, y) => x + (+y || 0), 0) - (src.spentCard | 0)) : 0;
    return { amt, whole, refund };
  }
  const lvBar = o => { const n = norm({ ...o }), cap = lvCap(n), max = n.level >= cap;
    const pc = lvPct(n); return `<div class="story-lv"><b>Lv.${n.level}${pc ? ` <i class="story-lvpct">+${pc}%</i>` : ''}</b>${max ? '<em>MAX</em>' : `<span>${n.exp}/${n.level * 100}</span>`}</div><div class="story-exp"><i style="width:${max ? 100 : Math.min(100, n.exp / n.level)}%"></i></div>`; };
  const ownedCards = () => save.owned.map(boosted).filter(Boolean);
  const normals = () => pool().filter(c => c.grade === 'NORMAL').sort((a, b) => a.power - b.power);
  const rand = a => a[Math.floor(Math.random() * a.length)];
  function pickEnemies(ph) {
    if (ph.enemies.ids) return ph.enemies.ids.map(card).filter(Boolean);
    const [a, b] = ph.enemies.rank, list = normals().slice(a, b), out = [];
    while (out.length < ph.enemies.count && list.length) out.push(list.splice(Math.floor(Math.random() * list.length), 1)[0]);
    return out;
  }

  // 고른 캐릭터 전용 대본(byStarter)이 있으면 챕터 기본값 위에 덮어씀
  function chapterFor(base) {
    const o = base.byStarter?.[save?.starter]; if (!o) return base;
    return { ...base, subtitle: o.subtitle ?? base.subtitle, start: o.start, ending: o.ending,
      phases: base.phases.map(p => { const x = o.phases?.[p.no]; return x ? { ...p, ...x, lines: x.lines ? { default: x.lines } : p.lines } : p; }) };
  }
  const introOf = s => D.chapters[0].byStarter?.[s.id]?.intro || s.tagline;

  // ----- BGM -----
  const BGM = { story: 'audio/story_story.mp3', battle: 'audio/story_battle.mp3', boss: 'audio/story_boss.mp3', ending: 'audio/story_ending.mp3', main: 'audio/main.mp3' };
  const bgm = k => { try { window.VRSound?.setTrack?.(BGM[k]); } catch {} };

  // ----- 화면 -----
  const root = () => $('story-screen');
  function show(html, track = 'story') {
    bgm(track);
    const r = root(); r.innerHTML = `<div class="story-wrap">${html}</div>`;
    r.classList.remove('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.add('hidden');
    r.scrollTop = 0;
  }
  function home() { bgm('main'); root().classList.add('hidden'); $('start-screen').classList.remove('hidden'); }
  const topBar = (title, back = 'home') => `<div class="story-top"><button class="story-back" data-go="${back}">← ${back === 'home' ? '처음으로' : '돌아가기'}</button><div class="story-top-title">${title}</div><span class="flex gap-1.5"><button class="story-mycards story-gacha-btn" data-go="gacha">🎴 카드 뽑기${canDraw() ? '<i class="story-badge">1</i>' : ''}</button><button class="story-mycards" data-go="cards">🃏 보유 카드</button></span></div>`;
  function bind(extra = {}) {
    root().querySelectorAll('[data-go]').forEach(b => b.onclick = () => ({ home, map: renderMap, cards: renderCards, gacha: openGacha, ...extra })[b.dataset.go]?.());
  }
  const tile = (c, extra = '') => `<div class="story-card"><div class="story-card-img"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'"><span class="story-rar">${RAR[c.grade] || 'N'}</span></div><div class="story-card-name">${esc(c.name)}</div><div class="story-card-stats"><span class="text-orange-400">⚔${fmt(c.ATK)}</span><span class="text-red-400">♥${fmt(c.HP)}</span><span class="text-sky-400">🛡${fmt(c.DEF)}</span></div>${extra}</div>`;

  // 바깥 클릭으로 닫히는 팝업
  function popup(html, onClose) {
    let m = $('story-pop'); if (!m) { m = document.createElement('div'); m.id = 'story-pop'; document.body.appendChild(m); }
    m.className = 'fixed inset-0 bg-black/80 flex items-center justify-center z-[60] p-4';
    m.innerHTML = `<div class="story-pop-panel">${html}</div>`;
    let down = false;
    m.onpointerdown = e => { down = e.target === m; };
    m.onclick = e => { if (down && e.target === m) close(); down = false; };
    const close = silent => { m.className = 'hidden'; m.innerHTML = ''; if (silent !== true) onClose?.(); };   // close(true): 다음 팝업으로 넘어갈 때 onClose 생략
    m.querySelectorAll('[data-close-pop]').forEach(b => b.onclick = () => close());
    return { el: m, close };
  }

  async function enter() {
    if (!user()) {
      popup(`<div class="text-xl font-black mb-2">📜 스토리 모드</div><div class="text-sm text-zinc-300 mb-4">스토리 모드는 로그인한 플레이어만 할 수 있어요.<br>구글로 로그인하면 진행 상황과 보유 카드가 저장돼요.</div>
        <button id="story-login" class="w-full py-3 rounded-xl bg-amber-400 text-black font-bold">🔑 구글로 로그인</button><button data-close-pop class="w-full mt-2 py-2 rounded-xl bg-white/10">닫기</button>`);
      $('story-login').onclick = () => window.VRCloud?.login?.();
      return;
    }
    if (!window.TCG?.ready) return;
    await load();
    if (!save.openingSeen) return renderOpening();
    if (!save.starter) return renderSelect();
    renderMap();
  }

  // ----- 오프닝 영상 (처음 들어올 때 1회 + '오프닝 다시 보기') -----
  // 전체 화면 · 화면을 누르면 건너뛰기 버튼 표시 · 소리 자동재생이 막히면 '눌러서 재생' 안내 · 재생 중 BGM 정지
  // 영상은 이 함수가 불릴 때만 만들어짐(메인 화면에서 미리 받지 않음)
  function playOpening(next) {
    const o = D.opening; if (!o.video) return next();
    const snd = window.VRSound; snd?.hold?.(true);
    document.getElementById('story-opening-fx')?.remove();
    const el = document.createElement('div'); el.id = 'story-opening-fx'; el.className = 'story-ovp';
    el.innerHTML = `<video playsinline preload="auto" ${o.poster ? `poster="${esc(o.poster)}"` : ''} src="${esc(o.video)}"></video>
      <button class="story-ovp-skip" type="button">건너뛰기 ▶▶</button>
      <div class="story-ovp-tap hidden"><button type="button">▶<span>눌러서 오프닝 보기</span></button></div>`;
    document.body.appendChild(el);
    const v = el.querySelector('video'), skip = el.querySelector('.story-ovp-skip'), tap = el.querySelector('.story-ovp-tap');
    let hideT = 0, ended = false;
    const showSkip = () => { skip.classList.add('on'); clearTimeout(hideT); hideT = setTimeout(() => skip.classList.remove('on'), 3000); };
    const finish = () => { if (ended) return; ended = true; clearTimeout(hideT); removeEventListener('keydown', key); try { v.pause(); v.removeAttribute('src'); v.load(); } catch {} el.remove(); snd?.hold?.(false); next(); };
    const key = e => { if (e.key === 'Escape') finish(); };
    const start = () => v.play().then(() => tap.classList.add('hidden')).catch(() => { tap.classList.remove('hidden'); });
    skip.onclick = e => { e.stopPropagation(); finish(); };
    tap.querySelector('button').onclick = e => { e.stopPropagation(); v.muted = false; v.play().then(() => { tap.classList.add('hidden'); showSkip(); }).catch(() => { v.muted = true; v.play().then(() => tap.classList.add('hidden')).catch(() => {}); }); };
    el.onclick = () => showSkip();
    v.onended = finish; v.onerror = () => { if (v.getAttribute('src')) finish(); };   // 영상 파일을 못 읽으면 바로 다음으로
    addEventListener('keydown', key);
    showSkip(); start();
    window.__storyOpening = { el, v, finish };
  }
  function renderOpening() {
    show('<div class="min-h-[60vh]"></div>');
    playOpening(async () => { await act('story_mark_seen', { p_key: 'openingSeen' }, () => { save.openingSeen = true; }); save.starter ? renderMap() : renderSelect(); });
  }
  const replayBtn = '<button class="story-back" data-go="opening">🎬 오프닝 다시 보기</button>';

  function renderSelect() {
    show(`<div class="text-center"><div class="story-chapter-sub">MAIN STORY</div><div class="text-2xl md:text-3xl font-black mt-1">함께할 캐릭터를 골라 주세요</div>
      <div class="text-sm text-zinc-400 mt-1">고른 카드는 내 카드로 영구 귀속되고, 리더가 돼요. (나중에 바꿀 수 없어요)</div></div>
      <div class="story-select">${D.starters.map(s => { const c = card(s.id); return c ? `<button class="story-pick" data-pick="${s.id}">${tile(c)}<div class="text-xs text-zinc-400 mt-1 story-intro-text">${esc(introOf(s))}</div></button>` : ''; }).join('')}</div>
      <div class="text-center mt-4 flex gap-2 justify-center flex-wrap"><button class="story-back" data-go="home">← 처음으로</button>${replayBtn}</div>`);
    bind({ opening: () => playOpening(renderSelect) });
    root().querySelectorAll('[data-pick]').forEach(b => b.onclick = () => {
      const c = card(b.dataset.pick);
      const p = popup(`<div class="text-lg font-black mb-3">${esc(c.name)}(으)로 시작할까요?</div>${tile(c)}<div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-pick-ok" class="flex-1 py-2.5 rounded-xl bg-amber-400 text-black font-bold">결정</button></div>`);
      $('story-pick-ok').onclick = async () => { p.close(); const r = await act('story_choose_starter', { p_id: String(c.id) }, () => { save.starter = String(c.id); save.owned = [{ id: String(c.id), boost: {}, count: 1 }, ...save.owned.filter(o => o.id !== String(c.id))]; }); if (!r.ok) return renderSelect(); const ch = chapterFor(D.chapters[0]); chapterIntro(ch, () => startStory(ch)); };
    });
  }

  function chapterIntro(ch, next) {
    show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">MAIN STORY</div><div class="story-chapter-big">${esc(ch.title)}</div><div class="story-chapter-name">${esc(ch.subtitle)}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
    $('story-intro').onclick = next;
  }

  // 시작 스토리: 캐릭터 선택 직후 1번
  function startStory(ch) {
    if (!ch.start?.length || save.startSeen) return renderMap();
    playLines(ch.start, [], async () => { await act('story_mark_seen', { p_key: 'startSeen' }, () => { save.startSeen = true; }); renderMap(); });
  }
  const clearedOf = ch => save.cleared[ch.id] || [];
  function renderMap() {
    const ch = chapterFor(D.chapters[0]), done = clearedOf(ch);
    if (ch.start?.length && !save.startSeen) return startStory(ch);
    const nextNo = ch.phases.find(p => !done.includes(p.no))?.no;
    const leader = boosted(save.owned[0]);
    show(`${topBar(esc(ch.title))}
      <div class="text-center mt-2"><div class="story-chapter-big text-3xl md:text-5xl">${esc(ch.title)}</div><div class="story-chapter-name">${esc(ch.subtitle)}</div></div>
      <div class="story-map">${ch.phases.map((p, i) => { const st = done.includes(p.no) ? 'done' : p.no === nextNo ? 'next' : 'lock';
        return `${i ? `<div class="story-path ${st !== 'lock' ? 'on' : ''}"></div>` : ''}<button class="story-node ${st} ${p.type}" data-phase="${p.no}" ${st === 'lock' ? 'disabled' : ''}><span class="story-node-dot">${st === 'done' ? '✔' : p.type === 'boss' ? '👑' : st === 'lock' ? '🔒' : p.no}</span><span class="story-node-label">Phase.${p.no}${p.type === 'boss' ? ' BOSS' : ''}</span></button>`; }).join('')}</div>
      <div class="story-status">${leader ? `<div>리더 <b class="text-amber-300">${esc(leader.name)}</b> · 보유 카드 <b>${save.owned.length}</b>장</div>` : ''}
        <div>스탯 포인트 <b class="text-emerald-300">${save.points}</b> ${save.points ? '<button class="story-mini" data-go="stats">분배하기</button>' : ''}</div>
        ${!serverMode && !window.__STORY_MOCK_USER ? '<div class="text-[11px] text-amber-400">⚠️ 서버 저장 준비 중이라 이 브라우저에만 저장돼요</div>' : ''}</div>
      ${nextNo ? '' : '<div class="text-center text-emerald-300 font-bold mt-4">🎉 챕터 1 클리어! 다음 챕터는 준비 중이에요.</div>'}
      <div class="text-center mt-5">${replayBtn}</div>`);
    bind({ stats: () => openStats(renderMap), opening: () => playOpening(renderMap) });
    root().querySelectorAll('[data-phase]').forEach(b => b.onclick = () => startPhase(ch, ch.phases.find(p => p.no === +b.dataset.phase)));
  }

  function startPhase(ch, ph) {
    const enemies = pickEnemies(ph);
    show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">${esc(ch.title)}</div><div class="story-chapter-big">Phase.${ph.no}</div><div class="story-chapter-name">${esc(ph.title)}${ph.type === 'boss' ? ' · BOSS' : ''}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
    $('story-intro').onclick = () => dialogue(ch, ph, enemies);
  }

  function dialogue(ch, ph, enemies) {
    playLines(ph.lines?.[save.starter] || ph.lines?.default || [], enemies, () => battle(ch, ph, enemies));
  }
  function playLines(lines, enemies, next, track = 'story') {
    const starter = card(save.starter), enemy = enemies[0];
    const byName = n => enemies.find(c => c.name === n) || pool().filter(c => c.name === n).sort((a, b) => (a.region === starter?.region ? -1 : 0) - (b.region === starter?.region ? -1 : 0))[0] || null;
    const who = L => L.portrait !== undefined ? (L.portrait === 'starter' ? starter : L.portrait === 'enemy' ? enemy : L.portrait ? card(L.portrait) : null)
      : (D.noPortrait || []).includes(L.speaker) ? null : L.speaker === starter?.name ? starter : byName(L.speaker);
    let i = 0;
    const step = () => {
      if (i >= lines.length) return next();
      const L0 = lines[i], tag = /^(.+?)\s*\((기본|화남|웃음)\)$/.exec(L0.speaker || ''), L = tag ? { ...L0, speaker: tag[1], expr: L0.expr || tag[2] } : L0;
      const pc = who(L), sp = L.speaker === 'starter' ? starter?.name : L.speaker === 'enemy' ? enemy?.name : (L.speaker === '내레이션' ? null : L.speaker);
      const left = pc ? pc === starter : true;
      const slug = pc && D.portraits?.[pc.name], ex = D.exprSlug?.[L.expr || '기본'] || 'base';
      show(`<div class="story-dlg" id="story-dlg">
        <div class="story-dlg-stage">${pc ? (slug ? `<img class="story-portrait sp ${left ? 'left' : 'right'}" src="img/story/portraits/${slug}_${ex}.webp" alt="${esc(pc.name)}" onerror="this.onerror=null;this.classList.remove('sp');this.src='${IMG}${pc.id}.webp'">` : `<img class="story-portrait ${left ? 'left' : 'right'}" src="${IMG}${pc.id}.webp" alt="${esc(pc.name)}">`) : ''}</div>
        <div class="story-dlg-box">${sp ? `<div class="story-dlg-name">${esc(sp)}</div>` : ''}<div class="story-dlg-text">${esc(L.text)}</div><div class="story-dlg-next">▼ ${i + 1}/${lines.length}</div></div>
        <button class="story-dlg-skip" id="story-dlg-skip">건너뛰기 ⏭</button></div>`, track);
      $('story-dlg').onclick = e => { if (e.target.id === 'story-dlg-skip') { i = lines.length; } else i++; step(); };
    };
    step();
  }

  async function battle(ch, ph, enemies) {
    const st = await act('story_start_phase', { p_chapter: ch.id, p_phase: ph.no }, () => {});
    if (!st.ok) return renderMap();
    root().classList.add('hidden');
    const boss = ph.type === 'boss';
    bgm(boss ? 'boss' : 'battle');
    window.TCG.startStory({
      me: ownedCards(), ai: enemies, win: boss ? 'ko' : 'wipe', aiHp: boss ? (ph.baseHp || 500) : undefined, aiName: ph.enemyName || (boss ? '보스' : '적군'), first: 'me',
      onEnd: (win, reason, st) => result(ch, ph, win, reason, st),
    });
    if (ph.tip) setTimeout(() => toast(`💡 ${ph.tip}`), 400);
    toast(boss ? '👑 보스전: 상대 진영을 무너뜨리세요!' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리세요!');
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'story-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 3200); }

  async function result(ch, ph, win, reason, st = {}) {
    if (!win) {
      show(`<div class="text-center py-10"><div class="story-chapter-big text-red-400">DEFEAT</div><div class="text-zinc-300 mt-2">${reason === 'wipe' ? '내 카드가 모두 쓰러졌어요.' : reason === 'timeout' ? '턴 제한 안에 적을 모두 쓰러뜨리지 못했어요.' : '패배했어요.'} 스탯을 올리고 다시 도전해 보세요!</div>
        <div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="story-retry">다시 도전</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
      bind(); $('story-retry').onclick = () => startPhase(ch, ph); return;
    }
    // 서버가 첫 클리어 여부·보상(카드·포인트)을 결정. 재클리어는 보상 없음
    let first = !clearedOf(ch).includes(ph.no), reward = null, pts = 0;
    // 전투 EXP: 이번 전투에 낸 내 카드 + 처치 수 (서버가 보유 여부·처치 상한·배율을 다시 계산)
    const kills = st.kills || {}, p_stats = [...new Set(st.played || [])].slice(0, 30).map(id => ({ id, kills: kills[id] | 0 }));
    const res = await act('story_complete_phase', { p_chapter: ch.id, p_phase: ph.no, p_stats }, () => {
      const exp = [], cap = ph.enemies?.ids?.length || ph.enemies?.count || 99; let ksum = 0;
      for (const s of p_stats) {
        const o = save.owned.find(x => x.id === s.id); if (!o) continue;
        const k = Math.min(s.kills, Math.max(0, cap - ksum)); ksum += k;
        const gain = (60 + 20 * k) * (ph.type === 'boss' ? 2 : 1), from = norm(o).level, g = gainCalc(o, gain);
        Object.assign(o, { level: g.level, exp: g.exp, totalExp: g.totalExp, cpts: g.cpts });
        exp.push({ id: s.id, kills: k, exp: gain, from, level: g.level });
      }
      if (!first) return { exp };
      const have = new Set(save.owned.map(o => o.id));
      const rc = ch.rewardCard ? rand(pool().filter(c => c.grade === ch.rewardCard && !have.has(String(c.id)))) : null;
      if (rc) save.owned.push({ id: String(rc.id), boost: {}, count: 1 });
      save.cleared[ch.id] = [...clearedOf(ch), ph.no];
      save.points += D.statPoints[ph.type];   // 스탯 포인트는 페이즈 첫 클리어 때만
      return { first: true, points: D.statPoints[ph.type], reward_id: rc && String(rc.id), exp };
    }, r => r.data);
    if (!res.ok) {
      const m = String(res.error?.message || ''), why = /too fast/.test(m) ? '전투가 너무 빨리 끝나서 기록이 인정되지 않았어요.' : /battle not started/.test(m) ? '전투 시작 기록이 없어요. (새로고침·다른 기기에서 전투를 시작했을 수 있어요)' : `결과를 서버에 저장하지 못했어요.${m ? ` (${esc(m)})` : ''}`;
      show(`<div class="text-center py-10"><div class="story-chapter-big text-amber-300">!</div><div class="text-zinc-300 mt-2">${why}<br>다시 도전해 주세요.</div><div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="story-retry">다시 도전</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
      bind(); $('story-retry').onclick = () => startPhase(ch, ph); return; }
    const r = res.r || {};
    first = !!r.first; pts = r.points | 0; reward = r.reward_id ? card(r.reward_id) : null;
    if (first && ph.type === 'boss' && ch.ending?.length) await new Promise(ok => playLines(ch.ending, [], ok, 'ending'));
    show(`<div class="text-center py-6"><div class="story-chapter-sub">Phase.${ph.no} CLEAR</div><div class="story-chapter-big text-emerald-300">VICTORY</div>
      ${reward ? `<div class="mt-4 text-amber-200 font-bold">🎁 보상 카드 획득!</div><div class="flex justify-center mt-2 story-reward">${tile(reward)}</div>` : `<div class="mt-4 text-zinc-400 text-sm">${first ? '이번 챕터는 카드 보상 없이 스탯 포인트만 받아요.' : '이미 클리어한 페이즈라 카드 보상은 없어요.'}</div>`}
      ${expList(r.exp)}
      <div class="mt-4 text-lg">${pts ? `스탯 포인트 <b class="text-emerald-300">+${pts}</b> (보유 ${save.points})` : '<span class="text-zinc-400 text-sm">다시 클리어한 페이즈라 스탯 포인트는 없어요.</span>'}</div>
      <div class="flex flex-col gap-2 max-w-xs mx-auto mt-5"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
    bind({ stats: () => openStats(renderMap) });
    if ((r.exp || []).some(e => e.level > e.from)) levelUpFx();
  }
  // 전투 EXP 결과 목록
  function expList(list) {
    if (!list?.length) return '';
    return `<div class="story-explist">${list.map(e => { const c = card(e.id), o = save.owned.find(x => x.id === e.id) || { id: e.id, level: e.level }, up = e.level > e.from;
      return `<div class="story-exprow ${up ? 'up' : ''}"><img src="${IMG}${e.id}.webp" alt=""><div class="flex-1 min-w-0"><div class="flex justify-between text-xs"><b class="truncate">${esc(c?.name)}</b><span class="text-sky-300">EXP +${e.exp}${e.kills ? ` · 처치 ${e.kills}` : ''}</span></div>${lvBar(o)}${up ? `<div class="story-lvup-tag">LEVEL UP! Lv.${e.from} → Lv.${e.level} · 스탯 +${lvPct({ id: e.id, level: e.level })}%</div>` : ''}</div></div>`; }).join('')}</div>`;
  }
  function levelUpFx(text = 'LEVEL UP!') {
    const el = document.createElement('div'); el.className = 'story-lvup-fx'; el.innerHTML = `<span>${text}</span>`;
    document.body.appendChild(el); try { window.VRSound?.sfx?.('levelup'); } catch {}
    setTimeout(() => el.remove(), 1600);
  }

  // ----- 스탯 분배 (팝업) -----
  // 카드 전용 포인트(레벨업 보상, 그 카드에만)를 먼저 쓰고, 모자라면 전역 포인트(첫 클리어 보상)를 씀
  function openStats(after, start = 0) {
    save.owned.forEach(norm);
    let sel = start, left = save.points, tabX = 0;
    const temp = save.owned.map(o => ({ ...(o.boost || {}) })), cleft = save.owned.map(o => o.cpts | 0), gUsed = save.owned.map(() => 0);
    const added = i => STATS.reduce((a, st) => a + (temp[i][st] || 0) - (save.owned[i].boost?.[st] || 0), 0);
    const draw = () => {
      const o = save.owned[sel], c = boosted({ ...o, boost: temp[sel] }), k = D.statPerPoint, avail = left + cleft[sel];
      const p = popup(`<div class="text-lg font-black mb-1">📈 스탯 분배</div><div class="text-xs text-zinc-400 mb-3">공용 포인트 <b class="text-emerald-300 text-base">${left}</b>${cleft[sel] ? ` · 이 카드 전용 <b class="text-sky-300 text-base" id="story-cpts">${cleft[sel]}</b>` : ''} · 포인트 1당 ATK +${k.ATK}, HP +${k.HP}, DEF +${k.DEF}${cleft.some(Boolean) ? '<div class="text-[11px] text-zinc-500">예전에 받은 카드 전용 포인트를 먼저 써요</div>' : ''}</div>
        <div class="story-tabwrap"><button class="story-tab-arr l" aria-label="왼쪽">‹</button><div class="story-tabs">${save.owned.map((x, i) => { const cc = card(x.id); return `<button data-sel="${i}" class="story-chip ${i === sel ? 'on' : ''}">${i === 0 ? '👑 ' : ''}${esc(cc?.name)} <small>Lv.${x.level}</small>${cleft[i] ? ` <b class="text-sky-300">+${cleft[i]}</b>` : ''}</button>`; }).join('')}</div><button class="story-tab-arr r" aria-label="오른쪽">›</button></div>
        <div class="flex gap-3 items-center"><img src="${IMG}${c.id}.webp" class="w-20 aspect-[3/4] object-cover rounded-lg" alt=""><div class="flex-1 space-y-2">${STATS.map(s => `<div class="flex items-center gap-2"><span class="w-16 text-sm font-bold">${STAT_LABEL[s]}</span><span class="flex-1 font-black">${fmt(c[s])}${(temp[sel][s] || 0) ? ` <span class="text-emerald-300 text-xs">(+${temp[sel][s] * k[s]})</span>` : ''}</span><button data-dec="${s}" class="story-pm" ${(temp[sel][s] || 0) > (o.boost?.[s] || 0) ? '' : 'disabled'}>−</button><button data-inc="${s}" class="story-pm" ${avail ? '' : 'disabled'}>＋</button></div>`).join('')}</div></div>
        <div class="mt-3 text-[11px] text-zinc-500">🗡️ 무기 · 🛡️ 방어구 장착은 준비 중이에요 (Coming soon)</div>
        <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-stat-ok" class="flex-1 py-2.5 rounded-xl bg-emerald-500 text-black font-bold">확정</button></div>`, after);
      // 이름 탭: 스크롤바 숨김(스와이프 가능) + 좌우 화살표. 끝에서는 화살표 비활성/숨김. 다시 그려도 스크롤 위치 유지
      const row = p.el.querySelector('.story-tabs'), al = p.el.querySelector('.story-tab-arr.l'), ar = p.el.querySelector('.story-tab-arr.r');
      const arrows = () => { const max = row.scrollWidth - row.clientWidth - 1; al.disabled = row.scrollLeft <= 0; ar.disabled = row.scrollLeft >= max; p.el.querySelector('.story-tabwrap').classList.toggle('fit', max <= 0); };
      row.scrollLeft = tabX; if (tabX === 0) row.querySelector('.on')?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      row.onscroll = () => { tabX = row.scrollLeft; arrows(); };
      al.onclick = () => row.scrollBy({ left: -row.clientWidth * 0.7, behavior: 'smooth' });
      ar.onclick = () => row.scrollBy({ left: row.clientWidth * 0.7, behavior: 'smooth' });
      arrows();
      p.el.querySelectorAll('[data-sel]').forEach(b => b.onclick = () => { sel = +b.dataset.sel; draw(); });
      p.el.querySelectorAll('[data-inc]').forEach(b => b.onclick = () => {
        if (cleft[sel]) cleft[sel]--; else if (left) { left--; gUsed[sel]++; } else return;
        temp[sel][b.dataset.inc] = (temp[sel][b.dataset.inc] || 0) + 1; draw(); });
      p.el.querySelectorAll('[data-dec]').forEach(b => b.onclick = () => {
        temp[sel][b.dataset.dec]--; if (gUsed[sel]) { gUsed[sel]--; left++; } else cleft[sel]++; draw(); });
      $('story-stat-ok').onclick = async () => {
        const alloc = {};
        save.owned.forEach((x, i) => { for (const st of STATS) { const n = (temp[i][st] || 0) - (x.boost?.[st] || 0); if (n > 0) (alloc[x.id] ||= {})[st] = n; } });
        if (Object.keys(alloc).length) await act('story_allocate', { p_alloc: alloc }, () => {
          save.owned.forEach((x, i) => { const fromCard = added(i) - gUsed[i]; x.boost = temp[i]; x.cpts -= fromCard; x.spentCard += fromCard; });
          save.points = left; });
        p.close();
      };
    };
    draw();
  }

  // ----- 보유 카드 -----
  const cptsTotal = () => save.owned.reduce((a, o) => a + (o.cpts | 0), 0);
  function renderCards() {
    const k = D.statPerPoint; save.owned.forEach(norm);
    const anyPts = save.points || cptsTotal();
    show(`${topBar('🃏 보유 카드', 'map')}<div class="text-center text-sm text-zinc-400 my-2">스토리 모드 전용 · ${save.owned.length}종 · 공용 포인트 ${save.points}${cptsTotal() ? ` · 카드 전용 ${cptsTotal()}` : ''}</div>
      <div class="text-center text-[11px] text-zinc-500 -mt-1 mb-2">카드를 누르면 상세 · 폐기할 수 있어요 ${save.owned.length > 1 ? '<button class="story-mini story-mini-red ml-1" data-go="bulk">🗑️ 일괄 폐기</button>' : ''}</div>
      <div class="story-grid">${save.owned.map((o, i) => { const c = boosted(o); if (!c) return ''; const b = o.boost || {};
        const up = STATS.filter(s => b[s]).map(s => `${s} +${b[s] * k[s]}`).join(' · ');
        return `<div data-card="${i}" class="story-owned">${tile(c, `${o.count > 1 ? `<div class="story-dup">x${o.count}</div>` : ''}${o.cpts ? `<div class="story-cpts">+${o.cpts}</div>` : ''}${lvBar(o)}<div class="text-[10px] text-emerald-300 h-3">${i === 0 ? '👑 리더 ' : ''}${up}</div><div class="story-equip"><span>🗡️ 무기</span><span>🛡️ 방어구</span><em>준비 중</em></div>`)}</div>`; }).join('')}</div>
      ${anyPts ? '<div class="text-center mt-4"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button></div>' : ''}`);
    bind({ stats: () => openStats(renderCards), bulk: () => bulkDiscard() });
    document.querySelectorAll('[data-card]').forEach(el => el.onclick = () => cardDetail(+el.dataset.card));
  }
  const isLeader = o => o.id === save.starter;
  const canDiscard = o => !(isLeader(o) && o.count <= 1) && save.owned.length > 1 || o.count > 1;
  function cardDetail(i) {
    const o = norm(save.owned[i]), c = boosted(o); if (!c) return;
    const cap = lvCap(o), dup = o.count > 1;
    const p = popup(`<div class="flex gap-3"><img src="${IMG}${c.id}.webp" class="w-24 aspect-[3/4] object-cover rounded-lg" alt=""><div class="flex-1 min-w-0">
        <div class="text-lg font-black truncate">${isLeader(o) ? '👑 ' : ''}${esc(c.name)} <span class="text-xs text-zinc-400">${RAR[c.grade] || 'N'}</span></div>
        ${lvBar(o)}<div class="text-[11px] text-zinc-400 mt-1">최대 Lv.${cap} · 누적 EXP ${fmt(o.totalExp)}${dup ? ` · 보유 x${o.count}` : ''}</div>
        <div class="text-xs mt-2"><span class="story-lvpct">Lv.${o.level} +${lvPct(o)}%</span> <span class="text-zinc-500">기본 스탯에 레벨 보너스</span></div>
        <div class="story-statrows">${STATS.map(s => { const base = card(o.id)[s], lvB = Math.round(base * (1 + lvPct(o) / 100)) - base, pt = (o.boost?.[s] || 0) * D.statPerPoint[s];
          return `<div><span>${STAT_LABEL[s]}</span><b>${fmt(c[s])}</b><small>기본 ${fmt(base)}${lvB ? ` <i class="text-amber-300">+${fmt(lvB)} 레벨</i>` : ''}${pt ? ` <i class="text-emerald-300">+${fmt(pt)} 포인트</i>` : ''}</small></div>`; }).join('')}</div>
        ${o.cpts ? `<div class="text-xs mt-1">남은 카드 전용 포인트 <b class="text-sky-300">${o.cpts}</b></div>` : ''}</div></div>
      ${dup ? `<div class="story-hint">💡 같은 카드가 ${o.count}장 있어요. 중복 카드는 나중에 합성(EX)에 쓸 수 있으니 폐기는 신중하게!</div>` : ''}
      <div class="flex gap-2 mt-4"><button id="story-d-stats" class="flex-1 py-2.5 rounded-xl bg-emerald-500 text-black font-bold" ${save.points || o.cpts ? '' : 'disabled'}>📈 스탯 분배</button>
      <button id="story-d-discard" class="flex-1 py-2.5 rounded-xl bg-red-500/80 font-bold" ${canDiscard(o) ? '' : 'disabled'}>🗑️ 폐기</button></div>
      ${isLeader(o) && !dup ? '<div class="text-[11px] text-zinc-500 mt-2 text-center">리더 카드는 폐기할 수 없어요</div>' : ''}`, renderCards);
    $('story-d-stats').onclick = () => { p.close(true); openStats(renderCards, i); };
    $('story-d-discard').onclick = () => { p.close(true); pickTarget(i); };
  }
  // ----- 일괄 폐기: 여러 장을 골라 EXP를 대상 1장에 (서버 story_discard_many, 전부 성공 또는 전부 취소) -----
  /** 선택(sel: {id: 장수}) → 미리보기 { n, amt, same, refund, ids } (서버와 같은 규칙) */
  function bulkCalc(sel, tgt) {
    const tc = card(tgt.id); let n = 0, amt = 0, same = 0, refund = 0; const ids = [];
    for (const o of save.owned) {
      const q = Math.min(sel[o.id] | 0, o.count); if (!q || o.id === tgt.id) continue;
      const c = card(o.id), base = FEED_EXP[c?.grade] || 50, sm = c && tc && c.name === tc.name;
      const per = sm ? Math.floor(base * 1.5) : base;
      amt += per * q; n += q; if (sm) same += q;
      if (q >= o.count) { amt += Math.floor((o.totalExp | 0) * 0.5); refund += Math.max(0, Object.values(o.boost || {}).reduce((x, y) => x + (+y || 0), 0) - (o.spentCard | 0)); }
      for (let k = 0; k < q; k++) ids.push(o.id);
    }
    return { n, amt, same, refund, ids };
  }
  function bulkDiscard(st = {}) {
    save.owned.forEach(norm);
    const tid = st.tid && save.owned.some(o => o.id === st.tid) ? st.tid : save.owned[0].id, sel = st.sel || {};
    const tgt = save.owned.find(o => o.id === tid), locked = o => o.id === tid || isLeader(o);
    for (const k of Object.keys(sel)) if (!save.owned.some(o => o.id === k && !locked(o))) delete sel[k];
    const f = bulkCalc(sel, tgt), g = gainCalc(tgt, f.amt);
    const grades = Object.keys(RAR).filter(gr => save.owned.some(o => !locked(o) && card(o.id)?.grade === gr));
    const p = popup(`<div class="text-lg font-black mb-1">🗑️ 일괄 폐기</div><div class="text-xs text-zinc-400 mb-2">고른 카드를 모두 폐기하고, EXP를 한 카드에 몰아줘요</div>
      <label class="text-xs text-zinc-300 font-bold">EXP 받을 카드</label>
      <select id="bulk-target" class="story-select-box">${save.owned.map(o => `<option value="${o.id}" ${o.id === tid ? 'selected' : ''}>${isLeader(o) ? '👑 ' : ''}${esc(card(o.id)?.name)} · ${RAR[card(o.id)?.grade] || 'N'} · Lv.${o.level}</option>`).join('')}</select>
      <div class="flex flex-wrap gap-1.5 my-2"><button class="story-chip" data-q="all">전체 선택</button>${grades.map(gr => `<button class="story-chip" data-q="${gr}">${RAR[gr]} 전체</button>`).join('')}<button class="story-chip" data-q="none">선택 해제</button></div>
      <div class="story-bulk-list" id="bulk-list">${save.owned.map(o => { const c = card(o.id), lk = locked(o), q = sel[o.id] | 0;
        return `<div class="story-bulk-row ${lk ? 'lock' : ''} ${q ? 'on' : ''}" ${lk ? '' : `data-row="${o.id}"`}><input type="checkbox" ${q ? 'checked' : ''} ${lk ? 'disabled' : ''}><img src="${IMG}${o.id}.webp" alt=""><div class="flex-1 min-w-0"><div class="text-sm font-bold truncate">${esc(c?.name)} <span class="text-[10px] text-zinc-400">${RAR[c?.grade] || 'N'} · Lv.${o.level}</span>${c?.name === card(tid)?.name && !lk ? ' <span class="text-amber-300 text-[10px]">×1.5</span>' : ''}</div><div class="text-[10px] text-zinc-500">${lk ? (o.id === tid ? 'EXP 받을 카드' : '리더 · 폐기 불가') : `보유 x${o.count}`}</div></div>
          ${!lk && o.count > 1 ? `<span class="story-qty"><button data-dq="${o.id}" ${q ? '' : 'disabled'}>−</button><b>${q}/${o.count}</b><button data-iq="${o.id}" ${q < o.count ? '' : 'disabled'}>＋</button></span>` : ''}</div>`; }).join('')}</div>
      <div class="story-bulk-sum">${f.n ? `<b>${f.n}장</b> 선택 · EXP <b class="text-sky-300">+${fmt(f.amt)}</b>${f.same ? ` <span class="text-amber-300 text-[11px]">(같은 이름 ${f.same}장 ×1.5)</span>` : ''}<br>${esc(card(tid)?.name)} Lv.${tgt.level} → <b class="text-emerald-300">Lv.${g.level}</b> · 스탯 +${lvPct(tgt)}% → +${lvPct({ id: tid, level: g.level })}%${f.refund ? `<br><span class="text-emerald-300 text-[11px]">공용 포인트 ${f.refund} 돌려받음</span>` : ''}` : '<span class="text-zinc-500">폐기할 카드를 골라 주세요</span>'}</div>
      ${g.wasted && f.n ? `<div class="story-warn">⚠️ 최대 레벨(Lv.${lvCap(tgt)})을 넘는 EXP ${fmt(g.wasted)}은 사라져요.</div>` : ''}
      ${f.n && save.owned.some(o => (sel[o.id] | 0) && o.count > 1) ? '<div class="story-hint">💡 중복 카드는 나중에 합성(EX)에 쓸 수 있어요.</div>' : ''}
      <div class="flex gap-2 mt-3"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="bulk-ok" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold" ${f.n ? '' : 'disabled'}>${f.n ? `${f.n}장 폐기` : '폐기'}</button></div>`, renderCards);
    const list = $('bulk-list'); list.scrollTop = st.scroll || 0;
    const re = () => bulkDiscard({ tid, sel, scroll: list.scrollTop });
    $('bulk-target').onchange = e => bulkDiscard({ tid: e.target.value, sel, scroll: list.scrollTop });
    p.el.querySelectorAll('[data-q]').forEach(b => b.onclick = () => { const q = b.dataset.q;
      for (const o of save.owned) if (!locked(o)) { if (q === 'none') delete sel[o.id]; else if (q === 'all' || card(o.id)?.grade === q) sel[o.id] = o.count; }
      re(); });
    p.el.querySelectorAll('[data-row]').forEach(r => r.onclick = e => { if (e.target.closest('.story-qty')) return; const o = save.owned.find(x => x.id === r.dataset.row); if (sel[o.id]) delete sel[o.id]; else sel[o.id] = o.count; re(); });
    p.el.querySelectorAll('[data-iq]').forEach(b => b.onclick = e => { e.stopPropagation(); const o = save.owned.find(x => x.id === b.dataset.iq); sel[o.id] = Math.min(o.count, (sel[o.id] | 0) + 1); re(); });
    p.el.querySelectorAll('[data-dq]').forEach(b => b.onclick = e => { e.stopPropagation(); const k = b.dataset.dq; sel[k] = (sel[k] | 0) - 1; if (sel[k] <= 0) delete sel[k]; re(); });
    $('bulk-ok').onclick = () => { if (f.n) { p.close(true); confirmBulk(tid, sel, f, g, list.scrollTop); } };
  }
  function confirmBulk(tid, sel, f, g, scroll) {
    const tgt = save.owned.find(o => o.id === tid), names = save.owned.filter(o => sel[o.id]).map(o => `${esc(card(o.id)?.name)}${sel[o.id] > 1 ? ` x${sel[o.id]}` : ''}`);
    const back = () => bulkDiscard({ tid, sel, scroll });
    const p = popup(`<div class="text-lg font-black mb-2">정말 폐기할까요?</div>
      <div class="text-sm"><b>${f.n}장</b>을 폐기하고 <b>${esc(card(tid)?.name)}</b>에게 EXP <b class="text-sky-300">+${fmt(f.amt)}</b></div>
      <div class="text-[11px] text-zinc-400 mt-1 max-h-24 overflow-y-auto">${names.join(', ')}</div>
      <div class="text-sm mt-1">Lv.${tgt.level} → <b class="text-emerald-300">Lv.${g.level}</b></div>
      ${g.wasted ? `<div class="story-warn">⚠️ 최대 레벨(Lv.${lvCap(tgt)})을 넘는 EXP ${fmt(g.wasted)}은 사라져요.</div>` : ''}
      <div class="text-[11px] text-red-300 mt-2">폐기한 카드는 되돌릴 수 없어요.</div>
      <div class="flex gap-2 mt-4"><button id="bulk-no" class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="bulk-yes" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold">${f.n}장 폐기</button></div>`, renderCards);
    $('bulk-no').onclick = () => { p.close(true); back(); };
    $('bulk-yes').onclick = async () => {
      $('bulk-yes').disabled = true;
      const res = await act('story_discard_many', { p_ids: f.ids, p_target: tid }, () => {
        const from = tgt.level; Object.assign(tgt, { level: g.level, exp: g.exp, totalExp: g.totalExp });
        for (const [k, q] of Object.entries(sel)) { const o = save.owned.find(x => x.id === k); if (!o) continue; if (q >= o.count) save.owned.splice(save.owned.indexOf(o), 1); else o.count -= q; }
        save.points += f.refund;
        return { count: f.n, exp: f.amt, from, level: g.level, refund: f.refund };
      }, r => r.data);
      p.close(true); renderCards();
      if (res.ok) { const r = res.r || {}; toast(`🗑️ ${r.count}장 폐기 · ${card(tid)?.name} EXP +${fmt(r.exp)}`); if (r.level > r.from) levelUpFx(`LEVEL UP! Lv.${r.level}`); }
    };
  }

  // 폐기: EXP를 받을 카드 1장 고르기
  function pickTarget(i) {
    const src = save.owned[i], sc = card(src.id);
    const targets = save.owned.map((o, j) => ({ o, j })).filter(({ o, j }) => j !== i || src.count > 1);
    const p = popup(`<div class="text-lg font-black mb-1">🗑️ ${esc(sc?.name)} 폐기</div><div class="text-xs text-zinc-400 mb-3">EXP를 받을 카드를 골라 주세요${src.count > 1 ? ' · 중복 1장만 사라져요' : ''}</div>
      <div class="story-target-list">${targets.map(({ o, j }) => { const c = card(o.id), f = feedCalc(src, o), g = gainCalc(o, f.amt);
        return `<button data-t="${j}" class="story-target"><img src="${IMG}${o.id}.webp" alt=""><div class="flex-1 min-w-0 text-left"><div class="text-sm font-bold truncate">${esc(c?.name)}${c?.name === sc?.name ? ' <span class="text-amber-300 text-[10px]">같은 이름 ×1.5</span>' : ''}</div><div class="text-[11px] text-zinc-400">Lv.${o.level} → <b class="${g.level > o.level ? 'text-emerald-300' : ''}">Lv.${g.level}</b> · EXP +${fmt(f.amt)}${g.wasted ? ` <span class="text-red-300">(${fmt(g.wasted)} 낭비)</span>` : ''}</div></div></button>`; }).join('')}</div>
      <button data-close-pop class="w-full mt-3 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button>`, renderCards);
    p.el.querySelectorAll('[data-t]').forEach(b => b.onclick = () => { p.close(true); confirmDiscard(i, +b.dataset.t); });
  }
  function confirmDiscard(i, j) {
    const src = save.owned[i], tgt = save.owned[j], sc = card(src.id), tc = card(tgt.id), f = feedCalc(src, tgt), g = gainCalc(tgt, f.amt);
    const p = popup(`<div class="text-lg font-black mb-2">정말 폐기할까요?</div>
      <div class="text-sm"><b>${esc(sc?.name)}</b>${src.count > 1 ? ` (x${src.count} 중 1장)` : ''} → <b>${esc(tc?.name)}</b> EXP <b class="text-sky-300">+${fmt(f.amt)}</b></div>
      <div class="text-sm mt-1">Lv.${tgt.level} → <b class="text-emerald-300">Lv.${g.level}</b>${g.level > tgt.level ? ` · 스탯 +${lvPct(tgt)}% → +${lvPct({ id: tgt.id, level: g.level })}%` : ''}</div>
      ${g.wasted ? `<div class="story-warn">⚠️ 최대 레벨(Lv.${lvCap(tgt)})을 넘는 EXP ${fmt(g.wasted)}은 사라져요.</div>` : ''}
      ${f.refund ? `<div class="text-xs text-emerald-300 mt-1">이 카드에 쓴 공용 포인트 ${f.refund}은 돌려받아요.</div>` : ''}
      ${src.count > 1 ? '<div class="story-hint">💡 중복 카드는 나중에 합성(EX)에 쓸 수 있어요.</div>' : f.whole && (src.cpts || src.spentCard) ? '<div class="text-[11px] text-zinc-400 mt-1">카드 전용 포인트와 그걸로 올린 스탯은 함께 사라져요.</div>' : ''}
      <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-disc-ok" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold">폐기</button></div>`, renderCards);
    $('story-disc-ok').onclick = async () => {
      const ok = $('story-disc-ok'); ok.disabled = true;
      const res = await act('story_discard', { p_id: src.id, p_target: tgt.id }, () => {
        const from = tgt.level; Object.assign(tgt, { level: g.level, exp: g.exp, totalExp: g.totalExp, cpts: g.cpts });
        if (f.whole) save.owned.splice(i, 1); else src.count--;
        save.points += f.refund;
        return { exp: f.amt, from, level: g.level, refund: f.refund };
      }, r => r.data);
      p.close(true); renderCards();
      if (res.ok) { const r = res.r || {}; toast(`🗑️ ${sc?.name} 폐기 · ${tc?.name} EXP +${r.exp}`); if (r.level > r.from) levelUpFx(`LEVEL UP! Lv.${r.level}`); }
    };
  }

  // ----- 일일 카드 뽑기 (하루 1회, KST 자정 초기화) -----
  const KST = 9 * 3600e3;
  const kstDay = (t = Date.now()) => new Date(t + KST).toISOString().slice(0, 10);
  const msToReset = () => { const t = Date.now() + KST; return 86400e3 - (t % 86400e3); };
  const canDraw = () => !!save && save.gachaLast !== kstDay();
  const hms = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return [s / 3600 | 0, (s / 60 | 0) % 60, s % 60].map(n => String(n).padStart(2, '0')).join(':'); };
  const GLOW = { 'NORMAL': 'n', 'RARE': 'r', 'HIGH RARE': 'hr', 'SUPER RARE': 'sr', 'ULTRA RARE': 'ur' };
  function addOwned(id, n = 1) {
    const o = save.owned.find(x => x.id === String(id));
    if (o) o.count = (o.count || 1) + n; else save.owned.push({ id: String(id), boost: {}, count: 1 });
    return save.owned.find(x => x.id === String(id)).count;
  }
  // 서버 RPC(story_daily_draw)로 추첨. 함수가 아직 없으면(SQL 미실행) 브라우저에서 추첨 (이 경우는 새로고침 방지가 약함)
  async function drawOnce() {
    const day = kstDay();
    if (save.gachaLast === day) return { ok: false, reason: 'already' };
    const sb = cloud()?.sb, u = cloud()?.user;
    let res = null;
    if (window.__GACHA_MOCK) res = await window.__GACHA_MOCK();
    else if (sb && u) {
      const { data, error } = await sb.rpc('story_daily_draw');
      if (!error) res = data;
      else if (!/story_daily_draw|PGRST202|42883|Could not find/i.test(`${error.code} ${error.message}`)) return { ok: false, reason: 'error', msg: error.message };
    }
    if (!res) { const g = window.rollGachaRarity(); const c = rand(pool().filter(x => x.grade === g)); res = { ok: true, card_id: String(c.id), grade: g, local: true }; }
    if (!res.ok) { if (res.reason === 'already') { save.gachaLast = day; await persist(); } return res; }
    if (serverMode && !res.local && !window.__GACHA_MOCK) { await reload(); res.count = save.owned.find(o => o.id === String(res.card_id))?.count || res.count || 1; return res; }
    res.count = addOwned(res.card_id);
    save.gachaLast = day;
    await persist();
    return res;
  }
  let gachaTimer = 0;
  function openGacha() {
    clearInterval(gachaTimer);
    const avail = canDraw();
    const p = popup(`<div class="text-lg font-black">🎴 오늘의 카드 뽑기</div><div class="text-[11px] text-zinc-400 mt-1">하루 1회 무료 · 매일 자정(KST) 초기화<br>N 70% · R 20% · HR 6.5% · SR 3% · UR 0.5%</div>
      <div class="gacha-stage"><div class="gacha-card" id="gacha-card"><div class="gacha-face gacha-back">🎴</div><div class="gacha-face gacha-front" id="gacha-front"></div></div></div>
      <div id="gacha-msg" class="text-sm min-h-[1.5rem]"></div>
      ${avail ? '<button id="gacha-go" class="story-btn w-full mt-2">뽑기!</button>' : ''}
      <div id="gacha-next" class="text-xs text-zinc-400 mt-2"></div>
      <button data-close-pop class="w-full mt-2 py-2 rounded-xl bg-white/10">닫기</button>`, () => { clearInterval(gachaTimer); if (!root().classList.contains('hidden') && root().querySelector('.story-map')) renderMap(); });
    const tick = () => { const n = $('gacha-next'); if (!n) return clearInterval(gachaTimer); n.textContent = canDraw() ? '' : `다음 뽑기까지 ${hms(msToReset())}`; };
    tick(); gachaTimer = setInterval(tick, 1000);
    const go = $('gacha-go'); if (!go) { $('gacha-msg').textContent = '오늘은 이미 뽑았어요.'; return; }
    go.onclick = async () => {
      go.disabled = true; go.textContent = '뽑는 중...';
      const r = await drawOnce();
      if (!r.ok) { go.remove(); $('gacha-msg').textContent = r.reason === 'already' ? '오늘은 이미 뽑았어요.' : `뽑기에 실패했어요: ${r.msg || ''}`; tick(); return; }
      const c = card(r.card_id), g = GLOW[r.grade] || 'n';
      $('gacha-front').innerHTML = `<img src="${IMG}${c.id}.webp" alt="${esc(c.name)}"><span class="story-rar">${RAR[c.grade]}</span><div class="gacha-name">${esc(c.name)}</div>`;
      const el = $('gacha-card'); el.parentElement.className = `gacha-stage g-${g}`;
      setTimeout(() => el.classList.add('flip'), 350);
      go.remove();
      setTimeout(() => { $('gacha-msg').innerHTML = `<b class="g-text-${g}">${RAR[c.grade]} · ${esc(c.name)}</b> 획득!${r.count > 1 ? ` <span class="story-dup-inline">x${r.count}</span>` : ''}<div class="text-[11px] text-zinc-400">보유 카드에 추가됐어요</div>`; tick(); }, 1300);
    };
  }

  function mountButton() {
    const start = $('start-btn'); if (!start || $('story-btn')) return;
    const b = document.createElement('button'); b.id = 'story-btn'; b.className = 'main-btn main-btn-primary story-entry'; b.textContent = '📜 스토리 모드';
    b.disabled = !window.TCG?.ready; b.onclick = enter; start.after(b);
    window.addEventListener('tcg:ready', () => { b.disabled = false; });
  }
  mountButton();
  window.VRStory = { enter, openGacha, drawOnce, kstDay, get save() { return save; }, renderMap, renderCards, openStats, renderSelect };
})();
