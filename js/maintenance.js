// ===== 점검 모드 (서버 한 줄 플래그). 새 폴링 없음 =====
// 앱 시작, 로그인, 홈 복귀, 포커스/탭 복귀(60초에 한 번), 전투 시작 직전에만 확인.
// 켜져 있으면 전체 화면으로 막고, 관리자(admin_check)만 들어가기를 할 수 있음. SQL 전이면 조용히 통과.
(() => {
  const FOCUS_GAP = 60000, NAV_GAP = 2000, CACHE_MS = 15000;
  const DEFAULT_MSG = '지금은 점검 중이에요. 잠시 후 다시 와 주세요.';
  let lastAt = 0, inFlight = false, off = false, cached = null, cachedAt = 0, bypass = false, shown = false, pending = false, adminTold = false;

  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const missing = e => /schema cache|Could not find the function|does not exist|PGRST202/i.test(`${e?.code || ''} ${e?.message || e || ''}`);
  const inBattle = () => { const g = $('game'); return !!(g && !g.classList.contains('hidden')); };

  function kstUntil(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime()) || d.getTime() <= Date.now()) return '';
    const p = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Seoul', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
    }).formatToParts(d);
    const g = t => p.find(x => x.type === t)?.value;
    return `${g('year')}년 ${g('month')}월 ${g('day')}일 ${g('hour')}:${g('minute')}까지`;
  }

  async function rpc(fn, args) {
    const mk = window.__MAINT_MOCK; if (mk) return mk(fn, args);
    const sb = window.VRCloud?.sb; if (!sb) return null;
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) { if (missing(error)) off = true; return null; }
    return data;
  }

  function overlay() {
    let ov = $('vr-maint');
    if (ov) return ov;
    ov = document.createElement('div');
    ov.id = 'vr-maint';
    ov.className = 'mt-ov hidden';
    ov.setAttribute('role', 'dialog');
    ov.setAttribute('aria-modal', 'true');
    ov.setAttribute('aria-labelledby', 'mt-title');
    ov.innerHTML = `<div class="mt-card" data-clarity-mask="true">
      <img class="mt-logo" src="img/ui/main/logo.webp" alt="">
      <h1 id="mt-title" class="mt-title">점검 중</h1>
      <p class="mt-msg" id="mt-msg"></p>
      <p class="mt-until" id="mt-until" hidden></p>
      <button type="button" class="main-btn mt-admin hidden" id="mt-admin">관리자로 들어가기</button>
    </div>`;
    document.body.appendChild(ov);
    ov.querySelector('#mt-admin').onclick = () => { bypass = true; hide(); };
    return ov;
  }

  function paint(st, isAdmin) {
    const ov = overlay();
    ov.querySelector('#mt-msg').textContent = st?.message || DEFAULT_MSG;
    const until = kstUntil(st?.ends_at);
    const el = ov.querySelector('#mt-until');
    el.hidden = !until;
    el.textContent = until;
    ov.querySelector('#mt-admin').classList.toggle('hidden', !isAdmin);
  }

  function show(st, isAdmin) {
    paint(st, isAdmin);
    overlay().classList.remove('hidden');
    shown = true;
    pending = false;
  }
  function hide() {
    $('vr-maint')?.classList.add('hidden');
    shown = false;
  }

  async function isAdmin() {
    if (!window.VRCloud?.user) return false;
    try {
      const r = await rpc('admin_check');
      return !!r?.admin;
    } catch { return false; }
  }

  async function fetchStatus(force) {
    if (off) return { on: false };
    const now = Date.now();
    if (!force && cached && now - cachedAt < CACHE_MS) return cached;
    const r = await rpc('maintenance_status');
    if (off) return { on: false };
    cached = r && typeof r === 'object' ? { on: !!r.on, message: r.message || DEFAULT_MSG, ends_at: r.ends_at || null } : { on: false };
    cachedAt = now;
    return cached;
  }

  function apply(st, admin) {
    if (!st?.on || bypass) { hide(); return true; }
    if (admin) {
      hide();
      if (!adminTold) {
        adminTold = true;
        (window.VRGem?.toast || (() => {}))('지금은 점검 중이에요. 관리자라서 들어왔어요.');
      }
      return true;
    }
    if (inBattle()) { pending = true; return false; }
    show(st, false);
    return false;
  }

  async function check(kind, { force = false } = {}) {
    if (off) return true;
    if ((kind === 'focus' || kind === 'visible') && document.hidden) return true;
    const now = Date.now();
    const gap = (kind === 'focus' || kind === 'visible') ? FOCUS_GAP : (kind === 'start' || kind === 'battle') ? 0 : NAV_GAP;
    if (!force && gap && now - lastAt < gap) return !(shown && !bypass);
    if (inFlight && kind !== 'battle') return !(shown && !bypass);
    inFlight = true; lastAt = now;
    try {
      const st = await fetchStatus(kind === 'battle' || force);
      const admin = st.on ? await isAdmin() : false;
      if (admin && st.on) bypass = true;
      return apply(st, admin);
    } finally { inFlight = false; }
  }

  async function ensureOk() {
    const ok = await check('battle', { force: true });
    if (ok) return true;
    show(cached || { on: true, message: DEFAULT_MSG }, false);
    return false;
  }

  function hookHome() {
    const scr = $('start-screen'); if (!scr || typeof MutationObserver !== 'function') return;
    let was = !scr.classList.contains('hidden');
    new MutationObserver(() => {
      const vis = !scr.classList.contains('hidden');
      if (vis && !was) {
        if (pending && cached?.on && !bypass) show(cached, false);
        else check('home');
      }
      was = vis;
    }).observe(scr, { attributes: true, attributeFilter: ['class'] });
  }

  function hookBattleEnd() {
    const g = $('game'); if (!g || typeof MutationObserver !== 'function') return;
    new MutationObserver(() => {
      if (pending && cached?.on && !bypass && !inBattle()) show(cached, false);
    }).observe(g, { attributes: true, attributeFilter: ['class'] });
  }

  function start() {
    hookHome(); hookBattleEnd();
    check('start');
  }

  window.addEventListener('vr:user', () => { bypass = false; adminTold = false; cached = null; cachedAt = 0; check('start'); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check('visible'); });
  window.addEventListener('focus', () => check('focus'));
  window.addEventListener('hashchange', () => check('nav'));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(start, 400));
  else setTimeout(start, 400);

  window.VRMaint = {
    check, ensureOk, show: (st, admin) => show(st, admin), hide,
    get active() { return shown && !bypass; },
    _kstUntil: kstUntil, _apply: apply, _fetchStatus: fetchStatus,
    _setBypass: v => { bypass = !!v; }, _cached: () => cached, _off: () => off
  };
})();
