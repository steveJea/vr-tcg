// ===== UI 아이콘 (이모지 대신 그림 아이콘) =====
// 사용: VRIcon.icon('mana') → <img> HTML 문자열 (글자 크기에 맞춰 1em 안팎, 세로 정렬).
// 새 아이콘 추가: 아래 ICONS 에 한 줄 추가하거나, 실행 중 VRIcon.register('name', { src: 'name.webp', alt: '이름' }).
// 파일은 img/ui/ 아래 webp (64px 정사각, 투명 배경). set2 아이콘도 같은 방식으로 추가하면 됩니다.
(function () {
  const BASE = 'img/ui/';
  const ICONS = {
    mana: { src: 'mana.webp', alt: '마나' },
    atk:  { src: 'atk.webp',  alt: 'ATK' },
    def:  { src: 'def.webp',  alt: 'DEF' },
    hp:   { src: 'hp.webp',   alt: 'HP' },
    // set2
    crown:   { src: 'leader_crown.webp', alt: '왕관' },
    merge:   { src: 'merge.webp',   alt: '합성' },
    discard: { src: 'discard.webp', alt: '폐기' },
    merc:    { src: 'merc.webp',    alt: '용병' },
    weapon:  { src: 'merc.webp',    alt: '무기' },
    opening: { src: 'opening.webp', alt: '연출' },
    sound_on:  { src: 'sound_on.webp',  alt: '소리 켜짐' },
    sound_off: { src: 'sound_off.webp', alt: '소리 꺼짐' },
    el_fire:  { src: 'el_fire.webp',  alt: '불' },
    el_wind:  { src: 'el_wind.webp',  alt: '바람' },
    el_ice:   { src: 'el_ice.webp',   alt: '얼음' },
    el_dark:  { src: 'el_dark.webp',  alt: '어둠' },
    el_light: { src: 'el_light.webp', alt: '빛' },
    el_death: { src: 'el_death.webp', alt: '심연' },
    skill:   { src: 'skill.webp',   alt: '스킬' },
    taunt:   { src: 'taunt.webp',   alt: '도발' },
    bleed:   { src: 'bleed.webp',   alt: '출혈' },
    immune:  { src: 'immune.webp',  alt: '면역' },
    shuffle: { src: 'shuffle.webp', alt: '패 섞기' },
    base:    { src: 'base.webp',    alt: '진영' },
    heal:    { src: 'heal.webp',    alt: '회복' },
    gear:    { src: 'gear.webp',    alt: '가속기' },
    rank:    { src: 'rank.webp',    alt: '랭킹' },
    gallery: { src: 'gallery.webp', alt: '갤러리' },
    login:   { src: 'login.webp',   alt: '로그인' },
  };
  // 이모지 → 아이콘 이름 (UI 라벨용. 대사·본문에는 쓰지 않음)
  const EMOJI = { '💧': 'mana', '♥': 'hp', '👑': 'crown', '🗑️': 'discard', '🗑': 'discard', '🗡️': 'merc', '🎬': 'opening', '🔊': 'sound_on', '🔇': 'sound_off',
    '🔥': 'el_fire', '🌪️': 'el_wind', '🌪': 'el_wind', '❄️': 'el_ice', '❄': 'el_ice', '🌑': 'el_dark', '💀': 'el_death', '🎯': 'taunt', '🩸': 'bleed', '🔰': 'immune',
    '🔀': 'shuffle', '🏰': 'base', '💚': 'heal', '⚙️': 'gear', '⚙': 'gear', '🏆': 'rank', '🖼️': 'gallery', '🖼': 'gallery', '🔑': 'login' };
  /** 이모지가 섞인 고정 UI 문구(HTML)에서 아는 이모지만 아이콘으로 바꿈. 대사·사용자 입력에는 쓰지 말 것 */
  function swap(html) { return String(html).replace(/🗑️|🗑|🗡️|🌪️|🌪|❄️|❄|⚙️|⚙|🖼️|🖼|💧|♥|👑|🎬|🔊|🔇|🔥|🌑|💀|🎯|🩸|🔰|🔀|🏰|💚|🏆|🔑/gu, m => icon(EMOJI[m]) || m); }
  const escAttr = s => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  /** 아이콘 <img> HTML. opts: { alt, title, cls, size } — size 는 CSS 길이(예: '1.4em'), 기본은 .ui-ic 크기 */
  function icon(name, opts = {}) {
    const d = ICONS[name]; if (!d) return '';
    const alt = opts.alt ?? d.alt;
    const style = opts.size ? ` style="width:${opts.size};height:${opts.size}"` : '';
    return `<img src="${BASE}${d.src}" alt="${escAttr(alt)}"${opts.title ? ` title="${escAttr(opts.title)}"` : ''} class="ui-ic ui-ic-${name}${opts.cls ? ' ' + opts.cls : ''}"${style} width="64" height="64" draggable="false" decoding="async">`;
  }
  function register(name, def) { ICONS[name] = { alt: name, ...def }; }
  window.VRIcon = { icon, register, swap, ICONS, EMOJI, BASE };
})();
