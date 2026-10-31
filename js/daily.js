// ===== 📅 일일 미션 + 출석 보상 — 서버: supabase/daily.sql =====
// 버튼: [data-dailybtn] (메인 상단·스토리 허브) · 받을 수 있는 보상 수 뱃지 · 한국 시간 00:00 초기화
// 진행: game.js 가 'vr:daily' 이벤트({k:'battle', mode, win} · {k:'skill'})를 보내면 여기서 서버 daily_track 호출
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, skills = 0;
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const rwText = r => [r.gold && `🪙 ${n(r.gold)}`, r.gem && `🔮 ${n(r.gem)}`, r.tickets && `🎟️ ${r.tickets}`].filter(Boolean).join(' · ');
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already claimed': '이미 받았어요', 'not done': '아직 완료하지 않았어요', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const ready = s => !s ? 0 : (s.attend.today ? 0 : 1) + s.missions.filter(m => !m.claimed && m.prog >= m.goal).length + (!s.all.claimed && s.all.done >= s.all.goal ? 1 : 0);
  function set(s) { if (s?.ok) { cache = s; paint(); } return cache; }
  async function status() { if (off) return null; try { return set(await rpc('daily_status')); } catch (e) { console.warn('[daily]', e?.message); return null; } }
  // 날짜가 바뀌면 새로 불러옴
  let lastDay = null; setInterval(() => { const d = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10); if (lastDay && d !== lastDay) status(); lastDay = d; }, 60000);

  function paint() {
    const ws = document.querySelectorAll('[data-dailybtn]');
    for (const w of ws) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.daily-btn')) { w.innerHTML = '<button class="story-mailbtn daily-btn" type="button" aria-label="일일 미션·출석" title="일일 미션·출석">📅<span>미션</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove(); const k = ready(cache);
      if (k > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${k}</i>`);
    }
  }
  async function claim(fn, args) {
    try { const r = await rpc(fn, args); if (!r) return; set(r); toast(`🎁 ${r.got_day ? `출석 ${r.got_day}일째 · ` : ''}${rwText(r.got || {})}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (r.got?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); }
    catch (e) { toast(errText(e)); }
  }
  function left() { const ms = cache?.next_reset ? new Date(cache.next_reset) - Date.now() : 0; if (ms <= 0) return ''; const h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 60000); return `${h}시간 ${m}분 뒤 초기화`; }
  function open() {
    document.querySelector('.daily-pop')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop daily-pop';
    const draw = () => { const s = cache; if (!s) { pop.innerHTML = '<div class="gem-panel daily-panel">불러오는 중...</div>'; return; }
      const a = s.attend, nextStep = a.today ? a.step : a.step + 1;
      pop.innerHTML = `<div class="gem-panel daily-panel" role="dialog" aria-label="일일 미션·출석"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">🗓️ 출석 보상 <small>총 ${n(a.total)}일</small></h3>
        <div class="daily-att">${a.rewards.map((r, i) => { const d = i + 1, got = d <= a.step, now = !a.today && d === nextStep;
          return `<div class="daily-day ${got ? 'got' : ''} ${now ? 'now' : ''} ${d === 7 ? 'big' : ''}"><b>${d}일</b><span>${rwText(r).replace(/ · /g, '<br>')}</span>${got ? '<i>✔</i>' : ''}</div>`; }).join('')}</div>
        <button class="daily-claim" data-att ${a.today ? 'disabled' : ''}>${a.today ? '오늘 출석 완료 ✔' : `${nextStep}일째 출석 보상 받기`}</button>
        <h3 class="daily-h">📋 일일 미션 <small>${left()}</small></h3>
        <div class="daily-list">${s.missions.map(m => { const ok = m.prog >= m.goal;
          return `<div class="daily-m ${m.claimed ? 'done' : ''}"><div class="daily-mt"><b>${m.name}</b><small>${rwText(m.reward)}</small><div class="daily-bar"><i style="width:${Math.round(m.prog / m.goal * 100)}%"></i></div></div>
          <button class="daily-claim sm" data-m="${m.key}" ${m.claimed || !ok ? 'disabled' : ''}>${m.claimed ? '완료' : ok ? '받기' : `${m.prog}/${m.goal}`}</button></div>`; }).join('')}
          <div class="daily-m all ${s.all.claimed ? 'done' : ''}"><div class="daily-mt"><b>🎁 모든 미션 완료</b><small>${rwText(s.all.reward)}</small><div class="daily-bar"><i style="width:${Math.round(s.all.done / s.all.goal * 100)}%"></i></div></div>
          <button class="daily-claim sm" data-m="all" ${s.all.claimed || s.all.done < s.all.goal ? 'disabled' : ''}>${s.all.claimed ? '완료' : s.all.done >= s.all.goal ? '받기' : `${s.all.done}/${s.all.goal}`}</button></div></div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelector('[data-att]').onclick = async () => { await claim('attend_claim'); draw(); };
      pop.querySelectorAll('[data-m]').forEach(b => b.onclick = async () => { await claim('daily_claim', { p_key: b.dataset.m }); draw(); });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    document.body.appendChild(pop); draw(); status().then(draw);
  }
  async function track(kind, k = 1) { if (off || !window.VRCloud?.user) return; try { await rpc('daily_track', { p_kind: kind, p_n: k }); } catch (e) { console.warn('[daily]', e?.message); } }
  window.addEventListener('vr:daily', async e => {
    const d = e.detail || {};
    if (d.k === 'skill') { skills++; return; }
    if (d.k !== 'battle' || !d.mode) return;
    const jobs = [];
    if (skills) { jobs.push(track('skill', skills)); skills = 0; }
    if (d.mode === 'arcade') jobs.push(track('arcade'));
    if (d.mode === 'tower') jobs.push(track('tower'));
    if (d.mode === 'story' && d.win) jobs.push(track('story'));
    if (d.win) jobs.push(track('win'));
    await Promise.all(jobs); status();
  });
  window.VRDaily = { open, status, paint };
  setTimeout(() => { paint(); status(); }, 1500); setTimeout(() => { paint(); status(); }, 4000);
  new MutationObserver(() => { if (document.querySelector('[data-dailybtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
