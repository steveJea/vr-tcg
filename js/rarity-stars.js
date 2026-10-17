// ===== 등급 별 표시 (카드 확대/상세 보기 전용, 모바일 필드 작은 카드에는 안 붙임) =====
// N=1 · R=2 · HR=3 · SR=4 · UR=5 · MR=6
// LR(레전드리 레어) 추가 시 STARS에 'LEGENDARY RARE': 7, LR: 7 만 넣으면 됨
// 별 색은 variant로 결정: 기본 'base'(흰색) → .rstars-base
// EX(합성) 카드: rarityStars(card, 'ex') → 빨간 별 (.rstars-ex, EX 전용 색)
(function () {
  const STARS = { 'NORMAL': 1, 'RARE': 2, 'HIGH RARE': 3, 'SUPER RARE': 4, 'ULTRA RARE': 5, 'MYTHIC RARE': 6,
                  N: 1, R: 2, HR: 3, SR: 4, UR: 5, MR: 6 };
  const count = g => STARS[String(g || '').toUpperCase()] || 0;
  // card: 카드 객체(grade 필드) 또는 등급 문자열('SUPER RARE' / 'SR')
  function rarityStars(card, variant = 'base', extraCls = '') {
    const n = count(typeof card === 'string' ? card : card?.grade);
    if (!n) return '';
    return `<div class="rstars rstars-${variant} ${extraCls}" aria-label="별 ${n}개">${'<span>★</span>'.repeat(n)}</div>`;
  }
  rarityStars.count = count;
  window.rarityStars = rarityStars;
  const css = document.createElement('style');
  css.textContent = `.rstars{display:flex;justify-content:center;gap:1px;line-height:1;font-size:18px;pointer-events:none}
.rstars span{text-shadow:0 0 2px #000,0 0 2px #000,0 1px 3px rgba(0,0,0,.9);-webkit-text-stroke:.6px rgba(0,0,0,.75)}
.rstars-base span{color:#fff}
.rstars-ex span{color:#ef4444} /* EX(합성) 카드 전용 빨간 별 — 다른 용도로 쓰지 않음 */
.rstars-over{position:absolute;top:4px;left:0;right:0;z-index:3}
.rstars-lg{font-size:26px}`;
  document.head.appendChild(css);
})();
