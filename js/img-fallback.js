// ===== 카드 프로필 이미지 대체 경로 =====
// 프로필은 vr-ideal-worldcup/img/bt_img/<id>.webp (raw.githubusercontent). 스토리 전용 NPC 카드(data/npc_cards.csv)는
// 그 저장소에 없으므로 이 저장소의 img/npc/<id>.webp 로 한 번 더 시도. 그래도 없으면 깨진 이미지 아이콘 대신 숨김.
(function () {
  const BASE = '/img/bt_img/', LOCAL = 'img/npc/';
  document.addEventListener('error', e => {
    const el = e.target;
    if (!(el instanceof HTMLImageElement)) return;
    const src = el.getAttribute('src') || '';
    const m = src.includes(BASE) && src.match(/\/(\d+)\.webp(?:\?.*)?$/);
    if (m && !el.dataset.npcTried) { el.dataset.npcTried = '1'; e.stopPropagation(); el.src = LOCAL + m[1] + '.webp'; return; }
    if (el.dataset.npcTried && !el.getAttribute('onerror')) { el.style.visibility = 'hidden'; el.alt = ''; }
  }, true);
})();

// ===== 프로필 교체 (이 저장소 img/npc/<id>.webp 가 우선) =====
// vr-ideal-worldcup 의 bt_img 를 이 저장소에서 바꿀 수 없어서, 여기 적은 id 는 화면에 붙는 순간 img/npc 로 바꿔 끼움 (<img src>, style background-image).
(function () {
  const OVERRIDE = new Set(['10266', '10509']);   // 용지효 (2026-10 새 프로필) · 강보람 10509 (bt_img 없음, img/npc)
  const RE = /https?:\/\/raw\.githubusercontent\.com\/steveJea\/vr-ideal-worldcup\/main\/img\/bt_img\/(\d+)\.webp/g;
  const swap = str => str.replace(RE, (m, id) => OVERRIDE.has(id) ? 'img/npc/' + id + '.webp' : m);
  window.cardImgOverride = swap;
  const fix = el => {
    if (el.nodeType !== 1) return;
    const src = el.getAttribute('src'); if (src && src.includes('/bt_img/')) { const n = swap(src); if (n !== src) el.setAttribute('src', n); }
    const st = el.getAttribute('style'); if (st && st.includes('/bt_img/')) { const n = swap(st); if (n !== st) el.setAttribute('style', n); }
  };
  const scan = root => { fix(root); root.querySelectorAll?.('[src*="/bt_img/"],[style*="/bt_img/"]').forEach(fix); };
  new MutationObserver(ms => { for (const m of ms) m.type === 'attributes' ? fix(m.target) : m.addedNodes.forEach(scan); })
    .observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src', 'style'] });
  document.addEventListener('DOMContentLoaded', () => scan(document.body));
})();
