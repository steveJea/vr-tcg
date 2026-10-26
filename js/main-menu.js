// ===== 메인: 인트로(첫 방문) · 4버튼 게스트 잠금 · 게임설정 메뉴 · 공지 한 줄 · 튜토리얼(계정 Lv5 미만) =====
(() => {
  const $ = id => document.getElementById(id);
  const INTRO_KEY = 'vrTcgIntroSeen', TUT_LV = 5;
  const user = () => window.VRCloud?.user;

  // --- Y/N 확인창 (바깥 클릭 = N) ---
  function confirmYN(html) {
    return new Promise(res => {
      const m = $('vr-confirm'); $('vr-confirm-msg').innerHTML = html; m.classList.remove('hidden');
      const done = v => { m.classList.add('hidden'); m.onclick = null; res(v); };
      m.onclick = e => { const yn = e.target.closest('[data-yn]')?.dataset.yn; if (yn) done(yn === 'y'); else if (e.target === m) done(false); };
    });
  }
  const login = () => window.VRCloud?.login ? window.VRCloud.login() : alert('로그인 서버 연결 중이에요. 잠시 뒤 다시 눌러 주세요.');

  // --- 인트로: 처음 방문(로그인 안 됨)일 때만 ---
  const intro = $('intro');
  async function showIntro() {
    intro.classList.remove('hidden');
    try {   // 영상 슬롯 (data/intro.json: pc 16:9 · mobile 9:16 mp4, 비우면 이미지)
      const cfg = await (await fetch('data/intro.json', { cache: 'no-cache' })).json();
      const mq = matchMedia('(orientation: portrait), (max-aspect-ratio: 4/5)');
      const v = $('intro-video');
      v.muted = true; v.loop = true; v.playsInline = true;
      const pick = () => { const src = mq.matches ? cfg.mobile : cfg.pc, poster = mq.matches ? cfg.mobilePoster : cfg.pcPoster;
        if (!src) { v.classList.add('hidden'); v.removeAttribute('src'); return; }
        if (v.getAttribute('src') !== src) {
          if (poster) { v.poster = poster; v.classList.remove('hidden'); }   // 포스터 먼저 → 영상. 실패하면 배경 이미지
          v.preload = 'auto'; v.src = src; v.onerror = () => v.classList.add('hidden'); v.oncanplay = () => v.classList.remove('hidden'); v.play().catch(() => {}); } };
      pick(); mq.addEventListener?.('change', pick);
    } catch {}
  }
  const hideIntro = () => { localStorage.setItem(INTRO_KEY, '1'); intro.classList.add('hidden'); const v = $('intro-video'); v.pause(); };
  $('intro-login').onclick = () => { localStorage.setItem(INTRO_KEY, '1'); login(); };
  $('intro-guest').onclick = async () => {
    if (await confirmYN('<b>게스트는 아케이드만</b> 플레이할 수 있어요.<br>카드 수집·소환은 할 수 없어요.<div class="vc-q">그래도 게스트로 하시겠어요?</div>')) hideIntro();
  };
  if (localStorage.getItem(INTRO_KEY) !== '1' && !/[?&]code=|access_token=/.test(location.search + location.hash)) {
    // 이미 로그인된 세션이면 바로 메인
    let n = 0; const wait = () => { if (window.VRCloud?.ready || n++ > 30) { user() ? localStorage.setItem(INTRO_KEY, '1') : showIntro(); } else setTimeout(wait, 100); };
    wait();
  }

  // --- 게스트 잠금: 아케이드 외 버튼 → 로그인 확인 ---
  const paintLocks = () => {
    const guest = !user();
    document.querySelectorAll('.main-tile[data-auth]').forEach(b => b.classList.toggle('guest-lock', guest));
  };
  document.querySelectorAll('.main-tile[data-auth]').forEach(b => b.addEventListener('click', async e => {
    if (user()) return;
    e.stopImmediatePropagation(); e.preventDefault();
    if (await confirmYN('로그인하시겠어요?')) login();
  }, true));
  // 로그아웃하면 인트로(로그인/게스트 선택)를 다시 보여 줌
  let hadUser = !!user();
  window.addEventListener('vr:user', () => {
    paintLocks(); paintTut();
    const now = !!user();
    if (hadUser && !now) { localStorage.removeItem(INTRO_KEY); showIntro(); }
    hadUser = now;
  });

  // --- 게임설정 메뉴 ---
  const gear = $('main-settings'), pop = $('main-menu-pop');
  const close = () => { pop.classList.add('hidden'); gear.setAttribute('aria-expanded', 'false'); };
  gear.addEventListener('click', e => { e.stopPropagation(); pop.classList.toggle('hidden'); gear.setAttribute('aria-expanded', String(!pop.classList.contains('hidden'))); paintTut(); });
  pop.addEventListener('click', e => { if (e.target === pop || e.target.closest('[data-close-menu]')) return close(); if (e.target.closest('.gm-btn')) close(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
  $('main-settings-open').addEventListener('click', () => setTimeout(() => window.VRSettings?.open(), 0));
  $('main-tutorial').addEventListener('click', () => { const go = (n = 0) => window.TCG?.POOL?.length ? window.HowTo?.Tutorial.start() : n < 50 && setTimeout(() => go(n + 1), 200); go(); });

  // --- 튜토리얼: 계정 레벨 5 미만 (게스트 포함) ---
  async function paintTut() {
    let lv = 0; try { lv = user() ? ((await window.VRPlayer?.status?.())?.level ?? 0) : 0; } catch {}
    $('main-tutorial').classList.toggle('hidden', lv >= TUT_LV);
  }

  // --- 공지 한 줄 (data/notice.json, 흐르는 글자) ---
  fetch('data/notice.json', { cache: 'no-cache' }).then(r => r.json()).then(d => {
    const items = (d.items || []).filter(Boolean); if (!items.length) return;
    const t = $('notice-text'); t.textContent = items.join('   ·   ');
    t.style.animationDuration = `${Math.max(10, t.textContent.length * 0.28)}s`;
    $('notice-line').classList.remove('hidden');
  }).catch(() => {});

  paintLocks(); paintTut();
  let tries = 0; const poll = setInterval(() => { paintLocks(); if (window.VRCloud?.ready || ++tries > 40) clearInterval(poll); }, 250);
  window.VRMainMenu = { confirmYN, showIntro, hideIntro };
})();
