// ===== 퀘스트 모드: 시련의 탑 =====
// 스토리 보유 카드 5장으로 층마다 적 5장(data/quest.json + js/quest-gen.js, 층 번호 시드로 고정)과 싸움.
// 진영 없음: 적 카드를 모두 쓰러뜨리면 승리 · 내 카드 전멸 또는 40턴 초과면 패배. 재도전 무제한.
// 진행·보상은 서버(supabase/tower_v2.sql: tower_status / tower_start / tower_complete / tower_sweep_*, p_tower='normal'). 첫 클리어만 보상 (10층마다 소환권 5, 50층마다 10)
// 하루 30층(소탕 포함, KST 자정 초기화)·유저 레벨 5 이상. tower_v2 리셋 후 1층부터 첫 클리어 보상 다시
// 확장 훅: 층 rewards(골드 등), 층 enemies/boss 고정, stamina(도전 비용) — QUEST_HOOKS
(() => {
  const $ = id => document.getElementById(id);
  const A = () => window.VRStory?.api;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const SW = () => window.VRIcon?.icon('sweep', { alt: '소탕' }) || '⚡';
  const fmt = n => Number(n || 0).toLocaleString('ko-KR');
  /** 확장 훅: canChallenge(floor) → { ok, reason } (스태미나 등), onReward(reward) */
  const QUEST_HOOKS = { canChallenge: () => ({ ok: true }), onReward: () => {} };
  let cfg = null, status = null, sel = null;
  const genCache = new Map();

  const M = () => window.__QUEST_MOCK;
  // 탑 v2 (supabase/tower_v2.sql): tower_* RPC + p_tower. 서버에 아직 없으면 예전 quest_* 로 (legacy)
  let TOWER = 'normal', legacy = false, hub = null;   // hub = tower_status 전체 응답
  // 탑 6종 (허브). 속성 탑: 적 = 그 속성 카드·NPC (시드 탑+층, 중복 가능, Lv = 시련의 탑 공식 + 10), 내 출전도 그 속성만
  const TOWERS = [
    { id: 'normal', name: '시련의 탑', ready: true }, { id: 'wind', name: '바람의 계곡', cls: 'WIND', ready: true }, { id: 'ice', name: '얼음의 숲', cls: 'ICE', ready: true },
    { id: 'fire', name: '불의 절벽', cls: 'FIRE', ready: true }, { id: 'light', name: '빛의 섬', cls: 'LIGHT', ready: true }, { id: 'dark', name: '어둠의 늪', cls: 'DARK', ready: true }];
  const EL = { WIND: '🍃 바람', ICE: '❄️ 얼음', FIRE: '🔥 불', LIGHT: '☀️ 빛', DARK: '🌑 어둠' };
  const tCls = () => TOWERS.find(t => t.id === TOWER)?.cls || null;
  const DOW = ['', '월', '화', '수', '목', '금', '토', '일'];
  const tName = () => TOWERS.find(t => t.id === TOWER)?.name || '시련의 탑';
  const NEW = { quest_status: 'tower_status', quest_start: 'tower_start', quest_complete: 'tower_complete', quest_sweep_start: 'tower_sweep_start', quest_sweep_complete: 'tower_sweep_complete', quest_sweep_info: 'tower_sweep_info' };
  async function trpc(name, args = {}) {
    if (M()?.rpc && !M().tower) legacy = true;   // 예전 목업(quest_* 만 응답)
    if (!legacy) {
      try { const d = await rpc(NEW[name], name === 'quest_status' ? {} : { p_tower: TOWER, ...args }); if (name === 'quest_status') { hub = d; return { ...(d?.towers?.[TOWER] || {}), level: d?.level }; } return d; }
      catch (e) { if (!/tower_|function|schema cache/.test(String(e?.message || ''))) throw e; legacy = true; }
    }
    return rpc(name, Object.keys(args).length ? args : undefined);
  }
  const ERR = m => /bag full/.test(m) ? '🎒 장비 가방이 꽉 찼어요. 가방을 정리하거나 칸을 늘린 뒤 도전해 주세요' : /daily limit/.test(m) ? `오늘 도전 가능한 층을 다 썼어요 (하루 ${status?.daily ?? 30}층, 한국 시간 자정에 초기화)` : /level too low/.test(m) ? `유저 레벨 ${status?.min_level ?? 5} 이상부터 도전할 수 있어요` : /closed today/.test(m) ? '오늘은 열리지 않는 탑이에요' : null;
  async function rpc(name, args) {
    if (M()?.rpc) return M().rpc(name, args);
    const sb = window.VRCloud?.sb; if (!sb) throw new Error('서버에 연결할 수 없어요');
    const { data, error } = await sb.rpc(name, args); if (error) throw error; return data;
  }
  async function loadCfg() { if (!cfg) cfg = await (await fetch('data/quest.json')).json(); return cfg; }
  const floorOf = n => cfg.floors[n - 1];
  function enemiesOf(n) {
    const key = TOWER + ':' + n; if (genCache.has(key)) return genCache.get(key);
    const cls = tCls(), G = window.VRQuestGen;
    const g = cls ? G.generateAttr(cfg, floorOf(n), window.TCG?.POOL || [], { tower: TOWER, cls, npc: window.TCG?.NPC || [], levelOffset: 10 })
                  : G.generate(cfg, floorOf(n), window.TCG?.POOL || [], window.TCG?.combos?.() || []);
    genCache.set(key, g); return g;
  }
  const rewardOf = n => { const r = window.VRQuestGen.rewardOf(cfg, floorOf(n)); return tCls() ? null : r; };   // 속성 탑: 소환권 없음 (골드·피·조각은 서버 재화)
  const rewardTxt = r => r ? [r.tickets ? `🎟️ 소환권 ${r.tickets}` : '', r.gold ? `🪙 골드 ${fmt(r.gold)}` : ''].filter(Boolean).join(' · ') : '';
  const best = () => status?.best_floor | 0;
  const maxF = () => Math.min(cfg.floors.length, status?.max_floor || cfg.floors.length);
  const unlocked = n => n <= Math.min(best() + 1, maxF());

  async function open() {
    const api = A();
    if (!api || !window.TCG?.ready) return;
    if (!api.user()) {
      const p = api.popup(`<div class="text-xl font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">퀘스트 모드는 로그인한 플레이어만 할 수 있어요.<br>스토리 모드에서 모은 인재로 한 층씩 올라가요.</div>
        <button id="quest-login" class="w-full py-3 rounded-xl bg-amber-400 text-black font-bold">구글로 로그인</button><button data-close-pop class="w-full mt-2 py-2 rounded-xl bg-zinc-700">닫기</button>`);
      $('quest-login').onclick = () => { p.close(true); window.VRCloud?.login?.(); };
      return;
    }
    await api.load(); await loadCfg();
    if (!api.ownedCount()) { api.popup(`<div class="text-lg font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">보유 인재가 없어요. 스토리 모드에서 먼저 인재를 골라 주세요.</div><button data-close-pop class="w-full py-2 rounded-xl bg-zinc-700">닫기</button>`); return; }
    try { status = await trpc('quest_status'); }
    catch (e) { status = null; api.popup(`<div class="text-lg font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">${/quest_status|function/.test(e?.message || '') ? '퀘스트 서버가 아직 준비 중이에요.' : '진행 상황을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'}</div><button data-close-pop class="w-full py-2 rounded-xl bg-zinc-700">닫기</button>`); return; }
    if (legacy || !hub?.towers) { TOWER = 'normal'; sel = Math.min(best() + 1, maxF()); return render(); }
    renderHub();
  }
  /** 잠김 이유: 준비중 · 유저 레벨 · 요일 (KST). 없으면 null */
  function lockOf(t) {
    const s = hub?.towers?.[t.id]; if (!s) return '준비중';
    const why = [];
    if (!s.unlocked) why.push(`Lv.${s.min_level} 필요`);
    if (!s.open_today) why.push(`${(s.days || []).map(d => DOW[d]).join('·')} 오픈`);
    if (!t.ready) why.unshift('준비중');
    return why.length ? why.join(' · ') : null;
  }
  function renderHub() {
    const api = A();
    const cards = TOWERS.map(t => { const s = hub?.towers?.[t.id] || {}, lock = lockOf(t), full = !lock && (s.today | 0) >= (s.daily | 0);
      return `<button class="th-card ${lock ? 'locked' : ''} ${full ? 'full' : ''}" data-tower="${t.id}" style="background-image:url('img/tower/${t.id}.webp')">
        <div class="th-shade"></div>
        ${lock ? `<div class="th-lock"><span>🔒</span>${lock.split(' · ').map((x, i) => i ? `<small>${esc(x)}</small>` : `<b>${esc(x)}</b>`).join('')}</div>` : ''}
        <div class="th-info"><div class="th-name">${esc(t.name)}</div>
          <div class="th-meta"><span title="최고 층">🏔 ${s.best_floor | 0}층</span><span title="오늘 이긴 층 / 하루 제한">⏳ ${s.today | 0}/${s.daily | 0}</span></div></div></button>`; }).join('');
    api.show(`<div class="story-top"><button class="story-back" id="q-home">← 처음으로</button><div class="story-top-title">🗼 탑</div><span class="th-lv">Lv.${hub?.level | 0}</span></div>
      <div class="th-grid">${cards}</div><div class="th-foot">하루 제한·요일은 한국 시간 자정 기준</div>`, 'tower');
    $('q-home').onclick = () => api.home();
    document.querySelectorAll('.th-card').forEach(b => b.onclick = () => enterTower(b.dataset.tower));
  }
  async function enterTower(id) {
    const api = A(), t = TOWERS.find(x => x.id === id), lock = t && lockOf(t);
    if (!t) return;
    if (lock) { api.toast(/준비중/.test(lock) ? `${t.name}은(는) 준비 중이에요` : `${t.name}: ${lock}${/Lv\./.test(lock) ? ` (지금 Lv.${hub?.level | 0})` : ''}${/오픈/.test(lock) ? ' (한국 시간)' : ''}`); return; }
    TOWER = id; genCache.clear();
    status = { ...(hub.towers[id] || {}), level: hub.level };
    sel = Math.min(best() + 1, maxF()); render();
  }
  async function backToHub() { try { status = await trpc('quest_status'); } catch {} renderHub(); }

  function enemyTile(c, lead) {
    return `<div class="q-enemy rar-${SHORT[c.grade]}" title="${esc(c.name)}"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'">
      <span class="q-rar">${SHORT[c.grade]}</span>${lead ? '<span class="q-lead">👑</span>' : ''}<span class="q-lv">Lv.${c.qLevel}</span>
      <div class="q-en-cap"><b>${esc(c.name)}</b><small>⚡ ${fmt(c.power)}</small></div></div>`;
  }
  function render() {
    const api = A(), n = sel, f = floorOf(n), g = enemiesOf(n), rw = rewardOf(n), cleared = n <= best(), open_ = unlocked(n);
    const rows = cfg.floors.slice(0, maxF()).map(x => {
      const k = x.floor, r = rewardOf(k), st = k <= best() ? 'done' : unlocked(k) ? 'next' : 'lock';
      return `<button class="q-row ${st} ${k === n ? 'on' : ''}" data-floor="${k}" ${st === 'lock' ? 'disabled' : ''}><span class="q-no">${k}층</span>${tCls() ? `<span class="q-g">${k % 10 === 0 ? '👑' : ''}</span><span class="q-pw">Lv.${window.VRQuestGen.levelOf(cfg, k, 10)}</span>` : `<span class="q-g rar-${SHORT[x.grade]}">${SHORT[x.grade]}</span><span class="q-pw">⚡ ${fmt(x.power)}</span>`}${!tCls() && x.bond ? '<span class="q-bond" title="인연 조합">🤝</span>' : ''}${r ? `<span class="q-rw ${st === 'done' ? 'got' : ''}">${r.tickets ? `🎟️${r.tickets}` : ''}${r.gold ? `🪙` : ''}</span>` : '<span class="q-rw"></span>'}<span class="q-st">${st === 'done' ? '✔' : st === 'next' ? '▶' : '🔒'}</span></button>`;
    }).reverse().join('');
    api.show(`<div class="story-top"><button class="story-back" id="q-home">${hub?.towers && !legacy ? '← 탑 목록' : '← 처음으로'}</button><div class="story-top-title">🗼 ${esc(tName())}</div><span></span></div>
      <div class="q-head"><div>최고 <b>${best()}</b>층 / ${maxF()}층${status?.daily ? ` · 오늘 ${status.today | 0}/${status.daily}` : ''}</div><div class="q-sub" title="적 인재를 모두 쓰러뜨리면 승리 · 내 인재 전멸 또는 ${cfg.maxTurns || 40}턴 초과 시 패배 · 재도전 무제한">적 전멸 = 승리 · ${cfg.maxTurns || 40}턴</div></div>
      <div class="q-wrap"><div class="q-cur">
        <div class="q-cur-h"><b>${n}층</b>${n % 10 === 0 ? '<span title="보스 층">👑</span>' : ''}<span class="q-g rar-${SHORT[g.grade || f.grade]}">${SHORT[g.grade || f.grade]}</span><span>적 Lv.${g.level ?? g.leader?.qLevel} · 리더 ⚡ ${fmt(g.leader?.power)}</span></div>
        <div class="q-cur-sub">${tCls() ? `${EL[tCls()]} 속성 적 · 내 출전도 ${EL[tCls()]} 속성만` : `<span title="${f.others === 'weak' ? '나머지: 리더보다 약함 (60~80%)' : '나머지: 리더와 비슷 (90~100%)'}">${f.others === 'weak' ? '나머지 약함' : '나머지 비슷'}</span>${g.combo ? ` · 🤝 인연 「${esc(g.combo)}」` : ''}`}</div>
        <div class="q-enemies">${g.enemies.map((c, i) => enemyTile(c, i === 0)).join('')}</div>
        <div class="q-reward">${rw ? (cleared ? `<span class="got">✔ 첫 클리어 보상 받음 (${rewardTxt(rw)})</span>` : `🎁 첫 클리어 보상: <b>${rewardTxt(rw)}</b>`) : '<span class="muted" title="10층마다 보상">보상 없음</span>'}</div>
        <button class="story-btn q-go" id="q-go" ${open_ ? '' : 'disabled'}>${cleared ? '다시 도전' : '도전'} (${n}층)</button>
        ${sweepBtn()}
      </div>
      <div class="q-list" id="q-list">${rows}</div></div>`, 'tower');
    $('q-home').onclick = () => hub?.towers && !legacy ? backToHub() : api.home();
    $('q-go').onclick = () => challenge(n);
    const sw = $('q-sweep'); if (sw) sw.onclick = () => sweep();
    $('q-list').querySelectorAll('[data-floor]').forEach(b => b.onclick = () => { sel = +b.dataset.floor; render(); });
    const on = $('q-list').querySelector('.q-row.on'); if (on) on.scrollIntoView({ block: 'center' });
  }

  /** 속성 탑 출전 제한: 그 속성 카드만 */
  const party = () => tCls() ? { onlyClass: tCls() } : null;
  const myCls = () => { const api = A(), c = tCls(); return (api.instances?.() || []).filter(o => !c || api.card(o.id)?.class === c); };
  function deckOk() {
    const c = tCls(); if (!c) return true;
    const n = myCls().length;
    if (!n) { A().popup(`<div class="text-lg font-black mb-2">${EL[c]} 속성 인재가 없어요</div><div class="text-sm text-zinc-300 mb-4">${esc(tName())}에는 ${EL[c]} 속성 인재만 출전할 수 있어요.<br>뽑기·스토리로 ${EL[c]} 인재를 모아 주세요.</div><button data-close-pop class="w-full py-2 rounded-xl bg-zinc-700">닫기</button>`); return false; }
    if (n <= 5) A().toast(`${EL[c]} 속성 인재 ${n}명이 모두 출전해요 (${esc(tName())}은 ${EL[c]} 속성만)`);
    return true;
  }
  function challenge(n) {
    const api = A(), g = enemiesOf(n);
    if (!unlocked(n)) return;
    const can = QUEST_HOOKS.canChallenge(n); if (!can.ok) { api.toast(can.reason || '지금은 도전할 수 없어요'); return; }
    if (!deckOk()) return;
    api.pickDeck(g.enemies, list => battle(n, list), () => render(), `🗼 ${esc(tName())} ${n}층 · 적 5장 (리더 ⚡ ${fmt(g.leader?.power)})${tCls() ? `<br><b class="text-amber-300">${EL[tCls()]} 속성 인재만 출전할 수 있어요</b>` : ''}`, party());
  }
// AUTO·X2 로 빨리 끝나도 서버 최소 전투 시간(_quest_min_secs 5초)을 채운 뒤 기록 → 'too fast' 방지. 서버 검사는 그대로
  const MIN_BATTLE_MS = 5600; let startedAt = 0;
  async function battle(n, list) {
    const api = A(), g = enemiesOf(n);
    try { await trpc('quest_start', { p_floor: n }); }
    catch (e) { const m = String(e?.message || ''); api.toast(ERR(m) || (/locked/.test(m) ? '아직 열리지 않은 층이에요' : `⚠️ 시작 실패: ${m}`)); return render(); }
    startedAt = Date.now();
    $('story-screen').classList.add('hidden'); api.bgm(n % 10 === 0 ? 'boss' : 'tower');
    const me = api.battleCards(list);
    window.TCG.startStory({ me, ai: g.enemies.map(c => ({ ...c })), leader: api.leaderFor(me), win: 'wipe', aiName: `${n}층`, quest: true,
      onEnd: (win, reason, st) => result(n, win, reason, st) });
    api.toast(`🗼 ${n}층: 적 인재 5명을 모두 쓰러뜨리세요!`);
  }
  async function result(n, win, reason, st = {}) {
    const api = A();
    if (!win) {
      api.show(`<div class="text-center py-10"><div class="story-chapter-big text-red-400">DEFEAT</div><div class="text-zinc-300 mt-2">${n}층 · ${reason === 'giveup' ? '도전을 포기했어요.' : reason === 'timeout' ? `${cfg.maxTurns || 40}턴 안에 적을 모두 쓰러뜨리지 못했어요.` : '내 인재가 모두 쓰러졌어요.'}</div>
        <div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="q-retry">다시 도전</button><button class="story-back" id="q-back">탑으로</button></div></div>`, 'tower');
      $('q-retry').onclick = () => challenge(n); $('q-back').onclick = render; return;
    }
    { const wait = startedAt + MIN_BATTLE_MS - Date.now(); if (wait > 0) await new Promise(r => setTimeout(r, wait)); }
    let res;
    try { res = await trpc('quest_complete', { p_floor: n, p_stats: { turns: Math.max(1, Math.min(40, st.turns | 0 || 1)) } }); }
    catch (e) {
      const m = String(e?.message || ''), why = /too fast/.test(m) ? '전투가 너무 빨리 끝나서 기록이 인정되지 않았어요.' : ERR(m) ? ERR(m) : /battle not started/.test(m) ? '전투 시작 기록이 없어요. (다른 기기에서 전투를 시작했을 수 있어요)' : `기록 실패: ${m}`;
      api.show(`<div class="text-center py-10"><div class="story-chapter-big text-amber-300">!</div><div class="text-zinc-300 mt-2">${esc(why)}<br>다시 도전해 주세요.</div><div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="q-retry">다시 도전</button><button class="story-back" id="q-back">탑으로</button></div></div>`, 'tower');
      $('q-retry').onclick = () => challenge(n); $('q-back').onclick = render; return;
    }
    status = { ...status, best_floor: res.best_floor ?? Math.max(best(), n), today: res.today ?? status?.today };
    const rw = res.first ? res.reward : null, got = rw && (rw.tickets || rw.gold);
    if (got) { QUEST_HOOKS.onReward(rw); try { await api.syncTickets(); } catch {} }
    const next = n + 1 <= maxF() ? n + 1 : null;
    const bossSw = !!next && isBoss(n) && best() === n;   // 보스 층 클리어 직후: 바로 소탕 (기존 소탕과 같은 규칙·서버)
    api.show(`<div class="text-center py-6"><div class="story-chapter-sub">${n}층 CLEAR</div><div class="story-chapter-big text-emerald-300">VICTORY</div>
      ${res.first && res.currency ? `<div class="mt-4 story-drops">🎁 첫 클리어 ${window.VRPlayer?.curTxt?.(res.currency) || ''}</div>` : ''}${got ? `<div class="mt-2 text-amber-200 font-bold">🎁 첫 클리어 보상: ${rewardTxt(rw)}</div>` : `<div class="mt-4 text-zinc-400 text-sm">${res.first ? (res.currency ? '' : '이 층은 보상이 없어요. 10층마다 보상이 있어요.') : '이미 클리어한 층이라 보상은 없어요.'}</div>`}
      <div class="mt-2 text-sm text-zinc-300">최고 기록 ${best()}층${status?.daily ? ` · 오늘 ${status.today | 0}/${status.daily}층` : ''}</div>
      <div class="flex flex-col gap-2 max-w-xs mx-auto mt-5">${next ? `<div class="q-win-row"><button class="story-btn" id="q-next">다음 층 (${next}층)</button>${bossSw ? `<button class="story-btn q-sweep" id="q-win-sweep" title="내 덱으로 자동 전투 · 패배 또는 보스 층에서 멈춤">${SW()} 소탕하기</button>` : ''}</div>` : ''}<button class="story-back" id="q-back">탑으로</button></div></div>`, 'tower');
    if (next) $('q-next').onclick = () => { sel = next; challenge(next); };
    if (bossSw) $('q-win-sweep').onclick = () => { sel = next; sweep(); };
    $('q-back').onclick = () => { sel = next || n; render(); };
    window.VRGear?.showDrops?.();   // 장비 PR4: 층 드롭
  }

  // ----- 소탕: 다음 층부터 연속된 일반 층을 내 덱으로 자동 전투 (supabase/quest_sweep.sql). 보스 층(10의 배수)에서 멈춤. 행동력 없음 -----
  const SWEEP_SECS = 1.1;   // 서버 최소 1초/층 + 여유
  const isBoss = k => k % 10 === 0;
  function sweepBtn() {
    const f = best() + 1; if (f > maxF()) return '';
    if (isBoss(f)) return `<div class="q-sweep-note">👑 ${f}층 보스는 직접 도전</div>`;
    const left = status?.daily ? Math.max(0, status.daily - (status.today | 0)) : Infinity;
    if (!left) return `<div class="q-sweep-note">⏳ 오늘 도전 가능한 층을 다 썼어요 (${status.today | 0}/${status.daily})</div>`;
    const last = Math.min(Math.ceil(f / 10) * 10 - 1, maxF(), f - 1 + left);
    return `<button class="story-btn q-sweep" id="q-sweep" title="내 덱으로 자동 전투 · 패배 또는 보스 층에서 멈춤">${SW()} 소탕 ${f}~${last}층${Number.isFinite(left) ? ` <small>· 오늘 ${left}층 남음</small>` : ''}</button>`;
  }
  async function sweep() {
    if (!deckOk()) return;
    const api = A(), c = tCls(), deck = (api.lastDeck?.() || []).filter(o => !c || api.card(o.id)?.class === c);
    if (!deck.length) { api.toast('출전 인재를 먼저 골라 주세요'); return api.pickDeck([], list => runSweep(list), () => render(), `${SW()} 소탕에 쓸 덱${tCls() ? ` · ${EL[tCls()]} 속성만` : ''}`, party(), { noLend: true }); }
    runSweep(deck);
  }
  async function runSweep(list) {
    const api = A();
    let st; try { st = await trpc('quest_sweep_start'); }
    catch (e) { const m = String(e?.message || ''); api.toast(ERR(m) || (/boss floor/.test(m) ? '보스 층은 직접 도전해야 해요' : /function|quest_sweep/.test(m) ? '소탕 서버가 아직 준비 중이에요' : `⚠️ 소탕 실패: ${m}`)); return render(); }
    let sim; try { sim = window.__QUEST_SIM || await import(new URL('js/quest-sim.js', document.baseURI).href); } catch (e) { api.toast('⚠️ 전투 엔진을 불러오지 못했어요'); return render(); }
    const me = api.battleCards(list), lead = api.leaderFor(me), from = st.from, lastF = Math.min(st.last, maxF());
    const p = api.popup(`<div class="text-lg font-black text-center">${SW()} 소탕 중…</div><div class="q-sw-prog" id="q-sw-prog"></div><div class="text-xs text-zinc-400 text-center mt-2">내 덱: ${list.map(o => esc(api.card(o.id)?.name || '')).join(' · ')}</div>`);
    const prog = [], turns = []; let to = from - 1, stop = null; const t0 = Date.now();
    window.VR_SWEEPING = true;   // 소탕 중 스킬 컷인·보이스·MR 영상 끔 (game.js)
    try {
    for (let k = from; k <= lastF; k++) {
      const r = await sim.simBattle(me.map(c => ({ ...c })), enemiesOf(k).enemies.map(c => ({ ...c })), cfg.maxTurns || 40, lead);
      prog.push(`<div class="q-sw-row ${r.win ? 'win' : 'lose'}"><b>${k}층</b><span>${r.win ? `✔ 승리 · ${r.turns}턴` : r.timeout ? `✕ ${cfg.maxTurns || 40}턴 초과` : '✕ 패배'}</span></div>`);
      const el = $('q-sw-prog'); if (el) { el.innerHTML = prog.join(''); el.scrollTop = el.scrollHeight; }
      const wait = t0 + (k - from + 1) * SWEEP_SECS * 1000 - Date.now(); if (wait > 0) await new Promise(res => setTimeout(res, wait));
      if (!r.win) { stop = { floor: k, why: r.timeout ? 'timeout' : 'lose' }; break; }
      to = k; turns.push(Math.max(1, Math.min(40, r.turns)));
    }
    } finally { window.VR_SWEEPING = false; }
    if (!stop) stop = to >= maxF() ? { floor: to, why: 'top' } : isBoss(to + 1) ? { floor: to + 1, why: 'boss' } : { floor: to + 1, why: 'daily' };
    let res; try { res = await trpc('quest_sweep_complete', { p_to: to, p_stats: { turns } }); }
    catch (e) { p.close(true); api.toast(`⚠️ 소탕 기록 실패: ${e?.message || e}`); return render(); }
    p.close(true);
    status = { ...status, best_floor: res.best_floor ?? Math.max(best(), to), today: res.today ?? status?.today };
    const tot = res.total || {}, tk = tot.tickets | 0, cur = { ...tot }; delete cur.tickets;
    if (tk) { QUEST_HOOKS.onReward({ tickets: tk }); try { await api.syncTickets(); } catch {} }
    window.VRPlayer?.wallet?.(true);
    const why = stop.why === 'daily' ? `⏳ 오늘 도전 가능한 층(하루 ${status?.daily ?? 30}층)을 다 썼어요.` : stop.why === 'boss' ? `👑 ${stop.floor}층은 보스 층이에요. 직접 도전해 주세요.` : stop.why === 'top' ? '🏁 마지막 층까지 올라갔어요.' : stop.why === 'timeout' ? `✕ ${stop.floor}층에서 ${cfg.maxTurns || 40}턴 안에 이기지 못했어요.` : `✕ ${stop.floor}층에서 패배했어요.`;
    sel = Math.min(best() + 1, maxF()); render();
    const rp = api.popup(`<div class="text-lg font-black text-center">${SW()} 소탕 결과</div>
      <div class="text-center mt-2 text-2xl font-black ${res.cleared ? 'text-emerald-300' : 'text-zinc-300'}">${res.cleared ? `${from}~${to}층 · ${res.cleared}층 클리어` : '클리어한 층 없음'}</div>
      ${res.cleared ? `<div class="mt-3 story-drops">🎁 첫 클리어 보상 ${window.VRPlayer?.curTxt?.(cur) || ''}${tk ? ` · 🎟️ 소환권 ${tk}` : ''}</div>` : ''}
      <div class="q-sw-stop">${why}</div>
      <div class="q-sw-prog small">${prog.join('')}</div>
      <div class="flex gap-2 mt-4">${stop.why === 'boss' ? `<button class="story-btn flex-1" id="q-sw-boss">👑 ${stop.floor}층 도전</button>` : ''}<button class="story-back flex-1" data-close-pop>닫기</button></div>`);
    window.VRGear?.showDrops?.();   // 장비 PR4: 소탕 드롭
    const bb = $('q-sw-boss'); if (bb) bb.onclick = () => { rp.close(true); sel = stop.floor; challenge(stop.floor); };
  }

  function mount() {
    const s = $('story-btn'); if (!s || $('quest-btn')) return !!$('quest-btn');
    const b = document.createElement('button'); b.id = 'quest-btn'; b.type = 'button'; b.className = 'main-btn quest-btn';
    b.title = '시련의 탑 · 보유 인재로 한 층씩 도전'; b.innerHTML = `${window.VRIcon?.icon('tower', { alt: '' }) || '🗼'}<span>시련의 탑</span>`;
    b.disabled = !window.TCG?.ready; b.onclick = open; s.after(b);
    window.addEventListener('tcg:ready', () => { b.disabled = false; });
    return true;
  }
  // 메인 화면 탑 배너는 없앰: 시련의 탑은 스토리 허브 하단 메뉴에서 (메인은 4버튼)
  /** 마이페이지·관리자용 최고 층 */
  async function bestFloor() { try { const s = await trpc('quest_status'); return s?.best_floor | 0; } catch { return null; } }
  window.VRQuest = { open, render, challenge, bestFloor, sweep, HOOKS: QUEST_HOOKS, _test: { result, enemiesOf, rewardOf, loadCfg, get status() { return status; }, set status(v) { status = v; } } };
})();
