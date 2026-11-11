// ===== 작은 카드 그림(썸네일) =====
// 작은 칸(전투 손패/필드, 목록 등)은 img/thumb/<id>.webp (가로 300px, tools/make_thumbs.py 로 생성)를 쓰고,
// 썸네일이 없으면 원본(bt_img → 아래 대체 경로들)으로 자동 전환.
// 상세 창은 썸네일을 먼저 띄운 뒤 원본이 디코드되면 교체(game.js fillDetailPortrait). 컷인·확대(🔍)는 원본.
(function () {
  const BT = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  window.cardThumb = id => 'img/thumb/' + id + '.webp';
  document.addEventListener('error', e => {
    const el = e.target;
    if (!(el instanceof HTMLImageElement)) return;
    const m = (el.getAttribute('src') || '').match(/(?:^|\/)img\/thumb\/(\d+)\.webp/);
    if (!m || el.dataset.localTried) return;   // 원본이 없어 썸네일로 내려온 경우는 다시 원본을 요청하지 않는다
    e.stopImmediatePropagation(); e.stopPropagation();   // 인라인 onerror(숨김)가 먼저 돌지 않게
    el.src = (window.cardImgOverride || (x => x))(BT + m[1] + '.webp');
  }, true);
})();

// ===== 카드 프로필 이미지 대체 경로 =====
// 프로필은 vr-ideal-worldcup/img/bt_img/<id>.webp (raw.githubusercontent). 스토리 전용 NPC 카드(data/npc_cards.csv)는
// 그 저장소에 없으므로 이 저장소의 img/npc/<id>.webp 로 한 번 더 시도. 그래도 없으면 깨진 이미지 아이콘 대신 숨김.
(function () {
  const BASE = '/img/bt_img/';
  // 이 저장소에 실제로 있는 초상화만 요청한다. 없는 id 로 img/npc·img/cards 를 두드리면 404 가 난다.
  const NPC_LOCAL = new Set('10015,10017,10025,10082,10116,10123,10136,10143,10144,10145,10146,10147,10148,10149,10150,10151,10152,10153,10154,10155,10156,10157,10158,10159,10160,10161,10162,10163,10164,10165,10166,10167,10168,10192,10196,10197,10198,10199,10210,10266,10280,10287,10301,10302,10334,10335,10423,10433,10475,10476,10477,10478,10479,10480,10481,10482,10483,10484,10485,10486,10487,10488,10489,10490,10491,10492,10493,10494,10495,10496,10497,10498,10499,10500,10501,10502,10503,10504,10505,10506,10507,10508,10509,10510,10511,10512,10513,10514,10515,10516,10517,10518,10519,10520,10521,10522,10523,10524,10525,10526,10527,10528,10529,10530,10531,10532'.split(','));
  const CARD_LOCAL = new Set('10018,10019,10074,10116,10196,10197,10198,10199,10267,10299,10301,10302'.split(','));
  document.addEventListener('error', e => {
    const el = e.target;
    if (!(el instanceof HTMLImageElement)) return;
    const src = el.getAttribute('src') || '';
    const m = src.includes(BASE) && src.match(/\/(\d+)\.webp(?:\?.*)?$/);
    if (!m || el.dataset.localTried) {
      if (el.dataset.localTried && !el.getAttribute('onerror')) { el.style.visibility = 'hidden'; el.alt = ''; }
      return;
    }
    const id = m[1];
    el.dataset.localTried = '1';
    e.stopImmediatePropagation();
    // 등급 문자열(NORMAL) 같은 비숫자 id 는 여기 정규식에 안 걸린다.
    el.src = NPC_LOCAL.has(id) ? 'img/npc/' + id + '.webp' : CARD_LOCAL.has(id) ? 'img/cards/' + id + '.webp' : 'img/thumb/' + id + '.webp';
  }, true);
})();

// ===== 프로필 교체 (이 저장소 img/npc/<id>.webp 가 우선) =====
// vr-ideal-worldcup 의 bt_img 를 이 저장소에서 바꿀 수 없어서, 여기 적은 id 는 화면에 붙는 순간 img/npc 로 바꿔 끼움 (<img src>, style background-image).
(function () {
  const OVERRIDE = new Set(['10266', '10509', '10015', '10017', '10136', '10192', '10287', '10423', '10433', '10123', '10280', '10025', '10510', '10511', '10512', '10513', '10514', '10515', '10516', '10517', '10518', '10519', '10520', '10521', '10522', '10523', '10524', '10525', '10526', '10527', '10528', '10529', '10530', '10531', '10532']);   // 용지효 (2026-10 새 프로필) · 강보람 10509 (bt_img 없음, img/npc)  · 2026-10-31 새 프로필 7명 · 11-01 박성관·윤미리내·고정태·평가관(10510 NPC) · 11-11 신규 22명 10511~10532 (bt_img 없음)
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
