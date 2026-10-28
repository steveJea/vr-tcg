// ===== 도움말 [?] : 메뉴별 짧은 설명 (화면 안 안내 문구를 여기로 모음). 바깥 누르면 닫힘 =====
(() => {
  const H = [
    ['arcade', '🎴', '아케이드', ['랜덤 덱으로 바로 붙는 대전', '마나로 소환 → 공격 → 진영 HP 0이면 승리', '등급·턴 룰은 게임설정에서']],
    ['story', '📜', '스토리', ['챕터 · 페이즈 진행, 클리어하면 인재와 스탯 포인트', '페이즈 1회 = 행동력 6 (패배·포기 시 반환) · 6분에 1 회복', '리더를 출전시켜야 리더 스킬이 켜져요']],
    ['gacha', '✨', '인재영입', ['일반: 하루 1회 (한국 시간 자정 초기화)', '프리미엄: 소환권 1장 = 1회 · 10회는 HR 이상 1명 보장', '소환권은 챕터 첫 클리어 · 심연석으로']],
    ['cards', '🧑‍🤝‍🧑', '내 인재', ['같은 인재가 여러 명이면 합성(EX) 재료 · 분해하면 재화', '합성: 둘 다 최대 레벨이면 +10%', '레벨업: 순수한 피 + 골드']],
    ['tower', '🗼', '시련의 탑', ['보유 인재로 한 층씩 도전 · 행동력 없음', '보스층은 직접 도전, 나머지는 소탕 가능']],
    ['pvp', '⚔️', 'PvP', ['내 덱 vs 상대 방어 덱 자동 전투', '이기면 점수 · 티어 보상']],
    ['guild', '🩸', '조직', ['집결: 하루 1번 출석, 많이 모이면 단계 보상', '의뢰: 일일 3개 + 주간 · 하루 1번 교체', '충성: 스토리·PvP로 세력을 올리면 쌓임 → 조직 상점']],
    ['raid', '🐉', '균열 토벌', ['하루 3회 · 조직이 함께 보스 HP를 깎아요', '일요일 22:00 정산 · 순위/참여 보상은 정산 24시간 전 가입자만', '난이도는 이번 주 첫 토벌 전까지만 변경']],
    ['war', '🏴', '구역 전쟁', ['매달 셋째 수~일 · 09:00~23:00 · 하루 1경기', '신청: 셋째 주 일~화 · 보스가 21칸 배치 (빈 칸 = 자동 · 남으면 동네 불량배)',
      '방어조 5곳을 먼저 부숴야 나머지 공격 가능 · 하루 공격 5회', '역할 버프: 방어조 방어 +20% · 돌격조 공격 +20% · 중간보스 +15% · 보스 +25%',
      '파괴 점수: 방어 200 · 돌격/조직원 150 · 중간보스 250 · 보스 400 · 보스 격파 = 즉시 승리', '방어 덱 2개(목숨 +1)는 시즌 시작에 잠김 · 1·2번 덱에 같은 인재 불가', '참가: 조직원은 각자 [참가 신청] · 보스는 신청 안 한 조직원도 배치 가능 (✔ = 신청, ! = 방어 덱 없음)',
      '<span class="vh-c" style="--c:#f59e0b"></span>방어조 <span class="vh-c" style="--c:#ef4444"></span>돌격조 <span class="vh-c" style="--c:#a855f7"></span>중간보스 <span class="vh-c" style="--c:#facc15"></span>보스 <span class="vh-c" style="--c:#3b82f6"></span>조직원']],
    ['mypage', '👤', '마이페이지', ['리더 · 재화 · 기록 · 덱', '스토리 카드를 누르면 바로 스토리 맵']],
  ];
  function open(key) {
    document.getElementById('vr-help')?.remove();
    const m = document.createElement('div'); m.id = 'vr-help'; m.className = 'vh-pop';
    m.innerHTML = `<div class="vh-panel" role="dialog" aria-label="도움말"><button class="vh-x" data-x aria-label="닫기">✕</button><div class="vh-h">도움말</div>
      <div class="vh-tabs">${H.map(([k, ic, t]) => `<button data-k="${k}">${ic}<span>${t}</span></button>`).join('')}</div><div class="vh-body"></div></div>`;
    const body = m.querySelector('.vh-body');
    const show = k => { const h = H.find(x => x[0] === k) || H[0]; m.querySelectorAll('[data-k]').forEach(b => b.classList.toggle('on', b.dataset.k === h[0]));
      body.innerHTML = `<div class="vh-t">${h[1]} ${h[2]}</div><ul>${h[3].map(x => `<li>${x}</li>`).join('')}</ul>`; };
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) return m.remove(); const b = e.target.closest('[data-k]'); if (b) show(b.dataset.k); });
    document.body.appendChild(m); show(key);
  }
  const css = document.createElement('style');
  css.textContent = `.main-q b{font:900 22px/1 serif;color:#f5c96a;text-shadow:0 1px 3px #000}
.vh-q{width:28px;height:28px;border-radius:50%;border:1px solid rgba(245,201,106,.6);color:#f5c96a;font-weight:900;background:rgba(0,0,0,.55);line-height:1}.wr-q{position:absolute;right:84px;bottom:8px;z-index:2}
.vh-c{display:inline-block;width:11px;height:11px;border-radius:50%;background:var(--c);margin:0 3px 0 6px;vertical-align:-1px;border:1px solid rgba(255,255,255,.5)}
.vh-pop{position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:14px}
.vh-panel{position:relative;width:min(440px,100%);max-height:86vh;overflow:auto;background:linear-gradient(#1c0a0e,#0b0305);border:1px solid rgba(245,201,106,.45);border-radius:16px;padding:14px;color:#f4f4f5}
.vh-x{position:absolute;right:10px;top:8px;font-size:18px;opacity:.7}.vh-h{font-weight:900;font-size:17px;color:#f5c96a;margin-bottom:8px}
.vh-tabs{display:grid;grid-template-columns:repeat(5,1fr);gap:5px;margin-bottom:10px}.vh-tabs button{display:flex;flex-direction:column;align-items:center;gap:2px;padding:6px 2px;border-radius:10px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);font-size:18px}
.vh-tabs button span{font-size:10px;font-weight:700}.vh-tabs button.on{border-color:#f5c96a;background:rgba(245,201,106,.15)}
.vh-t{font-weight:900;margin-bottom:6px}.vh-body ul{display:flex;flex-direction:column;gap:6px;font-size:13px;line-height:1.45}.vh-body li{padding:7px 9px;border-radius:9px;background:rgba(255,255,255,.05)}`;
  document.head.appendChild(css);
  window.VRHelp = { open, items: H };
})();
