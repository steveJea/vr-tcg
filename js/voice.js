// 캐릭터 보이스 한곳 관리: 화면이 바뀌면 재생 중인 보이스를 바로 멈춤 (BGM·효과음은 대상 아님)
(() => {
  const set = new Set();
  function track(a) {
    if (!a || a._vrVoice) return a; a._vrVoice = true; set.add(a);
    a.addEventListener('play', () => { a._vt = performance.now(); });
    return a;
  }
  /** minAge(ms): 그보다 최근에 시작한 보이스는 남김 (화면 전환과 같은 순간 시작한 새 화면 보이스 보호) */
  function stopAll(minAge = 0) {
    const now = performance.now();
    for (const a of set) { try { if (!a.paused && now - (a._vt || 0) >= minAge) { a.pause(); a.currentTime = 0; } } catch {} }
  }
  window.VRVoice = { track, stopAll };
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
