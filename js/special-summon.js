// 스페셜 소환 (이벤트 픽업): 서버 RPC special_summon_status / special_summon_draw (supabase/special_summon_staging.sql)
// 확률 단위는 만분율(10000 = 100%). 서버 special_banners 가 기준이고 아래 CONFIG 는 서버가 아직 없을 때 화면 안내용.
(() => {
  const GRADES = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE'];
  const RAR = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR' };
  const GLOW = { 'NORMAL': 'n', 'RARE': 'r', 'HIGH RARE': 'hr', 'SUPER RARE': 'sr', 'ULTRA RARE': 'ur' };
  /** 첫 스페셜 배너 (SQL insert 와 같아야 함 · tools/test_special_summon.mjs 가 확인) */
  const CONFIG = {
    banner_id: 'hajihye-20261113', pickup_id: '10440', pickup_name: '하지혜',
    starts_at: '2026-11-13T00:00:00+09:00', ends_at: null, pity: 50,
    rates: { 'NORMAL': 5000, 'RARE': 3000, 'HIGH RARE': 1000, 'SUPER RARE': 800, pickup: 100, other_ur: 100 },
  };
  /** 프리미엄 UR 목록 (supabase/gacha_premium_ur.sql story_premium_ur 와 같아야 함). 스페셜 "그 외 UR" = 이 목록 − 픽업 */
  const PREMIUM_UR = ['10051', '10053', '10054', '10058', '10176', '10312', '10323', '10324', '10325', '10331', '10358'];
  let status = null, missing = false;
  const cloud = () => window.VRCloud;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const isMissing = e => /could not find|does not exist|PGRST202|schema cache|404/i.test(`${e?.code || ''} ${e?.message || ''}`);
  const banner = () => status?.banner || { ...CONFIG, open: false };
  async function refresh() {
    if (window.__SPECIAL_MOCK) { status = await window.__SPECIAL_MOCK.status(); missing = !status?.ok; return status; }
    const sb = cloud()?.sb, u = cloud()?.user;
    if (!sb || !u) { status = null; missing = false; return null; }
    try {
      const { data, error } = await sb.rpc('special_summon_status', { p_banner: null });
      if (error) { missing = isMissing(error); status = null; return null; }
      missing = !data?.ok; status = data?.ok ? data : null; return status;
    } catch { status = null; return null; }
  }
  async function draw(n) {
    if (window.__SPECIAL_MOCK) { const r = await window.__SPECIAL_MOCK.draw(n); if (r?.ok && status) Object.assign(status, { tickets: r.tickets, misses: r.misses }); return r; }
    const sb = cloud()?.sb, u = cloud()?.user;
    if (!sb || !u) return { ok: false, reason: 'error', msg: '로그인이 필요해요' };
    const { data, error } = await sb.rpc('special_summon_draw', { p_banner: banner().banner_id, p_count: n });
    if (error) { if (isMissing(error)) { missing = true; return { ok: false, reason: 'preparing' }; } return { ok: false, reason: 'error', msg: error.message }; }
    if (data?.ok && status) Object.assign(status, { tickets: data.tickets, misses: data.misses });
    else if (data?.tickets != null && status) status.tickets = data.tickets;
    return data || { ok: false, reason: 'error' };
  }
  // ----- 확률 공개 -----
  const pct = p => `${+(p * 100).toFixed(4)}%`;
  /** 등급별 인재 목록: 서버 목록 우선, 없으면 게임 데이터(참고) */
  function pools() {
    const by = {}, ur = [];
    if (status?.pool) { for (const c of status.pool) (by[c.grade] ||= []).push(c); for (const c of status.premium_ur || []) ur.push(c); return { by, ur, server: true }; }
    const all = window.TCG?.POOL || [];
    for (const c of all) if (GRADES.includes(c.grade)) (by[c.grade] ||= []).push({ id: String(c.id), name: c.name });
    for (const id of PREMIUM_UR) { const c = window.TCG?.cardById?.(id) || all.find(x => String(x.id) === id); ur.push({ id, name: c?.name || id }); }
    return { by, ur, server: false };
  }
  /** 한 소환 종류의 표. gr = [[grade|label, rate(0~1), members[], key]] */
  function table(title, rows, note) {
    const head = `<div class="sp-rate-grades">${rows.map(([g, p, , lbl]) => `<span class="g-text-${GLOW[g] || 'ur'}">${esc(lbl || RAR[g])}</span><b>${pct(p)}</b>`).join('')}</div>`;
    const each = rows.map(([g, p, ms, lbl]) => ms.length ? `<div class="sp-rate-sec"><div class="sp-rate-h g-text-${GLOW[g] || 'ur'}">${esc(lbl || RAR[g])} ${pct(p)} · ${ms.length}명 · 1명당 ${pct(p / ms.length)}</div><div class="sp-rate-names">${ms.map(m => esc(m.name)).join(', ')}</div></div>` : '').join('');
    return `<details class="sp-rate-box"><summary><b>${esc(title)}</b>${head}</summary>${note ? `<div class="sp-rate-note">${note}</div>` : ''}${each}</details>`;
  }
  function ratesHtml() {
    const G = window.STORY_DATA?.gacha || {}, P = pools(), b = banner();
    const grades5 = [...GRADES, 'ULTRA RARE'];
    const std = (rates) => grades5.map((g, i) => [g, rates?.[i] || 0, g === 'ULTRA RARE' ? P.ur : (P.by[g] || [])]);
    const r = b.rates || CONFIG.rates, pick = { id: b.pickup_id, name: b.pickup_name || CONFIG.pickup_name };
    const sp = [...GRADES.map(g => [g, (r[g] || 0) / 10000, P.by[g] || []]),
      ['ULTRA RARE', (r.pickup || 0) / 10000, [pick], `UR 픽업 ${pick.name}`],
      ['ULTRA RARE', (r.other_ur || 0) / 10000, P.ur.filter(c => c.id !== pick.id), 'UR (픽업 외)']];
    const end = b.ends_at ? new Date(b.ends_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' }) + ' (KST)' : '종료일 미정';
    return `<div class="sp-rates"><div class="text-lg font-black mb-2">확률 안내</div>
      ${table(`스페셜 소환 · 픽업 ${pick.name}`, sp, `스페셜 소환권 1장 = 1회 · 10회 = 10장<br>천장: 픽업 없이 ${b.pity || CONFIG.pity}회째 소환은 <b>${esc(pick.name)}</b> 확정 (픽업을 얻으면 횟수 초기화 · 배너별 · 서버 기록)<br>기간: ${new Date(b.starts_at || CONFIG.starts_at).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' })} ~ ${esc(end)}`)}
      ${table('프리미엄 소환', std(G.special), '소환권 1장 = 1회 · 10회 소환은 HR 이상 1장 보장 · UR은 프리미엄 UR 목록에서만')}
      ${table('일반 소환 (하루 1회 무료)', std(G.rates), '매일 자정(KST) 초기화 · UR은 프리미엄 UR 목록에서만')}
      <div class="sp-rate-note">${P.server ? '인재 목록은 서버 기준입니다.' : '인재 목록은 게임 데이터 기준(참고)입니다. 로그인하면 서버 목록을 보여 줘요.'} 각 표를 누르면 인재별 확률이 보여요.</div>
      <button data-sp-close class="w-full mt-2 py-2 rounded-xl bg-white/10">닫기</button></div>`;
  }
  async function showRates() {
    if (!status && !window.__SPECIAL_MOCK) await refresh().catch(() => {});
    let m = document.getElementById('sp-rates-pop');
    if (!m) { m = document.createElement('div'); m.id = 'sp-rates-pop'; document.body.appendChild(m); }
    m.className = 'sp-rates-pop';
    m.innerHTML = `<div class="story-pop-panel sp-rates-panel" role="dialog" aria-label="확률 안내">${ratesHtml()}</div>`;
    const close = () => m.remove();
    m.onclick = e => { if (e.target === m || e.target.closest('[data-sp-close]')) close(); };
    m.querySelector('details')?.setAttribute('open', '');
  }
  window.VRSpecial = { CONFIG, PREMIUM_UR, refresh, draw, showRates, ratesHtml, banner, get status() { return status; }, get missing() { return missing; },
    get tickets() { return status ? status.tickets | 0 : null; }, get misses() { return status ? status.misses | 0 : 0; } };
})();
