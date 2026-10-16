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

  const user = () => window.VRCloud?.user || window.__STORY_MOCK_USER || null;
  const pool = () => window.TCG?.POOL || [];
  const card = id => pool().find(c => String(c.id) === String(id));
  let save = null, cloudOk = true;

  // ----- 저장 -----
  const KEY = () => `vrTcgStory.v1:${user()?.id || 'guest'}`;
  const fresh = () => ({ v: 1, openingSeen: false, starter: null, owned: [], points: 0, cleared: {}, updatedAt: 0 });
  function loadLocal() { try { return JSON.parse(localStorage.getItem(KEY())) || null; } catch { return null; } }
  async function load() {
    let local = loadLocal(), cloud = null;
    const sb = window.VRCloud?.sb, u = window.VRCloud?.user;
    if (sb && u) {
      try { const { data, error } = await sb.from('story_progress').select('data').eq('user_id', u.id).maybeSingle(); if (error) throw error; cloud = data?.data || null; }
      catch (e) { cloudOk = false; console.warn('[story] 클라우드 불러오기 실패 → 브라우저 저장 사용', e?.message || e); }
    }
    save = { ...fresh(), ...((cloud?.updatedAt || 0) >= (local?.updatedAt || 0) ? (cloud || local) : local) };
  }
  async function persist() {
    save.updatedAt = Date.now();
    try { localStorage.setItem(KEY(), JSON.stringify(save)); } catch {}
    const sb = window.VRCloud?.sb, u = window.VRCloud?.user;
    if (!sb || !u || !cloudOk) return;
    try { const { error } = await sb.from('story_progress').upsert({ user_id: u.id, data: save, updated_at: new Date().toISOString() }); if (error) throw error; }
    catch (e) { cloudOk = false; console.warn('[story] 클라우드 저장 실패 → 브라우저 저장만', e?.message || e); }
  }

  // ----- 카드 계산 -----
  function boosted(o) {
    const c = card(o.id); if (!c) return null;
    const b = o.boost || {}, k = D.statPerPoint;
    return { ...c, ATK: c.ATK + (b.ATK || 0) * k.ATK, HP: c.HP + (b.HP || 0) * k.HP, DEF: c.DEF + (b.DEF || 0) * k.DEF };
  }
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

  // ----- 화면 -----
  const root = () => $('story-screen');
  function show(html) {
    const r = root(); r.innerHTML = `<div class="story-wrap">${html}</div>`;
    r.classList.remove('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.add('hidden');
    r.scrollTop = 0;
  }
  function home() { root().classList.add('hidden'); $('start-screen').classList.remove('hidden'); }
  const topBar = (title, back = 'home') => `<div class="story-top"><button class="story-back" data-go="${back}">← ${back === 'home' ? '처음으로' : '돌아가기'}</button><div class="story-top-title">${title}</div><button class="story-mycards" data-go="cards">🃏 보유 카드</button></div>`;
  function bind(extra = {}) {
    root().querySelectorAll('[data-go]').forEach(b => b.onclick = () => ({ home, map: renderMap, cards: renderCards, ...extra })[b.dataset.go]?.());
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
    const close = () => { m.className = 'hidden'; m.innerHTML = ''; onClose?.(); };
    m.querySelectorAll('[data-close-pop]').forEach(b => b.onclick = close);
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

  function renderOpening() {
    const o = D.opening;
    show(`<div class="story-opening">${o.video ? `<video id="story-op-video" src="${esc(o.video)}" ${o.poster ? `poster="${esc(o.poster)}"` : ''} autoplay playsinline class="w-full max-h-[70vh] rounded-2xl bg-black"></video>` : `<div class="story-op-ph"><div class="story-chapter-big">${esc(o.title)}</div><div class="text-zinc-400 mt-3">${esc(o.text)}</div></div>`}
      <button id="story-op-skip" class="story-btn mt-6">${o.video ? '건너뛰기' : '계속하기'} ▶</button></div>`);
    const done = async () => { save.openingSeen = true; await persist(); save.starter ? renderMap() : renderSelect(); };
    $('story-op-skip').onclick = done; const v = $('story-op-video'); if (v) v.onended = done;
  }

  function renderSelect() {
    show(`<div class="text-center"><div class="story-chapter-sub">MAIN STORY</div><div class="text-2xl md:text-3xl font-black mt-1">함께할 캐릭터를 골라 주세요</div>
      <div class="text-sm text-zinc-400 mt-1">고른 카드는 내 카드로 영구 귀속되고, 리더가 돼요. (나중에 바꿀 수 없어요)</div></div>
      <div class="story-select">${D.starters.map(s => { const c = card(s.id); return c ? `<button class="story-pick" data-pick="${s.id}">${tile(c)}<div class="text-xs text-zinc-400 mt-1 story-intro-text">${esc(introOf(s))}</div></button>` : ''; }).join('')}</div>
      <div class="text-center mt-4"><button class="story-back" data-go="home">← 처음으로</button></div>`);
    bind();
    root().querySelectorAll('[data-pick]').forEach(b => b.onclick = () => {
      const c = card(b.dataset.pick);
      const p = popup(`<div class="text-lg font-black mb-3">${esc(c.name)}(으)로 시작할까요?</div>${tile(c)}<div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-pick-ok" class="flex-1 py-2.5 rounded-xl bg-amber-400 text-black font-bold">결정</button></div>`);
      $('story-pick-ok').onclick = async () => { p.close(); save.starter = String(c.id); save.owned = [{ id: String(c.id), boost: {} }]; await persist(); const ch = chapterFor(D.chapters[0]); chapterIntro(ch, () => startStory(ch)); };
    });
  }

  function chapterIntro(ch, next) {
    show(`<div class="story-intro" id="story-intro"><div class="story-chapter-sub">MAIN STORY</div><div class="story-chapter-big">${esc(ch.title)}</div><div class="story-chapter-name">${esc(ch.subtitle)}</div><div class="text-xs text-zinc-500 mt-8">화면을 누르면 계속</div></div>`);
    $('story-intro').onclick = next;
  }

  // 시작 스토리: 캐릭터 선택 직후 1번
  function startStory(ch) {
    if (!ch.start?.length || save.startSeen) return renderMap();
    playLines(ch.start, [], async () => { save.startSeen = true; await persist(); renderMap(); });
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
        ${!cloudOk ? '<div class="text-[11px] text-amber-400">⚠️ 서버 저장 준비 중이라 이 브라우저에만 저장돼요</div>' : ''}</div>
      ${nextNo ? '' : '<div class="text-center text-emerald-300 font-bold mt-4">🎉 챕터 1 클리어! 다음 챕터는 준비 중이에요.</div>'}`);
    bind({ stats: () => openStats(renderMap) });
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
  function playLines(lines, enemies, next) {
    const starter = card(save.starter), enemy = enemies[0];
    const byName = n => enemies.find(c => c.name === n) || pool().filter(c => c.name === n).sort((a, b) => (a.region === starter?.region ? -1 : 0) - (b.region === starter?.region ? -1 : 0))[0] || null;
    const who = L => L.portrait !== undefined ? (L.portrait === 'starter' ? starter : L.portrait === 'enemy' ? enemy : L.portrait ? card(L.portrait) : null)
      : (D.noPortrait || []).includes(L.speaker) ? null : L.speaker === starter?.name ? starter : byName(L.speaker);
    let i = 0;
    const step = () => {
      if (i >= lines.length) return next();
      const L = lines[i], pc = who(L), sp = L.speaker === 'starter' ? starter?.name : L.speaker === 'enemy' ? enemy?.name : (L.speaker === '내레이션' ? null : L.speaker);
      const left = pc ? pc === starter : true;
      show(`<div class="story-dlg" id="story-dlg">
        <div class="story-dlg-stage">${pc ? `<img class="story-portrait ${left ? 'left' : 'right'}" src="${IMG}${pc.id}.webp" alt="${esc(pc.name)}">` : ''}</div>
        <div class="story-dlg-box">${sp ? `<div class="story-dlg-name">${esc(sp)}</div>` : ''}<div class="story-dlg-text">${esc(L.text)}</div><div class="story-dlg-next">▼ ${i + 1}/${lines.length}</div></div>
        <button class="story-dlg-skip" id="story-dlg-skip">건너뛰기 ⏭</button></div>`);
      $('story-dlg').onclick = e => { if (e.target.id === 'story-dlg-skip') { i = lines.length; } else i++; step(); };
    };
    step();
  }

  function battle(ch, ph, enemies) {
    root().classList.add('hidden');
    const boss = ph.type === 'boss';
    window.TCG.startStory({
      me: ownedCards(), ai: enemies, win: boss ? 'ko' : 'wipe', aiHp: boss ? (ph.baseHp || 500) : undefined, aiName: ph.enemyName || (boss ? '보스' : '적군'), first: 'me',
      onEnd: (win, reason) => result(ch, ph, win, reason),
    });
    if (ph.tip) setTimeout(() => toast(`💡 ${ph.tip}`), 400);
    toast(boss ? '👑 보스전: 상대 진영을 무너뜨리세요!' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리세요!');
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'story-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 3200); }

  async function result(ch, ph, win, reason) {
    if (!win) {
      show(`<div class="text-center py-10"><div class="story-chapter-big text-red-400">DEFEAT</div><div class="text-zinc-300 mt-2">${reason === 'wipe' ? '내 카드가 모두 쓰러졌어요.' : reason === 'timeout' ? '턴 제한 안에 적을 모두 쓰러뜨리지 못했어요.' : '패배했어요.'} 스탯을 올리고 다시 도전해 보세요!</div>
        <div class="flex flex-col gap-2 max-w-xs mx-auto mt-6"><button class="story-btn" id="story-retry">다시 도전</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
      bind(); $('story-retry').onclick = () => startPhase(ch, ph); return;
    }
    const first = !clearedOf(ch).includes(ph.no);
    let reward = null, pts = 0;
    if (first) {
      const have = new Set(save.owned.map(o => o.id));
      reward = rand(normals().filter(c => !have.has(String(c.id))));
      if (ph.type === 'boss' && ch.ending?.length) await new Promise(r => playLines(ch.ending, [], r));
      if (reward) save.owned.push({ id: String(reward.id), boost: {} });
      save.cleared[ch.id] = [...clearedOf(ch), ph.no];
    }
    pts = first ? D.statPoints[ph.type] : 1;   // 재도전 승리도 1포인트
    save.points += pts;
    await persist();
    show(`<div class="text-center py-6"><div class="story-chapter-sub">Phase.${ph.no} CLEAR</div><div class="story-chapter-big text-emerald-300">VICTORY</div>
      ${reward ? `<div class="mt-4 text-amber-200 font-bold">🎁 보상 카드 획득!</div><div class="flex justify-center mt-2 story-reward">${tile(reward)}</div>` : '<div class="mt-4 text-zinc-400 text-sm">이미 클리어한 페이즈라 카드 보상은 없어요.</div>'}
      <div class="mt-4 text-lg">스탯 포인트 <b class="text-emerald-300">+${pts}</b> (보유 ${save.points})</div>
      <div class="flex flex-col gap-2 max-w-xs mx-auto mt-5"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button><button class="story-back" data-go="map">챕터 지도로</button></div></div>`);
    bind({ stats: () => openStats(renderMap) });
  }

  // ----- 스탯 분배 (팝업) -----
  function openStats(after) {
    let sel = 0, temp = save.owned.map(o => ({ ...(o.boost || {}) })), left = save.points;
    const draw = () => {
      const o = save.owned[sel], c = boosted({ id: o.id, boost: temp[sel] }), k = D.statPerPoint;
      const p = popup(`<div class="text-lg font-black mb-1">📈 스탯 분배</div><div class="text-xs text-zinc-400 mb-3">남은 포인트 <b class="text-emerald-300 text-base">${left}</b> · 포인트 1당 ATK +${k.ATK}, HP +${k.HP}, DEF +${k.DEF}</div>
        <div class="flex gap-1.5 overflow-x-auto pb-2 mb-2">${save.owned.map((x, i) => { const cc = card(x.id); return `<button data-sel="${i}" class="story-chip ${i === sel ? 'on' : ''}">${i === 0 ? '👑 ' : ''}${esc(cc?.name)}</button>`; }).join('')}</div>
        <div class="flex gap-3 items-center"><img src="${IMG}${c.id}.webp" class="w-20 aspect-[3/4] object-cover rounded-lg" alt=""><div class="flex-1 space-y-2">${STATS.map(s => `<div class="flex items-center gap-2"><span class="w-16 text-sm font-bold">${STAT_LABEL[s]}</span><span class="flex-1 font-black">${fmt(c[s])}${temp[sel][s] ? ` <span class="text-emerald-300 text-xs">(+${temp[sel][s] * k[s]})</span>` : ''}</span><button data-dec="${s}" class="story-pm" ${(temp[sel][s] || 0) > (o.boost?.[s] || 0) ? '' : 'disabled'}>−</button><button data-inc="${s}" class="story-pm" ${left ? '' : 'disabled'}>＋</button></div>`).join('')}</div></div>
        <div class="mt-3 text-[11px] text-zinc-500">🗡️ 무기 · 🛡️ 방어구 장착은 준비 중이에요 (Coming soon)</div>
        <div class="flex gap-2 mt-4"><button data-close-pop class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold">취소</button><button id="story-stat-ok" class="flex-1 py-2.5 rounded-xl bg-emerald-500 text-black font-bold">확정</button></div>`, after);
      p.el.querySelectorAll('[data-sel]').forEach(b => b.onclick = () => { sel = +b.dataset.sel; draw(); });
      p.el.querySelectorAll('[data-inc]').forEach(b => b.onclick = () => { if (!left) return; temp[sel][b.dataset.inc] = (temp[sel][b.dataset.inc] || 0) + 1; left--; draw(); });
      p.el.querySelectorAll('[data-dec]').forEach(b => b.onclick = () => { temp[sel][b.dataset.dec]--; left++; draw(); });
      $('story-stat-ok').onclick = async () => { save.owned.forEach((x, i) => x.boost = temp[i]); save.points = left; await persist(); p.close(); };
    };
    draw();
  }

  // ----- 보유 카드 -----
  function renderCards() {
    const k = D.statPerPoint;
    show(`${topBar('🃏 보유 카드', 'map')}<div class="text-center text-sm text-zinc-400 my-2">스토리 모드 전용 · ${save.owned.length}장 · 스탯 포인트 ${save.points}</div>
      <div class="story-grid">${save.owned.map((o, i) => { const c = boosted(o); if (!c) return ''; const b = o.boost || {};
        const up = STATS.filter(s => b[s]).map(s => `${s} +${b[s] * k[s]}`).join(' · ');
        return tile(c, `<div class="text-[10px] text-emerald-300 h-3">${i === 0 ? '👑 리더 ' : ''}${up}</div><div class="story-equip"><span>🗡️ 무기</span><span>🛡️ 방어구</span><em>준비 중</em></div>`); }).join('')}</div>
      ${save.points ? '<div class="text-center mt-4"><button class="story-btn" data-go="stats">📈 스탯 분배하기</button></div>' : ''}`);
    bind({ stats: () => openStats(renderCards) });
  }

  function mountButton() {
    const start = $('start-btn'); if (!start || $('story-btn')) return;
    const b = document.createElement('button'); b.id = 'story-btn'; b.className = 'main-btn main-btn-primary story-entry'; b.textContent = '📜 스토리 모드';
    b.disabled = !window.TCG?.ready; b.onclick = enter; start.after(b);
    window.addEventListener('tcg:ready', () => { b.disabled = false; });
  }
  mountButton();
  window.VRStory = { enter, get save() { return save; }, renderMap, renderCards, openStats, renderSelect };
})();
