// ===== 🎁 출석 보상 2종 — 서버: supabase/attendance_staging.sql =====
// 7일 간의 행운 (기준 시각 이후 가입한 계정 · 출석 7회 · 가입 후 기간 안) + 30일 접속 선물 (이번 달 N회째 출석 = N번 칸 · 매달 1일 1번부터)
// 버튼: [data-attendbtn] (메인 상단 미션 옆). 로그인 후 받을 게 있으면 하루 한 번 창이 자동으로 뜸. 받기는 서버만 확정 (KST 하루 1번, 트랙별)
// SQL 실행 전이거나 비로그인(게스트)이면 버튼도 창도 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, busy = false;
  async function rpc(name, args) {
    const m = window.__ATTEND_MOCK; if (m) return m(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; cache = null; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const K = {
    gold: ['골드', 'img/ui/cur_gold.webp'], blood: ['피', 'img/ui/cur_blood.webp'], shard: ['조각', 'img/ui/cur_shard_small.webp'],
    gem_free: ['무료 심연석', 'img/ui/guild/cur_gem.webp'], drink: ['무료 드링크', 'img/ui/cur_drink.webp'],
    tickets: ['소환권', 'img/ui/ticket.webp'], special_tickets: ['스페셜 소환권', null],
  };
  const ORDER = Object.keys(K);
  const ents = r => ORDER.filter(k => r?.[k]).map(k => [k, r[k]]);
  /** 보상 글자 (토스트·읽기용) */
  const rwText = r => ents(r).map(([k, v]) => `${K[k][0]} ${n(v)}${k === 'drink' ? ' (거래 불가)' : ''}`).join(' · ');
  const rwIcons = r => ents(r).map(([k, v]) => `<span class="att-rw" title="${K[k][0]}${k === 'drink' ? ' (거래 불가)' : ''}">${K[k][1] ? `<img src="${K[k][1]}" alt="${K[k][0]}">` : '<i>✨</i>'}<b>${k === 'gold' || k === 'blood' || k === 'shard' ? (v >= 1000 ? `${v / 1000}K` : v) : n(v)}</b></span>`).join('');
  function toast(t) { if (window.VRGem?.toast) return window.VRGem.toast(t); const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const luckyOn = s => !!s?.lucky?.eligible;
  const ready = s => !s ? 0 : (s.lucky?.open && !s.lucky.claimed_today ? 1 : 0) + (s.monthly && !s.monthly.claimed_today ? 1 : 0);
  async function status() {
    if (off || (!window.VRCloud?.user && !window.__ATTEND_MOCK)) { cache = null; paint(); return null; }
    try { const r = await rpc('attend_status'); if (r?.ok) cache = r; } catch (e) { console.warn('[attend]', e?.message); }
    paint(); return cache;
  }
  function paint() {
    for (const w of document.querySelectorAll('[data-attendbtn]')) {
      if (!cache) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.att-btn')) { w.innerHTML = '<button class="story-mailbtn att-btn" type="button" aria-label="출석 보상" title="출석 보상"><i class="att-btn-ic" aria-hidden="true">🎁</i><span>출석</span></button>'; w.firstChild.onclick = () => open(); }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove(); const k = ready(cache);
      if (k) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${k}</i>`);
    }
  }
  function grid(rewards, claims, today, can, label) {
    return `<div class="att-grid ${rewards.length > 7 ? 'att-month' : 'att-week'}">${rewards.map((r, i) => { const s = i + 1, done = s <= claims, next = s === claims + 1 && can;
      return `<div class="att-cell${done ? ' done' : ''}${next ? ' next' : ''}${s >= 29 ? ' tail' : ''}" title="${esc(`${label} ${s}회째 · ${rwText(r)}`)}"><small>${s}</small><div class="att-rws">${rwIcons(r)}</div>${done ? '<em>✔</em>' : ''}</div>`; }).join('')}</div>`;
  }
  function html(s) {
    const L = s.lucky, M = s.monthly, mon = +String(M.month).slice(5, 7);
    const lucky = luckyOn(s) ? `<section class="att-sec att-lucky"><div class="att-h"><b>🍀 7일 간의 행운</b><small>신규 가입 한정 · ${L.claims}/7 · ${esc(String(L.ends || '').slice(5).replace('-', '/'))}까지</small></div>
      ${grid(L.rewards, L.claims, s.today, L.open && !L.claimed_today, '7일 간의 행운')}
      <button type="button" class="att-claim" data-att-claim="lucky" ${L.open && !L.claimed_today ? '' : 'disabled'}>${L.claimed_today ? '오늘 받음 ✔' : `${L.claims + 1}일차 받기`}</button></section>` : '';
    const month = `<section class="att-sec"><div class="att-h"><b>📅 ${mon}월 접속 선물</b><small>이번 달 ${M.claims}회 출석 · 매달 1일 초기화</small></div>
      ${grid(M.rewards, M.claims, s.today, !M.claimed_today, `${mon}월 접속 선물`)}
      <button type="button" class="att-claim" data-att-claim="monthly" ${M.claimed_today ? 'disabled' : ''}>${M.claimed_today ? '오늘 받음 ✔' : `${M.claims + 1}회째 받기`}</button>
      <p class="att-note">출석 횟수만큼 칸이 열려요 (날짜와 상관없음) · 드링크는 거래 불가</p></section>`;
    return `<div class="att-panel" role="dialog" aria-label="출석 보상"><div class="att-top"><b>🎁 출석 보상</b><button type="button" class="att-x" data-att-x aria-label="닫기">✕</button></div>${lucky}${month}</div>`;
  }
  async function claim(track) {
    if (busy) return; busy = true;
    try {
      const r = await rpc('attend_claim', { p_track: track });
      if (r?.status?.ok) cache = r.status;
      if (r?.ok) { toast(`🎁 ${track === 'lucky' ? `행운 ${r.slot}일차` : `${r.slot}회째 출석`} · ${rwText(r.reward)}`);
        if (r.got?.wallet) window.VRPlayer?.setWallet?.(r.got.wallet); window.VRPlayer?.wallet?.(true); window.VRGem?.status?.(true); window.VRDrink?.status?.(); }
      else if (r) toast(r.reason === 'already' ? '오늘은 이미 받았어요' : r.reason === 'expired' ? '7일 간의 행운 기간이 끝났어요' : r.reason === 'done' ? '7일 간의 행운을 다 받았어요' : '받을 수 없어요');
    } catch (e) { toast(String(e?.message || e).slice(0, 60)); }
    finally { busy = false; paint(); }
  }
  function open() {
    if (!cache) return;
    let m = document.getElementById('att-pop'); if (!m) { m = document.createElement('div'); m.id = 'att-pop'; m.className = 'att-pop'; document.body.appendChild(m); }
    const draw = () => { if (!cache) return m.remove(); m.innerHTML = html(cache);
      m.querySelectorAll('[data-att-claim]').forEach(b => b.onclick = async () => { b.disabled = true; await claim(b.dataset.attClaim); draw(); }); };
    m.onclick = e => { if (e.target === m || e.target.closest('[data-att-x]')) m.remove(); };
    draw();
  }
  // 로그인 후 자동 창: 받을 게 있고, 오늘(KST) 이 계정에 아직 안 띄웠고, 동의·닉네임 창이 없고 메인 화면일 때만
  const kst = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  let autoTries = 0;
  async function auto() {
    const u = window.VRCloud?.user?.id || (window.__ATTEND_MOCK ? 'mock' : null); if (!u || off) return;
    const key = `vrAttendShown:${u}`;
    if (localStorage.getItem(key) === kst()) return;
    if (document.getElementById('consent-ov') || document.getElementById('nick-ov') || document.getElementById('att-pop') || document.getElementById('start-screen')?.classList.contains('hidden')) {
      if (++autoTries < 20) setTimeout(auto, 3000); return; }
    const s = cache || await status(); if (!s || !ready(s)) return;
    localStorage.setItem(key, kst()); open();
  }
  window.addEventListener('vr:user', () => { cache = null; autoTries = 0; setTimeout(() => status().then(auto), 1500); });
  let lastDay = null; setInterval(() => { const d = kst(); if (lastDay && d !== lastDay) status(); lastDay = d; }, 60000);
  window.VRAttend = { open, status, paint, claim, rwText, get now() { return cache; } };
  setTimeout(() => status().then(auto), 2500);
  new MutationObserver(() => { if (cache && document.querySelector('[data-attendbtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
