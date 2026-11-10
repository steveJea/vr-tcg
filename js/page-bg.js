// ===== 페이지 배경: 지금 열린 페이지(VRPages.current) → 배경 그룹 → #vr-page[data-bg] (css/page-bg.css) =====
// 하위 페이지는 부모 그룹 그림. 시련의 탑(quest)은 탑 배경을 쓰니 제외. 목록에 없는 페이지 = common
(() => {
  const MAP = [
    [/^quest$/, null],
    [/^exchange/, 'exchange'], [/^pvpshop$|^gem$|^shop$/, 'shop'], [/^pvp/, 'pvp'], [/^guild/, 'guild'], [/^raid/, 'raid'], [/^war/, 'war'],
    [/^friends/, 'social'], [/^ranking/, 'ranking'], [/^daily/, 'daily'], [/^mypage/, 'mypage'], [/^gallery/, 'gallery'],
    [/^dispatch/, 'dispatch'], [/^gearbag/, 'gear'], [/^story-p/, 'story'],
  ];
  const groupOf = name => { if (!name) return null; for (const [re, g] of MAP) if (re.test(name)) return g; return 'common'; };
  let last;
  const paint = () => { const el = document.getElementById('vr-page'); if (!el) return; const g = groupOf(window.VRPages?.current);
    if (g === last && (el.dataset.bg || null) === g) return; last = g; if (g) el.dataset.bg = g; else delete el.dataset.bg; };
  window.VRPageBg = { groupOf };
  addEventListener('hashchange', paint); setInterval(paint, 200); paint();
})();
