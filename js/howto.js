// ===== How to Play (슬라이드 가이드) + 첫 게임 튜토리얼 =====
// 게임 로직과 분리: window.TCG(game.js)만 읽고, 오버레이는 클릭을 막지 않음.
(() => {
  const $ = id => document.getElementById(id);
  const TUT_KEY = 'vrTutorialDone';      // '1'이면 첫 방문 튜토리얼 제안 안 함
  const SLIDES = [
    { icon: '🎯', title: '목표와 승리 조건', lines: [
      '상대 진영 <b>HP 3000</b>을 0으로 만들면 승리!',
      '각자 <b>20턴(총 40턴)</b>이 끝나면 진영 HP → 남은 필드 카드 수로 판정, 같으면 무승부',
      '선공은 동전 던지기, 후공은 시작 손패 +1장'] },
    { icon: '💧', img: 'img/howto/hud.webp', title: '마나', lines: [
      '첫 턴 <b>40</b>, 이후 매 턴 <b>+20</b>, 최대 <b>100</b> (남은 마나는 이월)',
      '카드 소환·상점·아이템·회수에 써요',
      '적 카드를 처치하면 즉시 <b>코스트 × 0.3</b> 마나'] },
    { icon: '🃏', title: '카드 내기', lines: [
      '손패 카드를 눌러 <b>소환하기</b> → 코스트만큼 마나 사용',
      '필드는 최대 <b>5장</b>, 소환한 턴에는 공격할 수 없어요',
      '상대 필드에 ✨빛 카드가 있으면 💀심연 카드는 소환 불가'] },
    { icon: '⚔️', img: 'img/howto/field.webp', title: '공격하기', lines: [
      '초록 테두리 카드를 누르고 → 적 카드나 상대 진영을 눌러 공격 (일괄 공격 버튼도 있어요)',
      '카드끼리 싸우면 <b>반격</b>을 받고, 처치하면 남은 피해가 진영으로 넘어가요',
      '진영 공격 불가: 내 <b>첫 2턴</b> · 상대 필드 <b>4장 이상</b> · 🎯도발 카드가 있을 때'] },
    { icon: '✦', title: '레벨 · 스킬 · MP', lines: [
      '공격·처치·턴 생존으로 XP를 얻어 최대 <b>Lv10 👑</b>까지 성장 (ATK·HP 상승)',
      '스킬은 <b>해금 레벨</b>에 도달하면 열려요. 액티브는 공격 대신 <b>MP</b>를 써서 사용 (쿨타임 있음)',
      '패시브는 자동 적용 · MP(파란 바)는 마나💧와 별개'] },
    { icon: '💎', title: '등급과 속성', lines: [
      '등급: <b>N · R · HR · SR · UR</b>, 아주 가끔 <b>MR</b>(진영 피해는 20%만)',
      '🔥불 → 🌪️바람 → ❄️얼음 → 🔥불 유리 ×1.5 / 불리 ×0.75',
      '✨빛 ↔ 🌑어둠 ×2 · 💀심연은 모두에게 ×1.25, 단 빛에게 ×2 피해'] },
    { icon: '🔗', title: '시너지와 조합', lines: [
      '같은 속성 <b>2/3/4/5장</b> → 그 속성 ATK·DEF <b>+10/15/20/30%</b>',
      '지정된 카드가 모두 내 필드에 있으면 <b>🔗조합</b> 발동',
      '발동 중인 효과는 진영 바 아래 배지로 보여요'] },
    { icon: '🏪', img: 'img/howto/shop.webp', title: '상점 (마나 액션)', lines: [
      '🔀패 섞기 50 · 🏰기지 보강 20(HP +200) · ⚔️공격력 강화 30(이번 턴 ATK +20%) · 💚필드 회복 20(최대 HP 10%)',
      '⚙️마나 가속기 30: 다음 턴부터 매 턴 마나 +5, 최대 5회',
      '가속기 말고는 <b>턴당 1번</b> · 필드 카드 장비: 🗡️무기·🛡️방어구 각 30'] },
    { icon: '🗡️', title: '용병 고용', lines: [
      '<b>🗡️ 용병 고용</b> 버튼(마나 액션 줄)에서 마나로 <b>HR·SR·UR</b> 카드를 고용 (N·R·MR은 없음)',
      '가격: 기본 코스트 × HR 1.2 · SR 1.5 · UR 1.8 (올림). 목록은 판마다 랜덤 3장',
      '<b>한 판에 1명</b>, 이번 판 내 덱·손패·필드에 이미 있는 카드는 고용 불가. 고용한 카드는 손패로 오고 <b>그 판에서만</b> 써요 (판이 끝나면 리셋)'] },
    { icon: '🩸', title: '희생과 회수', lines: [
      '<b>희생</b>: 필드 카드를 없애고 코스트의 <b>50%</b>를 마나로 (턴당 1번)',
      '<b>회수</b>: 코스트의 50% 마나를 내고 손패로 → HP 회복, 레벨·XP·아이템 초기화',
      '⚡마비·🌀교란 상태인 카드는 회수할 수 없어요'] },
    { icon: '🌀', title: '상태 이상', lines: [
      '⚡<b>마비</b>: 행동 불가 · 💫<b>혼란</b>: 아군을 공격 · 🌀<b>교란</b>: 자기 진영을 공격',
      '🩸출혈 · 🎯도발(먼저 맞아야 함) · 🔰피해 면역 · 🔒고유기술 봉인(상점 일부 불가)',
      '카드를 누르면 상세 정보와 스킬 설명을 볼 수 있어요'] },
    { icon: '💡', title: '팁', lines: [
      '행동할 카드가 남았는데 턴 종료를 누르면 한 번 더 물어봐요',
      '🎬 연출 버튼으로 공격 연출 생략, 연출 중 화면을 누르면 빨리 감기',
      '자세한 규칙은 게임 중 <b>?</b> 버튼에서 언제든 확인!'] },
  ];

  // ---------- 슬라이드 ----------
  let idx = 0, built = false;
  function build() {
    if (built) return; built = true;
    const ov = document.createElement('div');
    ov.id = 'howto'; ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-label', 'How to Play');
    ov.innerHTML = `<div class="ht-panel">
      <div class="ht-head"><span>HOW TO PLAY · <span id="ht-num"></span></span><button class="ht-x" aria-label="닫기">✕</button></div>
      <div class="ht-view"><div class="ht-track">${SLIDES.map(s => `<section class="ht-slide">
        ${s.img ? `<img class="ht-shot" src="${s.img}" alt="" onerror="this.remove()">` : `<div class="ht-icon">${s.icon}</div>`}
        <div class="ht-title">${s.icon} ${s.title}</div><ul class="ht-lines">${s.lines.map(l => `<li>${l}</li>`).join('')}</ul></section>`).join('')}</div></div>
      <button class="ht-tut">🎓 튜토리얼로 첫 게임 해보기</button>
      <div class="ht-foot"><button class="ht-arrow ht-prev" aria-label="이전">◀</button><div class="ht-dots">${SLIDES.map((_, i) => `<button aria-label="${i + 1}번 슬라이드" data-i="${i}"></button>`).join('')}</div><button class="ht-arrow ht-next" aria-label="다음">▶</button></div>
    </div>`;
    document.body.appendChild(ov);
    ov.querySelector('.ht-x').onclick = close;
    ov.querySelector('.ht-prev').onclick = () => go(idx - 1);
    ov.querySelector('.ht-next').onclick = () => idx >= SLIDES.length - 1 ? close() : go(idx + 1);
    ov.querySelectorAll('.ht-dots button').forEach(b => b.onclick = () => go(+b.dataset.i));
    ov.querySelector('.ht-tut').onclick = () => { close(); waitReady(() => Tutorial.start()); };
    let downBg = false;
    ov.addEventListener('pointerdown', e => { downBg = e.target === ov; });
    ov.addEventListener('click', e => { if (downBg && e.target === ov) close(); downBg = false; });
    // 터치/마우스 스와이프
    const view = ov.querySelector('.ht-view'), track = ov.querySelector('.ht-track');
    let x0 = null, y0 = 0, dx = 0;
    view.addEventListener('pointerdown', e => { x0 = e.clientX; y0 = e.clientY; dx = 0; });
    view.addEventListener('pointermove', e => { if (x0 == null) return; dx = e.clientX - x0; if (Math.abs(dx) > Math.abs(e.clientY - y0)) { track.style.transition = 'none'; track.style.transform = `translateX(calc(${-idx * 100}% + ${dx}px))`; } });
    const up = () => { if (x0 == null) return; track.style.transition = ''; x0 = null; const w = view.clientWidth || 1; if (dx < -w * 0.18) go(idx + 1); else if (dx > w * 0.18) go(idx - 1); else go(idx); dx = 0; };
    view.addEventListener('pointerup', up); view.addEventListener('pointercancel', up); view.addEventListener('pointerleave', up);
    document.addEventListener('keydown', e => {
      if (!ov.classList.contains('open')) return;
      if (e.key === 'Escape') { e.stopPropagation(); close(); }
      else if (e.key === 'ArrowRight') go(idx + 1); else if (e.key === 'ArrowLeft') go(idx - 1);
    }, true);
  }
  function go(i) {
    idx = Math.max(0, Math.min(SLIDES.length - 1, i));
    const ov = $('howto');
    ov.querySelector('.ht-track').style.transform = `translateX(${-idx * 100}%)`;
    ov.querySelectorAll('.ht-dots button').forEach((b, j) => b.classList.toggle('on', j === idx));
    ov.querySelector('.ht-prev').disabled = idx === 0;
    ov.querySelector('.ht-next').textContent = idx === SLIDES.length - 1 ? '✓' : '▶';
    $('ht-num').textContent = `${idx + 1}/${SLIDES.length}`;
  }
  function open(i = 0) { build(); $('tut-offer')?.remove(); $('howto').classList.add('open'); go(i); }
  function close() { $('howto')?.classList.remove('open'); }

  // ---------- 튜토리얼 ----------
  const STEPS = [
    { sel: '#ai-hero', title: '상대 진영', text: '상대 진영 HP를 0으로 만들면 이겨요. 각자 20턴이 끝나면 HP가 많은 쪽이 승리!' },
    { sel: '#me-hero', title: '내 진영과 마나 💧', text: '아래쪽 💧마나로 카드를 내요. 첫 턴 40, 매 턴 +20, 최대 100. 오른쪽 위는 내 턴 남은 횟수예요.' },
    { sel: '#me-hand', title: '카드 내기 🃏', text: '손패 카드를 누르고 "소환하기"를 눌러보세요. 흐린 카드는 지금 낼 수 없는 카드예요.' },
    { sel: '#me-field', title: '내 필드', text: '소환한 카드는 다음 내 턴부터 공격할 수 있어요. 공격 가능한 카드는 초록 테두리로 표시돼요.' },
    { sel: '#ai-field', title: '공격하기 ⚔️', text: '내 카드를 누른 뒤 적 카드나 상대 진영을 누르면 공격! 진영 공격 가능 여부는 가운데 안내 문구로 알려줘요.' },
    { sel: '#me-field', title: '스킬 사용 ✦', text: '레벨이 올라 스킬이 해금되고 MP가 차면 카드 아래 "✦스킬" 버튼이 생겨요. 액티브 스킬은 그 턴 공격 대신 써요.' },
    { sel: '#action-bar', title: '상점 🏪', text: '마나로 패 섞기, 기지 보강, 공격력 강화, 필드 회복, 마나 가속기를 살 수 있어요. 가속기 말고는 턴당 1번!' },
    { sel: '#end-turn', title: '턴 종료', text: '할 일을 다 했으면 턴 종료! 행동할 카드가 남아 있으면 한 번 더 물어봐요.' },
    { sel: '#help-btn', title: '도움말', text: '규칙이 헷갈리면 언제든 ? 버튼! How to Play도 여기서 다시 볼 수 있어요. 이제 직접 싸워보세요 💪' },
  ];
  const Tutorial = {
    i: -1, timer: null,
    start() {
      try {
        const T = window.TCG;
        if (!T) return;
        if (!T.S || T.S.over || $('game').classList.contains('hidden')) T.startGame();
        this.ensureDom(); this.i = 0; this.show();
        clearInterval(this.timer); this.timer = setInterval(() => this.place(), 400);
        addEventListener('resize', this.onResize ||= () => this.place());
        addEventListener('scroll', this.onResize, true);
      } catch (e) { this.end(); (window.TCG_ERRORS ||= []).push('tutorial: ' + e.message); }
    },
    ensureDom() {
      if ($('tut-spot')) return;
      const spot = document.createElement('div'); spot.id = 'tut-spot';
      const box = document.createElement('div'); box.id = 'tut-box'; box.setAttribute('role', 'dialog');
      box.innerHTML = `<div class="tt-step"></div><div class="tt-title"></div><div class="tt-text"></div>
        <div class="tt-btns"><label><input type="checkbox" class="tt-noask accent-amber-400"> 다시 보지 않기</label>
        <button class="tt-skip bg-zinc-700">건너뛰기</button><button class="tt-next bg-amber-400 text-black">다음</button></div>`;
      document.body.append(spot, box);
      box.querySelector('.tt-skip').onclick = () => this.end();
      box.querySelector('.tt-next').onclick = () => { this.i++; this.i >= STEPS.length ? this.end() : this.show(); };
      document.addEventListener('keydown', e => { if (e.key === 'Escape' && this.i >= 0 && !document.querySelector('#detail.flex,#help.flex,#endturn-confirm.flex,#howto.open,#zoom-view.open,#end-screen:not(.hidden)')) this.end(); }, true);
    },
    show() {
      const s = STEPS[this.i], box = $('tut-box');
      box.querySelector('.tt-step').textContent = `튜토리얼 ${this.i + 1}/${STEPS.length}`;
      box.querySelector('.tt-title').textContent = s.title;
      box.querySelector('.tt-text').textContent = s.text;
      box.querySelector('.tt-next').textContent = this.i === STEPS.length - 1 ? '시작!' : '다음';
      const el = document.querySelector(s.sel);
      try { el?.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch {}
      this.place();
    },
    place() {
      try {
        const spot = $('tut-spot'), box = $('tut-box');
        if (!spot || this.i < 0) return;
        // 모달(카드 상세 등)이 열리면 잠시 숨김 → 게임 조작 방해 안 함
        const modal = document.querySelector('#detail.flex,#help.flex,#endturn-confirm.flex,#end-screen:not(.hidden),#howto.open,#zoom-view.open');
        if (modal) { spot.style.display = box.style.display = 'none'; return; }
        box.style.display = 'block';
        const el = document.querySelector(STEPS[this.i].sel), r = el?.getBoundingClientRect();
        if (!r || !r.width) { spot.style.display = 'none'; box.style.top = '40%'; box.style.bottom = ''; return; }
        const p = 6;
        Object.assign(spot.style, { display: 'block', left: r.left - p + 'px', top: r.top - p + 'px', width: r.width + p * 2 + 'px', height: r.height + p * 2 + 'px' });
        const below = r.top + r.height / 2 < innerHeight / 2;
        if (below) { box.style.top = Math.min(innerHeight - box.offsetHeight - 8, r.bottom + 14) + 'px'; }
        else { box.style.top = Math.max(8, r.top - box.offsetHeight - 14) + 'px'; }
      } catch {}
    },
    end() {
      try {
        clearInterval(this.timer); this.timer = null;
        if (this.onResize) { removeEventListener('resize', this.onResize); removeEventListener('scroll', this.onResize, true); }
        const box = $('tut-box');
        if (box?.querySelector('.tt-noask')?.checked || this.i >= STEPS.length) localStorage.setItem(TUT_KEY, '1');
      } finally {
        this.i = -1;
        $('tut-spot')?.style.setProperty('display', 'none');
        $('tut-box')?.style.setProperty('display', 'none');
      }
    },
    get active() { return this.i >= 0; },
  };

  // ---------- 버튼 연결 + 첫 방문 제안 ----------
  function offer() {
    if (localStorage.getItem(TUT_KEY) === '1' || $('tut-offer')) return;
    const d = document.createElement('div'); d.id = 'tut-offer';
    d.innerHTML = `<div class="font-black">처음 오셨나요? 👋</div><div class="text-xs text-zinc-300 mt-1">튜토리얼로 첫 게임을 따라 해보세요</div>
      <div class="row"><button data-a="tut" class="bg-emerald-500 text-black">🎓 튜토리얼</button><button data-a="howto" class="bg-amber-400 text-black">📖 How to Play</button></div>
      <div class="row"><button data-a="no" class="bg-zinc-700 text-zinc-200 text-xs">다시 보지 않기</button></div>`;
    $('start-screen').appendChild(d);
    d.onclick = e => {
      const a = e.target.closest('button')?.dataset.a; if (!a) return;
      d.remove();
      if (a === 'no') localStorage.setItem(TUT_KEY, '1');
      else if (a === 'howto') open();
      else waitReady(() => Tutorial.start());
    };
  }
  function waitReady(fn, n = 0) { if (window.TCG?.POOL?.length) fn(); else if (n < 50) setTimeout(() => waitReady(fn, n + 1), 200); }
  $('main-howto')?.addEventListener('click', () => open());
  $('help-howto')?.addEventListener('click', () => { $('help').classList.add('hidden'); $('help').classList.remove('flex'); open(); });
  offer();
  window.HowTo = { open, close, go, get index() { return idx; }, SLIDES, STEPS, Tutorial };
})();
