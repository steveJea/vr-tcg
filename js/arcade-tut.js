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
  const GKEY = 'vrArcTut:guest';
  const key = () => window.VRCloud?.user?.id ? `vrArcTut:${window.VRCloud.user.id}` : GKEY;
  const load = () => { try { return JSON.parse(localStorage.getItem(key()) || '{}') || {}; } catch { return {}; } };
  const save = o => { try { localStorage.setItem(key(), JSON.stringify(o)); } catch {} };
  const cleared = n => !!load()[n];
  const unlocked = st => st.ready && (st.n === 1 || cleared(st.n - 1));
  // 첫 클리어 보상 (서버 supabase/arcade_tut.sql + arcade_tut_gem.sql · 계정당 단계별 1회): 초급 영입권 10 · 중급 심연석 100 · 상급 심연석 300. 로그인 안 하면 안내만
  const REWARD = { 1: { kind: 'tickets', n: 10 }, 2: { kind: 'gem', n: 100 }, 3: { kind: 'gem', n: 300 } };
  const CUR = { tickets: { icon: '🎟️', name: '영입권', unit: '장' }, gem: { icon: '🔮', name: '심연석', unit: '개' } };
  const rwLabel = (n, plus) => { const r = REWARD[n], c = CUR[r.kind]; return `${c.icon} ${c.name} ${plus ? '+' : ''}${r.n}`; };
  const sumText = list => Object.entries(list.reduce((o, r) => (o[r.kind] = (o[r.kind] || 0) + r.n, o), {})).map(([k, v]) => `${CUR[k].icon} ${CUR[k].name} +${v}`).join(' · ');
  const sb = () => window.VRCloud?.user ? window.VRCloud.sb : null;
  let srv = null;   // { claimed:[n] } · false = 서버 함수 없음
  async function status() { const c = sb(); if (!c) return null; try { const { data, error } = await c.rpc('arcade_tut_status'); if (error) throw error; srv = data; return data; } catch { srv = false; return null; } }
  const claimedSrv = n => !!srv?.claimed?.includes(n);
  async function claim(n) {
    const c = sb(); if (!c) return { login: true };
    try { const { data, error } = await c.rpc('arcade_tut_claim', { p_stage: n }); if (error) throw error; if (data?.ok !== true) throw new Error('reward verification pending'); srv = { ...(srv || {}), claimed: [...new Set([...(srv?.claimed || []), n])] }; try { if (data?.kind === 'gem') window.VRGem?.status?.(true); else if (data?.tickets != null) window.dispatchEvent(new CustomEvent('vr:tickets', { detail: { tickets: data.tickets } })); } catch {} return data; }
    catch (e) { return { error: String(e?.message || e) }; }
  }
  const rewardText = (r, n) => r.login ? `게스트 클리어 기록은 저장됐어요. 로그인하면 첫 클리어 보상 ${rwLabel(n)}${CUR[REWARD[n].kind].unit}${REWARD[n].kind === 'gem' ? '를' : '을'} 받아요` : r.error ? (/reward verification pending/.test(r.error) ? '지급 보류' : /previous/.test(r.error) ? '앞 단계 보상을 먼저 받아야 해요' : '보상은 잠시 뒤 다시 받을 수 있어요 (단계 목록에서 받기)') : r.already ? '보상은 이미 받았어요' : r.kind === 'gem' ? `🔮 심연석 +${r.gave}${r.gem != null ? ` (보유 ${r.gem})` : ''}` : `🎟️ 영입권 +${r.gave}${r.tickets != null ? ` (보유 ${r.tickets})` : ''}`;
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
        <b>${st.name}</b><span>${st.title}</span><i>${done ? '✔ 클리어' : !st.ready ? '준비 중' : ok ? '도전' : '🔒 앞 단계 클리어'} · 첫 클리어 ${rwLabel(st.n)}${claimedSrv(st.n) ? ' (받음)' : ''}</i></button>
        ${done && srv && !claimedSrv(st.n) ? `<button class="yt-claim" data-claim="${st.n}" ${srv.reward_held ? 'disabled' : ''}>${srv.reward_held ? '지급 보류' : `${rwLabel(st.n)} 받기`}</button>` : ''}`;
    }).join('');
    panel(`<div class="yt-head"><img src="${FACE}" alt=""><div><b>유리의 특강</b><p>${cleared(1) ? '또 왔어? 복습은 칭찬해 줄게.' : '하… 아케이드도 모르면서 들어온 거야? 언니가 알려줄게.'}</p></div></div>
      <div class="yt-list">${rows}</div><small class="yt-note">정해진 덱으로 진행 · 아케이드 전적에 기록되지 않아요</small>`,
      async e => { const c = e.target.closest('[data-claim]'); if (c) { c.disabled = true; const r = await claim(+c.dataset.claim); c.textContent = rewardText(r, +c.dataset.claim); if (!r.error) setTimeout(open, 1400); return; }
        const b = e.target.closest('[data-st]'); if (b && !b.disabled) play(+b.dataset.st); });
    if (srv === null && sb()) status().then(d => { if (d && ov && document.querySelector('.yt-list')) open(); });
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
      ${win && !window.VRCloud?.user ? `<button class="yt-login" data-login>로그인하면 ${rwLabel(st.n)}${CUR[REWARD[st.n].kind].unit} 받기</button>` : ''}
      <div class="yt-btns">${win && next && unlocked(next) ? `<button data-go="${next.n}" class="yt-main">${next.name} 도전</button>` : ''}${win ? '' : `<button data-go="${st.n}" class="yt-main">다시 하기</button>`}<button data-list>단계 목록</button><button data-x>닫기</button></div>`,
      e => { if (e.target.closest('[data-login]')) { close(); return login(); } const g = e.target.closest('[data-go]'); if (g) return play(+g.dataset.go); if (e.target.closest('[data-list]')) open(); });
    if (win) claim(st.n).then(r => { const el = ov?.querySelector('.yt-reward'); if (el) el.textContent = rewardText(r, st.n); });
    try { window.dispatchEvent(new CustomEvent('vr:arcade-tut', { detail: { stage: st.n, win: !!win, first } })); } catch {}
  }
  // 게스트 → 로그인: 게스트로 깬 단계를 계정 기록으로 옮기고, 첫 클리어 보상을 순서대로 받음 (서버가 단계별 1회만 지급)
  function login() { if (window.VRCloud?.login) window.VRCloud.login(); else (window.VRGem?.toast || alert)('로그인 서버 연결 중이에요. 잠시 뒤 다시 눌러 주세요.'); }
  let migrating = false;
  async function migrateGuest() {
    const u = window.VRCloud?.user; if (!u || migrating) return;
    let g; try { g = JSON.parse(localStorage.getItem(GKEY) || '{}') || {}; } catch { g = {}; }
    const stages = Object.keys(g).map(Number).filter(n => REWARD[n]).sort((a, b) => a - b); if (!stages.length) return;
    migrating = true;
    try {
      const mine = load(); for (const n of stages) mine[n] = 1; save(mine);
      const got = []; let fail = false;
      for (const n of [1, 2, 3].filter(n => mine[n])) {   // 계정에 이미 있던 클리어도 포함 (앞 단계부터)
        const r = await claim(n);
        if (r.error) { fail = true; break; }
        if (r.gave) got.push({ kind: r.kind || REWARD[n].kind, n: r.gave });
      }
      if (!fail) localStorage.removeItem(GKEY);   // 실패하면 남겨 두고 다음 로그인·새로고침 때 다시
      if (got.length) (window.VRGem?.toast || (t => console.log(t)))(`📖 유리의 특강 게스트 클리어 보상: ${sumText(got)}`);
    } finally { migrating = false; }
  }
  window.addEventListener('vr:user', () => { if (window.VRCloud?.user && ov?.querySelector('.yt-promo')) close(); setTimeout(migrateGuest, 800); });   // 로그인하면 홍보 창 닫기 + 게스트 보상
  if (window.VRCloud?.user) setTimeout(migrateGuest, 1500);

  // 첫 방문 게스트 홍보 창: 로그인 안 한 방문자에게 크게. 세션당 한 번 · '다시 보지 않기' 또는 로그인하면 더 안 뜸
  const PROMO_KEY = 'vrYuriPromoOff', PROMO_SS = 'vrYuriPromoShown';
  function promo(force) {
    if (!force && (localStorage.getItem(PROMO_KEY) === '1' || sessionStorage.getItem(PROMO_SS) === '1' || window.VRCloud?.user)) return;
    try { sessionStorage.setItem(PROMO_SS, '1'); } catch {}
    panel(`<div class="yt-promo"><img class="yt-promo-img" src="https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/10325.webp" alt="임유리">
      <b class="yt-promo-t">📖 유리의 특강</b>
      <p>"하… 아케이드도 모르면서 들어온 거야? 언니가 딱 한 번만 알려줄게."</p>
      <ul><li>로그인 없이 바로 플레이</li><li>초급 · 중급 · 상급 3단계, 마지막엔 MR 카드로 싹 쓸어버리기</li><li>로그인하면 첫 클리어 보상 🎟️ 영입권 10장 + 🔮 심연석 최대 400개</li></ul>
      <button class="yt-main yt-promo-go" data-promo-go>바로 시작 (게스트)</button>
      <label class="yt-promo-off"><input type="checkbox" data-promo-off> 다시 보지 않기</label></div>`,
      e => { if (e.target.closest('[data-promo-go]')) { offIf(); play(1); } });
    const offIf = () => { if (ov?.querySelector('[data-promo-off]')?.checked) localStorage.setItem(PROMO_KEY, '1'); };
    ov.addEventListener('click', e => { if (e.target === ov || e.target.closest('[data-x]')) offIf(); }, true);
  }
  // 메인 화면이 보이고(인트로·전투·스토리 아님) 로그인 상태를 안 뒤에만
  (function waitMain(n = 0) {
    const vis = id => { const e = document.getElementById(id); return e && !e.classList.contains('hidden') && e.offsetParent !== null; };
    const ready = window.VRCloud?.ready || n > 60;
    if (ready && window.TCG?.ready && localStorage.getItem('vrTcgIntroSeen') === '1' && !vis('intro') && !vis('game') && !(window.VRPages?.depth > 0) && !document.querySelector('.hub-ov, #story-screen:not(.hidden), #vr-confirm:not(.hidden), #story-dlg')) return promo();
    if (n < 600) setTimeout(() => waitMain(n + 1), 500);
  })();
  window.VRArcadeTut = { _end: (n, win = true) => end(STAGES[n - 1], win), promo: () => promo(true), migrateGuest, open, play, STAGES, cleared, reset: () => save({}) };
})();
