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
    merc:    { src: 'merc_hire.webp',    alt: '용병' },
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
  const EMOJI = { '💧': 'mana', '♥': 'hp', '👑': 'crown', '🗑️': 'discard', '🗑': 'discard', '🗡️': 'weapon', '🎬': 'opening', '🔊': 'sound_on', '🔇': 'sound_off',
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

  // ===== set4: 남은 UI 이모지 → 그림 (화면 글자를 자동 치환, 대사·입력칸 제외) =====
  ICONS["magic_orb_guild"] = ICONS["magic_orb_guild"] || { src: 'magic_orb_guild.webp', alt: "magic orb (guild" };
  ICONS["drink_item"] = ICONS["drink_item"] || { src: 'drink_item.webp', alt: "drink item" };
  ICONS["upgrade"] = ICONS["upgrade"] || { src: 'upgrade.webp', alt: "upgrade" };
  ICONS["pinned"] = ICONS["pinned"] || { src: 'pinned.webp', alt: "pinned" };
  ICONS["critical"] = ICONS["critical"] || { src: 'critical.webp', alt: "critical" };
  ICONS["deck"] = ICONS["deck"] || { src: 'deck.webp', alt: "deck" };
  ICONS["invite"] = ICONS["invite"] || { src: 'invite.webp', alt: "invite" };
  ICONS["war_flag"] = ICONS["war_flag"] || { src: 'war_flag.webp', alt: "war flag" };
  ICONS["1st_place"] = ICONS["1st_place"] || { src: '1st_place.webp', alt: "1st place" };
  ICONS["2nd_place"] = ICONS["2nd_place"] || { src: '2nd_place.webp', alt: "2nd place" };
  ICONS["3rd_place"] = ICONS["3rd_place"] || { src: '3rd_place.webp', alt: "3rd place" };
  ICONS["done"] = ICONS["done"] || { src: 'done.webp', alt: "done" };
  ICONS["ai_opponent"] = ICONS["ai_opponent"] || { src: 'ai_opponent.webp', alt: "AI opponent" };
  ICONS["shop_cart"] = ICONS["shop_cart"] || { src: 'shop_cart.webp', alt: "shop cart" };
  ICONS["guild_ritual_candle"] = ICONS["guild_ritual_candle"] || { src: 'guild_ritual_candle.webp', alt: "guild ritual candle" };
  ICONS["dragon"] = ICONS["dragon"] || { src: 'dragon.webp', alt: "dragon" };
  ICONS["skip"] = ICONS["skip"] || { src: 'skip.webp', alt: "skip" };
  ICONS["guild_members"] = ICONS["guild_members"] || { src: 'guild_members.webp', alt: "guild members" };
  ICONS["mail_received"] = ICONS["mail_received"] || { src: 'mail_received.webp', alt: "mail received" };
  ICONS["home_base"] = ICONS["home_base"] || { src: 'home_base.webp', alt: "home base" };
  ICONS["war_jester_event"] = ICONS["war_jester_event"] || { src: 'war_jester_event.webp', alt: "war jester event" };
  ICONS["void"] = ICONS["void"] || { src: 'void.webp', alt: "void" };
  ICONS["gear_bag"] = ICONS["gear_bag"] || { src: 'gear_bag.webp', alt: "gear bag" };
  ICONS["craft"] = ICONS["craft"] || { src: 'craft.webp', alt: "craft" };
  ICONS["stop"] = ICONS["stop"] || { src: 'stop.webp', alt: "stop" };
  ICONS["guild_emblem"] = ICONS["guild_emblem"] || { src: 'guild_emblem.webp', alt: "guild emblem" };
  ICONS["swap"] = ICONS["swap"] || { src: 'swap.webp', alt: "swap" };
  ICONS["live"] = ICONS["live"] || { src: 'live.webp', alt: "live" };
  ICONS["medal"] = ICONS["medal"] || { src: 'medal.webp', alt: "medal" };
  ICONS["star"] = ICONS["star"] || { src: 'star.webp', alt: "star" };
  ICONS["reject_trade"] = ICONS["reject_trade"] || { src: 'reject_trade.webp', alt: "reject trade" };
  ICONS["bind"] = ICONS["bind"] || { src: 'bind.webp', alt: "bind" };
  ICONS["watch"] = ICONS["watch"] || { src: 'watch.webp', alt: "watch" };
  ICONS["announcement"] = ICONS["announcement"] || { src: 'announcement.webp', alt: "announcement" };
  ICONS["receive"] = ICONS["receive"] || { src: 'receive.webp', alt: "receive" };
  ICONS["money"] = ICONS["money"] || { src: 'money.webp', alt: "money" };
  ICONS["purple_marker"] = ICONS["purple_marker"] || { src: 'purple_marker.webp', alt: "purple marker" };
  ICONS["pvp_ticket"] = ICONS["pvp_ticket"] || { src: 'pvp_ticket.webp', alt: "pvp ticket" };
  ICONS["wind"] = ICONS["wind"] || { src: 'wind.webp', alt: "wind" };
  ICONS["light_element"] = ICONS["light_element"] || { src: 'light_element.webp', alt: "light element" };
  ICONS["defeat"] = ICONS["defeat"] || { src: 'defeat.webp', alt: "defeat" };
  ICONS["unlimited"] = ICONS["unlimited"] || { src: 'unlimited.webp', alt: "unlimited" };
  ICONS["exchange"] = ICONS["exchange"] || { src: 'exchange.webp', alt: "exchange" };
  ICONS["pause"] = ICONS["pause"] || { src: 'pause.webp', alt: "pause" };
  ICONS["balance"] = ICONS["balance"] || { src: 'balance.webp', alt: "balance" };
  ICONS["raid_demon_boss"] = ICONS["raid_demon_boss"] || { src: 'raid_demon_boss.webp', alt: "raid demon boss" };
  ICONS["guild_rose"] = ICONS["guild_rose"] || { src: 'guild_rose.webp', alt: "guild rose" };
  ICONS["guild_bird"] = ICONS["guild_bird"] || { src: 'guild_bird.webp', alt: "guild bird" };
  ICONS["empty_slot"] = ICONS["empty_slot"] || { src: 'empty_slot.webp', alt: "empty slot" };
  ICONS["guild_fang"] = ICONS["guild_fang"] || { src: 'guild_fang.webp', alt: "guild fang" };
  ICONS["guild_snake"] = ICONS["guild_snake"] || { src: 'guild_snake.webp', alt: "guild snake" };
  ICONS["guild_spider"] = ICONS["guild_spider"] || { src: 'guild_spider.webp', alt: "guild spider" };
  ICONS["moon"] = ICONS["moon"] || { src: 'moon.webp', alt: "moon" };
  ICONS["search"] = ICONS["search"] || { src: 'search.webp', alt: "search" };
  ICONS["edit"] = ICONS["edit"] || { src: 'edit.webp', alt: "edit" };
  ICONS["add"] = ICONS["add"] || { src: 'add.webp', alt: "add" };
  ICONS["party"] = ICONS["party"] || { src: 'party.webp', alt: "party" };
  ICONS["fail"] = ICONS["fail"] || { src: 'fail.webp', alt: "fail" };
  ICONS["dark_heart"] = ICONS["dark_heart"] || { src: 'dark_heart.webp', alt: "dark heart" };
  ICONS["blue_marker"] = ICONS["blue_marker"] || { src: 'blue_marker.webp', alt: "blue marker" };
  ICONS["yellow_marker"] = ICONS["yellow_marker"] || { src: 'yellow_marker.webp', alt: "yellow marker" };
  ICONS["chat"] = ICONS["chat"] || { src: 'chat.webp', alt: "chat" };
  ICONS["payment"] = ICONS["payment"] || { src: 'payment.webp', alt: "payment" };
  ICONS["map"] = ICONS["map"] || { src: 'map.webp', alt: "map" };
  ICONS["tower_tier_mountain"] = ICONS["tower_tier_mountain"] || { src: 'tower_tier_mountain.webp', alt: "tower tier mountain" };
  ICONS["finish"] = ICONS["finish"] || { src: 'finish.webp', alt: "finish" };
  ICONS["strength"] = ICONS["strength"] || { src: 'strength.webp', alt: "strength" };
  ICONS["greeting"] = ICONS["greeting"] || { src: 'greeting.webp', alt: "greeting" };
  ICONS["male"] = ICONS["male"] || { src: 'male.webp', alt: "male" };
  ICONS["female"] = ICONS["female"] || { src: 'female.webp', alt: "female" };
  ICONS["abyss"] = ICONS["abyss"] || { src: 'abyss.webp', alt: "abyss" };
  ICONS["time_over"] = ICONS["time_over"] || { src: 'time_over.webp', alt: "time over" };
  ICONS["peace"] = ICONS["peace"] || { src: 'peace.webp', alt: "peace" };
  ICONS["cloud_save"] = ICONS["cloud_save"] || { src: 'cloud_save.webp', alt: "cloud save" };
  ICONS["online"] = ICONS["online"] || { src: 'online.webp', alt: "online" };
  ICONS["orange_marker"] = ICONS["orange_marker"] || { src: 'orange_marker.webp', alt: "orange marker" };
  ICONS.mailbox = ICONS.mailbox || { src: 'mailbox.webp', alt: '우편함' };
  const EMOJI2 = {
    "🔮": "magic_orb_guild",
    "🥤": "drink_item",
    "⬆": "upgrade",
    "📮": "mailbox",
    "📌": "pinned",
    "💥": "critical",
    "🗂": "deck",
    "📨": "invite",
    "🏴": "war_flag",
    "🥇": "1st_place",
    "🥈": "2nd_place",
    "🥉": "3rd_place",
    "✅": "done",
    "🤖": "ai_opponent",
    "🛒": "shop_cart",
    "🕯": "guild_ritual_candle",
    "🐉": "dragon",
    "⏭": "skip",
    "👥": "guild_members",
    "📬": "mail_received",
    "🏠": "home_base",
    "🤡": "war_jester_event",
    "🌌": "void",
    "🎒": "gear_bag",
    "🔨": "craft",
    "✋": "stop",
    "⚜": "guild_emblem",
    "🔄": "swap",
    "🔴": "live",
    "🏅": "medal",
    "⭐": "star",
    "🙅": "reject_trade",
    "⛓": "bind",
    "👁": "watch",
    "📢": "announcement",
    "📥": "receive",
    "💰": "money",
    "🟣": "purple_marker",
    "🎫": "pvp_ticket",
    "🍃": "wind",
    "☀": "light_element",
    "💔": "defeat",
    "♾": "unlimited",
    "💱": "exchange",
    "⏸": "pause",
    "⚖": "balance",
    "👹": "raid_demon_boss",
    "🌹": "guild_rose",
    "🐦": "guild_bird",
    "⬛": "empty_slot",
    "🦷": "guild_fang",
    "🐍": "guild_snake",
    "🕷": "guild_spider",
    "🌙": "moon",
    "🔎": "search",
    "✏": "edit",
    "➕": "add",
    "🧑‍🤝‍🧑": "party",
    "❌": "fail",
    "🖤": "dark_heart",
    "🔵": "blue_marker",
    "🟡": "yellow_marker",
    "💬": "chat",
    "💳": "payment",
    "🗺": "map",
    "❤": "hp",
    "🏔": "tower_tier_mountain",
    "🏁": "finish",
    "💪": "strength",
    "👋": "greeting",
    "🚹": "male",
    "🚺": "female",
    "🕳": "abyss",
    "⌛": "time_over",
    "🕊": "peace",
    "☁": "cloud_save",
    "🟢": "online",
    "🟠": "orange_marker"
  };
  const norm = s => s.replace(/\uFE0F/g, '');
  const E2RE = new RegExp(Object.keys(EMOJI2).sort((a, b) => b.length - a.length).map(e => e.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\uFE0F?').join('|'), 'gu');
  const SKIP_SEL = '.story-dlg, #story-dlg, #event-layer, .ev-line, input, textarea, select, script, style, [contenteditable], [data-noemoji], .stfx-text';
  function swapText(tn) {
    const t = tn.nodeValue; E2RE.lastIndex = 0; if (!t || !E2RE.test(t)) return;
    const p = tn.parentElement; if (!p || p.closest(SKIP_SEL)) return;
    E2RE.lastIndex = 0;
    const frag = document.createDocumentFragment(); let last = 0, m;
    while ((m = E2RE.exec(t))) {
      if (m.index > last) frag.appendChild(document.createTextNode(t.slice(last, m.index)));
      const name = EMOJI2[norm(m[0])], d = ICONS[name];
      if (!d) { frag.appendChild(document.createTextNode(m[0])); last = m.index + m[0].length; continue; }
      const img = document.createElement('img');
      img.src = BASE + d.src; img.alt = m[0]; img.className = `ui-ic ui-ic-${name}`; img.width = 64; img.height = 64; img.draggable = false; img.decoding = 'async';
      img.onerror = () => img.replaceWith(document.createTextNode(m0));   // 그림 못 받으면 이모지로
      const m0 = m[0]; frag.appendChild(img); last = m.index + m[0].length;
    }
    if (last < t.length) frag.appendChild(document.createTextNode(t.slice(last)));
    tn.replaceWith(frag);
  }
  function swapTree(root) {
    if (!root) return;
    if (root.nodeType === 3) return swapText(root);
    if (root.nodeType !== 1 || root.closest?.(SKIP_SEL)) return;
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), list = [];
    for (let n; (n = w.nextNode());) list.push(n);
    list.forEach(swapText);
  }
  function startSwap() {
    swapTree(document.body);
    new MutationObserver(ms => { for (const mu of ms) { if (mu.type === 'characterData') swapText(mu.target); else mu.addedNodes.forEach(swapTree); } })
      .observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', startSwap); else startSwap();
  window.VRIcon = { icon, register, swap, cur, or, ICONS, EMOJI, EMOJI2, BASE, swapTree };
})();
