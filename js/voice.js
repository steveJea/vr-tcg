// 캐릭터 보이스 한곳 관리: 화면이 바뀌면 재생 중인 보이스를 바로 멈춤 (BGM·효과음은 대상 아님)
(() => {
  const set = new Set();
  const RATE = 1.15;   // 보이스 재생 속도 (음높이 유지). 여기만 바꾸면 전부 적용
  function rate(a) { try { a.preservesPitch = a.mozPreservesPitch = a.webkitPreservesPitch = true; a.defaultPlaybackRate = window.VRVoice.RATE; a.playbackRate = window.VRVoice.RATE; } catch {} }
  function track(a) {
    if (!a || a._vrVoice) return a; a._vrVoice = true; rate(a);
    // 목록에는 있어도 배포/네트워크 문제로 일본어 파일이 실패하면 기본 보이스로 한 번 재시도.
    a.addEventListener('error', () => {
      const m = (a.getAttribute?.('src') || a.src || '').match(/(?:^|\/)data\/voice\/ja\/([0-9]+_[0-9g]+)\.mp3$/);
      if (!m) return;
      const resume = !a.paused; a.src = `data/voice/${m[1]}.mp3`;
      if (resume) a.play()?.catch?.(() => {});
    });
    if (!a.paused) set.add(a);
    a.addEventListener('loadedmetadata', () => rate(a));   // load() 때 속도가 기본값으로 돌아가는 브라우저 대비
    a.addEventListener('play', () => { a._vt = performance.now(); set.add(a); rate(a); });
    // 재생 중인 것만 들고 있음: 끝나거나 멈추면 집합에서 빼서 오래 켜 둬도 쌓이지 않게 (다시 재생하면 다시 들어옴)
    const off = () => set.delete(a);
    ['pause', 'ended', 'error', 'abort', 'emptied'].forEach(ev => a.addEventListener(ev, off));
    return a;
  }
  /** minAge(ms): 그보다 최근에 시작한 보이스는 남김 (화면 전환과 같은 순간 시작한 새 화면 보이스 보호) */
  function stopAll(minAge = 0) {
    const now = performance.now();
    for (const a of set) { try { if (!a.paused && now - (a._vt || 0) >= minAge) { a.pause(); a.currentTime = 0; } } catch {} }
  }
  // 보이스 언어 (게임설정 → 설정 → 보이스 언어): 'en' = 기본 파일 data/voice/<key>.mp3, 'ja' = data/voice/ja/<key>.mp3
  // 보이스 파일 경로는 전부 path() 하나로 (전투·등장·가챠·UR 확대·도감). 일본어 파일이 없는 줄은 기본 파일로 재생
  const LANG_KEY = 'vrTcgVoiceLang', LANGS = ['en', 'ja'], subs = new Set();
  let lang = 'en'; try { if (localStorage.getItem(LANG_KEY) === 'ja') lang = 'ja'; } catch {}
  let jaSet = null, jaP = null;
  function loadJa() {
    if (!jaP) jaP = (typeof fetch === 'function' ? fetch('data/voice/ja/index.json').then(r => r.ok ? r.json() : []) : Promise.resolve([]))
      .then(a => { jaSet = new Set(Array.isArray(a) ? a : []); }).catch(() => { jaSet = new Set(); });
    return jaP;
  }
  const emit = () => { for (const f of subs) { try { f(lang); } catch {} } };
  function path(k) { return lang === 'ja' && jaSet?.has(k) ? `data/voice/ja/${k}.mp3` : `data/voice/${k}.mp3`; }
  /** 언어 바꾸기: 재생 중 보이스 멈춤 → 저장 → (일본어면 목록 받은 뒤) 구독자에게 알림 = 캐시 비우기 */
  function setLang(l) {
    l = LANGS.includes(l) ? l : 'en'; if (l === lang) return Promise.resolve(lang);
    lang = l; try { localStorage.setItem(LANG_KEY, l); } catch {}
    stopAll(); emit();   // 바로 캐시 비움 (목록 다운로드 중에도 이전 언어가 재생되지 않게)
    return (l === 'ja' ? loadJa() : Promise.resolve()).then(() => { if (lang === l) emit(); return lang; });
  }
  function onLang(f) { subs.add(f); return () => subs.delete(f); }
  if (lang === 'ja') loadJa().then(() => { if (lang === 'ja') emit(); });   // 첫 로드: 목록 오기 전에 만든 기본 파일 캐시는 비움
  window.VRVoice = { RATE, track, stopAll, path, setLang, onLang, LANGS, get lang() { return lang; }, get jaReady() { return !!jaSet; }, get jaCount() { return jaSet ? jaSet.size : 0; } };
  const SCREENS = ['intro', 'start-screen', 'game', 'story-screen'];
  const onChange = () => stopAll(150);
  function watch() {
    const mo = new MutationObserver(muts => { if (muts.some(m => m.type === 'childList' || (m.oldValue || '').includes('hidden') !== m.target.classList.contains('hidden'))) onChange(); });
    for (const id of SCREENS) { const el = document.getElementById(id); if (el) mo.observe(el, { attributes: true, attributeFilter: ['class'], attributeOldValue: true }); }
    const ss = document.getElementById('story-screen'); if (ss) mo.observe(ss, { childList: true });   // 스토리 화면 전환 = 내용 통째 교체
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watch); else watch();
  addEventListener('hashchange', () => stopAll());
  addEventListener('popstate', () => stopAll());
  addEventListener('pagehide', () => stopAll());
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopAll(); });
})();
