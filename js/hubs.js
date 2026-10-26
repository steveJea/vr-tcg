// ===== 아케이드 허브: 게임플레이 · 아케이드 랭킹 · 내 전적 (바깥 클릭·Esc로 닫힘) =====
(() => {
  const $ = id => document.getElementById(id);
  let ov = null;
  const rec = () => { try { return window.TCG?.Stats?.load?.() || { wins: 0, losses: 0, draws: 0 }; } catch { return { wins: 0, losses: 0, draws: 0 }; } };
  function close() { ov?.remove(); ov = null; }
  function open() {
    close();
    const s = rec(), n = (s.wins | 0) + (s.losses | 0) + (s.draws | 0), rate = n ? Math.round((s.wins | 0) / n * 100) : 0;
    ov = document.createElement('div'); ov.id = 'arcade-hub'; ov.className = 'hub-ov';
    ov.innerHTML = `<div class="hub-page" role="dialog" aria-label="아케이드">
      <button class="hub-x" data-x aria-label="닫기">✕</button>
      <div class="hub-hero"><img src="img/ui/v2/arcade_banner.webp" alt=""><b>아케이드</b></div>
      <div class="hub-rec" title="아케이드 전적${window.VRCloud?.user ? ' · 클라우드 저장' : ''}">
        <div><b>${s.wins | 0}</b><small>승</small></div><div><b>${s.losses | 0}</b><small>패</small></div><div><b>${s.draws | 0}</b><small>무</small></div><div><b>${rate}%</b><small>승률</small></div></div>
      <div class="hub-acts">
        <button class="hub-big" data-a="play"><img src="img/ui/battle.webp" alt=""><span>게임플레이</span></button>
        <button class="hub-big" data-a="rank"><img src="img/ui/v2/icon_ranking.webp" alt=""><span>아케이드 랭킹</span></button></div>
      <button class="hub-sub" data-a="opts"><img src="img/ui/v2/icon_arcade_settings.webp" alt="" class="ui-ic"> 아케이드 설정</button>
    </div>`;
    ov.addEventListener('click', e => {
      if (e.target === ov || e.target.closest('[data-x]')) return close();
      const a = e.target.closest('[data-a]')?.dataset.a; if (!a) return;
      if (a === 'play') { close(); window.TCG?.startGame?.(); }
      else if (a === 'rank') window.VRRanking?.open();
      else if (a === 'opts') window.TCG?.openArcadeOpts?.();
    });
    document.body.appendChild(ov);
  }
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && ov && !document.querySelector('#rank-ov.on')) close(); });
  // 메인 아케이드 버튼(#start-btn): 바로 시작 대신 허브를 연다
  const bind = () => { const b = $('start-btn'); if (!b || b.dataset.hub) return; b.dataset.hub = '1';
    b.addEventListener('click', e => { if (b.disabled) return; e.stopImmediatePropagation(); e.preventDefault(); open(); }, true); };
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', bind) : bind();
  window.VRArcadeHub = { open, close };
})();
