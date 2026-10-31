// ===== UI 아이콘 (이모지 대신 그림 아이콘) =====
// 사용: VRIcon.icon('mana') → <img> HTML 문자열 (글자 크기에 맞춰 1em 안팎, 세로 정렬).
// 새 아이콘 추가: 아래 ICONS 에 한 줄 추가하거나, 실행 중 VRIcon.register('name', { src: 'name.webp', alt: '이름' }).
// 파일은 img/ui/ 아래 webp (64px/128px 정사각, 투명 배경). set2 아이콘도 같은 방식으로 추가하면 됩니다.
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
    discard: { src: 'discard.webp', alt: '분해' },
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
    skill_count: { src: 'skill_count.webp', alt: '스킬 수' },   // 그림순이 (카드 상세 스킬 수 태그)
    taunt:   { src: 'taunt.webp',   alt: '도발' },
    bleed:   { src: 'bleed.webp',   alt: '출혈' },
    immune:  { src: 'immune.webp',  alt: '면역' },
    shuffle: { src: 'shuffle.webp', alt: '패 섞기' },
    base:    { src: 'base.webp',    alt: '진영' },
    heal:    { src: 'heal.webp',    alt: '회복' },
    gear:    { src: 'gear.webp',    alt: '가속기' },
    mana_accel: { src: 'mana_accel.webp', alt: '마나 가속기' },
    rank:    { src: 'rank.webp',    alt: '랭킹' },
    gallery: { src: 'gallery.webp', alt: '갤러리' },
    login:   { src: 'login.webp',   alt: '로그인' },
    // set3 (128px)
    cur_gold: { src: 'cur_gold.webp', alt: '골드' },
    cur_blood: { src: 'cur_blood.webp', alt: '순수한 피' },
    cur_shard: { src: 'cur_shard.webp', alt: '이상한 조각' },
    cur_soul: { src: 'cur_soul.webp', alt: '각성자의 혼' },
    stamina: { src: 'stamina.webp', alt: '행동력' },
    player_xp: { src: 'player_xp.webp', alt: '플레이어 경험치' },
    level_up: { src: 'level_up.webp', alt: '레벨업' },
    ticket: { src: 'ticket.webp', alt: '소환권' },
    gacha: { src: 'gacha.webp', alt: '인재영입' },
    my_cards: { src: 'my_cards.webp', alt: '보유 인재' },
    sweep: { src: 'sweep.webp', alt: '소탕' },
    reward: { src: 'reward.webp', alt: '보상' },
    stat_point: { src: 'stat_point.webp', alt: '스탯 포인트' },
    lock: { src: 'lock.webp', alt: '잠김' },
    unlock: { src: 'unlock.webp', alt: '잠금 해제' },
    clear_check: { src: 'clear_check.webp', alt: '클리어' },
    close: { src: 'close.webp', alt: '닫기' },
    tower: { src: 'tower.webp', alt: '시련의 탑' },
    story_mode: { src: 'story_mode.webp', alt: '스토리 모드' },
    event_story: { src: 'event_story.webp', alt: '이벤트 스토리' },
    mypage_btn: { src: 'mypage_btn.webp', alt: '마이페이지' },
    arcade_opts: { src: 'arcade_opts.webp', alt: '게임 설정' },
    se_on: { src: 'se_on.webp', alt: '효과음 켜짐' },
    se_off: { src: 'se_off.webp', alt: '효과음 꺼짐' },
    howto_book: { src: 'howto_book.webp', alt: 'How to Play' },
    tutorial: { src: 'tutorial.webp', alt: '튜토리얼' },
    zoom: { src: 'zoom.webp', alt: '크게 보기' },
    share: { src: 'share.webp', alt: '공유' },
    gacha_rates: { src: 'gacha_rates.webp', alt: '뽑기 확률' },
    warning: { src: 'warning.webp', alt: '주의' },
    tip: { src: 'tip.webp', alt: '팁' },
    offline: { src: 'offline.webp', alt: '오프라인' },
    bond: { src: 'bond.webp', alt: '인연' },
    synergy: { src: 'synergy.webp', alt: '시너지' },
    admin_wallet: { src: 'admin_wallet.webp', alt: '재화 지급' },
    battle: { src: 'battle.webp', alt: '전투' },
    give_up: { src: 'give_up.webp', alt: '도전 포기' },
    me: { src: 'me.webp', alt: '나' },
    cpu: { src: 'cpu.webp', alt: '컴퓨터' },
    last_turn: { src: 'last_turn.webp', alt: '마지막 턴' },
    hero_hit: { src: 'hero_hit.webp', alt: '진영 피해' },
    awaken: { src: 'awaken.webp', alt: '각성' },
    buff_up: { src: 'buff_up.webp', alt: '버프' },
    buff_down: { src: 'buff_down.webp', alt: '디버프' },
    gender: { src: 'gender.webp', alt: '성별' },
    mr_star: { src: 'mr_star.webp', alt: 'MR' },
    armor: { src: 'armor.webp', alt: '방어구' },
    st_para: { src: 'st_para.webp', alt: '마비' },
    st_confuse: { src: 'st_confuse.webp', alt: '혼란' },
    st_disrupt: { src: 'st_disrupt.webp', alt: '교란' },
    st_debuff_immune: { src: 'st_debuff_immune.webp', alt: '디버프 면역' },
    st_esoteric: { src: 'st_esoteric.webp', alt: 'Esoteric' },
    st_dot: { src: 'st_dot.webp', alt: 'HP 고갈' },
    st_noheal: { src: 'st_noheal.webp', alt: '회복 불가' },
    st_decoy: { src: 'st_decoy.webp', alt: '대신 맞기' },
    st_pleading: { src: 'st_pleading.webp', alt: '꼭 이래야해?' },
    st_seed: { src: 'st_seed.webp', alt: '쾌락의 씨앗' },
    st_thorns: { src: 'st_thorns.webp', alt: '반격 강화' },
    st_evade: { src: 'st_evade.webp', alt: '회피' },
    st_endure: { src: 'st_endure.webp', alt: '불사' },
    st_soulsteal: { src: 'st_soulsteal.webp', alt: '영혼 강탈' },
    st_curse: { src: 'st_curse.webp', alt: '지옥 교향곡' },
    st_cry: { src: 'st_cry.webp', alt: '천사의 절규' },
    rarity_star: { src: 'rarity_star.webp', alt: '등급' },
    rank_1: { src: 'rank_1.webp', alt: '1위' },
    rank_2: { src: 'rank_2.webp', alt: '2위' },
    rank_3: { src: 'rank_3.webp', alt: '3위' },
    crown_blue: { src: 'crown_blue.webp', alt: '파란 왕관' },
    crown_purple: { src: 'crown_purple.webp', alt: '보라 왕관' },
    crown_yellow: { src: 'crown_yellow.webp', alt: '노란 왕관' },
    crown_red: { src: 'crown_red.webp', alt: '붉은 왕관' },
    element_note: { src: 'element_note.webp', alt: '등급과 속성' },
    shop: { src: 'shop.webp', alt: '상점' },
    settings_text: { src: 'gear.webp', alt: '설정' },
  };
  // 이모지 → 아이콘 이름 (UI 라벨용. 대사·본문에는 쓰지 않음)
  const EMOJI = { '💧': 'mana', '♥': 'hp', '👑': 'crown', '🗑️': 'discard', '🗑': 'discard', '🗡️': 'merc', '🎬': 'opening', '🔊': 'sound_on', '🔇': 'sound_off',
    '🔥': 'el_fire', '🌪️': 'el_wind', '🌪': 'el_wind', '❄️': 'el_ice', '❄': 'el_ice', '🌑': 'el_dark', '💀': 'el_death', '🎯': 'taunt', '🩸': 'bleed', '🔰': 'immune',
    '🔀': 'shuffle', '🏰': 'base', '💚': 'heal', '⚙️': 'gear', '⚙': 'gear', '🏆': 'rank', '🖼️': 'gallery', '🖼': 'gallery', '🔑': 'login',
    // set3. ⚠ 🩸(출혈)·🔥(불 속성)·⚡(마비/소탕/전투력)·✨ 은 뜻이 여러 개라 swap 하지 않음 → 재화는 VRIcon.cur(), 소탕은 icon('sweep') 직접
    '🪙': 'cur_gold', '💠': 'cur_shard', '🔋': 'stamina', '🎟️': 'ticket', '🎟': 'ticket', '🎴': 'gacha', '🃏': 'my_cards', '🎁': 'reward', '📈': 'stat_point',
    '🔒': 'lock', '🔓': 'unlock', '🗼': 'tower', '📜': 'story_mode', '📅': 'event_story', '👤': 'mypage_btn', '🎛️': 'arcade_opts', '🎛': 'arcade_opts', '🔔': 'se_on', '🔕': 'se_off',
    '📖': 'howto_book', '🎓': 'tutorial', '🔍': 'zoom', '📤': 'share', '📊': 'gacha_rates', '⚠️': 'warning', '💡': 'tip', '📡': 'offline', '🤝': 'bond', '🔗': 'synergy',
    '⚔️': 'battle', '🏳️': 'give_up', '⏳': 'last_turn', '⏱️': 'last_turn', '🔺': 'buff_up', '🔻': 'buff_down', '🚻': 'gender', '🌟': 'mr_star', '🛡️': 'armor', '💎': 'element_note', '🏪': 'shop',
    '💫': 'st_confuse', '🌀': 'st_disrupt', '✳️': 'st_debuff_immune', '☠️': 'st_esoteric', '🩻': 'st_dot', '🚫': 'st_noheal', '🪞': 'st_decoy', '🌱': 'st_seed', '🌵': 'st_thorns', '💨': 'st_evade', '💢': 'st_endure', '👻': 'st_soulsteal', '🥀': 'st_curse', '😇': 'st_cry' };
  /** 이모지가 섞인 고정 UI 문구(HTML)에서 아는 이모지만 아이콘으로 바꿈. 대사·사용자 입력에는 쓰지 말 것 */
  const SWAP_RE = new RegExp(Object.keys(EMOJI).sort((a, b) => b.length - a.length).map(e => e.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'gu');
  function swap(html) { return String(html).replace(SWAP_RE, m => icon(EMOJI[m]) || m); }
  const escAttr = s => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  /** 아이콘 <img> HTML. opts: { alt, title, cls, size } — size 는 CSS 길이(예: '1.4em'), 기본은 .ui-ic 크기 */
  function icon(name, opts = {}) {
    const d = ICONS[name]; if (!d) return '';
    const alt = opts.alt ?? d.alt;
    const style = opts.size ? ` style="width:${opts.size};height:${opts.size}"` : '';
    return `<img src="${BASE}${d.src}" alt="${escAttr(alt)}"${opts.title ? ` title="${escAttr(opts.title)}"` : ''} class="ui-ic ui-ic-${name}${opts.cls ? ' ' + opts.cls : ''}"${style} width="64" height="64" draggable="false" decoding="async">`;
  }
  /** 재화 아이콘 (gold/blood/shard/soul/tickets). 그림이 없으면 이모지 */
  const CUR = { gold: ['cur_gold', '🪙'], blood: ['cur_blood', '🩸'], shard: ['cur_shard', '💠'], soul: ['cur_soul', '🔥'], tickets: ['ticket', '🎟️'], stamina: ['stamina', '🔋'] };
  function cur(k, opts = {}) { const d = CUR[k]; if (!d) return ''; return icon(d[0], opts) || d[1]; }
  /** 아이콘, 없으면 fb 문자 */
  const or = (name, fb, opts) => icon(name, opts) || fb || '';
  function register(name, def) { ICONS[name] = { alt: name, ...def }; }
  window.VRIcon = { icon, register, swap, cur, or, ICONS, EMOJI, BASE };
})();
