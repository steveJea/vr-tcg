// ===== 📅 일일 미션 + 📋 주간 미션 — 서버: supabase/daily.sql · daily_social.sql =====
// 예전 7일 출석(attend_claim)은 2026-11-13에 화면에서 뺐음. 출석 보상은 js/attendance.js (🎁 출석 버튼)
// 버튼: [data-dailybtn] (메인 상단·스토리 허브) · 받을 수 있는 보상 수 뱃지 · 한국 시간 00:00 / 월요일 00:00 초기화
// 진행도는 서버만 확정. 브라우저 전투 이벤트는 상태 새로고침만 요청한다.
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, week = null, off = false, weekOff = false;
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { if (/weekly/i.test(name)) weekOff = true; else off = true; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const rwText = r => [r?.gold && `🪙 ${n(r.gold)}`, r?.gem && `🔮 ${n(r.gem)}`, r?.tickets && `🎟️ ${r.tickets}`, r?.stamina && `🔋 ${r.stamina}`].filter(Boolean).join(' · ');
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already claimed': '이미 받았어요', 'not done': '아직 완료하지 않았어요', 'login required': '로그인이 필요해요', 'reward verification pending': '지급 보류' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const readyDaily = s => readyMissions(s);
  const readyWeek = s => readyMissions(s);
  const readyMissions = s => !s || s.reward_held ? 0 : s.missions.filter(m => !m.claimed && !m.held && m.prog >= m.goal).length + (!s.all.claimed && !s.all.held && s.all.done >= s.all.goal ? 1 : 0);
  const claimableKeys = s => {
    if (!s || s.reward_held) return [];
    const keys = s.missions.filter(m => !m.claimed && !m.held && m.prog >= m.goal).map(m => m.key);
    if (!s.all.claimed && !s.all.held && s.all.done >= s.all.goal) keys.push('all');
    return keys;
  };
  // 월간 미션은 아직 없음. 목록에 { id:'monthly', label:'월간 미션', get, fn } 만 넣으면 탭이 생긴다.
  const TABS = [
    { id: 'daily', label: '일일 미션', get: () => cache, fn: 'daily_claim' },
    { id: 'weekly', label: '주간 미션', get: () => week, fn: 'weekly_claim' },
  ];
  let tab = 'daily';
  const MISSION_ACT = { arcade: '아케이드 플레이', win: '전투 승리', story: '스토리 스테이지 클리어', tower: '시련의 탑 도전', skill: '고유기술 사용' };
  const missionName = m => MISSION_ACT[m.key] ? `${MISSION_ACT[m.key]} x ${m.goal}` : m.name;
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
    try { const r = await rpc(fn, args); if (!r) return; if (/weekly/.test(fn)) setWeek(r); else set(r); toast(`🎁 ${rwText(r.got || {})}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (r.got?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); }
    catch (e) { toast(errText(e)); }
  }
  async function claimAll(fn, keys) {
    const got = {}; let n = 0;
    for (const key of keys) {
      try {
        const r = await rpc(fn, { p_key: key }); if (!r) break;
        if (/weekly/.test(fn)) setWeek(r); else set(r);
        for (const [k, v] of Object.entries(r.got || {})) got[k] = (got[k] || 0) + Number(v || 0);
        if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); n++;
      } catch (e) { toast(errText(e)); break; }
    }
    if (n) { if (got.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); toast(`🎁 ${rwText(got)}`); }
  }
  function left(ts) { const ms = ts ? new Date(ts) - Date.now() : 0; if (ms <= 0) return ''; const h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 60000); if (h >= 24) return `${Math.floor(h / 24)}일 ${h % 24}시간 뒤 초기화`; return `${h}시간 ${m}분 뒤 초기화`; }
  const GO = {
    arcade: () => window.VRArcadeHub?.open(), win: () => window.VRArcadeHub?.open(), skill: () => window.VRArcadeHub?.open(),
    story: () => window.VRStory?.enter?.(), tower: () => window.VRQuest?.open?.(),
  };
  function missionRows(list, all, keyAttr, held) {
    return `${list.map(m => { const ok = m.prog >= m.goal;
      return `<div class="daily-m ${m.claimed ? 'done' : ''}"><div class="daily-mt ${!m.claimed && GO[m.key] ? 'go' : ''}" ${!m.claimed && GO[m.key] ? `data-go="${m.key}" role="button" tabindex="0" title="바로 가기"` : ''}><b>${missionName(m)}${!m.claimed && GO[m.key] ? ' <span class="daily-arrow">›</span>' : ''}</b><small>${rwText(m.reward)}</small><div class="daily-bar"><i style="width:${Math.round(m.prog / m.goal * 100)}%"></i></div></div>
      <button class="daily-claim sm" ${keyAttr}="${m.key}" ${m.claimed || held || m.held || !ok ? 'disabled' : ''}>${m.claimed ? '완료' : held || m.held ? '지급 보류' : ok ? '받기' : `${m.prog}/${m.goal}`}</button></div>`; }).join('')}
      <div class="daily-m all ${all.claimed ? 'done' : ''}"><div class="daily-mt"><b>🎁 모든 미션 완료</b><small>${rwText(all.reward)}</small><div class="daily-bar"><i style="width:${Math.round(all.done / all.goal * 100)}%"></i></div></div>
      <button class="daily-claim sm" ${keyAttr}="all" ${all.claimed || held || all.held || all.done < all.goal ? 'disabled' : ''}>${all.claimed ? '완료' : held || all.held ? '지급 보류' : all.done >= all.goal ? '받기' : `${all.done}/${all.goal}`}</button></div>`;
  }
  function open() {
    document.querySelector('.daily-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop daily-pop';
    const draw = () => { const s = cache; if (!s && !week) { pop.innerHTML = '<div class="gem-panel daily-panel">불러오는 중...</div>'; return; }
      const tabs = TABS.filter(t => t.get());
      if (!tabs.some(t => t.id === tab)) tab = tabs[0]?.id || 'daily';
      const cur = tabs.find(t => t.id === tab), src = cur?.get() || null, ready = readyMissions(src);
      const keyAttr = cur?.id === 'weekly' ? 'data-w' : 'data-m';
      pop.innerHTML = `<div class="gem-panel daily-panel" role="dialog" aria-label="일일·주간 미션"><button class="gem-x" data-x aria-label="닫기">✕</button>
        ${tabs.length ? `<div class="daily-tabs" role="tablist">${tabs.map(t => { const k = readyMissions(t.get()); return `<button type="button" class="daily-tab ${t.id === tab ? 'on' : ''}" role="tab" aria-selected="${t.id === tab}" data-tab="${t.id}">${t.label}${k ? `<i class="story-badge">${k}</i>` : ''}</button>`; }).join('')}</div>` : ''}
        ${src ? `<p class="daily-reset">${left(src.next_reset)}</p>
        <button class="daily-claim" data-all-ready ${ready ? '' : 'disabled'}>한번에 다 받기</button>
        <div class="daily-list">${missionRows(src.missions, src.all, keyAttr, src.reward_held)}</div>` : ''}</div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(); });
      pop.querySelector('[data-all-ready]')?.addEventListener('click', async () => { const keys = claimableKeys(cur.get()); if (!keys.length) return; await claimAll(cur.fn, keys); draw(); });
      pop.querySelectorAll('[data-go]').forEach(el => el.onclick = () => { const f = GO[el.dataset.go]; pop.remove(); f?.(); });
      pop.querySelectorAll('[data-m]').forEach(b => b.onclick = async () => { await claim('daily_claim', { p_key: b.dataset.m }); draw(); });
      pop.querySelectorAll('[data-w]').forEach(b => b.onclick = async () => { await claim('weekly_claim', { p_key: b.dataset.w }); draw(); });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('daily', '📅 미션', pop)) document.body.appendChild(pop);
    draw(); status().then(draw);
  }
  window.addEventListener('vr:daily', e => { if (e.detail?.k === 'battle') status(); });
  window.VRDaily = { open, status, paint };
  setTimeout(() => { paint(); status(); }, 1500); setTimeout(() => { paint(); status(); }, 4000);
  new MutationObserver(() => { if (document.querySelector('[data-dailybtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
