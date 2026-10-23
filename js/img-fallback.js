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
