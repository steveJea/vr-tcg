// ===== 스토리 모드 (로그인 전용) =====
// 저장: Supabase story_progress(user_id, data jsonb) + localStorage 백업. 테이블이 없으면 브라우저에만 저장.
(() => {
  const D = window.STORY_DATA;
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = n => Number(n).toLocaleString('ko-KR');
  const MAX_PICK = () => window.STORY_DATA?.battleCards || 5;   // 스토리 전투 출전 카드 최대 장수
  const RULES_TURNS = () => window.TCG?.RULES?.MAX_TURNS || 40;
  const STATS = ['ATK', 'HP', 'DEF'];
  const ic = (n, o) => window.VRIcon?.icon(n, o) || '';   // js/icons.js
  const STAT_LABEL = { ATK: `${ic('atk')} ATK`, HP: `${ic('hp')} HP`, DEF: `${ic('def')} DEF` };
  const RAR = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };

  const user = () => (window.__STORY_MOCK_CLOUD || window.VRCloud)?.user || window.__STORY_MOCK_USER || null;
  const pool = () => window.TCG?.POOL || [];
  const skillsOf = id => window.TCG?.skillsOf?.(id) || [];
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
    if (serverMode || save.statRefunded) cacheLocal();
  }
  // 반복 클리어 악용 방지: (보유 + 분배한) 포인트는 첫 클리어로 얻을 수 있는 총량을 넘을 수 없음
  function earnedPoints(sv) {
    let n = 0;
    for (const ch of D.chapters) for (const no of sv.cleared?.[ch.id] || []) { const ph = ch.phases.find(p => p.no === no); if (ph) n += D.statPoints[ph.type] || 0; }
    return n;
  }
  /** 스탯 규칙이 바뀌면 예전 분배를 전부 돌려줌: 카드 전용 포인트로 쓴 만큼은 그 카드 전용으로, 나머지는 공용 포인트로 (서버는 story_statpt.sql) */
  function refundStats(sv) {
    if ((sv.statV | 0) >= (D.statRuleV || 1)) return;
    let any = 0;
    for (const o of sv.owned || []) {
      const used = Object.values(o.boost || {}).reduce((x, y) => x + (+y || 0), 0), card = Math.min(used, o.spentCard | 0);
      sv.points = (sv.points | 0) + used - card; o.cpts = (o.cpts | 0) + card; o.spentCard = 0; o.boost = {}; any += used;
    }
    sv.statV = D.statRuleV || 1; if (any) sv.statRefunded = true;   // 돌려준 게 있을 때만 안내
  }
  function clampPoints(sv) {
    migrate(sv);
    if (!serverMode) refundStats(sv);   // 서버 모드는 서버(SQL)가 돌려줌
    const used = (sv.owned || []).reduce((a, o) => a + Object.values(o.boost || {}).reduce((x, y) => x + (+y || 0), 0) - (o.spentCard | 0), 0);   // 카드 전용 포인트로 쓴 양은 제외
    sv.points = Math.max(0, Math.min(sv.points | 0, earnedPoints(sv) - used));
    return sv;
  }
  // ----- 보유 카드 = 카드 1장씩(인스턴스). 예전 형식(count)은 서버 story_merge.sql 과 같은 방식으로 분리 -----
  // { uid, id, level, exp, totalExp, boost, cpts, spentCard, ex, exb } · save.leader = 리더 인스턴스 uid
  const newUid = () => 'c' + Array.from(crypto.getRandomValues(new Uint8Array(8)), b => b.toString(16).padStart(2, '0')).join('').slice(0, 15);
  const newCard = id => ({ uid: newUid(), id: String(id), boost: {}, level: 1, exp: 0, totalExp: 0, cpts: 0, spentCard: 0, ex: 0, exb: 0 });
  function migrate(sv) {
    if (!Array.isArray(sv.owned)) sv.owned = [];
    const out = [];
    for (const e of sv.owned) {
      if (!e || !e.id) continue;
      if (e.uid) { const { count, ...rest } = e; out.push(rest); continue; }
      const { count, ...rest } = e, c = Math.max(1, Math.min(500, count | 0 || 1));
      out.push({ ...rest, id: String(e.id), uid: newUid() });
      for (let k = 1; k < c; k++) out.push(newCard(e.id));
    }
    sv.owned = out;
    if (sv.starter && !out.some(o => o.uid === sv.leader)) sv.leader = out.find(o => o.id === String(sv.starter))?.uid || null;
    return sv;
  }
  const byUid = u => save.owned.find(o => o.uid === u);
  const copiesOf = id => save.owned.filter(o => o.id === String(id));
  /** 전투 출전 카드: 카드마다 1장 (리더 인스턴스, 아니면 레벨·EX 가 가장 높은 장) */
  function deckInstances() {
    const best = new Map();
    for (const o of save.owned) {
      const b = best.get(o.id), score = x => (x.uid === save.leader ? 1e9 : 0) + (x.ex | 0) * 1e5 + (x.level | 0);
      if (!b || score(o) > score(b)) best.set(o.id, o);
    }
    const list = [...best.values()];
    return list.sort((a, b) => (b.uid === save.leader) - (a.uid === save.leader));
  }
  const repOf = id => deckInstances().find(o => o.id === String(id));
  function cacheLocal() { try { localStorage.setItem(KEY(), JSON.stringify(save)); } catch {} }
  // 브라우저 저장 (테이블이 없을 때만 쓰는 대체 경로)
  async function persist() { save.updatedAt = Date.now(); cacheLocal(); }
  const missingFn = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  /** 서버 쓰기: 서버 함수(rpc) 호출 후 서버가 돌려준 data 로 교체. 서버 함수가 없으면 local() 로 브라우저 저장 */
  async function act(rpc, args, local, pick = r => r) {
    if (serverMode) {
      const { data, error } = await cloud().sb.rpc(rpc, args);
      if (!error) { const r = data || {}; save = clampPoints({ ...fresh(), ...(pick(r) || {}) }); cacheLocal(); return { ok: true, r, raw: r }; }
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
  // EX 합성: 기본 스탯 × (1 + EX 보너스 합계%) 가 새 기본 스탯 → 그 위에 레벨 % → 반올림 → 포인트 강화 더하기
  const exOf = o => Math.max(0, o?.ex | 0), exbOf = o => Math.max(0, +o?.exb || 0);
  const exName = (o, name) => exOf(o) ? `[EX${exOf(o)}] ${name}` : name;
  // ----- 스탯 포인트 규칙 (서버 story_statpt.sql 과 같음) -----
  /** 한 스탯에 n 포인트 넣었을 때 오르는 양: statFull 개까지 1당 statPerPoint, 그 뒤로는 절반 (버림) */
  const ptGain = (s, n) => { n = Math.max(0, n | 0); const k = D.statPerPoint[s], f = D.statFull ?? Infinity; return k * Math.min(n, f) + Math.floor(k * Math.max(0, n - f) / 2); };
  /** 다음 1포인트 효율 표시: 그대로면 +k, 절반 구간이면 +k/2 */
  const ptNext = (s, n) => { const k = D.statPerPoint[s]; return (n | 0) >= (D.statFull ?? Infinity) ? k / 2 : k; };
  /** 한 스탯 상한: 그 카드 포인트 합계의 절반(올림) */
  const ptCap = total => Math.ceil(Math.max(0, total) / 2);
  const ptSum = b => STATS.reduce((a, s) => a + (b?.[s] | 0), 0);
  const ptOk = b => { const cap = ptCap(ptSum(b)); return STATS.every(s => (b?.[s] | 0) <= cap); };
  const statCalc = (o, s) => { const c = card(o.id); return Math.round(c[s] * (1 + exbOf(o) / 100) * (1 + lvPct(o) / 100)) + ptGain(s, (o.boost || {})[s]); };
  function boosted(o) {
    const c = card(o.id); if (!c) return null;
    return { ...c, name: exName(o, c.name), ex: exOf(o), ATK: statCalc(o, 'ATK'), HP: statCalc(o, 'HP'), DEF: statCalc(o, 'DEF') };
  }

  // ----- 카드 레벨 (서버 story_levels.sql 과 같은 규칙. 브라우저 저장 대체 경로·미리보기용) -----
  // 다음 레벨 EXP = 레벨×100 · 최대 레벨 N20 R30 HR40 SR50 UR60 MR70 (+ex 합성 1회당 +10, 추후 EX 합성용) · 레벨당 기본 스탯 +N1% R2% HR3% SR4% UR5% MR6% (레벨업 포인트 지급은 없음, 예전에 받은 카드 전용 포인트는 그대로 사용 가능)
  const LV_CAP = { 'NORMAL': 20, 'RARE': 30, 'HIGH RARE': 40, 'SUPER RARE': 50, 'ULTRA RARE': 60, 'MYTHIC RARE': 70 };
  const FEED_EXP = { 'NORMAL': 50, 'RARE': 150, 'HIGH RARE': 400, 'SUPER RARE': 1000, 'ULTRA RARE': 3000, 'MYTHIC RARE': 6000 };
  const lvCap = o => (LV_CAP[card(o.id)?.grade] || 20) + 5 * exOf(o);   // EX 단계마다 최대 레벨 +5
  const MAX_EX = { 'NORMAL': 1, 'RARE': 2, 'HIGH RARE': 3, 'SUPER RARE': 4, 'ULTRA RARE': 5, 'MYTHIC RARE': 6 };
  const maxEx = o => MAX_EX[card(o.id)?.grade] || 1;
  /** 합성 미리보기 (서버 story_merge 와 같은 계산): 10% × (대상 Lv/최대) × (재료 Lv/최대) */
  const mergeCalc = (o, m) => { const cap = lvCap(o), ratio = Math.min(1, o.level / cap), mcap = lvCap(m), mratio = Math.min(1, m.level / mcap), bonus = Math.round(10 * ratio * mratio * 100) / 100;
    return { cap, ratio, mcap, mratio, bonus, exb: Math.round((exbOf(o) + bonus) * 100) / 100, ex: exOf(o) + 1, capTo: cap + 5 }; };
  /** 합성 재료 후보: 같은 카드의 다른 장 (리더 제외), 레벨 높은 순 */
  const materialsOf = o => copiesOf(o.id).filter(x => x.uid !== o.uid && !isLocked(x)).sort((a, b) => b.level - a.level || b.exp - a.exp);
  const norm = o => Object.assign(o, { boost: o.boost || {}, level: Math.max(1, o.level | 0 || 1), exp: Math.max(0, o.exp | 0), totalExp: Math.max(0, o.totalExp | 0), cpts: Math.max(0, o.cpts | 0), spentCard: Math.max(0, o.spentCard | 0) });
  /** EXP 적용 결과 (원본 변경 없음): { level, exp, totalExp, cpts, wasted } */
  function gainCalc(o, amt) {
    const n = norm({ ...o }), cap = lvCap(n); let { level, exp, totalExp, cpts } = n, wasted = 0;
    if (level >= cap) return { level, exp: 0, totalExp, cpts, wasted: amt };
    exp += amt;
    while (level < cap && exp >= level * 100) { exp -= level * 100; level++; }
    if (level >= cap) { wasted = exp; totalExp += amt - exp; exp = 0; } else totalExp += amt;
    return { level, exp, totalExp, cpts, wasted };
  }
  const lvBar = o => { const n = norm({ ...o }), cap = lvCap(n), max = n.level >= cap;
    const pc = lvPct(n); return `<div class="story-lv"><b>Lv.${n.level}${pc ? ` <i class="story-lvpct">+${pc}%</i>` : ''}</b>${max ? '<em>MAX</em>' : `<span>${n.exp}/${n.level * 100}</span>`}</div><div class="story-exp"><i style="width:${max ? 100 : Math.min(100, n.exp / n.level)}%"></i></div>`; };
  const ownedCards = () => deckInstances().map(o => ({ ...boosted(o), uid: o.uid })).filter(x => x.id);
  const normals = () => pool().filter(c => c.grade === 'NORMAL').sort((a, b) => a.power - b.power);
  const rand = a => a[Math.floor(Math.random() * a.length)];
  function pickEnemies(ph) {
    if (ph.enemies.ids) return ph.enemies.ids.map(card).filter(Boolean);
    const [a, b] = ph.enemies.rank, list = normals().slice(a, b), out = [];
    while (out.length < ph.enemies.count && list.length) out.push(list.splice(Math.floor(Math.random() * list.length), 1)[0]);
    return out;
  }

  // 고른 캐릭터 전용 대본(byStarter)이 있으면 챕터 기본값 위에 덮어씀
  // 챕터 2~: 고른 루트(byRoute, save.routes[챕터 id]) 대본을 덮어씀. 루트 주인공(hero)은 출전 카드 필수
  const routeOf = base => base.byRoute ? save?.routes?.[base.id] || null : null;
  function chapterFor(base) {
    const key = base.byStarter ? save?.starter : routeOf(base);
    const o = (base.byStarter || base.byRoute)?.[key]; if (!o) return base;
    return { ...base, route: base.byRoute ? key : undefined, hero: o.hero, subtitle: o.subtitle ?? base.subtitle, start: base.byRoute ? o.start ?? base.start : o.start, ending: base.byRoute ? o.ending ?? base.ending : o.ending,
      phases: base.phases.map(p => { const x = o.phases?.[p.no]; return x ? { ...p, ...x, lines: x.lines ? { default: x.lines } : p.lines } : p; }) };
  }
  // ----- 챕터 선택 -----
  let curCh = null;          // 보고 있는 챕터 위치 (D.chapters 기준)
  let chReady = {};          // 서버에 페이즈 설정이 있는 챕터 (서버 모드에서만 확인)
  const chapterDone = base => base.phases.every(p => (save.cleared[base.id] || []).includes(p.no));
  const chapterOpen = i => i === 0 || (chapterDone(D.chapters[i - 1]) && chReady[D.chapters[i].id] !== false);
  async function checkChapters() {
    chReady = {};
    if (!serverMode) return;
    try { const { data, error } = await cloud().sb.from('story_phase_config').select('chapter'); if (error) throw error; const have = new Set((data || []).map(r => r.chapter));
      for (const c of D.chapters) chReady[c.id] = have.has(c.id); } catch {}
  }
  const latestOpen = () => { let i = 0; while (i + 1 < D.chapters.length && chapterOpen(i + 1)) i++; return i; }
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
  const topBar = (title, back = 'home') => `<div class="story-top"><button class="story-back" data-go="${back}">← ${back === 'home' ? '처음으로' : back === 'hub' ? '스토리 메인' : '돌아가기'}</button><div class="story-top-title">${title}</div><span class="flex gap-1.5"><button class="story-mycards story-gacha-btn" data-go="gacha">🎴 카드 뽑기${canDraw() ? '<i class="story-badge">1</i>' : ''}</button><button class="story-mycards" data-go="cards">🃏 보유 카드</button></span></div>`;
  function bind(extra = {}) {
    root().querySelectorAll('[data-go]').forEach(b => b.onclick = () => ({ home, hub: renderHub, map: renderMap, cards: renderCards, gacha: renderShop, bonds: renderBonds, ...extra })[b.dataset.go]?.());
  }
  const rcls = c => `rar-${(RAR[c?.grade] || 'N').toLowerCase()}`;
  const tile = (c, extra = '') => `<div class="story-card ${rcls(c)}"><div class="story-card-img"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'"><span class="story-rar">${RAR[c.grade] || 'N'}</span></div><div class="story-card-name">${esc(c.name)}</div><div class="story-card-stats"><span class="text-orange-400">${ic('atk', { cls: 'ui-ic-sm' })}${fmt(c.ATK)}</span><span class="text-red-400">${ic('hp', { cls: 'ui-ic-sm' })}${fmt(c.HP)}</span><span class="text-sky-400">${ic('def', { cls: 'ui-ic-sm' })}${fmt(c.DEF)}</span></div>${extra}</div>`;

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
        <button id="story-login" class="w-full py-3 rounded-xl bg-amber-400 text-black font-bold">${ic('login', { alt: '' })} 구글로 로그인</button><button data-close-pop class="w-full mt-2 py-2 rounded-xl bg-white/10">닫기</button>`);
      $('story-login').onclick = () => window.VRCloud?.login?.();
      return;
    }
    if (!window.TCG?.ready) return;
    await load();
    await checkChapters(); curCh = null; tickets = null;
    if (!save.openingSeen) return renderOpening();
    if (!save.starter) return renderSelect();
    renderHub();
    // 스탯 규칙 변경 안내 (한 번만)
    const RF = `vrTcgStatRefundSeen:${user()?.id || 'guest'}:${D.statRuleV || 1}`;
    if (save.statRefunded && !localStorage.getItem(RF)) {
      try { localStorage.setItem(RF, '1'); } catch {}
      const k = D.statPerPoint;
      popup(`<div class="text-lg font-black mb-2">📈 스탯 포인트 규칙이 바뀌었어요</div>
        <div class="text-sm text-zinc-300 space-y-1"><div>· 포인트 1당 ATK +${k.ATK}, HP +${k.HP}, DEF +${k.DEF}</div><div>· 같은 스탯 ${D.statFull + 1}번째 포인트부터는 절반만 올라요</div><div>· 한 스탯에는 그 카드 포인트 합계의 절반(올림)까지만 넣을 수 있어요</div>
        <div class="text-emerald-300 font-bold mt-2">지금까지 분배한 포인트를 모두 돌려드렸어요. 다시 분배해 주세요!</div></div>
        <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">나중에</button><button id="story-refund-go" class="flex-1 py-2.5 rounded-xl bg-emerald-500 text-black font-bold">📈 지금 분배</button></div>`);
      $('story-refund-go').onclick = () => { $('story-pop')?.querySelector('[data-close-pop]')?.click(); openStats(() => renderHub()); };
    }
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
  const replayBtn = `<button class="story-back" data-go="opening">${ic('opening', { alt: '' })} 오프닝 다시 보기</button>`;

  function renderSelect() {
    show(`<div class="text-center"><div class="story-chapter-sub">MAIN STORY</div><div class="text-2xl md:text-3xl font-black mt-1">함께할 캐릭터를 골라 주세요</div>
      <div class="text-sm text-zinc-400 mt-1">고른 카드는 내 카드로 영구 귀속되고, 리더가 돼요. (나중에 바꿀 수 없어요)</div></div>
      <div class="story-select">${D.starters.map(s => { const c = card(s.id); return c ? `<button class="story-pick" data-pick="${s.id}">${tile(c)}<div class="text-xs text-zinc-400 mt-1 story-intro-text">${esc(introOf(s))}</div></button>` : ''; }).join('')}</div>
      <div class="text-center mt-4 flex gap-2 justify-center flex-wrap"><button class="story-back" data-go="home">← 처음으로</button>${replayBtn}</div>`);
    bind({ opening: () => playOpening(renderSelect) });
    root().querySelectorAll('[data-pick]').forEach(b => b.onclick = () => {
      const c = card(b.dataset.pick);
      const p = popup(`<div class="text-lg font-black mb-3">${esc(c.name)}(으)로 시작할까요?</div>${tile(c)}<div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-pick-ok" class="flex-1 py-2.5 rounded-xl bg-amber-400 text-black font-bold">결정</button></div>`);
      $('story-pick-ok').onclick = async () => { p.close(); const r = await act('story_choose_starter', { p_id: String(c.id) }, () => { save.starter = String(c.id); const lead = newCard(c.id); save.leader = lead.uid; save.owned = [lead, ...save.owned]; }); if (!r.ok) return renderSelect(); const ch = chapterFor(D.chapters[0]); chapterIntro(ch, () => startStory(ch)); };
    });
  }

  function chapterIntro(ch, next) {
    show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">MAIN STORY</div><div class="story-chapter-big">${esc(ch.title)}</div><div class="story-chapter-name">${esc(ch.subtitle)}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
    $('story-intro').onclick = next;
  }

  // ----- 루트 선택 (챕터 2~): 서버 story_choose_route. 그 챕터 페이즈를 깨기 전까지만 바꿀 수 있음 -----
  function renderRouteSelect(i) {
    const base = D.chapters[i], cur = routeOf(base);
    show(`${topBar(esc(base.title))}<div class="text-center mt-3"><div class="story-chapter-sub">${esc(base.title)}</div><div class="text-2xl md:text-3xl font-black mt-1">${esc(base.routeTitle || '루트를 골라 주세요')}</div>
      <div class="text-sm text-zinc-400 mt-1">${esc(base.routeNote || '')}</div></div>
      <div class="story-select">${(base.routeOrder || Object.keys(base.byRoute)).map(id => [id, base.byRoute[id]]).map(([id, r]) => { const c = card(id); return c ? `<button class="story-pick ${cur === id ? 'on' : ''}" data-route="${id}">${tile(c, `<div class="text-[10px] mt-0.5 ${repOf(id) ? 'text-emerald-300' : 'text-sky-300'}">${repOf(id) ? '보유 카드로 출전' : '게스트로 출전'}</div>`)}<div class="text-xs text-zinc-400 mt-1 story-intro-text">${esc(r.tagline || '')}</div></button>` : ''; }).join('')}</div>
      <div class="text-center mt-4"><button class="story-back" data-go="${cur ? 'map' : 'prev'}">← ${cur ? '돌아가기' : `${esc(D.chapters[Math.max(0, i - 1)].title)}로`}</button></div>`);
    bind({ map: () => renderMap(i), prev: () => renderMap(Math.max(0, i - 1)) });
    root().querySelectorAll('[data-route]').forEach(b => b.onclick = () => {
      const c = card(b.dataset.route);
      const p = popup(`<div class="text-lg font-black mb-3">${esc(c.name)} 루트로 갈까요?</div>${tile(c)}<div class="text-xs text-zinc-400 mt-2">페이즈를 하나라도 깨면 루트를 바꿀 수 없어요.</div><div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-route-ok" class="flex-1 py-2.5 rounded-xl bg-amber-400 text-black font-bold">결정</button></div>`);
      $('story-route-ok').onclick = async () => { p.close(true); const r = await act('story_choose_route', { p_chapter: base.id, p_route: String(c.id) }, () => { save.routes = { ...(save.routes || {}), [base.id]: String(c.id) }; });
        if (!r.ok) return renderRouteSelect(i); curCh = i; const ch = chapterFor(base); chapterIntro(ch, () => renderMap(i)); };
    });
  }
  // 루트 시작 스토리: 루트마다 1번 (본 표시는 이 브라우저에만 저장)
  const RS_KEY = ch => `vrTcgStoryRouteStart:${user()?.id || 'guest'}:${ch.id}:${ch.route}`;
  const routeStartSeen = ch => { try { return localStorage.getItem(RS_KEY(ch)) === '1'; } catch { return true; } };
  function routeStart(ch) { playLines(ch.start, [], () => { try { localStorage.setItem(RS_KEY(ch), '1'); } catch {} renderMap(); }, 'story', ch.hero); }

  // 시작 스토리: 캐릭터 선택 직후 1번
  function startStory(ch) {
    if (!ch.start?.length || save.startSeen) return renderMap();
    playLines(ch.start, [], async () => { await act('story_mark_seen', { p_key: 'startSeen' }, () => { save.startSeen = true; }); renderMap(); });
  }
  const clearedOf = ch => save.cleared[ch.id] || [];
  function renderMap(idx) {
    if (typeof idx === 'number') curCh = idx;
    if (curCh == null || !chapterOpen(curCh)) curCh = latestOpen();
    const base = D.chapters[curCh];
    if (base.byRoute && !routeOf(base)) return renderRouteSelect(curCh);
    const ch = chapterFor(base), done = clearedOf(ch);
    if (curCh === 0 && ch.start?.length && !save.startSeen) return startStory(ch);
    if (ch.route && ch.start?.length && !routeStartSeen(ch)) return routeStart(ch);
    const nextNo = ch.phases.find(p => !done.includes(p.no))?.no;
    const leader = boosted(byUid(save.leader) || save.owned[0]);
    const hero = ch.hero && card(ch.hero);
    const node = (p, i) => { const st = done.includes(p.no) ? 'done' : p.no === nextNo ? 'next' : 'lock';
      return `${i ? `<div class="story-path ${st !== 'lock' ? 'on' : ''}"></div>` : ''}<button class="story-node ${st} ${p.type}" data-phase="${p.no}" ${st === 'lock' ? 'disabled' : ''}><span class="story-node-dot">${st === 'done' ? '✔' : p.type === 'boss' ? ic('crown', { alt: '보스', cls: 'story-node-ic' }) : st === 'lock' ? '🔒' : p.no}</span><span class="story-node-label">Phase.${p.no}${p.type === 'boss' ? ' BOSS' : ''}</span></button>`; };
    const rows = []; for (let k = 0; k < ch.phases.length; k += 5) rows.push(ch.phases.slice(k, k + 5));   // 5칸씩 한 줄
    const tabs = D.chapters.length > 1 ? `<div class="story-chtabs">${D.chapters.map((c, i) => { const open = chapterOpen(i), why = !open ? (i && !chapterDone(D.chapters[i - 1]) ? `${esc(D.chapters[i - 1].title)} 클리어 후` : '준비 중') : '';
      return `<button class="story-chtab ${i === curCh ? 'on' : ''}" data-ch="${i}" ${open ? '' : 'disabled'}>${open ? '' : '🔒 '}${esc(c.title)}${why ? `<small>${why}</small>` : ''}</button>`; }).join('')}</div>` : '';
    const nextCh = D.chapters[curCh + 1], nextOpen = nextCh && chapterOpen(curCh + 1);
    show(`${topBar(esc(ch.title), 'hub')}${tabs}
      <div class="text-center mt-2"><div class="story-chapter-big text-3xl md:text-5xl">${esc(ch.title)}</div><div class="story-chapter-name">${esc(ch.subtitle)}</div>
        ${hero ? `<div class="story-route-tag">루트 <b>${esc(hero.name)}</b>${clearedOf(ch).length ? '' : ' <button class="story-mini" data-go="route">루트 바꾸기</button>'}</div>` : ''}</div>
      <div class="story-player-row" data-vr-player></div>
      ${rows.map(r => `<div class="story-map ${rows.length > 1 ? 'story-map-row' : ''}">${r.map(node).join('')}</div>`).join('')}
      <div class="story-status">${leader ? `<div>리더 <b class="text-amber-300">${esc(leader.name)}</b> · 보유 카드 <b>${save.owned.length}</b>장</div>` : ''}
        <div class="story-rule">⚔️ 스토리 전투: 출전 카드 최대 ${MAX_PICK()}장이 모두 필드에서 시작해요 (손패·드로우·용병 없음, 내 진영 없음). 내 카드가 모두 쓰러지거나 ${RULES_TURNS()}턴이 지나면 패배 · 일반전은 상대 카드 전멸, 👑 보스전은 상대 진영 HP 0이면 승리</div>
        <div>스탯 포인트 <b class="text-emerald-300">${save.points}</b> ${save.points ? '<button class="story-mini" data-go="stats">분배하기</button>' : ''}</div>
        ${!serverMode && !window.__STORY_MOCK_USER ? '<div class="text-[11px] text-amber-400">⚠️ 서버 저장 준비 중이라 이 브라우저에만 저장돼요</div>' : ''}</div>
      ${nextNo ? '' : `<div class="text-center text-emerald-300 font-bold mt-4">🎉 ${esc(ch.title)} 클리어! ${nextOpen ? `<button class="story-btn ml-1" data-ch="${curCh + 1}">${esc(nextCh.title)}로 →</button>` : '다음 챕터는 준비 중이에요.'}</div>`}
      <div class="text-center mt-5">${replayBtn}</div>`);
    bind({ stats: () => openStats(renderMap), opening: () => playOpening(renderMap), route: () => renderRouteSelect(curCh) }); playerPaint();
    root().querySelectorAll('[data-ch]').forEach(b => b.onclick = () => renderMap(+b.dataset.ch));
    root().querySelectorAll('[data-phase]').forEach(b => b.onclick = () => startPhase(ch, ch.phases.find(p => p.no === +b.dataset.phase)));
  }

  // ----- 스토리 메인 (허브): 이어하기 · 챕터 목록 · 메뉴. 배경 img/story/hub/bg_pc.webp / bg_m.webp (없으면 메인 배경) -----
  function nextPlay() {   // 열린 챕터 중 안 깬 페이즈가 있는 첫 챕터
    for (let i = 0; i < D.chapters.length && chapterOpen(i); i++) {
      const base = D.chapters[i], ch = chapterFor(base), ph = ch.phases.find(p => !clearedOf(ch).includes(p.no));
      if (ph) return { i, base, ch, ph };
    }
    return null;
  }
  // ----- 인연: data/combos.json 의 특정 조합. 보유한 카드는 공개, 없는 카드는 실루엣 -----
  const combosAll = () => window.TCG?.combos?.() || [];
  const bondEff = b => { const k = [b.atk && 'ATK', b.def && 'DEF', b.hp && 'HP'].filter(Boolean).join('·'); return `${b.scope === 'all' ? '아군 전체' : '조합 카드'} ${k} +${Math.round((b.value || 0) * 100)}%`; };
  function bondStats() { const have = new Set(save.owned.map(o => o.id)), list = combosAll(); return { total: list.length, done: list.filter(b => b.cards.every(id => have.has(String(id)))).length }; }
  function renderBonds() {
    const have = new Set(save.owned.map(o => o.id)), list = combosAll().map(b => ({ ...b, n: b.cards.filter(id => have.has(String(id))).length }))
      .sort((a, b) => (b.n === b.cards.length) - (a.n === a.cards.length) || b.n / b.cards.length - a.n / a.cards.length);
    const st = bondStats();
    show(`${topBar('🤝 인연', 'hub')}<div class="text-center text-sm text-zinc-400 my-2">특정 카드가 함께 필드에 있으면 발동해요 · 완성 ${st.done}/${st.total}</div>
      <div class="story-bonds">${list.map(b => { const full = b.n === b.cards.length;
        return `<div class="story-bond ${full ? 'full' : ''}"><div class="story-bond-h"><b>${esc(b.name)}</b><span class="story-bond-n">${b.n}/${b.cards.length}${full ? ' ✔' : ''}</span></div>
          <div class="story-bond-cards">${b.cards.map(id => { const c = card(id), own = have.has(String(id));
            return `<div class="story-bond-card ${own ? 'own' : 'sil'} ${rcls(c)}"><img src="${IMG}${id}.webp" alt="" loading="lazy" onerror="this.style.visibility='hidden'"><span>${own ? esc(c?.name || '') : '???'}</span></div>`; }).join('')}</div>
          <div class="story-bond-eff">${esc(bondEff(b))}</div></div>`; }).join('') || '<div class="text-center text-zinc-500">인연 데이터가 없어요</div>'}</div>`);
    bind();
  }
  function renderHub() {
    const nx = nextPlay();
    const rows = D.chapters.map((base, i) => {
      const open = chapterOpen(i), ch = chapterFor(base), n = clearedOf(ch).length, tot = ch.phases.length, r = routeOf(base), hero = r && card(r);
      const why = open ? '' : (i && !chapterDone(D.chapters[i - 1]) ? `${esc(D.chapters[i - 1].title)} 클리어 후` : '준비 중');
      return `<button class="story-hub-ch main-btn ${open ? '' : 'locked'}" data-hubch="${i}" ${open ? '' : 'disabled'}>
        <span class="story-hub-ch-t">${open ? '' : '🔒 '}${esc(base.title)}${ch.subtitle ? ` 「${esc(ch.subtitle)}」` : ''}</span>
        <span class="story-hub-ch-s">${open ? `${hero ? `${esc(hero.name)} 루트 · ` : base.byRoute ? '루트 선택 전 · ' : ''}${n}/${tot}${n >= tot ? ' ✔ 클리어' : ''}` : why}</span></button>`; }).join('');
    show(`<div class="story-hub-bg" aria-hidden="true"></div><div class="story-hub">
      <div class="story-top"><button class="story-back" data-go="home">← 처음으로</button><div class="story-top-title">스토리 모드</div><span data-vr-player></span></div>
      <button class="story-hub-go main-btn" id="story-continue" ${nx ? '' : 'disabled'}><b>▶ 이어하기</b><small>${nx ? `${esc(nx.base.title)} · Phase.${nx.ph.no}${nx.ph.title ? ` 「${esc(nx.ph.title)}」` : ''}${nx.ph.type === 'boss' ? ' · BOSS' : ''}` : '열린 챕터를 모두 클리어했어요'}</small></button>
      <div class="story-hub-list">${rows}</div>
      <div class="story-hub-menu">
        <button class="main-btn" data-go="gacha">🎴 카드 뽑기${canDraw() ? '<i class="story-badge">1</i>' : ''}<small class="story-hub-tk">${tickets ? `🎟️ ${tickets}` : ''}</small></button>
        <button class="main-btn" data-go="cards">🃏 내 카드/스탯${save.points ? ` <i class="story-badge">${save.points}</i>` : ''}</button>
        <button class="main-btn" data-go="bonds">🤝 인연${(() => { const b = bondStats(); return b.total ? ` <small>${b.done}/${b.total}</small>` : ''; })()}</button>
        <button class="main-btn" id="story-quest" type="button" onclick="window.VRQuest&&VRQuest.open()">🗼 시련의 탑</button>
        <button class="main-btn" id="story-mypage" type="button" onclick="window.VRMyPage&&VRMyPage.open()">👤 마이페이지</button>
        <button class="main-btn" disabled title="준비 중">📅 이벤트 스토리 <small>준비 중</small></button></div>
    </div>`);
    bind(); playerPaint();
    if (tickets == null) syncTickets().then(r => { if (r.added) toast(`🎟️ 소환권 +${r.added} (챕터 클리어 보상)`); const el = root().querySelector('.story-hub-tk'); if (el) el.textContent = tickets ? `🎟️ ${tickets}` : ''; });
    root().querySelectorAll('[data-hubch]').forEach(b => b.onclick = () => renderMap(+b.dataset.hubch));
    $('story-continue').onclick = () => {
      if (!nx) return;
      curCh = nx.i;
      // 루트 선택·시작 대사가 남았으면 지도 쪽 흐름으로, 아니면 바로 다음 페이즈
      if ((nx.base.byRoute && !routeOf(nx.base)) || (nx.i === 0 && nx.ch.start?.length && !save.startSeen) || (nx.ch.route && nx.ch.start?.length && !routeStartSeen(nx.ch))) return renderMap(nx.i);
      startPhase(nx.ch, nx.ph);
    };
  }

  function startPhase(ch, ph) {
    const enemies = pickEnemies(ph);
    show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">${esc(ch.title)}</div><div class="story-chapter-big">Phase.${ph.no}</div><div class="story-chapter-name">${esc(ph.title)}${ph.type === 'boss' ? ' · BOSS' : ''}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
    $('story-intro').onclick = () => dialogue(ch, ph, enemies);
  }

  function dialogue(ch, ph, enemies) {
    playLines(ph.lines?.[save.starter] || ph.lines?.default || [], enemies, () => pickDeck(ch, ph, enemies), 'story', ph.hero || ch.hero);
  }
  function playLines(lines, enemies, next, track = 'story', heroId = null) {
    const heroes = (Array.isArray(heroId) ? heroId : [heroId || save.starter]).map(card).filter(Boolean);   // 대사 왼쪽(주인공) 자리. 여러 명 가능
    const starter = heroes[0] || card(save.starter), enemy = enemies[0];
    const byName = n => enemies.find(c => c.name === n) || pool().filter(c => c.name === n).sort((a, b) => (a.region === starter?.region ? -1 : 0) - (b.region === starter?.region ? -1 : 0))[0] || null;
    const who = L => L.portrait !== undefined ? (L.portrait === 'starter' ? starter : L.portrait === 'enemy' ? enemy : L.portrait ? card(L.portrait) : null)
      : (D.noPortrait || []).includes(L.speaker) ? null : (heroes.find(h => h.name === L.speaker) || byName(L.speaker));
    let i = 0;
    const step = () => {
      if (i >= lines.length) return next();
      const L0 = lines[i], tag = /^(.+?)\s*\((기본|화남|웃음)\)$/.exec(L0.speaker || ''), L = tag ? { ...L0, speaker: tag[1], expr: L0.expr || tag[2] } : L0;
      const pc = who(L), sp = L.speaker === 'starter' ? starter?.name : L.speaker === 'enemy' ? enemy?.name : (L.speaker === '내레이션' ? null : L.speaker);
      const left = pc ? heroes.includes(pc) : true;
      const slug = pc && D.portraits?.[pc.name], ex = D.exprSlug?.[L.expr || '기본'] || 'base';
      show(`<div class="story-dlg" id="story-dlg">
        <div class="story-dlg-stage">${pc ? (slug ? `<img class="story-portrait sp ${left ? 'left' : 'right'}" src="img/story/portraits/${slug}_${ex}.webp" alt="${esc(pc.name)}" onerror="this.onerror=null;this.classList.remove('sp');this.src='${IMG}${pc.id}.webp'">` : `<img class="story-portrait ${left ? 'left' : 'right'}" src="${IMG}${pc.id}.webp" alt="${esc(pc.name)}">`) : ''}</div>
        <div class="story-dlg-box">${sp ? `<div class="story-dlg-name">${esc(sp)}</div>` : ''}<div class="story-dlg-text">${esc(L.text)}</div><div class="story-dlg-next">▼ ${i + 1}/${lines.length}</div></div>
        <button class="story-dlg-skip" id="story-dlg-skip">건너뛰기 ⏭</button></div>`, track);
      $('story-dlg').onclick = e => { if (e.target.id === 'story-dlg-skip') { i = lines.length; } else i++; step(); };
    };
    step();
  }

  // ----- 스토리 전투 규칙: 출전 카드(최대 5장) 전부 필드에서 시작, 손패·드로우·용병 없음, 내 진영 없음 -----
  /** 보스전 상대 진영 HP: 페이즈 baseHp → 챕터 표(bossBaseHp) → 표 뒤 챕터는 마지막 값 + 250씩 */
  function bossHp(ch, ph) {
    if (ph.baseHp) return ph.baseHp;
    const t = D.bossBaseHp || [500], i = Math.max(0, (ch.id | 0 || 1) - 1);
    return i < t.length ? t[i] : t[t.length - 1] + 250 * (i - t.length + 1);
  }
  /** 보스 카드: 페이즈 bossId → enemyName 과 같은 이름 → ids 지정 시 첫 카드 → 가장 강한 카드 */
  function bossOf(ph, enemies) {
    if (!enemies.length) return null;
    const byId = ph.bossId != null && enemies.find(c => String(c.id) === String(ph.bossId));
    const byName = ph.enemyName && enemies.find(c => c.name === ph.enemyName);
    return byId || byName || (ph.enemies?.ids ? enemies[0] : [...enemies].sort((a, b) => (b.power || 0) - (a.power || 0))[0]);
  }
  const PICK_KEY = () => `vrTcgStoryPick:${user()?.id || 'guest'}`;
  /** 출전 카드 고르기 (카드마다 1장, 최대 5장). 보유 카드가 5종 이하면 전부 출전 */
  /** 페이즈 필수 출전: party.forced (없으면 루트 주인공). 보유하지 않은 카드는 게스트(리더 레벨, 강화·EX 없음, 전투 EXP 없음) */
  const isGuest = o => String(o?.uid || '').startsWith('guest:');
  function guestOf(id) {
    const lead = byUid(save.leader) || save.owned[0], g = { uid: 'guest:' + id, id: String(id), boost: {}, level: 1, exp: 0, totalExp: 0, cpts: 0, spentCard: 0, ex: 0, exb: 0, guest: true };
    g.level = Math.max(1, Math.min(lvCap(g), norm({ ...(lead || {}) }).level || 1)); return g;
  }
  function partyOf(ch, ph) {
    const pt = ph.party || (ch.hero ? { forced: [ch.hero] } : null);
    const forced = (pt?.forced || []).map(id => repOf(id) || guestOf(id)).filter(o => card(o.id));
    return { forced, exclude: new Set([...(pt?.exclude || []), ...(pt?.forced || [])].map(String)) };
  }
  /** opts (퀘스트 등 재사용): { onGo(list), onCancel(), note } — 없으면 스토리 페이즈 전투 */
  function pickDeck(ch, ph, enemies, opts = null) {
    const { forced, exclude } = partyOf(ch, ph), slots = Math.max(0, MAX_PICK() - forced.length);
    const all = deckInstances().filter(o => !exclude.has(o.id));
    const go = opts?.onGo || (list => battle(ch, ph, enemies, list));
    if (all.length <= slots && !forced.length) return go(all);
    let last = []; try { last = JSON.parse(localStorage.getItem(PICK_KEY()) || '[]'); } catch {}
    const valid = new Set(all.map(o => o.uid));
    let sel = last.filter(u => valid.has(u)).slice(0, slots);
    if (!sel.length) sel = all.slice().sort((a, b) => (isLeader(b) - isLeader(a)) || (boosted(b)?.power || 0) - (boosted(a)?.power || 0)).slice(0, slots).map(o => o.uid);
    const deck0 = new Set(sel);   // 현재 덱: 창을 연 순간의 출전 카드 (고르는 동안 자리가 바뀌지 않게)
    let list = sortInst(all, deck0);
    /** 출전 카드 타일: 등급·별·기술 수·레벨·이름 */
    const pickTile = o => { const c = boosted(o), n = skillsOf(o.id).length; return `<div class="story-card story-pick-tile ${rcls(c)}"><div class="story-card-img"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'"><span class="story-rar">${RAR[c.grade] || 'N'}</span>${window.rarityStars?.(c, exOf(o) ? 'ex' : 'base', 'rstars-over rstars-sm') || ''}${n ? `<span class="story-skn" title="기술 ${n}개">✦${n}</span>` : ''}${deck0.has(o.uid) ? '<span class="story-curdeck">현재 덱</span>' : ''}</div><div class="story-card-name">${esc(c.name)}</div><div class="text-[11px] text-zinc-300 font-bold">Lv.${norm({ ...o }).level}${isLeader(o) ? ` · ${ic('crown', { alt: '' })} 리더` : ''}</div></div>`; };
    const boss = ph.type === 'boss';
    const fTile = o => { const c = boosted(o); return `<div class="story-pick-card on locked" title="이번 페이즈 필수 출전">${tile(c, `<div class="text-[10px] ${isGuest(o) ? 'text-sky-300' : 'text-zinc-400'}">Lv.${norm({ ...o }).level}${isGuest(o) ? ' · 게스트' : ''}</div>`)}<i class="story-pick-check">🔒</i></div>`; };
    const draw = () => {
      const p = popup(`<div class="story-pop-title">출전 카드 선택 <span class="text-emerald-300">${forced.length + sel.length}/${MAX_PICK()}</span></div>
        <div class="text-xs text-zinc-400 mb-2">${opts?.note ? `${opts.note}<br>` : ''}고른 카드가 모두 필드에서 시작해요. 손패·드로우는 없고, 내 카드가 모두 쓰러지면 패배예요.${boss ? '<br>👑 보스전: 보스는 진영 안에서 쓰러지지 않아요. 상대 진영 HP를 0으로!' : ''}</div>
        ${forced.length ? `<div class="story-forced-h">${ic('crown', { alt: '' })} 필수 출전 ${forced.length}장 <small>(게스트는 리더 레벨로 함께 싸우고, 전투 EXP는 받지 않아요)</small></div><div class="story-grid story-deckpick story-forced">${forced.map(fTile).join('')}</div>
          <div class="story-forced-h">나머지 ${slots}장 고르기${[...exclude].filter(id => !forced.some(o => o.id === id)).map(id => card(id)).filter(Boolean).map(c => ` · <span class="text-red-300">${esc(c.name)} 출전 불가</span>`).join('')}</div>` : ''}
        ${sortBar()}<div class="story-grid story-deckpick">${list.map(o => { const on = sel.includes(o.uid);
          return `<button class="story-pick-card ${on ? 'on' : ''}" data-pick="${o.uid}">${pickTile(o)}${on ? '<i class="story-pick-check">✔</i>' : ''}</button>`; }).join('')}</div>
        ${(() => { const lo = byUid(save.leader); if (!lo) return ''; const inF = forced.some(f => f.uid === lo.uid), out = inF ? '' : exclude.has(lo.id) ? '이번 페이즈에는 리더가 출전할 수 없어 리더 스킬이 꺼져요' : !sel.includes(lo.uid) ? '리더를 출전시키지 않으면 리더 스킬이 꺼져요' : ''; return out ? `<div class="story-hint">${ic('crown', { alt: '' })} ${out}</div>` : `<div class="text-[11px] text-amber-200 mt-2">${ic('crown', { alt: '' })} 리더 스킬 켜짐: ${esc(leaderEff(lo.id)?.text || '')}</div>`; })()}
        <div class="flex gap-2 mt-3 story-pop-actions"><button class="story-back flex-1" data-close-pop>취소</button><button class="story-btn flex-1" id="story-deck-ok" ${sel.length || forced.length ? '' : 'disabled'}>출전 (${forced.length + sel.length}장)</button></div>`, () => (opts?.onCancel || renderMap)());
      p.el.querySelectorAll('[data-pick]').forEach(b => b.onclick = () => {
        const u = b.dataset.pick;
        if (sel.includes(u)) sel = sel.filter(x => x !== u);
        else if (sel.length < slots) sel.push(u);
        else { toast(`최대 ${MAX_PICK()}장까지 출전할 수 있어요.`); return; }
        p.close(true); draw();
      });
      p.el.querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { setSort(b.dataset.sort); list = sortInst(all, deck0); p.close(true); draw(); });
      $('story-deck-ok').onclick = () => { if (!sel.length && !forced.length) return; try { localStorage.setItem(PICK_KEY(), JSON.stringify(sel)); } catch {} p.close(true); go([...forced, ...list.filter(o => sel.includes(o.uid))]); };
    };
    draw();
  }

  let deckUid = {};   // 이번 전투 출전 카드 id → 인스턴스 uid
  async function battle(ch, ph, enemies, picked) {
    const P = window.VRPlayer, ps = serverMode && P ? await P.status(true) : null;
    if (ps && ps.stamina < P.cost) { staminaShort(ps); return renderMap(); }
    const st = await act('story_start_phase', { p_chapter: ch.id, p_phase: ph.no }, () => {});
    if (!st.ok) { if (/stamina/.test(st.error?.message || '')) staminaShort(await P?.status(true)); return renderMap(); }
    if (ps) P.status(true);
    root().classList.add('hidden');
    const boss = ph.type === 'boss';
    bgm(boss ? 'boss' : 'battle');
    const me = (picked || deckInstances()).slice(0, MAX_PICK()).map(o => ({ ...boosted(o), uid: o.uid })).filter(x => x.id);
    deckUid = Object.fromEntries(me.map(c => [String(c.id), c.uid]));
    const bc = boss ? bossOf(ph, enemies) : null;
    // 보스 카드를 맨 앞에 (진영 안 표시), 나머지는 그대로
    const ai = bc ? [bc, ...enemies.filter(c => c !== bc)] : enemies;
    window.TCG.startStory({
      me, ai, leader: (() => { const lo = me.find(c => c.uid === save.leader), le = lo && leaderEff(lo.id); return le ? { ...le, uid: lo.uid } : undefined; })(), win: boss ? 'ko' : 'wipe', aiHp: boss ? bossHp(ch, ph) : undefined, bossId: bc ? String(bc.id) : undefined, aiName: ph.enemyName || (boss ? '보스' : '적군'), first: 'me',
      onEnd: (win, reason, st) => result(ch, ph, win, reason, st),
    });
    if (ph.tip) setTimeout(() => toast(`💡 ${ph.tip}`), 3400);   // 규칙 안내 뒤에 이어서 (겹치지 않게)
    toast(boss ? `👑 보스전: 보스는 쓰러지지 않아요. 상대 진영 HP ${fmt(bossHp(ch, ph))}을 0으로!` : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리세요!');
  }
  // ----- 플레이어 레벨 · 행동력 (js/player.js, 서버 phaseE_2.sql) -----
  function playerPaint() { const P = window.VRPlayer; if (!P || !serverMode) return; P.paint(); P.status().then(() => P.paint()); }
  function staminaShort(s) {
    const P = window.VRPlayer, t = s && !s.stamina_max ? '' : s ? ` (보유 ${s.stamina}/${P.cost}${s.next_regen_secs ? ` · 다음 회복 ${P.mmss(s.next_regen_secs)}` : ''})` : '';
    toast(`🔋 행동력이 부족해요${t} · 6분에 1씩 회복돼요`);
  }
  function playerResult(p) {
    if (!p) return '';
    const pct = p.xp_next ? Math.min(100, Math.round(p.xp / p.xp_next * 100)) : 100;
    return `<div class="story-pxp">플레이어 경험치 <b class="text-amber-300">+${p.gained_xp | 0}</b> · Lv.${p.level} ${p.xp_next ? `(${p.xp}/${p.xp_next})` : '(최대)'}<div class="bar"><i style="width:${pct}%"></i></div>
      ${p.levelups ? `<div class="story-plvup">PLAYER LEVEL UP! Lv.${p.level - p.levelups} → Lv.${p.level} · 🔋 행동력 충전${p.levelup_gold ? ` · 🪙 골드 +${fmt(p.levelup_gold)}` : ''}</div>` : ''}</div>`;
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'story-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 3200); }

  async function result(ch, ph, win, reason, st = {}) {
    if (!win) {
      const ab = serverMode && window.VRPlayer ? await window.VRPlayer.abort() : null;
      show(`<div class="text-center py-10"><div class="story-chapter-big text-red-400">DEFEAT</div><div class="text-zinc-300 mt-2">${reason === 'giveup' ? '도전을 포기했어요.' : reason === 'wipe' ? '내 필드 카드가 모두 쓰러졌어요.' : reason === 'timeout' ? (ph.type === 'boss' ? '턴 제한 안에 상대 진영을 무너뜨리지 못했어요.' : '턴 제한 안에 적을 모두 쓰러뜨리지 못했어요.') : '패배했어요.'} 스탯을 올리고 다시 도전해 보세요!</div>${ab?.refunded ? `<div class="mt-2 text-emerald-300 text-sm">🔋 행동력 ${ab.refunded} 반환 (보유 ${ab.stamina}/${ab.stamina_max})</div>` : ''}
        <div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="story-retry">다시 도전</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
      bind(); $('story-retry').onclick = () => startPhase(ch, ph); return;
    }
    // 서버가 첫 클리어 여부·보상(카드·포인트)을 결정. 재클리어는 보상 없음
    let first = !clearedOf(ch).includes(ph.no), reward = null, pts = 0;
    // 전투 EXP: 이번 전투에 낸 내 카드 + 처치 수 (서버가 보유 여부·처치 상한·배율을 다시 계산)
    const kills = st.kills || {}, p_stats = [...new Set(st.played || [])].filter(id => !isGuest({ uid: deckUid[id] })).slice(0, 30).map(id => ({ uid: deckUid[id], id, kills: kills[id] | 0 }));
    const res = await act('story_complete_phase', { p_chapter: ch.id, p_phase: ph.no, p_stats }, () => {
      const exp = [], cap = Math.max(0, (ph.enemies?.ids?.length || ph.enemies?.count || 99) - (ph.type === 'boss' ? 1 : 0)); let ksum = 0;   // 보스 카드는 쓰러지지 않음
      for (const s of p_stats) {
        const o = byUid(s.uid) || save.owned.find(x => x.id === s.id); if (!o) continue;
        const k = Math.min(s.kills, Math.max(0, cap - ksum)); ksum += k;
        const gain = (60 + 20 * k) * (ph.type === 'boss' ? 2 : 1), from = norm(o).level, g = gainCalc(o, gain);
        Object.assign(o, { level: g.level, exp: g.exp, totalExp: g.totalExp, cpts: g.cpts });
        exp.push({ uid: o.uid, id: o.id, kills: k, exp: gain, from, level: g.level });
      }
      if (!first) return { exp };
      const have = new Set(save.owned.map(o => o.id));
      const rc = ch.rewardCard ? rand(pool().filter(c => c.grade === ch.rewardCard && !have.has(String(c.id)))) : null;
      if (rc) save.owned.push(newCard(rc.id));
      save.cleared[ch.id] = [...clearedOf(ch), ph.no];
      save.points += D.statPoints[ph.type];   // 스탯 포인트는 페이즈 첫 클리어 때만
      return { first: true, points: D.statPoints[ph.type], reward_id: rc && String(rc.id), exp };
    }, r => r.data);
    if (!res.ok) {
      const m = String(res.error?.message || ''), why = /too fast/.test(m) ? '전투가 너무 빨리 끝나서 기록이 인정되지 않았어요.' : /battle not started/.test(m) ? '전투 시작 기록이 없어요. (새로고침·다른 기기에서 전투를 시작했을 수 있어요)' : `결과를 서버에 저장하지 못했어요.${m ? ` (${esc(m)})` : ''}`;
      show(`<div class="text-center py-10"><div class="story-chapter-big text-amber-300">!</div><div class="text-zinc-300 mt-2">${why}<br>다시 도전해 주세요.</div><div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="story-retry">다시 도전</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
      bind(); $('story-retry').onclick = () => startPhase(ch, ph); return; }
    const r = res.r || {};
    const pr = res.raw?.player || null; if (pr) window.VRPlayer?.set(pr);
    first = !!r.first; pts = r.points | 0; reward = r.reward_id ? card(r.reward_id) : null;
    // 승리 후 대사: 페이즈 after(막간·루트 엔딩) → 보스면 챕터 엔딩. 첫 클리어 때만
    if (first && ph.after?.length) await new Promise(ok => {
      const go = () => playLines(ph.after, [], ok, /엔딩/.test(ph.afterTitle || '') ? 'ending' : 'story', ph.hero || ch.hero);
      if (!ph.afterTitle) return go();
      show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">${esc(ch.title)} · Phase.${ph.no} 승리 후</div><div class="story-chapter-name">${esc(ph.afterTitle)}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
      $('story-intro').onclick = go;
    });
    if (first && ph.type === 'boss' && ch.ending?.length) await new Promise(ok => playLines(ch.ending, [], ok, 'ending', ph.hero || ch.hero));
    const tk = first && chapterDone(D.chapters.find(c => c.id === ch.id) || ch) ? await syncTickets() : null;   // 챕터 첫 클리어 → 소환권
    show(`<div class="text-center py-6"><div class="story-chapter-sub">Phase.${ph.no} CLEAR</div><div class="story-chapter-big text-emerald-300">VICTORY</div>
      ${reward ? `<div class="mt-4 text-amber-200 font-bold">🎁 보상 카드 획득!</div><div class="flex justify-center mt-2 story-reward">${tile(reward)}</div>` : `<div class="mt-4 text-zinc-400 text-sm">${first ? '이번 챕터는 카드 보상 없이 스탯 포인트만 받아요.' : '이미 클리어한 페이즈라 카드 보상은 없어요.'}</div>`}
      ${tk?.added ? `<div class="mt-3 text-amber-200 font-bold">🎟️ 챕터 클리어 보상: 소환권 +${tk.added} <small class="text-zinc-400">(특수 뽑기에서 사용)</small></div>` : ''}
      ${r.drops ? `<div class="story-drops mt-3">${first ? '🎁 첫 클리어 ' : ''}획득 ${curTxt(r.drops)}</div>` : ''}
      ${playerResult(pr)}
      ${expList(r.exp)}
      <div class="mt-4 text-lg">${pts ? `스탯 포인트 <b class="text-emerald-300">+${pts}</b> (보유 ${save.points})` : '<span class="text-zinc-400 text-sm">다시 클리어한 페이즈라 스탯 포인트는 없어요.</span>'}</div>
      <div class="flex flex-col gap-2 max-w-xs mx-auto mt-5"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
    bind({ stats: () => openStats(renderMap) });
    if (pr?.levelups) levelUpFx('PLAYER LEVEL UP!'); else if ((r.exp || []).some(e => e.level > e.from)) levelUpFx();
  }
  // 전투 EXP 결과 목록
  function expList(list) {
    if (!list?.length) return '';
    return `<div class="story-explist">${list.map(e => { const c = card(e.id), o = (e.uid && byUid(e.uid)) || save.owned.find(x => x.id === e.id) || { id: e.id, level: e.level }, up = e.level > e.from;
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
      const p = popup(`<div class="text-lg font-black mb-1">📈 스탯 분배</div><div class="text-xs text-zinc-400 mb-3">공용 포인트 <b class="text-emerald-300 text-base">${left}</b>${cleft[sel] ? ` · 이 카드 전용 <b class="text-sky-300 text-base" id="story-cpts">${cleft[sel]}</b>` : ''} · 포인트 1당 ATK +${k.ATK}, HP +${k.HP}, DEF +${k.DEF}
          <div class="text-[11px] text-zinc-500 mt-0.5">같은 스탯 ${D.statFull + 1}번째 포인트부터는 절반 · 한 스탯에는 이 카드 포인트 합계의 절반(올림)까지</div>${cleft.some(Boolean) ? '<div class="text-[11px] text-zinc-500">예전에 받은 카드 전용 포인트를 먼저 써요</div>' : ''}</div>
        <div class="story-tabwrap"><button class="story-tab-arr l" aria-label="왼쪽">‹</button><div class="story-tabs">${save.owned.map((x, i) => { const cc = card(x.id); return `<button data-sel="${i}" class="story-chip ${i === sel ? 'on' : ''}">${x.uid === save.leader ? ic('crown', { alt: '리더' }) + ' ' : ''}${esc(exName(x, cc?.name))} <small>Lv.${x.level}</small>${cleft[i] ? ` <b class="text-sky-300">+${cleft[i]}</b>` : ''}</button>`; }).join('')}</div><button class="story-tab-arr r" aria-label="오른쪽">›</button></div>
        <div class="flex gap-3 items-center"><img src="${IMG}${c.id}.webp" class="w-20 aspect-[3/4] object-cover rounded-lg" alt=""><div class="flex-1 space-y-2">${STATS.map(s => { const n = temp[sel][s] | 0, sum = ptSum(temp[sel]), cap = ptCap(sum + 1), canInc = avail && n + 1 <= cap, canDec = n > (o.boost?.[s] || 0) && ptOk({ ...temp[sel], [s]: n - 1 });
          return `<div class="flex items-center gap-2"><span class="w-16 text-sm font-bold">${STAT_LABEL[s]}</span><span class="flex-1 font-black">${fmt(c[s])}${n ? ` <span class="text-emerald-300 text-xs">(+${fmt(ptGain(s, n))})</span>` : ''}
            <span class="story-ptinfo block text-[10px] font-normal ${n >= D.statFull ? 'text-amber-300' : 'text-zinc-500'}">${n}포인트 (최대 ${ptCap(sum)}) · 다음 +${ptNext(s, n)}${n >= D.statFull ? ' (절반)' : ''}${avail && !canInc ? ' · <i class="not-italic text-red-300">상한</i>' : ''}</span></span><button data-dec="${s}" class="story-pm" ${canDec ? '' : 'disabled'}>−</button><button data-inc="${s}" class="story-pm" ${canInc ? '' : 'disabled'}>＋</button></div>`; }).join('')}</div></div>
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
        if (!ptOk({ ...temp[sel], [b.dataset.inc]: (temp[sel][b.dataset.inc] | 0) + 1 })) return;
        if (cleft[sel]) cleft[sel]--; else if (left) { left--; gUsed[sel]++; } else return;
        temp[sel][b.dataset.inc] = (temp[sel][b.dataset.inc] || 0) + 1; draw(); });
      p.el.querySelectorAll('[data-dec]').forEach(b => b.onclick = () => {
        if (!ptOk({ ...temp[sel], [b.dataset.dec]: (temp[sel][b.dataset.dec] | 0) - 1 })) return;
        temp[sel][b.dataset.dec]--; if (gUsed[sel]) { gUsed[sel]--; left++; } else cleft[sel]++; draw(); });
      $('story-stat-ok').onclick = async () => {
        const alloc = {};
        save.owned.forEach((x, i) => { for (const st of STATS) { const n = (temp[i][st] || 0) - (x.boost?.[st] || 0); if (n > 0) (alloc[x.uid] ||= {})[st] = n; } });
        if (Object.keys(alloc).length) await act('story_allocate', { p_alloc: alloc }, () => {
          save.owned.forEach((x, i) => { const fromCard = added(i) - gUsed[i]; x.boost = temp[i]; x.cpts -= fromCard; x.spentCard += fromCard; });
          save.points = left; });
        p.close();
      };
    };
    draw();
  }

  // ----- 보유 카드 (카드별로 묶어서 보여 주고, 펼치면 한 장씩) -----
  const cptsTotal = () => save.owned.reduce((a, o) => a + (o.cpts | 0), 0);
  const isLeader = o => !!o && o.uid === save.leader;
  /** 분해 잠금: 직접 잠근 카드 + 리더(자동 잠금). 잠긴 카드는 분해·합성 재료로 못 씀 (서버도 같은 검사) */
  const isLocked = o => !!o && (isLeader(o) || !!o.locked);
  const canDiscard = o => !isLocked(o) && save.owned.length > 1;
  // ----- 리더 스킬 (스토리 전용): 속성 효과 + 클래스 효과 -----
  const LS_KEYS = [['atk', 'ATK'], ['def', 'DEF'], ['hp', 'HP']], LS_FOE = [['eAtk', 'ATK'], ['eDef', 'DEF']];
  const pc = v => Math.round(v * 100);
  function leaderEff(id) {
    const c = card(id), L = D.leader; if (!c || !L) return null;
    const el = L.el[c.class] || {}, cl = L.cls[c.attribute] || {}, e = {};
    for (const k of ['atk', 'def', 'hp', 'eAtk', 'eDef']) { const v = Math.round(((el[k] || 0) + (cl[k] || 0)) * 1000) / 1000; if (v) e[k] = v; }
    const own = LS_KEYS.filter(([k]) => e[k]).map(([k, l]) => `${l} +${pc(e[k])}%`), foe = LS_FOE.filter(([k]) => e[k]).map(([k, l]) => `${l} −${pc(e[k])}%`);
    const text = [own.length ? `아군 전체 ${own.join(' · ')}` : '', foe.length ? `적 전체 ${foe.join(' · ')}` : ''].filter(Boolean).join(' / ');
    const short = [...own, ...LS_FOE.filter(([k]) => e[k]).map(([k, l]) => `적${l} −${pc(e[k])}%`)].join(' ');
    return { ...e, name: c.name, label: `${el.name || c.class}·${cl.name || c.attribute}`, text, short, deathPenalty: L.deathPenalty ?? 0.3 };
  }
  const leaderUnlocked = () => chapterDone(D.chapters[0]);   // 리더 변경: 챕터 1 클리어 후
  const canMerge = o => exOf(o) < maxEx(o) && materialsOf(o).length > 0;
  const idxOf = o => save.owned.indexOf(o);
  let openGroups = new Set();
  function groups() {
    const m = new Map();
    for (const o of save.owned) { if (!m.has(o.id)) m.set(o.id, []); m.get(o.id).push(norm(o)); }
    const deck = new Map(deckInstances().map(o => [o.id, o]));
    return [...m.entries()].map(([id, list]) => ({ id, rep: deck.get(id), list: list.sort((a, b) => (isLeader(b) - isLeader(a)) || (b === deck.get(id)) - (a === deck.get(id)) || b.level - a.level) }))
      .sort((a, b) => (isLeader(b.rep) - isLeader(a.rep)) || sortCmp(a, b));
  }
  // ----- 보유 카드 정렬: 등급순 · 레벨순 · 획득순 (기본 획득순 최신 먼저, 같은 버튼 다시 누르면 오름/내림 전환, localStorage 기억) -----
  const SORT_KEY = 'vr-story-card-sort', SORTS = { new: '획득순', grade: '등급순', level: '레벨순' }, GRADE_ORD = Object.keys(RAR);
  let cardSort = (() => { try { const v = JSON.parse(localStorage.getItem(SORT_KEY)); if (v && SORTS[v.k]) return { k: v.k, desc: v.desc !== false }; } catch {} return { k: 'new', desc: true }; })();
  const setSort = k => { cardSort = cardSort.k === k ? { k, desc: !cardSort.desc } : { k, desc: true }; try { localStorage.setItem(SORT_KEY, JSON.stringify(cardSort)); } catch {} };
  /** 그룹 정렬 키: 획득 = 그 카드의 가장 최근 장(보유 목록 순서), 등급 = 등급 순위, 레벨 = 대표 장 레벨. 동점은 등급 → 레벨 → 최신 순 */
  function sortCmp(a, b) {
    const nw = g => Math.max(...g.list.map(idxOf)), gr = g => GRADE_ORD.indexOf(card(g.id)?.grade || 'NORMAL'), lv = g => g.rep?.level || 0;
    const key = { new: [nw], grade: [gr, lv, nw], level: [lv, gr, nw] }[cardSort.k];
    for (const f of key) { const d = f(a) - f(b); if (d) return cardSort.desc ? -d : d; }
    return 0;
  }
  /** 인스턴스 목록 정렬 (모든 카드 목록 창 공용): 리더 → pin(현재 덱 등) → 고른 정렬 */
  function sortInst(list, pin = null) {
    const nw = o => idxOf(o), gr = o => GRADE_ORD.indexOf(card(o.id)?.grade || 'NORMAL'), lv = o => o.level | 0;
    const key = { new: [nw], grade: [gr, lv, nw], level: [lv, gr, nw] }[cardSort.k];
    return list.slice().sort((a, b) => (isLeader(b) - isLeader(a)) || (pin ? (pin.has(b.uid) - pin.has(a.uid)) : 0) || (() => { for (const f of key) { const d = f(a) - f(b); if (d) return cardSort.desc ? -d : d; } return 0; })());
  }
  /** 팝업 안 정렬 버튼: 누르면 팝업을 다시 그림 */
  const bindSort = (p, again) => p.el.querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { setSort(b.dataset.sort); p.close(true); again(); });
  const sortBar = () => `<div class="story-sortbar">${Object.entries(SORTS).map(([k, l]) => `<button class="story-chip ${cardSort.k === k ? 'on' : ''}" data-sort="${k}" aria-pressed="${cardSort.k === k}">${l}${cardSort.k === k ? (cardSort.desc ? ' ▼' : ' ▲') : ''}</button>`).join('')}</div>`;
  /** 내 카드 썸네일: 별(등급) + 이름 + 현재 레벨만 */
  const ownTile = (o, c, badges = '', after = '') => `<div class="story-card story-own-tile ${rcls(c)}"><div class="story-card-img"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'">${window.rarityStars?.(c, exOf(o) ? 'ex' : 'base', 'rstars-over rstars-sm') || ''}${isLeader(o) ? `<span class="story-own-leader" title="리더">${ic('crown', { alt: '리더' })}</span>` : ''}${o.cpts ? `<div class="story-cpts">+${o.cpts}</div>` : ''}${badges}</div><div class="story-card-name">${esc(exName(o, c.name.replace(/^\[EX\d+\] /, '')))}</div><div class="story-own-lv">Lv.${o.level}</div>${after}</div>`;
  function renderCards() {
    const k = D.statPerPoint; save.owned.forEach(norm);
    const anyPts = save.points || cptsTotal(), gs = groups();
    show(`${topBar('🃏 보유 카드', 'hub')}<div class="text-center text-sm text-zinc-400 my-2">스토리 모드 전용 · ${gs.length}종 ${save.owned.length}장 · 공용 포인트 ${save.points}${cptsTotal() ? ` · 카드 전용 ${cptsTotal()}` : ''}</div>
      <div class="text-center text-[11px] text-zinc-500 -mt-1 mb-2">카드를 누르면 상세 · 분해 · 합성 ${save.owned.length > 1 ? '<button class="story-mini story-mini-red ml-1" data-go="bulk">' + ic('discard', { alt: '' }) + ' 일괄 분해</button>' : ''}</div>
      ${(() => { const lo = byUid(save.leader), le = lo && leaderEff(lo.id); return le ? `<div class="story-leader-bar"><div class="min-w-0">${ic('crown', { alt: '' })} 리더 <b>${esc(exName(lo, card(lo.id)?.name))}</b> <small>${esc(le.label)}</small><div class="text-[11px] text-amber-100/80">${esc(le.text)}</div></div><button class="story-mini" data-go="leader" ${leaderUnlocked() ? '' : 'disabled title="챕터 1 클리어 후"'}>${leaderUnlocked() ? '리더 변경' : '🔒 챕터 1 클리어 후 변경'}</button></div>` : ''; })()}
      ${gs.length > 1 ? sortBar() : ''}<div class="story-grid">${gs.map(gr => { const o = gr.rep, c = boosted(o); if (!c) return ''; const b = o.boost || {}, n = gr.list.length, open = openGroups.has(gr.id);
        const up = STATS.filter(s => b[s]).map(s => `${s} +${ptGain(s, b[s])}`).join(' · ');
        const mergeable = gr.list.some(canMerge);
        return `<div class="story-group ${open ? 'open' : ''}"><div data-uid="${o.uid}" class="story-owned">${ownTile(o, c, `${n > 1 ? `<div class="story-dup">x${n}</div>` : ''}${gr.list.some(x => x.locked && !isLeader(x)) ? '<div class="story-lockbadge" title="분해 잠금">🔒</div>' : ''}`, `${mergeable ? `<button class="story-merge-mini" data-merge="${(gr.list.find(canMerge)).uid}">${ic('merge', { alt: '' })} 합성</button>` : ''}${n > 1 ? `<button class="story-expand" data-expand="${gr.id}">${open ? '▴ 접기' : `▾ ${n}장 모두 보기`}</button>` : ''}`)}</div>
          ${open ? `<div class="story-copies">${gr.list.map(x => `<button class="story-copy" data-uid="${x.uid}"><span class="font-bold">${isLeader(x) ? ic('crown', { alt: '리더' }) + ' ' : x === o ? '⚔️ ' : ''}${x.locked && !isLeader(x) ? '🔒 ' : ''}Lv.${x.level}${exOf(x) ? ` <i class="text-red-300 not-italic">EX${exOf(x)}</i>` : ''}</span><span class="text-[10px] text-zinc-400">${ic('atk', { cls: 'ui-ic-sm' })}${fmt(statCalc(x, 'ATK'))} ${ic('hp', { cls: 'ui-ic-sm' })}${fmt(statCalc(x, 'HP'))} ${ic('def', { cls: 'ui-ic-sm' })}${fmt(statCalc(x, 'DEF'))}</span></button>`).join('')}</div>` : ''}</div>`; }).join('')}</div>
      ${anyPts ? '<div class="text-center mt-4"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button></div>' : ''}`);
    bind({ stats: () => openStats(renderCards), bulk: () => bulkDiscard(), leader: () => pickLeader() });
    root().querySelectorAll('[data-uid]').forEach(el => el.onclick = () => cardDetail(el.dataset.uid));
    root().querySelectorAll('[data-merge]').forEach(b => b.onclick = e => { e.stopPropagation(); mergePreview(b.dataset.merge); });
    root().querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { setSort(b.dataset.sort); renderCards(); });
    root().querySelectorAll('[data-expand]').forEach(b => b.onclick = e => { e.stopPropagation(); const g = b.dataset.expand; openGroups.has(g) ? openGroups.delete(g) : openGroups.add(g); renderCards(); });
  }
  // ----- 카드 레벨업 (단계 E-4, 서버 story_card_levelup): L → L+1 = 순수한 피 b×L, 골드 g×L×10 -----
  const LV_B = { 'NORMAL': 2, 'RARE': 3, 'HIGH RARE': 5, 'SUPER RARE': 8, 'ULTRA RARE': 12, 'MYTHIC RARE': 18 };
  const LV_G = { 'NORMAL': 1, 'RARE': 1.5, 'HIGH RARE': 2, 'SUPER RARE': 3, 'ULTRA RARE': 4, 'MYTHIC RARE': 6 };
  const SHARD_BASE = { 'NORMAL': 1, 'RARE': 2, 'HIGH RARE': 4, 'SUPER RARE': 8, 'ULTRA RARE': 15, 'MYTHIC RARE': 30 };
  /** o 를 n 단계 올리는 비용 (최대 레벨까지만) */
  function lvUpCost(o, n, w) {
    const g = card(o.id)?.grade || 'NORMAL', cap = lvCap(o); let lv = o.level | 0 || 1, k = 0, gold = 0, blood = 0;
    while (k < n && lv < cap) { const b = Math.ceil(LV_B[g] * lv), gg = Math.ceil(LV_G[g] * lv * 10);
      if (w && k > 0 && (gold + gg > (w.gold | 0) || blood + b > (w.blood | 0))) break;
      blood += b; gold += gg; lv++; k++; }
    return { n: k, to: lv, gold, blood };
  }
  const shardCost = o => (SHARD_BASE[card(o.id)?.grade] || 1) * (exOf(o) + 1);
  const W = () => window.VRPlayer?.walletNow || null;
  const afford = (c, w = W()) => !w || ((w.gold | 0) >= (c.gold | 0) && (w.blood | 0) >= (c.blood | 0) && (w.shard | 0) >= (c.shard | 0));
  const costTxt = c => `${c.gold ? `🪙 ${fmt(c.gold)}` : ''}${c.blood ? ` · 🩸 ${fmt(c.blood)}` : ''}${c.shard ? `💠 ${fmt(c.shard)}` : ''}`;
  function lvUpBox(o) {
    if (!serverMode) return '';
    const cap = lvCap(o); if ((o.level | 0) >= cap) return `<div class="story-lvup-box max">최대 레벨 Lv.${cap}${exOf(o) < maxEx(o) ? ' · 합성(EX)하면 최대 레벨 +5' : ''}</div>`;
    const w = W(), one = lvUpCost(o, 1), ten = lvUpCost(o, 10, w);
    const btn = (c, id, label) => `<button id="${id}" class="story-lvup-btn ${afford(c) ? '' : 'short'}" ${afford(c) ? '' : 'disabled'}><b>${label}</b><small>${costTxt(c)}</small></button>`;
    return `<div class="story-lvup-box"><div class="story-lvup-h">⬆ 레벨업 <small>골드 + 순수한 피 · 전투 EXP 로도 올라요</small></div>
      <div class="flex gap-2">${btn(one, 'story-d-lv1', `Lv.${o.level} → ${one.to}`)}${ten.n > 1 ? btn(ten, 'story-d-lv10', `${ten.n < 10 && ten.to < lvCap(o) ? '최대 ' : ''}+${ten.n} (→ Lv.${ten.to})`) : ''}</div>
      <div class="story-lvup-have">${w ? `보유 🪙 ${fmt(w.gold)} · 🩸 ${fmt(w.blood)}` : '보유 재화 불러오는 중…'}</div></div>`;
  }
  async function doLevelUp(o, n) {
    const c = lvUpCost(o, n, n > 1 ? W() : null); if (!c.n) return;
    const res = await act('story_card_levelup', { p_uid: o.uid, p_levels: n > 1 ? Math.min(n, lvCap(o) - (o.level | 0)) : 1 }, () => null, r => r.data);
    if (!res.ok) { if (/not enough/.test(res.error?.message || '')) toast(`재화가 부족해요 (필요 ${costTxt(c).replace(/<[^>]+>/g, '')})`); window.VRPlayer?.wallet(true); return cardDetail(o.uid); }
    const r = res.r || {}; window.VRPlayer?.setWallet(r.wallet);
    cardDetail(o.uid); levelUpFx(`LEVEL UP! Lv.${r.from} → Lv.${r.level}`);
    toast(`⬆ ${card(o.id)?.name} Lv.${r.level} · 🪙 −${fmt(r.gold)} · 🩸 −${fmt(r.blood)}`);
  }
  function cardDetail(u) {
    const o = byUid(u); if (!o) return renderCards(); norm(o);
    const c = boosted(o), cap = lvCap(o), n = copiesOf(o.id).length, rep = repOf(o.id) === o;
    const p = popup(`<div class="flex gap-3"><div class="relative shrink-0 self-start"><img src="${IMG}${c.id}.webp" class="w-24 aspect-[3/4] object-cover rounded-lg" alt="">${window.rarityStars?.(c, exOf(o) ? 'ex' : 'base', 'rstars-over') || ''}</div><div class="flex-1 min-w-0">
        <div class="text-lg font-black truncate">${isLeader(o) ? ic('crown', { alt: '리더' }) + ' ' : ''}${esc(c.name)} <span class="text-xs text-zinc-400">${RAR[c.grade] || 'N'}</span></div>
        ${lvBar(o)}<div class="text-[11px] text-zinc-400 mt-1">최대 Lv.${cap} · 누적 EXP ${fmt(o.totalExp)}${n > 1 ? ` · 같은 카드 ${n}장 중 1장${rep ? ' (⚔️ 전투 출전)' : ''}` : ''}</div>
        <div class="text-xs mt-2"><span class="story-lvpct">Lv.${o.level} +${lvPct(o)}%</span> <span class="text-zinc-500">기본 스탯에 레벨 보너스</span></div>
        ${exOf(o) ? `<div class="text-xs mt-1"><span class="story-expct">EX${exOf(o)} +${exbOf(o)}%</span> <span class="text-zinc-500">합성 보너스 (기본 스탯) · ${exOf(o)}/${maxEx(o)}</span></div>` : ''}
        <div class="story-statrows">${STATS.map(s => { const base = card(o.id)[s], exB = Math.round(base * (1 + exbOf(o) / 100)) - base, lvB = Math.round(base * (1 + exbOf(o) / 100) * (1 + lvPct(o) / 100)) - base - exB, pt = ptGain(s, o.boost?.[s]);
          return `<div><span>${STAT_LABEL[s]}</span><b>${fmt(c[s])}</b><small>기본 ${fmt(base)}${exB ? ` <i class="text-red-300">+${fmt(exB)} EX</i>` : ''}${lvB ? ` <i class="text-amber-300">+${fmt(lvB)} 레벨</i>` : ''}${pt ? ` <i class="text-emerald-300">+${fmt(pt)} 포인트</i>` : ''}</small></div>`; }).join('')}</div>
        ${o.cpts ? `<div class="text-xs mt-1">남은 카드 전용 포인트 <b class="text-sky-300">${o.cpts}</b></div>` : ''}</div></div>
      ${n > 1 ? '<div class="story-hint">💡 전투에는 같은 카드 중 1장만 나가요 (리더 · 없으면 레벨이 가장 높은 장). 남는 장은 합성 재료로 쓸 수 있어요.</div>' : ''}
      <div id="story-d-lvwrap">${lvUpBox(o)}</div>
      ${canMerge(o) ? `<button id="story-d-merge" class="story-merge-btn">${ic('merge', { alt: '' })} 합성 (EX${exOf(o)} → EX${exOf(o) + 1})${serverMode ? ` <small>💠 ${shardCost(o)}</small>` : ''}</button>` : exOf(o) >= maxEx(o) ? `<div class="text-[11px] text-red-300 mt-2 text-center">최대 합성 단계 (EX${maxEx(o)})</div>` : ''}
      <div class="flex gap-2 mt-4"><button id="story-d-stats" class="flex-1 py-2.5 rounded-xl bg-emerald-500 text-black font-bold" ${save.points || o.cpts ? '' : 'disabled'}>📈 스탯 분배</button>
      <button id="story-d-discard" class="flex-1 py-2.5 rounded-xl bg-red-500/80 font-bold" ${canDiscard(o) ? '' : 'disabled'}>${ic('discard', { alt: '' })} 분해</button></div>
      ${(() => { const le = leaderEff(o.id); return le ? `<div class="story-leader-eff ${isLeader(o) ? 'on' : ''}">${ic('crown', { alt: '' })} <b>리더 스킬</b> <small>${esc(le.label)}</small><div>${esc(le.text)}</div>${isLeader(o) ? '' : '<small class="text-zinc-500">이 카드를 리더로 하면 적용돼요</small>'}</div>` : ''; })()}
      <div class="flex gap-2 mt-2"><button id="story-d-lock" class="flex-1 py-2 rounded-xl bg-zinc-700 font-bold text-sm" ${isLeader(o) ? 'disabled' : ''}>${isLeader(o) ? '🔒 리더 자동 잠금' : o.locked ? '🔓 잠금 해제' : '🔒 분해 잠금'}</button>
      ${isLeader(o) ? '' : `<button id="story-d-leader" class="flex-1 py-2 rounded-xl bg-amber-500/90 text-black font-bold text-sm" ${leaderUnlocked() ? '' : 'disabled'}>${ic('crown', { alt: '' })} ${leaderUnlocked() ? '리더로 지정' : '리더 변경: 챕터 1 클리어 후'}</button>`}</div>
      ${isLocked(o) ? `<div class="text-[11px] text-zinc-500 mt-2 text-center">${isLeader(o) ? '리더 카드는 자동으로 잠겨 분해·합성 재료로 쓸 수 없어요' : '잠긴 카드는 분해·합성 재료로 쓸 수 없어요'}</div>` : ''}
      ${skillsOf(o.id).length ? `<div class="story-detail-skills"><div class="text-sm font-black mt-4">보유 기술 ${skillsOf(o.id).length}개</div>${window.TCG?.skillListHTML?.(c, o.level) || ''}</div>` : ''}`, renderCards);
    $('story-d-lock').onclick = () => { p.close(true); setLock(o.uid, !o.locked); };
    { const lb = $('story-d-leader'); if (lb) lb.onclick = () => { p.close(true); confirmLeader(o.uid, () => cardDetail(o.uid)); }; }
    $('story-d-stats').onclick = () => { p.close(true); openStats(renderCards, idxOf(o)); };
    $('story-d-discard').onclick = () => { p.close(true); pickTarget(o.uid); };
    const mb = $('story-d-merge'); if (mb) mb.onclick = () => { p.close(true); mergePreview(o.uid); };
    const bindLv = () => { const b1 = $('story-d-lv1'), b10 = $('story-d-lv10');
      if (b1) b1.onclick = () => { b1.disabled = true; doLevelUp(o, 1); };
      if (b10) b10.onclick = () => { b10.disabled = true; doLevelUp(o, 10); }; };
    bindLv();
    if (serverMode && window.VRPlayer) window.VRPlayer.wallet().then(() => { const el = $('story-d-lvwrap'); if (el && p.el.isConnected) { el.innerHTML = lvUpBox(o); bindLv(); } });
  }
  // ----- EX 합성: 대상 + 같은 카드의 다른 장(재료) → EX +1, 기본 스탯 보너스, 레벨 1로 초기화 (서버 story_merge) -----
  function mergePreview(tu, mu) {
    const o = byUid(tu); if (!o) return renderCards(); norm(o);
    if (serverMode && window.VRPlayer && !W()) { window.VRPlayer.wallet().then(() => mergePreview(tu, mu)); return; }
    const mats = materialsOf(o); if (!mats.length) return cardDetail(tu);
    const mat = mats.find(x => x.uid === mu) || mats[0], c = card(o.id), m = mergeCalc(o, mat), after = { ...o, ex: m.ex, exb: m.exb, level: 1, exp: 0 };
    const p = popup(`<div class="text-lg font-black mb-1">${ic('merge', { alt: '' })} 합성 미리보기</div>
      <div class="flex gap-3 items-center"><div class="relative shrink-0"><img src="${IMG}${c.id}.webp" class="w-20 aspect-[3/4] object-cover rounded-lg" alt="">${window.rarityStars?.(c, 'ex', 'rstars-over') || ''}</div>
        <div class="flex-1 min-w-0 text-sm"><div class="font-black">${esc(exName(o, c.name))} → <span class="text-red-300">${esc(exName(after, c.name))}</span></div>
        <div class="mt-1">합성 보너스 <b class="text-red-300">+${m.bonus}%</b> <span class="text-xs text-zinc-400">(누적 ${exbOf(o)}% → ${m.exb}%)</span></div></div></div>
      <div class="text-xs font-bold mt-3 mb-1 text-left">재료로 쓸 카드 (사라져요)</div>
      <div class="story-mat-list">${mats.map(x => `<button class="story-mat ${x === mat ? 'on' : ''}" data-mat="${x.uid}">Lv.${x.level}${exOf(x) ? ` · EX${exOf(x)}` : ''}<small>${Math.round(Math.min(1, x.level / lvCap(x)) * 100)}%</small></button>`).join('')}</div>
      <div class="story-merge-calc">10% × 대상 Lv.${o.level}/${m.cap} (<b>${Math.round(m.ratio * 100)}%</b>) × 재료 Lv.${mat.level}/${m.mcap} (<b>${Math.round(m.mratio * 100)}%</b>) = <b class="text-red-300">+${m.bonus}%</b></div>
      <div class="story-statrows mt-2">${STATS.map(s => `<div><span>${STAT_LABEL[s]}</span><b>${fmt(statCalc(o, s))}</b><small>→ <b class="text-white">${fmt(statCalc(after, s))}</b> (Lv.1 기준)</small></div>`).join('')}</div>
      <div class="text-xs mt-2">레벨 Lv.${o.level} → <b class="text-amber-300">Lv.1</b> · 최대 레벨 Lv.${m.cap} → <b class="text-emerald-300">Lv.${m.capTo}</b></div>
      ${m.ratio < 1 || m.mratio < 1 ? `<div class="story-hint">💡 대상과 재료 둘 다 최대 레벨이면 +10%예요. 레벨을 올린 뒤 합성하면 보너스가 커져요.</div>` : ''}
      ${mat.cpts || Object.values(mat.boost || {}).some(Boolean) ? '<div class="text-[11px] text-zinc-400 mt-1">재료 카드에 분배한 스탯 포인트는 함께 사라져요.</div>' : ''}
      <div class="story-warn">⚠️ 합성하면 대상 카드 레벨이 1로 초기화돼요. (EXP 0)</div>
      ${serverMode ? (() => { const sc = shardCost(o), w = W(), ok = !w || (w.shard | 0) >= sc; return `<div class="story-merge-cost ${ok ? '' : 'short'}">💠 이상한 조각 <b>${sc}</b> 필요 <small>(${SHARD_BASE[c.grade] || 1} × EX${exOf(o) + 1})</small>${w ? ` · 보유 ${fmt(w.shard)}` : ''}${ok ? '' : ' · <b>부족해요</b>'}</div>`; })() : ''}
      <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="merge-next" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold" ${serverMode && W() && (W().shard | 0) < shardCost(o) ? 'disabled' : ''}>합성하기</button></div>`, renderCards);
    p.el.querySelectorAll('[data-mat]').forEach(b => b.onclick = () => { p.close(true); mergePreview(tu, b.dataset.mat); });
    $('merge-next').onclick = () => { p.close(true); mergeConfirm(o.uid, mat.uid, m); };
  }
  function mergeConfirm(tu, mu, m) {
    const o = byUid(tu), mat = byUid(mu), c = card(o.id);
    const p = popup(`<div class="text-lg font-black mb-2">정말 합성할까요?</div>
      <div class="text-sm"><b>${esc(exName(o, c.name))}</b> Lv.${o.level} 이 <b class="text-red-300">${esc(exName({ ex: m.ex }, c.name))}</b> <b class="text-amber-300">Lv.1</b> 이 돼요. (+${m.bonus}%)</div>
      <div class="text-xs text-zinc-400 mt-1">재료: ${esc(c.name)} Lv.${mat.level} 1장${serverMode ? ` + 💠 이상한 조각 ${shardCost(o)}` : ''}</div>
      <div class="story-warn">⚠️ 레벨이 1로 초기화되고 재료 카드가 사라져요. 되돌릴 수 없어요.</div>
      <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="merge-yes" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold">합성</button></div>`, renderCards);
    $('merge-yes').onclick = async () => {
      $('merge-yes').disabled = true;
      const res = await act('story_merge', { p_target: tu, p_material: mu }, () => {
        if (!byUid(mu) || mu === tu || mat.id !== o.id || isLocked(mat) || exOf(o) >= maxEx(o)) return null;
        Object.assign(o, { ex: m.ex, exb: m.exb, level: 1, exp: 0 });
        save.owned.splice(idxOf(mat), 1);
        return { ex: m.ex, bonus: m.bonus, exb: m.exb };
      }, r => r.data);
      p.close(true);
      if (!res.ok && /not enough shard/.test(res.error?.message || '')) toast(`💠 이상한 조각이 부족해요 (필요 ${shardCost(o)})`);
      if (!res.ok || !res.r) return renderCards();
      window.VRPlayer?.setWallet(res.r.wallet);
      cardDetail(tu);
      levelUpFx(`EX${res.r.ex} 합성! +${res.r.bonus}%`);
    };
  }
  // ----- 분해 잠금 (서버 story_set_lock) -----
  async function setLock(u, on) {
    const o = byUid(u); if (!o || isLeader(o)) return cardDetail(u);
    const res = await act('story_set_lock', { p_uid: u, p_on: !!on }, () => { if (on) o.locked = true; else delete o.locked; return { locked: !!on }; }, r => r.data);
    if (res.ok) toast(on ? `🔒 ${card(o.id)?.name} 잠금 · 분해·합성 재료로 쓸 수 없어요` : `🔓 ${card(o.id)?.name} 잠금 해제`);
    renderCards(); if (byUid(u)) cardDetail(u);
  }
  // ----- 리더 변경 (챕터 1 클리어 후, 서버 story_set_leader). 시작 캐릭터(starter)·루트는 그대로 -----
  function pickLeader() {
    if (!leaderUnlocked()) return toast('리더 변경은 챕터 1을 클리어하면 열려요.');
    save.owned.forEach(norm);
    const list = sortInst(groups().map(gr => gr.list[0]).filter(Boolean));
    const p = popup(`<div class="text-lg font-black mb-1">${ic('crown', { alt: '' })} 리더 변경</div>${sortBar()}
      <div class="text-xs text-zinc-400 mb-2">리더 스킬(속성 + 클래스)은 리더가 출전해 필드에 있는 동안 아군 전체에 적용돼요. 리더가 쓰러지면 해제되고 아군 진영 HP −${pc(D.leader?.deathPenalty ?? 0.3)}%.</div>
      <div class="story-target-list">${list.map(o => { const c = card(o.id), le = leaderEff(o.id);
        return `<button data-ld="${o.uid}" class="story-target ${isLeader(o) ? 'cur' : ''}" ${isLeader(o) ? 'disabled' : ''}><img src="${IMG}${o.id}.webp" alt=""><div class="flex-1 min-w-0 text-left"><div class="text-sm font-bold truncate">${isLeader(o) ? ic('crown', { alt: '리더' }) + ' ' : ''}${esc(exName(o, c?.name))} <span class="text-[10px] text-zinc-400">${RAR[c?.grade] || 'N'} · Lv.${o.level}</span></div><div class="text-[11px] text-amber-200">${esc(le?.label || '')} · ${esc(le?.text || '')}</div></div><span class="text-emerald-300 text-sm">${isLeader(o) ? '현재' : '선택 ›'}</span></button>`; }).join('')}</div>
      <button data-close-pop class="w-full mt-3 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button>`, renderCards);
    p.el.querySelectorAll('[data-ld]').forEach(b => b.onclick = () => { p.close(true); confirmLeader(b.dataset.ld, pickLeader); });
    bindSort(p, pickLeader);
  }
  function confirmLeader(u, back) {
    const o = byUid(u), c = card(o?.id), le = leaderEff(o?.id); if (!o || isLeader(o) || isGuest(o)) return renderCards();
    const p = popup(`<div class="text-lg font-black mb-2">${esc(exName(o, c?.name))}을(를) 리더로 할까요?</div>
      <div class="story-leader-eff on">${ic('crown', { alt: '' })} <b>리더 스킬</b> <small>${esc(le?.label || '')}</small><div>${esc(le?.text || '')}</div></div>
      <div class="text-[11px] text-zinc-400 mt-2">리더는 자동으로 분해 잠금돼요. 시작 캐릭터와 챕터 루트는 바뀌지 않아요. 언제든 다시 바꿀 수 있어요.</div>
      <div class="flex gap-2 mt-4"><button id="ld-no" class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="ld-yes" class="flex-1 py-2.5 rounded-xl bg-amber-500 text-black font-bold">리더로 지정</button></div>`, renderCards);
    $('ld-no').onclick = () => { p.close(true); back ? back() : renderCards(); };
    $('ld-yes').onclick = async () => {
      $('ld-yes').disabled = true;
      const res = await act('story_set_leader', { p_uid: u }, () => { if (!leaderUnlocked() || !byUid(u)) return null; save.leader = u; return { leader: u }; }, r => r.data);
      p.close(true); renderCards();
      if (res.ok && save.leader === u) toast(`👑 리더 변경: ${c?.name} · ${le?.text || ''}`);
    };
  }
  // ----- 분해 (단계 E-3): 카드를 재화로 바꿈 (서버 story_dismantle, 전부 성공 또는 전부 취소). EXP 는 주지 않음 -----
  // 등급별 수익 (서버 _dismantle_yield 와 같음) + 누적 EXP 50% 를 순수한 피로 (EXP 10 = 피 1). 공용 포인트로 올린 강화는 환급
  const DIS_YIELD = { 'NORMAL': [20, 10, 0], 'RARE': [50, 30, 1], 'HIGH RARE': [120, 80, 3], 'SUPER RARE': [300, 200, 10], 'ULTRA RARE': [800, 500, 30], 'MYTHIC RARE': [2000, 1200, 80] };
  function disCalc(o) {
    const y = DIS_YIELD[card(o.id)?.grade] || DIS_YIELD.NORMAL;
    const refund = Math.max(0, Object.values(o.boost || {}).reduce((x, v) => x + (+v || 0), 0) - (o.spentCard | 0));
    return { gold: y[0], blood: y[1] + Math.floor((o.totalExp | 0) * 0.5 / 10) + Math.floor((o.bloodSpent | 0) * 0.5), soul: y[2], refund };
  }
  function bulkCalc(sel) {
    const f = { n: 0, gold: 0, blood: 0, soul: 0, refund: 0, ids: [] };
    for (const o of save.owned) { if (!sel.has(o.uid)) continue; const d = disCalc(o); f.gold += d.gold; f.blood += d.blood; f.soul += d.soul; f.refund += d.refund; f.n++; f.ids.push(o.uid); }
    return f;
  }
  const curTxt = c => window.VRPlayer?.curTxt?.(c) || `🪙 +${fmt(c.gold | 0)} · 🩸 +${fmt(c.blood | 0)}${c.soul ? ` · 🔥 +${fmt(c.soul)}` : ''}`;
  const disLocked = o => isLeader(o) || isLocked(o);
  async function doDismantle(ids, n, back) {
    const res = await act('story_dismantle', { p_uids: ids }, () => {
      const f = bulkCalc(new Set(ids)); save.owned = save.owned.filter(o => !ids.includes(o.uid)); save.points += f.refund;
      return { count: f.n, gold: 0, blood: 0, soul: 0, refund: f.refund, local: true };
    }, r => r.data);
    back();
    if (!res.ok) return;
    const r = res.r || {};
    if (res.local) { toast(`🗑️ ${n}장 분해 (재화는 서버 저장에서만 받아요)`); return; }
    showDisResult(r);
  }
  function showDisResult(r) {
    const p = popup(`<div class="text-center"><div class="text-lg font-black">🗑️ ${r.count | 0}장 분해 완료</div>
      <div class="story-drops mt-3">${curTxt(r)}</div>
      ${r.refund ? `<div class="text-xs text-emerald-300 mt-2">공용 포인트 ${r.refund} 돌려받음</div>` : ''}
      ${r.wallet ? `<div class="text-[11px] text-zinc-400 mt-2">보유: 🪙 ${fmt(r.wallet.gold)} · 🩸 ${fmt(r.wallet.blood)} · 🔥 ${fmt(r.wallet.soul)}</div>` : ''}
      <button data-close-pop class="w-full mt-4 py-2.5 rounded-xl bg-zinc-700 font-bold">확인</button></div>`, renderCards);
    try { window.TCG?.playSe?.(5); } catch {}
    return p;
  }
  function bulkDiscard(st = {}) {
    save.owned.forEach(norm);
    const sel = st.sel || new Set();
    for (const k of [...sel]) { const o = byUid(k); if (!o || disLocked(o)) sel.delete(k); }
    const f = bulkCalc(sel);
    const list = sortInst(save.owned);
    const grades = Object.keys(RAR).filter(gr => save.owned.some(o => !disLocked(o) && card(o.id)?.grade === gr));
    const spare = o => !disLocked(o) && copiesOf(o.id).length > 1 && repOf(o.id) !== o;
    const p = popup(`<div class="text-lg font-black mb-1">${ic('discard', { alt: '' })} 일괄 분해</div>
      <div class="text-xs text-zinc-400 mb-1">고른 카드를 모두 분해하고 <b class="text-amber-200">재화</b>(골드 · 순수한 피 · 각성자의 혼)를 받아요</div>
      <div class="flex flex-wrap gap-1.5 my-2"><button class="story-chip" data-q="all">전체 선택</button>${save.owned.some(spare) ? '<button class="story-chip" data-q="spare">출전 안 하는 중복만</button>' : ''}${grades.map(gr => `<button class="story-chip" data-q="${gr}">${RAR[gr]} 전체</button>`).join('')}<button class="story-chip" data-q="none">선택 해제</button></div>
      ${sortBar()}<div class="story-bulk-list" id="bulk-list">${list.map(o => { const c = card(o.id), lk = disLocked(o), on = sel.has(o.uid), d = disCalc(o);
        return `<div class="story-bulk-row ${lk ? 'lock' : ''} ${on ? 'on' : ''}" ${lk ? '' : `data-row="${o.uid}"`}><input type="checkbox" ${on ? 'checked' : ''} ${lk ? 'disabled' : ''}><img src="${IMG}${o.id}.webp" alt=""><div class="flex-1 min-w-0"><div class="text-sm font-bold truncate">${esc(exName(o, c?.name))} <span class="text-[10px] text-zinc-400">${RAR[c?.grade] || 'N'} · Lv.${o.level}</span></div><div class="text-[10px] text-zinc-500">${lk ? (isLeader(o) ? '리더 · 분해 불가' : '🔒 잠금 · 분해 불가') : `${repOf(o.id) === o ? '⚔️ 출전 카드 · ' : ''}${curTxt(d)}`}</div></div></div>`; }).join('')}</div>
      <div class="story-bulk-sum">${f.n ? `<b>${f.n}장</b> 선택 · <span class="story-drops">${curTxt(f)}</span>${f.refund ? `<br><span class="text-emerald-300 text-[11px]">공용 포인트 ${f.refund} 돌려받음</span>` : ''}` : '<span class="text-zinc-500">분해할 카드를 골라 주세요</span>'}</div>
      ${f.n && save.owned.some(o => sel.has(o.uid) && canMergeAny(o)) ? '<div class="story-hint">💡 같은 카드가 여러 장이면 분해 대신 합성(EX)에 쓸 수도 있어요.</div>' : ''}
      <div class="flex gap-2 mt-3"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="bulk-ok" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold" ${f.n ? '' : 'disabled'}>${f.n ? `${f.n}장 분해` : '분해할 카드를 골라 주세요'}</button></div>`, renderCards);
    const box = $('bulk-list'); box.scrollTop = st.scroll || 0;
    const re = () => bulkDiscard({ sel, scroll: box.scrollTop });
    p.el.querySelectorAll('[data-q]').forEach(b => b.onclick = () => { const q = b.dataset.q;
      if (q === 'none') sel.clear(); else for (const o of save.owned) if (!disLocked(o) && (q === 'all' || (q === 'spare' ? spare(o) : card(o.id)?.grade === q))) sel.add(o.uid);
      re(); });
    p.el.querySelectorAll('[data-row]').forEach(r => r.onclick = () => { const k = r.dataset.row; sel.has(k) ? sel.delete(k) : sel.add(k); re(); });
    $('bulk-ok').onclick = () => { if (f.n) { p.close(true); confirmBulk(sel, f, box.scrollTop); } };
    bindSort(p, () => bulkDiscard({ sel, scroll: 0 }));
  }
  const canMergeAny = o => copiesOf(o.id).length > 1 && exOf(o) < maxEx(o);
  function confirmBulk(sel, f, scroll) {
    const names = save.owned.filter(o => sel.has(o.uid)).map(o => `${esc(exName(o, card(o.id)?.name))} Lv.${o.level}`);
    const p = popup(`<div class="text-lg font-black mb-2">정말 분해할까요?</div>
      <div class="text-sm"><b>${f.n}장</b>을 분해하고 받아요: <span class="story-drops">${curTxt(f)}</span></div>
      <div class="text-[11px] text-zinc-400 mt-1 max-h-24 overflow-y-auto">${names.join(', ')}</div>
      ${f.refund ? `<div class="text-xs text-emerald-300 mt-1">공용 포인트 ${f.refund} 돌려받음</div>` : ''}
      <div class="text-[11px] text-red-300 mt-2">분해한 카드는 되돌릴 수 없어요.</div>
      <div class="flex gap-2 mt-4"><button id="bulk-no" class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="bulk-yes" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold">${f.n}장 분해</button></div>`, renderCards);
    $('bulk-no').onclick = () => { p.close(true); bulkDiscard({ sel, scroll }); };
    $('bulk-yes').onclick = async () => { $('bulk-yes').disabled = true; p.close(true); await doDismantle(f.ids, f.n, renderCards); };
  }
  // ----- 1장 분해 (대상 카드 없음) -----
  function pickTarget(su) { confirmDiscard(su); }
  function confirmDiscard(su) {
    const src = byUid(su), sc = card(src.id), d = disCalc(src);
    if (disLocked(src)) { toast(isLeader(src) ? '리더 카드는 분해할 수 없어요.' : '🔒 잠긴 카드는 분해할 수 없어요.'); return; }
    const p = popup(`<div class="text-lg font-black mb-2">정말 분해할까요?</div>
      <div class="text-sm"><b>${esc(exName(src, sc?.name))}</b> Lv.${src.level} 분해 → <span class="story-drops">${curTxt(d)}</span></div>
      ${d.refund ? `<div class="text-xs text-emerald-300 mt-1">이 카드에 쓴 공용 포인트 ${d.refund}은 돌려받아요.</div>` : ''}
      ${canMergeAny(src) ? '<div class="story-hint">💡 같은 카드가 여러 장이면 합성(EX) 재료로 쓸 수도 있어요.</div>' : ''}
      ${src.cpts || src.spentCard ? '<div class="text-[11px] text-zinc-400 mt-1">카드 전용 포인트와 그걸로 올린 스탯은 함께 사라져요.</div>' : ''}
      <div class="text-[11px] text-red-300 mt-2">분해한 카드는 되돌릴 수 없어요.</div>
      <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-disc-ok" class="flex-1 py-2.5 rounded-xl bg-red-500 font-bold">분해</button></div>`, renderCards);
    $('story-disc-ok').onclick = async () => { $('story-disc-ok').disabled = true; p.close(true); await doDismantle([su], 1, renderCards); };
  }

  // ----- 일일 카드 뽑기 (하루 1회, KST 자정 초기화) -----
  const KST = 9 * 3600e3;
  const kstDay = (t = Date.now()) => new Date(t + KST).toISOString().slice(0, 10);
  const msToReset = () => { const t = Date.now() + KST; return 86400e3 - (t % 86400e3); };
  const canDraw = () => !!save && save.gachaLast !== kstDay();
  const hms = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return [s / 3600 | 0, (s / 60 | 0) % 60, s % 60].map(n => String(n).padStart(2, '0')).join(':'); };
  const GLOW = { 'NORMAL': 'n', 'RARE': 'r', 'HIGH RARE': 'hr', 'SUPER RARE': 'sr', 'ULTRA RARE': 'ur' };
  function addOwned(id, n = 1) {
    for (let k = 0; k < n; k++) save.owned.push(newCard(id));   // 뽑을 때마다 새 카드 1장
    return copiesOf(id).length;
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
    if (serverMode && !res.local && !window.__GACHA_MOCK) { await reload(); res.count = copiesOf(res.card_id).length || res.count || 1; return res; }
    res.count = addOwned(res.card_id);
    save.gachaLast = day;
    await persist();
    return res;
  }
  // ----- 소환권 (특수 뽑기): 챕터 첫 클리어마다 +10. 서버 모드는 서버(story_tickets / story_ticket_draw)가 기준 -----
  const G = () => D.gacha;
  let tickets = null, ticketSrv = null;   // ticketSrv: 서버 함수 사용 여부 (null = 아직 모름)
  const ticketMissing = e => /story_ticket|PGRST202|42883|Could not find/i.test(`${e?.code} ${e?.message}`);
  function localTicketSync() {   // 브라우저 저장 모드: 다 깬 챕터마다 한 번 +10
    const got = new Set(save.ticketChs || []); let added = 0;
    for (const c of D.chapters) if (chapterDone(c) && !got.has(c.id)) { got.add(c.id); added += G().ticketsPerChapter; }
    if (added) { save.tickets = (save.tickets | 0) + added; save.ticketChs = [...got]; persist(); }
    return { tickets: save.tickets | 0, added };
  }
  /** 소환권 개수 갱신 (+ 새로 받은 양). 반환 { tickets, added } */
  async function syncTickets() {
    const sb = cloud()?.sb, u = cloud()?.user;
    if (window.__TICKET_MOCK) { const r = await window.__TICKET_MOCK.sync(); tickets = r.tickets; return r; }
    if (serverMode && sb && u && ticketSrv !== false) {
      const { data, error } = await sb.rpc('story_tickets');
      if (!error) { ticketSrv = true; tickets = data.tickets | 0; return data; }
      if (!ticketMissing(error)) return { tickets: tickets | 0, added: 0, error: error.message };
      ticketSrv = false;
    }
    const r = localTicketSync(); tickets = r.tickets; return r;
  }
  /** 특수 뽑기 n회 (1 또는 10). 반환 { ok, cards:[{card_id, grade}], tickets } */
  async function drawTickets(n) {
    const sb = cloud()?.sb, u = cloud()?.user;
    let res = null;
    if (window.__TICKET_MOCK) res = await window.__TICKET_MOCK.draw(n);
    else if (serverMode && sb && u && ticketSrv !== false) {
      const { data, error } = await sb.rpc('story_ticket_draw', { p_count: n });
      if (!error) res = data; else if (!ticketMissing(error)) return { ok: false, reason: 'error', msg: error.message }; else ticketSrv = false;
    }
    if (res) {
      if (res.ok) { tickets = res.tickets | 0; if (!window.__TICKET_MOCK) await reload(); else for (const c of res.cards) addOwned(c.card_id); }
      return res;
    }
    // 브라우저 저장 모드 (서버 함수 없음)
    localTicketSync();
    if ((save.tickets | 0) < n) return { ok: false, reason: 'tickets', tickets: save.tickets | 0 };
    const cards = []; let hr = false;
    for (let i = 0; i < n; i++) {
      let r = Math.random(); if (n === 10 && i === 9 && !hr) r = 0.8 + Math.random() * 0.2;   // 10회 HR 이상 보장
      const g = window.rollGachaRarity(r, G().special); if (!['NORMAL', 'RARE'].includes(g)) hr = true;
      const c = rand(pool().filter(x => x.grade === g)); addOwned(c.id); cards.push({ card_id: String(c.id), grade: g });
    }
    save.tickets -= n; tickets = save.tickets; await persist();
    return { ok: true, cards, tickets, local: true };
  }
  const ticketBadge = n => `<span class="story-ticket" title="소환권">🎟️ <b>${n ?? '…'}</b></span>`;
  const pct = p => `${+(p * 100).toFixed(1)}%`;
  function showRates() {
    const row = (t, rs, note) => `<div class="mb-3"><div class="font-bold mb-1">${t}</div><div class="story-rates">${rs.map(([g, p]) => `<span class="g-text-${GLOW[g]}">${RAR[g]}</span><b>${pct(p)}</b>`).join('')}</div>${note ? `<div class="text-[11px] text-zinc-400 mt-1">${note}</div>` : ''}</div>`;
    popup(`<div class="text-lg font-black mb-3">📊 뽑기 확률</div>${row('일반 뽑기 (하루 1회 무료)', G().rates, '매일 자정(KST, 한국 시간 00:00) 초기화')}${row('특수 뽑기 (소환권 1장 = 1회)', G().special, `10회 뽑기는 HR 이상 1장 보장 · 소환권은 챕터를 처음 다 깰 때마다 +${G().ticketsPerChapter}`)}<button data-close-pop class="w-full mt-1 py-2 rounded-xl bg-white/10">닫기</button>`);
  }

  let gachaTimer = 0, shopTab = 'daily';
  // ----- 상점 (카드 뽑기) 화면: 일반 뽑기(하루 1회 무료) · 특수 뽑기(소환권) -----
  function renderShop(tab) {
    if (tab) shopTab = tab;
    clearInterval(gachaTimer);
    const avail = canDraw(), daily = shopTab === 'daily';
    show(`${topBar('🎴 카드 뽑기', 'hub')}<div class="story-shop story-pop-panel">
      <div class="story-shop-tabs"><button class="${daily ? 'on' : ''}" data-tab="daily">일반 뽑기${avail ? '<i class="story-badge">1</i>' : ''}</button><button class="${daily ? '' : 'on'}" data-tab="special">특수 뽑기 ${ticketBadge(tickets)}</button></div>
      ${daily ? `<div class="text-lg font-black">🎴 오늘의 카드 뽑기</div><div class="text-[11px] text-zinc-400 mt-1">하루 1회 무료 · 매일 자정(KST) 초기화</div>
      <div class="gacha-stage"><div class="gacha-card" id="gacha-card"><div class="gacha-face gacha-back">🎴</div><div class="gacha-face gacha-front" id="gacha-front"></div></div></div>
      <div id="gacha-msg" class="text-sm min-h-[1.5rem]"></div>
      ${avail ? '<button id="gacha-go" class="story-btn w-full mt-2">뽑기!</button>' : ''}
      <div id="gacha-next" class="text-xs text-zinc-400 mt-2"></div>`
      : `<div class="text-lg font-black">✨ 특수 뽑기</div><div class="text-[11px] text-zinc-400 mt-1">소환권 1장 = 1회 · 10회는 HR 이상 1장 보장<br>소환권은 챕터를 처음 다 깰 때마다 +${G().ticketsPerChapter}</div>
      <div class="my-3 text-base">보유 ${ticketBadge(tickets)}</div>
      <div id="tk-result" class="story-tk-result"></div><div id="gacha-msg" class="text-sm min-h-[1.5rem]"></div>
      <div class="flex gap-2"><button class="story-btn flex-1" data-draw="1" ${(tickets | 0) >= 1 ? '' : 'disabled'}>1회 <small>🎟️1</small></button><button class="story-btn flex-1" data-draw="10" ${(tickets | 0) >= 10 ? '' : 'disabled'}>10회 <small>🎟️10</small></button></div>`}
      <button id="gacha-rates" class="w-full mt-2 py-2 rounded-xl bg-white/10 text-sm">📊 확률 보기</button>
      <button data-go="cards" class="w-full mt-2 py-2 rounded-xl bg-white/10">🃏 내 카드 보기</button></div>`);
    bind();
    root().querySelectorAll('[data-tab]').forEach(b => b.onclick = () => renderShop(b.dataset.tab));
    $('gacha-rates').onclick = showRates;
    if (tickets == null) syncTickets().then(r => { if (root().querySelector('.story-shop')) { if (r.added) toast(`🎟️ 소환권 +${r.added} (챕터 클리어 보상)`); renderShop(); } });
    if (!daily) {
      root().querySelectorAll('[data-draw]').forEach(b => b.onclick = async () => {
        root().querySelectorAll('[data-draw]').forEach(x => x.disabled = true); $('gacha-msg').textContent = '뽑는 중...';
        const r = await drawTickets(+b.dataset.draw);
        if (!r.ok) { $('gacha-msg').textContent = r.reason === 'tickets' ? '소환권이 부족해요.' : `뽑기에 실패했어요: ${r.msg || ''}`; return; }
        const best = r.cards.reduce((a, c) => Math.max(a, Object.keys(GLOW).indexOf(c.grade)), 0);
        root().querySelectorAll('.story-ticket b').forEach(x => x.textContent = tickets);
        $('tk-result').innerHTML = r.cards.map((x, i) => { const c = card(x.card_id); return `<div class="story-tk-card g-${GLOW[x.grade]}" style="animation-delay:${i * 0.08}s"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}"><span class="story-rar">${RAR[x.grade]}</span><div>${esc(c.name)}</div></div>`; }).join('');
        $('tk-result').className = `story-tk-result n${r.cards.length}`;
        $('gacha-msg').innerHTML = `${r.cards.length}장 획득! <span class="g-text-${Object.values(GLOW)[best]}">최고 ${RAR[Object.keys(GLOW)[best]]}</span><div class="text-[11px] text-zinc-400">보유 카드에 추가됐어요</div>`;
        root().querySelectorAll('[data-draw]').forEach(x => x.disabled = (tickets | 0) < +x.dataset.draw);
      });
      return;
    }
    const tick = () => { const n = $('gacha-next'); if (!n) return clearInterval(gachaTimer); n.textContent = canDraw() ? '' : `다음 무료 뽑기까지 ${hms(msToReset())} (한국 시간 자정)`; };
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
      root().querySelectorAll('.story-gacha-btn .story-badge, [data-tab="daily"] .story-badge').forEach(x => x.remove());
      setTimeout(() => { $('gacha-msg').innerHTML = `<b class="g-text-${g}">${RAR[c.grade]} · ${esc(c.name)}</b> 획득!${r.count > 1 ? ` <span class="story-dup-inline">x${r.count}</span>` : ''}<div class="text-[11px] text-zinc-400">보유 카드에 추가됐어요</div>`; tick(); }, 1300);
    };
  }

  function mountButton() {
    const start = $('start-btn'); if (!start || $('story-btn')) return;
    const b = document.createElement('button'); b.id = 'story-btn'; b.type = 'button'; b.className = 'main-banner banner-story';
    b.innerHTML = '<img src="img/ui/main/banner_story.webp" srcset="img/ui/main/banner_story_600.webp 600w, img/ui/main/banner_story.webp 1200w" sizes="(max-width: 520px) 92vw, 460px" alt="" class="main-banner-img" width="1200" height="360" decoding="async"><span class="main-banner-text"><b class="main-banner-title">스토리 모드</b><small>캐릭터별 챕터 · 카드 수집</small></span>';
    b.disabled = !window.TCG?.ready; b.onclick = enter; start.after(b);
    window.addEventListener('tcg:ready', () => { b.disabled = false; });
  }
  mountButton();
  const openGacha = renderShop;
  /** 마이페이지용 요약 (화면 없이 데이터만). 반환 { ok, serverMode, owned:[{uid,id,name,grade,level,ex,power,locked,leader}], leaderUid, deckUids, tickets, chapters:[{id,title,done,total}] } */
  async function summary() {
    if (!user()) return { ok: false, reason: 'login' };
    await load(); if (!save) return { ok: false, reason: 'load' };
    let tk = null; try { const r = await syncTickets(); tk = r?.tickets ?? tickets; } catch {}
    const inst = deckInstances(), byUid = new Map(save.owned.map(o => [o.uid, o]));
    let deck = []; try { deck = JSON.parse(localStorage.getItem(PICK_KEY()) || '[]').filter(u => byUid.has(u)); } catch {}
    if (!deck.length) deck = inst.slice().sort((a, b) => (b.uid === save.leader) - (a.uid === save.leader) || (boosted(b)?.power || 0) - (boosted(a)?.power || 0)).slice(0, MAX_PICK()).map(o => o.uid);
    const view = o => { const b = boosted(o) || {}; return { uid: o.uid, id: o.id, name: b.name || card(o.id)?.name || o.id, grade: b.grade || card(o.id)?.grade, level: o.level | 0, ex: o.ex | 0, power: b.power || 0, locked: !!o.locked, leader: o.uid === save.leader }; };
    return {
      ok: true, serverMode, leaderUid: save.leader || null, deckUids: deck, tickets: tk,
      owned: save.owned.map(view), uniq: inst.length,
      chapters: D.chapters.map(ch => ({ id: ch.id, title: ch.title, done: (save.cleared?.[ch.id] || []).filter(no => ch.phases.some(p => p.no === no)).length, total: ch.phases.length })),
    };
  }
  /** 다른 모드(퀘스트)용 내부 도구 */
  const api = {
    load: async () => { if (!user()) return false; await load(); return !!save; }, get save() { return save; }, user, show, home, popup, toast, bgm, tile, esc, IMG, card,
    pickDeck: (enemies, onGo, onCancel, note) => pickDeck({}, {}, enemies, { onGo, onCancel, note }),
    battleCards: list => list.slice(0, MAX_PICK()).map(o => ({ ...boosted(o), uid: o.uid })).filter(x => x.id),
    leaderFor: me => { const lo = me.find(c => c.uid === save.leader), le = lo && leaderEff(lo.id); return le ? { ...le, uid: lo.uid } : undefined; },
    ownedCount: () => deckInstances().length, syncTickets,
  };
  window.VRStory = { api, summary, enter, openGacha, renderHub, renderShop, drawOnce, kstDay, get save() { return save; }, renderMap, renderCards, openStats, renderSelect };
})();
