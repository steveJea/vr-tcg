// 같은 사이트의 카드 그림이 빠진 경우에만 예전 원본을 시도. 실제로 옮긴 id 만 (NPC는 기존 대체 경로 유지).
(function () {
  const LOCAL = new Set('10001,10002,10003,10004,10005,10006,10007,10008,10009,10010,10011,10012,10013,10014,10015,10016,10017,10018,10019,10020,10021,10022,10023,10024,10025,10026,10027,10028,10029,10030,10031,10032,10033,10034,10035,10036,10037,10038,10039,10040,10041,10042,10043,10044,10045,10046,10047,10048,10049,10050,10051,10052,10053,10054,10055,10056,10057,10058,10059,10060,10061,10062,10063,10064,10065,10066,10067,10068,10069,10070,10071,10072,10073,10074,10075,10076,10077,10078,10079,10080,10081,10083,10084,10085,10086,10087,10088,10089,10090,10091,10092,10093,10094,10095,10096,10097,10098,10099,10100,10101,10102,10103,10104,10105,10106,10107,10108,10109,10110,10111,10112,10113,10114,10115,10117,10118,10119,10120,10121,10122,10123,10124,10125,10126,10127,10128,10129,10130,10131,10132,10133,10134,10135,10136,10137,10138,10139,10140,10141,10142,10169,10170,10171,10172,10173,10174,10175,10176,10177,10178,10179,10180,10181,10182,10183,10184,10185,10186,10187,10188,10189,10190,10191,10192,10193,10194,10195,10200,10201,10202,10203,10204,10205,10206,10207,10208,10209,10211,10212,10213,10214,10215,10216,10217,10218,10219,10220,10221,10222,10223,10224,10225,10226,10227,10228,10229,10230,10231,10232,10233,10234,10235,10236,10237,10238,10239,10240,10241,10242,10243,10244,10245,10246,10247,10248,10249,10250,10251,10252,10253,10254,10255,10256,10257,10258,10259,10260,10261,10262,10263,10264,10265,10266,10267,10268,10269,10270,10271,10272,10273,10274,10275,10276,10277,10278,10279,10280,10281,10282,10283,10284,10285,10286,10287,10288,10289,10290,10291,10292,10293,10294,10295,10296,10297,10298,10299,10300,10303,10304,10305,10306,10307,10308,10309,10310,10311,10312,10313,10314,10315,10316,10317,10318,10319,10320,10321,10322,10323,10324,10325,10326,10327,10328,10329,10330,10331,10332,10333,10336,10337,10338,10339,10340,10341,10342,10343,10344,10345,10346,10347,10348,10349,10350,10351,10352,10353,10354,10355,10356,10357,10358,10359,10360,10361,10362,10363,10364,10365,10366,10367,10368,10369,10370,10371,10372,10373,10374,10375,10376,10377,10378,10379,10380,10381,10382,10383,10384,10385,10386,10387,10388,10389,10390,10391,10392,10393,10394,10395,10396,10397,10398,10399,10400,10401,10402,10403,10404,10405,10406,10407,10408,10409,10410,10411,10412,10413,10414,10415,10416,10417,10418,10419,10420,10421,10422,10423,10424,10425,10426,10427,10428,10429,10430,10431,10432,10433,10434,10435,10436,10437,10438,10439,10440,10441,10442,10443,10444,10445,10446,10447,10448,10449,10450,10451,10452,10453,10454,10455,10456,10457,10458,10459,10460,10461,10462,10463,10464,10465,10466,10467,10468,10469,10470,10471,10472,10473,10474,10509,10511,10512,10513,10520,10521,10522,10523,10524,10525,10526,10527,10528,10529,10530,10531,10532'.split(','));
  const OLD = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  window.cardArtOld = OLD;
  document.addEventListener('error', e => {
    const el = e.target;
    if (!(el instanceof HTMLImageElement) || el.dataset.remoteTried) return;
    const src = el.getAttribute('src') || '', m = src.match(/^\/img\/bt_img\/(\d+)\.webp(?:\?.*)?$/);
    if (!m || !LOCAL.has(m[1])) return;
    e.stopImmediatePropagation(); e.stopPropagation(); el.dataset.remoteTried = '1'; el.src = OLD + m[1] + '.webp';
  }, true);
})();

// ===== 작은 카드 그림(썸네일) =====
// 작은 칸(전투 손패/필드, 목록 등)은 img/thumb/<id>.webp (가로 300px, tools/make_thumbs.py 로 생성)를 쓰고,
// 썸네일이 없으면 원본(bt_img → 아래 대체 경로들)으로 자동 전환.
// 상세 창은 썸네일을 먼저 띄운 뒤 원본이 디코드되면 교체(game.js fillDetailPortrait). 컷인·확대(🔍)는 원본.
(function () {
  const BT = '/img/bt_img/';
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
  const NPC_LOCAL = new Set('10015,10017,10025,10082,10116,10123,10136,10143,10144,10145,10146,10147,10148,10149,10150,10151,10152,10153,10154,10155,10156,10157,10158,10159,10160,10161,10162,10163,10164,10165,10166,10167,10168,10192,10196,10197,10198,10199,10210,10266,10280,10287,10301,10302,10334,10335,10423,10433,10475,10476,10477,10478,10479,10480,10481,10482,10483,10484,10485,10486,10487,10488,10489,10490,10491,10492,10493,10494,10495,10496,10497,10498,10499,10500,10501,10502,10503,10504,10505,10506,10507,10508,10509,10510,10511,10512,10513,10514,10515,10516,10517,10518,10519,10520,10521,10522,10523,10524,10525,10526,10527,10528,10529,10530,10531,10532,10059,10321,10329,10459,10460,10461,10470'.split(','));
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
  const OVERRIDE = new Set(['10266', '10509', '10015', '10017', '10136', '10192', '10287', '10423', '10433', '10123', '10280', '10025', '10510', '10511', '10512', '10513', '10514', '10515', '10516', '10517', '10518', '10519', '10520', '10521', '10522', '10523', '10524', '10525', '10526', '10527', '10528', '10529', '10530', '10531', '10532', '10059', '10321', '10329', '10459', '10460', '10461', '10470']);   // 용지효 (2026-10 새 프로필) · 강보람 10509 (bt_img 없음, img/npc)  · 2026-10-31 새 프로필 7명 · 11-01 박성관·윤미리내·고정태·평가관(10510 NPC) · 11-11 신규 22명 10511~10532 (bt_img 없음)
  const RE = /(?:https?:\/\/raw\.githubusercontent\.com\/steveJea\/vr-ideal-worldcup\/main)?\/img\/bt_img\/(\d+)\.webp/g;
  const swap = str => str.replace(RE, (m, id) => OVERRIDE.has(id) ? 'img/npc/' + id + '.webp' : '/img/bt_img/' + id + '.webp');
  window.cardImgOverride = swap;
  const fix = el => {
    if (el.nodeType !== 1 || el.dataset.remoteTried) return;
    const src = el.getAttribute('src'); if (src && src.includes('/bt_img/')) { const n = swap(src); if (n !== src) el.setAttribute('src', n); }
    const st = el.getAttribute('style'); if (st && st.includes('/bt_img/')) { const n = swap(st); if (n !== st) el.setAttribute('style', n);
      const m = n.match(/url\(["']?(\/img\/bt_img\/(\d+)\.webp)/); if (m && !el.dataset.bgChecked) { el.dataset.bgChecked = '1'; const im = new Image(); im.onerror = () => { el.dataset.remoteTried = '1'; el.setAttribute('style', n.replace(m[1], window.cardArtOld + m[2] + '.webp')); }; im.src = m[1]; } }
  };
  const scan = root => { fix(root); root.querySelectorAll?.('[src*="/bt_img/"],[style*="/bt_img/"]').forEach(fix); };
  new MutationObserver(ms => { for (const m of ms) m.type === 'attributes' ? fix(m.target) : m.addedNodes.forEach(scan); })
    .observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src', 'style'] });
  document.addEventListener('DOMContentLoaded', () => scan(document.body));
})();

// ===== 스킬 연출 이미지 추가분 (data/fx/<id>_<n>.webp) =====
// data/skills.json 은 서버 전투 엔진(phase3~7) 해시 입력이라, 그림만 늘릴 때는 여기 적어서 화면 쪽에서만 fx 를 채운다.
// 빈 fx 만 채우고 이미 있는 fx 는 건드리지 않음. 다음 엔진 갱신 때 skills.json 으로 옮기면 이 목록은 비워도 됨.
(function () {
  const EXTRA = {
    10321: ['10321_1.webp', '10321_2.webp'],   // 인창수 (2026-11-12 Drive)
    10025: ['10025_1.webp', '10025_2.webp'],   // 고정태 (2026-11-12 Drive)
    10329: ['10329_1.webp', '10329_2.webp'],   // 임창열 (2026-11-12 Drive)
  };
  globalThis.VRSkillFx = sk => {
    if (sk && typeof sk === 'object') for (const [id, list] of Object.entries(EXTRA)) {
      const arr = sk[id]; if (!Array.isArray(arr)) continue;
      list.forEach((fx, i) => { if (fx && arr[i] && !arr[i].fx) arr[i].fx = fx; });
    }
    return sk;
  };
  globalThis.VRSkillFxExtra = EXTRA;
})();
