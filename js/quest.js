// ===== 퀘스트 모드: 시련의 탑 =====
// 스토리 보유 카드 5장으로 층마다 적 5장(data/quest.json + js/quest-gen.js, 층 번호 시드로 고정)과 싸움.
// 진영 없음: 적 카드를 모두 쓰러뜨리면 승리 · 내 카드 전멸 또는 40턴 초과면 패배. 재도전 무제한.
// 진행·보상은 서버(supabase/quest.sql: quest_status / quest_start / quest_complete). 첫 클리어만 보상 (10층마다 소환권 5, 50층마다 10)
// 확장 훅: 층 rewards(골드 등), 층 enemies/boss 고정, stamina(도전 비용) — QUEST_HOOKS
(() => {
  const $ = id => document.getElementById(id);
  const A = () => window.VRStory?.api;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const fmt = n => Number(n || 0).toLocaleString('ko-KR');
  /** 확장 훅: canChallenge(floor) → { ok, reason } (스태미나 등), onReward(reward) */
  const QUEST_HOOKS = { canChallenge: () => ({ ok: true }), onReward: () => {} };
  let cfg = null, status = null, sel = null;
  const genCache = new Map();

  const M = () => window.__QUEST_MOCK;
  async function rpc(name, args) {
    if (M()?.rpc) return M().rpc(name, args);
    const sb = window.VRCloud?.sb; if (!sb) throw new Error('서버에 연결할 수 없어요');
    const { data, error } = await sb.rpc(name, args); if (error) throw error; return data;
  }
  async function loadCfg() { if (!cfg) cfg = await (await fetch('data/quest.json')).json(); return cfg; }
  const floorOf = n => cfg.floors[n - 1];
  function enemiesOf(n) {
    if (genCache.has(n)) return genCache.get(n);
    const g = window.VRQuestGen.generate(cfg, floorOf(n), window.TCG?.POOL || [], window.TCG?.combos?.() || []);
    genCache.set(n, g); return g;
  }
  const rewardOf = n => window.VRQuestGen.rewardOf(cfg, floorOf(n));
  const rewardTxt = r => r ? [r.tickets ? `🎟️ 소환권 ${r.tickets}` : '', r.gold ? `🪙 골드 ${fmt(r.gold)}` : ''].filter(Boolean).join(' · ') : '';
  const best = () => status?.best_floor | 0;
  const maxF = () => Math.min(cfg.floors.length, status?.max_floor || cfg.floors.length);
  const unlocked = n => n <= Math.min(best() + 1, maxF());

  async function open() {
    const api = A();
    if (!api || !window.TCG?.ready) return;
    if (!api.user()) {
      const p = api.popup(`<div class="text-xl font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">퀘스트 모드는 로그인한 플레이어만 할 수 있어요.<br>스토리 모드에서 모은 카드로 한 층씩 올라가요.</div>
        <button id="quest-login" class="w-full py-3 rounded-xl bg-amber-400 text-black font-bold">구글로 로그인</button><button data-close-pop class="w-full mt-2 py-2 rounded-xl bg-zinc-700">닫기</button>`);
      $('quest-login').onclick = () => { p.close(true); window.VRCloud?.login?.(); };
      return;
    }
    await api.load(); await loadCfg();
    if (!api.ownedCount()) { api.popup(`<div class="text-lg font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">보유 카드가 없어요. 스토리 모드에서 먼저 카드를 골라 주세요.</div><button data-close-pop class="w-full py-2 rounded-xl bg-zinc-700">닫기</button>`); return; }
    try { status = await rpc('quest_status'); }
    catch (e) { status = null; api.popup(`<div class="text-lg font-black mb-2">🗼 시련의 탑</div><div class="text-sm text-zinc-300 mb-4">${/quest_status|function/.test(e?.message || '') ? '퀘스트 서버가 아직 준비 중이에요.' : '진행 상황을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'}</div><button data-close-pop class="w-full py-2 rounded-xl bg-zinc-700">닫기</button>`); return; }
    sel = Math.min(best() + 1, maxF());
    render();
  }

  function enemyTile(c, lead) {
    return `<div class="q-enemy rar-${SHORT[c.grade]}" title="${esc(c.name)}"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'">
      <span class="q-rar">${SHORT[c.grade]}</span>${lead ? '<span class="q-lead">👑</span>' : ''}<span class="q-lv">Lv.${c.qLevel}</span>
      <div class="q-en-cap"><b>${esc(c.name)}</b><small>⚡ ${fmt(c.power)}</small></div></div>`;
  }
  function render() {
    const api = A(), n = sel, f = floorOf(n), g = enemiesOf(n), rw = rewardOf(n), cleared = n <= best(), open_ = unlocked(n);
    const rows = cfg.floors.slice(0, maxF()).map(x => {
      const k = x.floor, r = rewardOf(k), st = k <= best() ? 'done' : unlocked(k) ? 'next' : 'lock';
      return `<button class="q-row ${st} ${k === n ? 'on' : ''}" data-floor="${k}" ${st === 'lock' ? 'disabled' : ''}><span class="q-no">${k}층</span><span class="q-g rar-${SHORT[x.grade]}">${SHORT[x.grade]}</span><span class="q-pw">⚡ ${fmt(x.power)}</span>${x.bond ? '<span class="q-bond" title="인연 조합">🤝</span>' : ''}${r ? `<span class="q-rw ${st === 'done' ? 'got' : ''}">${r.tickets ? `🎟️${r.tickets}` : ''}${r.gold ? `🪙` : ''}</span>` : '<span class="q-rw"></span>'}<span class="q-st">${st === 'done' ? '✔' : st === 'next' ? '▶' : '🔒'}</span></button>`;
    }).reverse().join('');
    api.show(`<div class="story-top"><button class="story-back" id="q-home">← 처음으로</button><div class="story-top-title">🗼 시련의 탑</div><span></span></div>
      <div class="q-head"><div>최고 <b>${best()}</b>층 / ${maxF()}층</div><div class="q-sub">적 카드를 모두 쓰러뜨리면 승리 · 내 카드 전멸 또는 ${cfg.maxTurns || 40}턴 초과 시 패배 · 재도전 무제한</div></div>
      <div class="q-wrap"><div class="q-cur">
        <div class="q-cur-h"><b>${n}층</b><span class="q-g rar-${SHORT[f.grade]}">${SHORT[f.grade]}</span><span>적 리더 ⚡ ${fmt(g.leader?.power)} <small>(목표 ${fmt(f.power)})</small></span></div>
        <div class="q-cur-sub">${f.others === 'weak' ? '나머지: 리더보다 약함 (60~80%)' : '나머지: 리더와 비슷 (90~100%)'}${g.combo ? ` · 🤝 인연 「${esc(g.combo)}」` : ''}</div>
        <div class="q-enemies">${g.enemies.map((c, i) => enemyTile(c, i === 0)).join('')}</div>
        <div class="q-reward">${rw ? (cleared ? `<span class="got">✔ 첫 클리어 보상 받음 (${rewardTxt(rw)})</span>` : `🎁 첫 클리어 보상: <b>${rewardTxt(rw)}</b>`) : '<span class="muted">이 층은 보상이 없어요 (10층마다 보상)</span>'}</div>
        <button class="story-btn q-go" id="q-go" ${open_ ? '' : 'disabled'}>${cleared ? '다시 도전' : '도전'} (${n}층)</button>
      </div>
      <div class="q-list" id="q-list">${rows}</div></div>`, 'story');
    $('q-home').onclick = () => api.home();
    $('q-go').onclick = () => challenge(n);
    $('q-list').querySelectorAll('[data-floor]').forEach(b => b.onclick = () => { sel = +b.dataset.floor; render(); });
    const on = $('q-list').querySelector('.q-row.on'); if (on) on.scrollIntoView({ block: 'center' });
  }

  function challenge(n) {
    const api = A(), g = enemiesOf(n);
    if (!unlocked(n)) return;
    const can = QUEST_HOOKS.canChallenge(n); if (!can.ok) { api.toast(can.reason || '지금은 도전할 수 없어요'); return; }
    api.pickDeck(g.enemies, list => battle(n, list), () => render(), `🗼 ${n}층 · 적 5장 (리더 ⚡ ${fmt(g.leader?.power)})`);
  }
  async function battle(n, list) {
    const api = A(), g = enemiesOf(n);
    try { await rpc('quest_start', { p_floor: n }); }
    catch (e) { api.toast(/locked/.test(e?.message) ? '아직 열리지 않은 층이에요' : `⚠️ 시작 실패: ${e?.message || e}`); return render(); }
    $('story-screen').classList.add('hidden'); api.bgm('battle');
    const me = api.battleCards(list);
    window.TCG.startStory({ me, ai: g.enemies.map(c => ({ ...c })), leader: api.leaderFor(me), win: 'wipe', aiName: `${n}층`,
      onEnd: (win, reason, st) => result(n, win, reason, st) });
    api.toast(`🗼 ${n}층: 적 카드 5장을 모두 쓰러뜨리세요!`);
  }
  async function result(n, win, reason, st = {}) {
    const api = A();
    if (!win) {
      api.show(`<div class="text-center py-10"><div class="story-chapter-big text-red-400">DEFEAT</div><div class="text-zinc-300 mt-2">${n}층 · ${reason === 'giveup' ? '도전을 포기했어요.' : reason === 'timeout' ? `${cfg.maxTurns || 40}턴 안에 적을 모두 쓰러뜨리지 못했어요.` : '내 카드가 모두 쓰러졌어요.'}</div>
        <div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="q-retry">다시 도전</button><button class="story-back" id="q-back">탑으로</button></div></div>`);
      $('q-retry').onclick = () => challenge(n); $('q-back').onclick = render; return;
    }
    let res;
    try { res = await rpc('quest_complete', { p_floor: n, p_stats: { turns: Math.max(1, Math.min(40, st.turns | 0 || 1)) } }); }
    catch (e) {
      const m = String(e?.message || ''), why = /too fast/.test(m) ? '전투가 너무 빨리 끝나서 기록이 인정되지 않았어요.' : /battle not started/.test(m) ? '전투 시작 기록이 없어요. (다른 기기에서 전투를 시작했을 수 있어요)' : `기록 실패: ${m}`;
      api.show(`<div class="text-center py-10"><div class="story-chapter-big text-amber-300">!</div><div class="text-zinc-300 mt-2">${esc(why)}<br>다시 도전해 주세요.</div><div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="q-retry">다시 도전</button><button class="story-back" id="q-back">탑으로</button></div></div>`);
      $('q-retry').onclick = () => challenge(n); $('q-back').onclick = render; return;
    }
    status = { ...status, best_floor: res.best_floor ?? Math.max(best(), n) };
    const rw = res.first ? res.reward : null, got = rw && (rw.tickets || rw.gold);
    if (got) { QUEST_HOOKS.onReward(rw); try { await api.syncTickets(); } catch {} }
    const next = n + 1 <= maxF() ? n + 1 : null;
    api.show(`<div class="text-center py-6"><div class="story-chapter-sub">${n}층 CLEAR</div><div class="story-chapter-big text-emerald-300">VICTORY</div>
      ${res.first && res.currency ? `<div class="mt-4 story-drops">🎁 첫 클리어 ${window.VRPlayer?.curTxt?.(res.currency) || ''}</div>` : ''}${got ? `<div class="mt-2 text-amber-200 font-bold">🎁 첫 클리어 보상: ${rewardTxt(rw)}</div>` : `<div class="mt-4 text-zinc-400 text-sm">${res.first ? (res.currency ? '' : '이 층은 보상이 없어요. 10층마다 보상이 있어요.') : '이미 클리어한 층이라 보상은 없어요.'}</div>`}
      <div class="mt-2 text-sm text-zinc-300">최고 기록 ${best()}층</div>
      <div class="flex flex-col gap-2 max-w-xs mx-auto mt-5">${next ? `<button class="story-btn" id="q-next">다음 층 (${next}층) 도전</button>` : ''}<button class="story-back" id="q-back">탑으로</button></div></div>`);
    if (next) $('q-next').onclick = () => { sel = next; challenge(next); };
    $('q-back').onclick = () => { sel = next || n; render(); };
  }

  function mount() {
    const s = $('story-btn'); if (!s || $('quest-btn')) return !!$('quest-btn');
    const b = document.createElement('button'); b.id = 'quest-btn'; b.type = 'button'; b.className = 'main-btn quest-btn';
    b.innerHTML = '<span>🗼 시련의 탑</span><small>퀘스트 · 보유 카드로 도전</small>';
    b.disabled = !window.TCG?.ready; b.onclick = open; s.after(b);
    window.addEventListener('tcg:ready', () => { b.disabled = false; });
    return true;
  }
  if (!mount()) { const t = setInterval(() => { if (mount()) clearInterval(t); }, 300); setTimeout(() => clearInterval(t), 10000); }
  /** 마이페이지·관리자용 최고 층 */
  async function bestFloor() { try { const s = await rpc('quest_status'); return s?.best_floor | 0; } catch { return null; } }
  window.VRQuest = { open, render, challenge, bestFloor, HOOKS: QUEST_HOOKS, _test: { result, enemiesOf, rewardOf, loadCfg, get status() { return status; }, set status(v) { status = v; } } };
})();
