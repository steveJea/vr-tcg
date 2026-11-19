// ===== 점검 / 곧 오픈 모드 (서버 한 줄 플래그). 새 폴링 없음 =====
// 앱 시작, 로그인, 홈 복귀, 포커스/탭 복귀(60초에 한 번), 전투 시작 직전에만 확인.
// 켜져 있으면 전체 화면으로 막고, 관리자(admin_check)와 allow_emails 만 들어가기를 할 수 있음.
// SQL 전이거나 함수가 없으면 조용히 통과(게임은 그대로).
(() => {
  const FOCUS_GAP = 60000, NAV_GAP = 2000, CACHE_MS = 15000;
  const DEFAULT_MSG = '지금은 점검 중이에요. 잠시 후 다시 와 주세요.';
  const SOON_TITLE = '곧 오픈 / COMING SOON';
  const SOON_MSG = 'Violence Royale : The Abyss Gate 곧 오픈합니다';
  const LEGAL = [
    { href: '/about.html', label: '사업자 정보' },
    { href: '/terms.html', label: '이용약관' },
    { href: '/privacy.html', label: '개인정보처리방침' },
    { href: '/shop-info.html', label: '상품/환불 안내' }
  ];
  let lastAt = 0, inFlight = false, off = false, cached = null, cachedAt = 0, bypass = false, shown = false, pending = false, adminTold = false;

  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const missing = e => /schema cache|Could not find the function|does not exist|PGRST202/i.test(`${e?.code || ''} ${e?.message || e || ''}`);
  const inBattle = () => { const g = $('game'); return !!(g && !g.classList.contains('hidden')); };

  function isComingSoon(st) {
    if (st?.kind === 'coming_soon') return true;
    return /곧\s*오픈|coming\s*soon/i.test(`${st?.title || ''} ${st?.message || ''}`);
  }

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

  function companyHtml() {
    const c = window.VRCompany || { name: '엔터인코드', ceo: '장윤석', brn: '738-44-01302', address: '서울시 성북구 보국문로 95, 303호', phone: '070-5275-5361', mailOrderNo: '2026-서울성북-1401' };
    const mail = (c.mailOrderNo || '').trim() || '신고 준비중';
    return `<div class="mt-biz" role="contentinfo" aria-label="사업자 정보">
      <span>상호 ${esc(c.name)}</span>
      <span>대표자 ${esc(c.ceo)}</span>
      <span>사업자등록번호 ${esc(c.brn)}</span>
      <span>주소 ${esc(c.address)}</span>
      <span>전화 <a href="tel:${esc(c.phone)}">${esc(c.phone)}</a></span>
      <span>통신판매업신고번호 ${esc(mail)}</span>
    </div>`;
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
      <img class="mt-logo" src="img/ui/main/logo_v2.webp" alt="Violence Royale : The Abyss Gate">
      <h1 id="mt-title" class="mt-title">점검 중</h1>
      <p class="mt-msg" id="mt-msg"></p>
      <p class="mt-until" id="mt-until" hidden></p>
      <p class="mt-denied hidden" id="mt-denied">이 계정은 아직 입장할 수 없어요. 곧 오픈합니다.</p>
      <nav class="mt-legal" id="mt-legal" aria-label="서비스 정책">${LEGAL.map(l => `<a href="${l.href}" target="_blank" rel="noopener noreferrer">${l.label}</a>`).join('')}</nav>
      <div id="mt-foot" class="mt-foot">${companyHtml()}</div>
      <button type="button" class="main-btn mt-admin hidden" id="mt-admin">관리자로 들어가기</button>
      <button type="button" class="mt-login-toggle" id="mt-login-toggle">로그인</button>
      <div class="mt-login-box hidden" id="mt-login-box">
        <button type="button" class="main-btn" data-mt-login="google">구글 로그인</button>
        <button type="button" class="main-btn oauth-kakao hidden" data-mt-login="kakao"><img src="img/ui/kakao-symbol.svg" class="oauth-symbol" width="18" height="18" alt="">카카오 로그인</button>
        <button type="button" class="main-btn oauth-x hidden" data-mt-login="x">X 로그인</button>
        <button type="button" class="main-btn oauth-naver hidden" data-mt-login="naver"><img src="img/ui/v2/icon_naver.svg" class="oauth-symbol" width="18" height="18" alt="">네이버 로그인</button>
      </div>
    </div>`;
    document.body.appendChild(ov);
    ov.querySelector('#mt-admin').onclick = () => { bypass = true; hide(); };
    ov.querySelector('#mt-login-toggle').onclick = () => {
      const box = ov.querySelector('#mt-login-box');
      box.classList.toggle('hidden');
      paintLogin();
    };
    ov.querySelectorAll('[data-mt-login]').forEach(b => {
      b.onclick = () => window.VRCloud?.login?.(b.dataset.mtLogin);
    });
    return ov;
  }

  function paintLogin() {
    const ov = $('vr-maint'); if (!ov) return;
    const cloud = window.VRCloud;
    const can = p => { try { return !!cloud?.canLogin?.(p); } catch { return p === 'google'; } };
    ov.querySelectorAll('[data-mt-login]').forEach(b => {
      const p = b.dataset.mtLogin;
      b.classList.toggle('hidden', p !== 'google' && !can(p));
    });
    const logged = !!cloud?.user;
    ov.querySelector('#mt-login-toggle').classList.toggle('hidden', logged);
    if (logged) ov.querySelector('#mt-login-box').classList.add('hidden');
  }

  function paint(st, canEnter) {
    const ov = overlay();
    const soon = isComingSoon(st);
    ov.classList.toggle('mt-soon', soon);
    const title = (st?.title || '').trim() || (soon ? SOON_TITLE : '점검 중');
    ov.querySelector('#mt-title').textContent = title;
    ov.querySelector('#mt-msg').textContent = st?.message || (soon ? SOON_MSG : DEFAULT_MSG);
    const until = soon ? '' : kstUntil(st?.ends_at);
    const el = ov.querySelector('#mt-until');
    el.hidden = !until;
    el.textContent = until;
    ov.querySelector('#mt-legal').classList.toggle('hidden', false);
    ov.querySelector('#mt-foot').innerHTML = companyHtml();
    ov.querySelector('#mt-admin').classList.toggle('hidden', !canEnter);
    paintLogin();
  }

  function show(st, canEnter) {
    paint(st, canEnter);
    overlay().classList.remove('hidden');
    shown = true;
    pending = false;
  }
  function hide() {
    $('vr-maint')?.classList.add('hidden');
    shown = false;
  }

  function mayEnter(st) {
    return !!(st?.allowed);
  }

  async function fetchStatus(force) {
    if (off) return { on: false };
    const now = Date.now();
    if (!force && cached && now - cachedAt < CACHE_MS) return cached;
    const r = await rpc('maintenance_status');
    if (off) return { on: false };
    if (r && typeof r === 'object') {
      cached = {
        on: !!r.on,
        message: r.message || DEFAULT_MSG,
        ends_at: r.ends_at || null,
        title: r.title || '',
        kind: r.kind || '',
        allowed: !!r.allowed
      };
    } else cached = { on: false };
    cachedAt = now;
    return cached;
  }

  function apply(st, entered) {
    if (!st?.on || bypass) { hide(); return true; }
    if (entered || mayEnter(st)) {
      bypass = true;
      hide();
      if (!adminTold) {
        adminTold = true;
        const soon = isComingSoon(st);
        (window.VRGem?.toast || (() => {}))(soon ? '곧 오픈 화면을 관리자 권한으로 통과했어요.' : '지금은 점검 중이에요. 관리자라서 들어왔어요.');
      }
      return true;
    }
    if (inBattle()) { pending = true; return false; }
    show(st, false);
    if (window.VRCloud?.user) $('mt-denied')?.classList.remove('hidden');
    else $('mt-denied')?.classList.add('hidden');
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
      return apply(st, !!(st.on && st.allowed));
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

  function hookGuestLock() {
    document.addEventListener('click', e => {
      if (!shown || bypass) return;
      const t = e.target.closest?.('#intro-guest, [data-promo-go], #intro-login, #intro-login-kakao, #intro-login-x, #intro-login-naver');
      if (!t) return;
      // 게스트·홍보 시작은 막고, 인트로 로그인 버튼은 곧 오픈 화면의 로그인으로 안내
      if (t.id === 'intro-guest' || t.hasAttribute('data-promo-go')) {
        e.preventDefault();
        e.stopPropagation();
      }
    }, true);
  }

  function start() {
    hookHome(); hookBattleEnd(); hookGuestLock();
    check('start');
  }

  window.addEventListener('vr:user', () => { bypass = false; adminTold = false; cached = null; cachedAt = 0; check('start'); });
  window.addEventListener('vr:auth-providers', () => paintLogin());
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check('visible'); });
  window.addEventListener('focus', () => check('focus'));
  window.addEventListener('hashchange', () => check('nav'));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(start, 400));
  else setTimeout(start, 400);

  window.VRMaint = {
    check, ensureOk, show: (st, admin) => show(st, admin), hide, isComingSoon,
    get active() { return shown && !bypass; },
    _kstUntil: kstUntil, _apply: apply, _fetchStatus: fetchStatus,
    _setBypass: v => { bypass = !!v; }, _cached: () => cached, _off: () => off
  };
})();
