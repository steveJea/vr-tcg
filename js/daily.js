// ===== 📅 일일 미션 + 출석 보상 + 📋 주간 미션 — 서버: supabase/daily.sql · daily_social.sql =====
// 버튼: [data-dailybtn] (메인 상단·스토리 허브) · 받을 수 있는 보상 수 뱃지 · 한국 시간 00:00 / 월요일 00:00 초기화
// 진행: game.js 가 'vr:daily' 이벤트({k:'battle', mode, win} · {k:'skill'})를 보내면 여기서 서버 daily_track · weekly_track 호출
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, week = null, off = false, weekOff = false, skills = 0;
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { if (/weekly/i.test(name)) weekOff = true; else off = true; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const rwText = r => [r?.gold && `🪙 ${n(r.gold)}`, r?.gem && `🔮 ${n(r.gem)}`, r?.tickets && `🎟️ ${r.tickets}`, r?.stamina && `🔋 ${r.stamina}`].filter(Boolean).join(' · ');
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already claimed': '이미 받았어요', 'not done': '아직 완료하지 않았어요', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const readyDaily = s => !s ? 0 : (s.attend.today ? 0 : 1) + s.missions.filter(m => !m.claimed && m.prog >= m.goal).length + (!s.all.claimed && s.all.done >= s.all.goal ? 1 : 0);
  const readyWeek = s => !s ? 0 : s.missions.filter(m => !m.claimed && m.prog >= m.goal).length + (!s.all.claimed && s.all.done >= s.all.goal ? 1 : 0);
  function set(s) { if (s?.ok) { cache = s; paint(); } return cache; }
  function setWeek(s) { if (s?.ok) { week = s; paint(); } return week; }
  async function status() {
    if (off && weekOff) return null;
    try { if (!off) set(await rpc('daily_status')); } catch (e) { console.warn('[daily]', e?.message); }
    try { if (!weekOff) setWeek(await rpc('weekly_status')); } catch (e) { console.warn('[weekly]', e?.message); }
    return cache;
  }
  let lastDay = null; setInterval(() => { const d = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10); if (lastDay && d !== lastDay) status(); lastDay = d; }, 60000);

  function paint() {
    const ws = document.querySelectorAll('[data-dailybtn]');
    for (const w of ws) {
      if ((off && weekOff) || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.daily-btn')) { w.innerHTML = '<button class="story-mailbtn daily-btn" type="button" aria-label="일일·주간 미션" title="일일·주간 미션"><img class="ui-btn-ic" src="img/ui/icon/mission.webp" alt="미션" width="20" height="20"><span>미션</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove(); const k = readyDaily(cache) + readyWeek(week);
      if (k > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${k}</i>`);
    }
  }
  async function claim(fn, args) {
    try { const r = await rpc(fn, args); if (!r) return; if (/weekly/.test(fn)) setWeek(r); else set(r); toast(`🎁 ${r.got_day ? `출석 ${r.got_day}일째 · ` : ''}${rwText(r.got || {})}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (r.got?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); }
    catch (e) { toast(errText(e)); }
  }
  function left(ts) { const ms = ts ? new Date(ts) - Date.now() : 0; if (ms <= 0) return ''; const h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 60000); if (h >= 24) return `${Math.floor(h / 24)}일 ${h % 24}시간 뒤 초기화`; return `${h}시간 ${m}분 뒤 초기화`; }
  const GO = {
    arcade: () => window.VRArcadeHub?.open(), win: () => window.VRArcadeHub?.open(), skill: () => window.VRArcadeHub?.open(),
    story: () => window.VRStory?.enter?.(), tower: () => window.VRQuest?.open?.(),
  };
  function missionRows(list, all, keyAttr) {
    return `${list.map(m => { const ok = m.prog >= m.goal;
      return `<div class="daily-m ${m.claimed ? 'done' : ''}"><div class="daily-mt ${!m.claimed && GO[m.key] ? 'go' : ''}" ${!m.claimed && GO[m.key] ? `data-go="${m.key}" role="button" tabindex="0" title="바로 가기"` : ''}><b>${m.name}${!m.claimed && GO[m.key] ? ' <span class="daily-arrow">›</span>' : ''}</b><small>${rwText(m.reward)}</small><div class="daily-bar"><i style="width:${Math.round(m.prog / m.goal * 100)}%"></i></div></div>
      <button class="daily-claim sm" ${keyAttr}="${m.key}" ${m.claimed || !ok ? 'disabled' : ''}>${m.claimed ? '완료' : ok ? '받기' : `${m.prog}/${m.goal}`}</button></div>`; }).join('')}
      <div class="daily-m all ${all.claimed ? 'done' : ''}"><div class="daily-mt"><b>🎁 모든 미션 완료</b><small>${rwText(all.reward)}</small><div class="daily-bar"><i style="width:${Math.round(all.done / all.goal * 100)}%"></i></div></div>
      <button class="daily-claim sm" ${keyAttr}="all" ${all.claimed || all.done < all.goal ? 'disabled' : ''}>${all.claimed ? '완료' : all.done >= all.goal ? '받기' : `${all.done}/${all.goal}`}</button></div>`;
  }
  function open() {
    document.querySelector('.daily-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop daily-pop';
    const draw = () => { const s = cache; if (!s && !week) { pop.innerHTML = '<div class="gem-panel daily-panel">불러오는 중...</div>'; return; }
      const a = s?.attend, nextStep = a ? (a.today ? a.step : a.step + 1) : 0;
      pop.innerHTML = `<div class="gem-panel daily-panel" role="dialog" aria-label="일일·주간 미션"><button class="gem-x" data-x aria-label="닫기">✕</button>
        ${a ? `<h3 class="daily-h">🗓️ 출석 보상 <small>총 ${n(a.total)}일</small></h3>
        <div class="daily-att">${a.rewards.map((r, i) => { const d = i + 1, got = d <= a.step, now = !a.today && d === nextStep;
          return `<div class="daily-day ${got ? 'got' : ''} ${now ? 'now' : ''} ${d === 7 ? 'big' : ''}"><b>${d}일</b><span>${rwText(r).replace(/ · /g, '<br>')}</span>${got ? '<i>✔</i>' : ''}</div>`; }).join('')}</div>
        <button class="daily-claim" data-att ${a.today ? 'disabled' : ''}>${a.today ? '오늘 출석 완료 ✔' : `${nextStep}일째 출석 보상 받기`}</button>` : ''}
        ${s ? `<h3 class="daily-h">📋 일일 미션 <small>${left(s.next_reset)}</small></h3>
        <div class="daily-list">${missionRows(s.missions, s.all, 'data-m')}</div>` : ''}
        ${week ? `<h3 class="daily-h">🗓️ 주간 미션 <small>${left(week.next_reset)}</small></h3>
        <div class="daily-list">${missionRows(week.missions, week.all, 'data-w')}</div>` : ''}</div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelector('[data-att]')?.addEventListener('click', async () => { await claim('attend_claim'); draw(); });
      pop.querySelectorAll('[data-go]').forEach(el => el.onclick = () => { const f = GO[el.dataset.go]; pop.remove(); f?.(); });
      pop.querySelectorAll('[data-m]').forEach(b => b.onclick = async () => { await claim('daily_claim', { p_key: b.dataset.m }); draw(); });
      pop.querySelectorAll('[data-w]').forEach(b => b.onclick = async () => { await claim('weekly_claim', { p_key: b.dataset.w }); draw(); });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('daily', '🗓️ 출석 · 미션', pop)) document.body.appendChild(pop);
    draw(); status().then(draw);
  }
  let achOff = false;
  function achTrack(kind, k) {
    if (achOff || !window.VRCloud?.user) return;
    window.VRCloud.sb?.rpc('ach_track', { p_kind: kind, p_n: k }).then(({ error }) => { if (error && missing(error)) achOff = true; }, () => {});
  }
  async function track(kind, k = 1) {
    if (!window.VRCloud?.user) return;
    const jobs = [];
    if (!off) jobs.push(rpc('daily_track', { p_kind: kind, p_n: k }).catch(e => console.warn('[daily]', e?.message)));
    if (!weekOff) jobs.push(rpc('weekly_track', { p_kind: kind, p_n: k }).catch(e => console.warn('[weekly]', e?.message)));
    await Promise.all(jobs);
  }
  window.addEventListener('vr:daily', async e => {
    const d = e.detail || {};
    if (d.k === 'skill') { skills++; return; }
    if (d.k !== 'battle' || !d.mode) return;
    const jobs = [];
    if (skills) { jobs.push(track('skill', skills)); achTrack('skill', skills); skills = 0; }
    if (d.mode === 'arcade' && d.win) achTrack('arcade_win', 1);
    if (d.mode === 'arcade') jobs.push(track('arcade'));
    if (d.mode === 'tower') jobs.push(track('tower'));
    if (d.mode === 'story' && d.win) {
      // 소탕 n회 = 스테이지 n회 클리어 (daily per=1 · weekly per=2 이라 회차마다 호출)
      const n = Math.max(1, d.n | 0);
      for (let i = 0; i < n; i++) jobs.push(track('story'));
    }
    if (d.win && !d.sweep) jobs.push(track('win'));   // 소탕은 전투 승리가 아님 → story 만 n회
    await Promise.all(jobs); status();
  });
  window.VRDaily = { open, status, paint };
  setTimeout(() => { paint(); status(); }, 1500); setTimeout(() => { paint(); status(); }, 4000);
  new MutationObserver(() => { if (document.querySelector('[data-dailybtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
