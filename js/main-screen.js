// ===== 메인 화면: 불씨 파티클 + 배경음악 =====
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const screen = document.getElementById('start-screen');

  // --- 세로 화면 배경 영상: 세로일 때만 src를 넣어 데스크톱은 다운로드하지 않음 ---
  const vid = document.getElementById('main-video');
  const portraitMq = matchMedia('(orientation: portrait), (max-aspect-ratio: 4/5)');
  const syncVideo = () => {
    if (!vid || reduce) return;                 // 동작 줄이기: 영상 대신 정지 이미지
    if (portraitMq.matches) {
      if (!vid.dataset.loaded) {
        vid.dataset.loaded = '1';
        vid.innerHTML = '<source src="video/main-portrait.webm" type="video/webm"><source src="video/main-portrait.mp4" type="video/mp4">';
        vid.load();
      }
      vid.classList.remove('hidden');
      vid.play().catch(() => {});
    } else { vid.classList.add('hidden'); vid.pause(); }
  };
  syncVideo();
  portraitMq.addEventListener?.('change', syncVideo);
  // 게임 화면으로 가면 영상 정지, 돌아오면 재생
  new MutationObserver(() => { if (!vid?.dataset.loaded) return; screen.classList.contains('hidden') ? vid.pause() : syncVideo(); }).observe(screen, { attributes: true, attributeFilter: ['class'] });

  // --- 불씨 파티클 (가벼운 canvas) ---
  const cv = document.getElementById('embers');
  if (cv && !reduce) {
    const ctx = cv.getContext('2d');
    let W = 0, H = 0, dpr = Math.min(2, window.devicePixelRatio || 1);
    const resize = () => { W = cv.clientWidth; H = cv.clientHeight; cv.width = W * dpr; cv.height = H * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); };
    resize(); addEventListener('resize', resize);
    const N = Math.round(Math.min(70, (W * H) / 18000));
    const mk = (init) => ({ x: Math.random() * W, y: init ? Math.random() * H : H + 10, r: 0.6 + Math.random() * 2.2, vy: 0.25 + Math.random() * 0.8, vx: (Math.random() - 0.5) * 0.3, ph: Math.random() * 6.28, life: 0.4 + Math.random() * 0.6 });
    const ps = Array.from({ length: N }, () => mk(true));
    const tick = () => {
      if (!screen.classList.contains('hidden') && !document.hidden) {
        ctx.clearRect(0, 0, W, H);
        ctx.globalCompositeOperation = 'lighter';
        for (const p of ps) {
          p.y -= p.vy; p.ph += 0.03; p.x += p.vx + Math.sin(p.ph) * 0.35;
          if (p.y < -10) Object.assign(p, mk(false));
          const a = Math.max(0, Math.min(1, p.y / H)) * p.life;
          const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 4);
          g.addColorStop(0, `rgba(255, 200, 120, ${a})`); g.addColorStop(0.4, `rgba(239, 68, 68, ${a * 0.5})`); g.addColorStop(1, 'rgba(120, 0, 0, 0)');
          ctx.fillStyle = g; ctx.beginPath(); ctx.arc(p.x, p.y, p.r * 4, 0, 6.283); ctx.fill();
        }
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  // --- 배경음악: audio/main.mp3 (없으면 조용히 무시) ---
  const KEY = 'vrTcgSound';
  let soundOn = localStorage.getItem(KEY) !== '0';
  let audio = null, missing = false;
  // 덕킹: 스킬 보이스가 나오는 동안 BGM을 기본 볼륨의 35%로 부드럽게(200ms) 낮춤
  const DUCK = 0.35, FADE = 200;
  let baseVol = 0.5, ducked = false, fadeRaf = 0;
  const fadeTo = (target) => {
    cancelAnimationFrame(fadeRaf);
    if (!audio) return;
    const from = audio.volume, t0 = performance.now();
    const step = (t) => { if (!audio) return; const k = Math.min(1, (t - t0) / FADE); audio.volume = Math.min(1, Math.max(0, from + (target - from) * k)); if (k < 1) fadeRaf = requestAnimationFrame(step); };
    fadeRaf = requestAnimationFrame(step);
  };
  const duck = (on) => { on = !!on; if (on === ducked) return; ducked = on; fadeTo(baseVol * (ducked ? DUCK : 1)); };
  const setVolume = (v) => { baseVol = Math.min(1, Math.max(0, +v || 0)); fadeTo(baseVol * (ducked ? DUCK : 1)); };
  const btn = document.getElementById('main-sound');
  const renderBtn = () => { if (btn) { btn.textContent = soundOn ? '🔊' : '🔇'; btn.classList.toggle('on', soundOn); btn.title = missing ? '배경음악 파일 없음 (audio/main.mp3)' : '배경음악 켜기/끄기'; } };
  const getAudio = () => {
    if (audio || missing) return audio;
    audio = new Audio(src); audio.loop = true; audio.volume = baseVol * (ducked ? DUCK : 1); audio.preload = 'auto';
    const el = audio; audio.addEventListener('error', () => { if (audio !== el || !el.getAttribute('src')) return; missing = true; audio = null; renderBtn(); });
    return audio;
  };
  // 트랙 전환(크로스페이드): 스토리 모드 장면별 BGM. 덕킹·음소거·볼륨 설정은 그대로 적용
  let src = 'audio/main.mp3', xfRaf = 0;
  const setTrack = (next, ms = 900) => {
    if (!next || next === src) return;
    src = next;
    const old = audio; audio = null; missing = false;
    cancelAnimationFrame(fadeRaf); cancelAnimationFrame(xfRaf);
    const a = getAudio(); if (!a) return;
    a.volume = 0;
    const target = () => baseVol * (ducked ? DUCK : 1);
    if (soundOn && !held) a.play().catch(() => {});
    const v0 = old ? old.volume : 0, t0 = performance.now();
    const step = t => { const k = Math.min(1, Math.max(0, (t - t0) / ms));
      if (old) old.volume = Math.max(0, v0 * (1 - k));
      if (audio === a) a.volume = Math.min(1, target() * k);
      if (k < 1) xfRaf = requestAnimationFrame(step); else if (old) { old.pause(); old.removeAttribute('src'); old.load(); } };
    xfRaf = requestAnimationFrame(step);
  };
  // 일시 정지 유지(오프닝 영상 등): hold(true) 동안은 재생·트랙 전환 시 자동 재생을 막고, hold(false) 로 다시 재생
  let held = false;
  const play = () => { if (!soundOn || held) return; const a = getAudio(); if (a) a.play().catch(() => {}); };
  const stop = () => { if (audio) audio.pause(); };
  const hold = (on) => { held = !!on; held ? stop() : play(); };
  btn?.addEventListener('click', e => { e.stopPropagation(); soundOn = !soundOn; localStorage.setItem(KEY, soundOn ? '1' : '0'); soundOn ? play() : stop(); renderBtn(); });
  // 브라우저 자동재생 정책: 첫 사용자 입력 후 재생
  const first = () => { play(); removeEventListener('pointerdown', first); removeEventListener('keydown', first); };
  addEventListener('pointerdown', first); addEventListener('keydown', first);
  renderBtn();
  window.VRSound = { play, stop, hold, duck, setVolume, setTrack, get track() { return src; }, get held() { return held; }, get paused() { return !audio || audio.paused; }, get on() { return soundOn; }, get ducked() { return ducked; }, get volume() { return audio ? audio.volume : null; }, get baseVolume() { return baseVol; } };
})();
