// ===== 유리의 특강: 아케이드 튜토리얼 (초급 · 중급 · 상급) =====
// 단계 = data/tutorials/arcade_<n>.json : 가이드 단계(steps) + 전투 대본(arcade). 전투는 TCG.startArcadeTut (js/game.js)
// 진행: localStorage vrArcTut:<user> = { "1": 1, … } (클리어한 단계). 앞 단계를 깨야 다음 단계가 열림 · 다시 하기 자유
(() => {
  const STAGES = [
    { n: 1, id: 'arcade_1', name: '초급', title: '기본도 모르면 나가 죽어', ready: true },
    { n: 2, id: 'arcade_2', name: '중급', title: '마나 없으면 넌 그냥 개미야', ready: true },
    { n: 3, id: 'arcade_3', name: '상급', title: '이 정도면 언니랑 놀 자격 있네', ready: true },
  ];
  const FACE = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/10325.webp';
  const key = () => `vrArcTut:${window.VRCloud?.user?.id || 'guest'}`;
  const load = () => { try { return JSON.parse(localStorage.getItem(key()) || '{}') || {}; } catch { return {}; } };
  const save = o => { try { localStorage.setItem(key(), JSON.stringify(o)); } catch {} };
  const cleared = n => !!load()[n];
  const unlocked = st => st.ready && (st.n === 1 || cleared(st.n - 1));
  let ov = null;
  const close = () => { ov?.remove(); ov = null; };
  function panel(html, onClick) {
    close();
    ov = document.createElement('div'); ov.id = 'yuri-tut'; ov.className = 'hub-ov yt-ov';
    ov.innerHTML = `<div class="hub-page yt-page" role="dialog" aria-label="유리의 특강"><button class="hub-x" data-x aria-label="닫기">✕</button>${html}</div>`;
    ov.addEventListener('click', e => { if (e.target === ov || e.target.closest('[data-x]')) return close(); onClick?.(e); });
    document.body.appendChild(ov);
  }
  function open() {
    const rows = STAGES.map(st => {
      const ok = unlocked(st), done = cleared(st.n);
      return `<button class="yt-st ${done ? 'done' : ''}" data-st="${st.n}" ${ok ? '' : 'disabled'}>
        <b>${st.name}</b><span>${st.title}</span><i>${done ? '✔ 클리어' : !st.ready ? '준비 중' : ok ? '도전' : '🔒 앞 단계 클리어'}</i></button>`;
    }).join('');
    panel(`<div class="yt-head"><img src="${FACE}" alt=""><div><b>유리의 특강</b><p>${cleared(1) ? '또 왔어? 복습은 칭찬해 줄게.' : '하… 아케이드도 모르면서 들어온 거야? 언니가 알려줄게.'}</p></div></div>
      <div class="yt-list">${rows}</div><small class="yt-note">정해진 덱으로 진행 · 아케이드 전적에 기록되지 않아요</small>`,
      e => { const b = e.target.closest('[data-st]'); if (b && !b.disabled) play(+b.dataset.st); });
  }
  async function play(n) {
    const st = STAGES.find(x => x.n === n); if (!st || !unlocked(st)) return;
    let def; try { const r = await fetch(`data/tutorials/${st.id}.json`, { cache: 'no-cache' }); def = await r.json(); } catch { return; }
    const A = def.arcade, C = id => window.TCG.cardById(id), L = a => (a || []).map(C).filter(Boolean);
    close(); window.VRArcadeHub?.close?.();
    window.TCG.startArcadeTut({ ...A, tutorial: st.id, me: L(A.me), aiField: L(A.aiField), aiDeck: L(A.aiDeck), aiGuard: A.aiGuard ? C(A.aiGuard) : null, mercs: L(A.mercs),
      onEnd: (win, reason) => end(st, win, reason) });
  }
  function end(st, win) {
    try { window.VRSound?.setTrack?.('audio/main.mp3'); } catch {}
    document.getElementById('start-screen')?.classList.remove('hidden');
    const first = win && !cleared(st.n);
    if (win) { const o = load(); o[st.n] = 1; save(o); }
    const next = STAGES.find(x => x.n === st.n + 1);
    const say = win ? (st.n === 3 ? '…봤어? 이게 아케이드야. 이제 혼자 해 봐. 지면 웃어줄게~' : '흥, 이 정도는 개미도 해. 다음 거나 해.') : '…진짜? 정해진 덱으로 졌다고? 다시 해.';
    panel(`<div class="yt-head"><img src="${FACE}" alt=""><div><b>${st.name} ${win ? '클리어!' : '실패'}</b><p>${say}</p></div></div>
      <div class="yt-reward" data-reward="${st.n}" data-first="${first ? 1 : 0}"></div>
      <div class="yt-btns">${win && next && unlocked(next) ? `<button data-go="${next.n}" class="yt-main">${next.name} 도전</button>` : ''}${win ? '' : `<button data-go="${st.n}" class="yt-main">다시 하기</button>`}<button data-list>단계 목록</button><button data-x>닫기</button></div>`,
      e => { const g = e.target.closest('[data-go]'); if (g) return play(+g.dataset.go); if (e.target.closest('[data-list]')) open(); });
    try { window.dispatchEvent(new CustomEvent('vr:arcade-tut', { detail: { stage: st.n, win: !!win, first } })); } catch {}
  }
  window.VRArcadeTut = { open, play, STAGES, cleared, reset: () => save({}) };
})();
