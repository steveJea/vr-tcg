// ===== 스킬 · 상태이상 · 시너지 엔진 (게임·시뮬레이션 공용) =====
// 스킬 데이터: data/skills.json (카드 id → 스킬 목록), 조합: data/combos.json
// 각 스킬 효과는 '효과 내용' 기준으로 아래 ACTIVE / PASSIVE 표에 스킬 이름별로 구현
import { critRate, RULES, elementMultiplier, calcDamage, gainXp, heroLocked, killXp, levelDown, levelUpOnce, genderMult, baseEvade } from './rules.js';
import { poolCard } from './rules.js';

export const SK = {
  MP_BASE: 50, MP_PER_MEN: 1,           // 최대 MP = 50 + MEN (51~150)
  MP_REGEN_BASE: 4, MP_REGEN_PER_MOR: 0.16, // 턴당 MP 회복 = 4 + MOR × 0.16 (약 4~20)
  MP_START_RATIO: 0.5,                  // 소환 시 MP 50%로 시작
  MP_ABSORB_RATIO: 0.2, MP_ABSORB_MIN: 3, // 처치 시 상대가 가진 현재 MP의 20% 흡수 (최소 3)
  SYNERGY: { 2: 0.10, 3: 0.15, 4: 0.20, 5: 0.30 }, // 같은 속성 필드 장수별 ATK·DEF 보너스
};

let SKILL_DB = {}, COMBOS = [];
export function setSkillData(skills, combos) { SKILL_DB = skills || {}; COMBOS = combos || []; }
export const skillsOf = id => SKILL_DB[String(id)] || [];
export const combos = () => COMBOS;

// ---- 이벤트 (UI 로그·연출, 시뮬 통계) ----
let emitFn = () => {};
export function setEmitter(fn) { emitFn = fn || (() => {}); }
export const emit = ev => emitFn(ev);
let rng = Math.random;
export function setRng(f) { rng = f; }

// ---- 플레이어 / 유닛 초기화 ----
let uidSeq = 1;
/** first: 선공 플레이어. 시작 배치(0턴) 때 생기는 상태는 선공 쪽이면 '자기 턴 진행 중'으로 보고 +1턴 (자기 턴 종료에 바로 꺼져 상대 턴을 못 막던 문제) */
export function initPlayers(a, b, first) {
  for (const [p, f] of [[a, b], [b, a]]) Object.assign(p, { foe: f, grave: [], once: {}, st: {}, actionLock: 0, activeSyn: [], activeCombos: [] });
  if (first !== undefined) TURN.p = first;
}
/** 필드에 카드 배치 (소환). 게임·시뮬 공용 */
/** front=true: 새로 소환한 카드를 필드 맨 앞(왼쪽)에 놓음 (턴 중 소환). 스토리 시작 배치는 출전 순서 유지(false) */
export function placeUnit(p, card, makeUnit, front = false) {
  const u = makeUnit(card, uidSeq++);
  initUnit(u, p);
  front ? p.field.unshift(u) : p.field.push(u);
  refreshAll(p);
  onUnlockCheck(u);
  return u;
}
export function initUnit(u, p) {
  u.owner = p;
  u.maxMp = Math.round(SK.MP_BASE + (u.base.MEN || 0) * SK.MP_PER_MEN);
  u.mp = Math.round(u.maxMp * SK.MP_START_RATIO);
  u.mpRegen = Math.round(SK.MP_REGEN_BASE + (u.base.MOR || 0) * SK.MP_REGEN_PER_MOR);
}

// ---- 상태이상 ----
export const STATUS = {
  bleed:   { icon: '🩸', img: 'bleed', label: '출혈', debuff: true, desc: 'ATK·DEF -5%, 걸릴 때 최대 HP 5% 손실' },
  para:    { icon: '⚡', img: 'st_para', label: '마비', debuff: true, desc: '행동 불가 (연속 2턴 마비 불가)' },
  confuse: { icon: '💫', img: 'st_confuse', label: '혼란', debuff: true, desc: '자기 턴에 아군을 강제 공격' },
  disrupt: { icon: '🌀', img: 'st_disrupt', label: '교란', debuff: true, desc: '자기 턴에 자기 본진을 강제 공격' },
  immune:  { icon: '🔰', img: 'immune', label: '피해 면역', desc: '모든 피해 무효' },
  debuffImmune: { icon: '✳️', img: 'st_debuff_immune', label: '디버프 면역', desc: '디버프에 걸리지 않음' },
  taunt:   { icon: '🎯', img: 'taunt', label: '도발', desc: '상대는 이 카드부터 공격해야 함' },
  esoteric:{ icon: '☠️', img: 'st_esoteric', label: 'Esoteric', debuff: true, desc: '매 턴 HP -10%, ATK -3% 누적' },
  dot:     { icon: '🩻', img: 'st_dot', label: 'HP 고갈', debuff: true, desc: '매 턴 시작 시 HP 감소' },
  regen:   { icon: '💚', img: 'heal', label: '재생', desc: '매 턴 시작 시 HP 회복' },
  noheal:  { icon: '🚫', img: 'st_noheal', label: '회복 불가', debuff: true, desc: 'HP가 회복되지 않음' },
  decoy:   { icon: '🪞', img: 'st_decoy', label: '대신 맞기', desc: '이 카드를 향한 기본 공격을 상대 카드가 대신 맞음' },
  pleading:{ icon: '🛡️', img: 'st_pleading', label: '꼭 이래야해?', desc: '피해 50% 감면, 반격 250%, 종료 시 HP 30% 회복' },
  seed:    { icon: '🌱', img: 'st_seed', label: '쾌락의 씨앗', desc: '종료 시 HP 5% 회복' },
  provoked:{ icon: '🎯', img: 'taunt', label: '도발당함', debuff: true, desc: '도발한 카드만 공격할 수 있고 스킬을 쓸 수 없음' },
  notweak: { icon: '😤', img: 'taunt', label: '나는 약하지 않아', desc: '도발 효과가 끝나면 최대 HP 30% 회복' },
  vow:     { icon: '🛡️', img: 'def', label: '지킨다', desc: '이영아가 같은 필드에 있는 동안 매 턴 DEF +0.4% 누적, 최대 HP 2% 회복' },
  thorns:  { icon: '🌵', img: 'st_thorns', label: '반격 강화', desc: '받는 피해 감소·반격 배율 증가 (반격으로는 공격자가 쓰러지지 않음)' },
  burn:    { icon: '🔥', label: '화상', debuff: true, desc: '주는 피해 -5% (불 속성 기본 공격, 2턴)' },
  sisterSwap: { icon: '🔄', label: '선미영 교체', desc: '선나영 대신 선미영이 전투 (끝나면 선나영 HP 100% 회복, 선미영이 쓰러지면 선나영도 쓰러짐)' },
  evade:   { icon: '💨', img: 'st_evade', label: '회피', desc: '기본 공격을 확률로 회피 (회피 시 피해·반격 없음, 스킬은 회피 불가)' },
  endure:  { icon: '💢', img: 'st_endure', label: '불사', desc: 'HP가 1 아래로 내려가지 않음 (즉사 포함)' },
  guard:   { icon: '🛡️', img: 'def', label: '대신 맞기', desc: '지정한 아군을 향한 기본 공격을 대신 맞음' },
  soulsteal:{ icon: '👻', img: 'st_soulsteal', label: '영혼 강탈', desc: '이 카드를 기본 공격한 상대의 MP 20% 제거' },
  mod:     { icon: '', label: '' },
};
const MOD_ICON = (atk, def) => (atk > 0 || def > 0) ? '🔺' : '🔻';
const MOD_IMG = (atk, def) => (atk > 0 || def > 0) ? 'buff_up' : 'buff_down';

/** 상태 부여. turns: '자기 턴' 기준 지속. 대상 소유자의 턴 중에 걸리면 현재 턴은 세지 않음 */
export function addStatus(u, key, turns, data = {}, kind = key) {
  if (SKC && (typeof data.atk === 'number' || typeof data.def === 'number')) data = { ...data, ...(typeof data.atk === 'number' ? { atk: skScale(data.atk) } : {}), ...(typeof data.def === 'number' ? { def: skScale(data.def) } : {}) };   // 스킬 레벨
  const def = STATUS[kind] || {};
  const isDebuff = def.debuff || (data.atk < 0 || data.def < 0);
  if (isDebuff && (u.st.debuffImmune || hasPassive(u, '반야'))) { emit({ type: 'resist', unit: u, text: '디버프 면역' }); return false; }
  if (kind === 'para' && (u.paraBlock || u.st.para)) return false;
  const t = turns + (u.owner === TURN.p ? 1 : 0);
  u.st[key] = { ...(u.st[key] || {}), ...data, kind, t: Math.max(t, u.st[key]?.t || 0) };
  emit({ type: 'status', unit: u, kind, key, text: data.label || def.label });
  return true;
}
export const TURN = { p: null };   // 현재 턴 플레이어

export function statusIcons(u) {
  const out = [];
  for (const [k, s] of Object.entries(u.st)) {
    if (s.kind === 'mod') out.push({ icon: MOD_ICON(s.atk || 0, s.def || 0), img: MOD_IMG(s.atk || 0, s.def || 0), title: `${s.label || k} (${s.t}턴)` });
    else if (STATUS[s.kind]) out.push({ icon: STATUS[s.kind].icon, img: STATUS[s.kind].img, title: s.kind === 'vow' ? `지킨다: DEF +${(s.def * 100).toFixed(1)}% (이영아와 함께)` : s.kind === 'provoked' ? `도발당함: ${s.by?.card?.name || ''}만 공격 · 스킬 불가 (${s.t}턴)` : `${STATUS[s.kind].label} (${s.t}턴)` });
  }
  if (u.curse && foeHasPassive(u.owner, '자수정 눈물의 지옥 교향곡')) out.push({ icon: '🥀', img: 'st_curse', title: `지옥 교향곡 ×${u.curse}` });
  if (u.pairShield) out.push({ icon: '🛡️', title: `자매의 가호: 피해 무효 (${u.pairShield}턴까지)` });
  if (u.cry) out.push({ icon: '😇', img: 'st_cry', title: `천사의 절규 ×${u.cry}` });
  return out;
}

// ---- 스탯 재계산 (레벨·아이템·강화는 raw, 시너지·조합·상태는 배율) ----
const hasPassive = (u, name) => u.sk?.some(s => s.name === name && s.mode === 'passive' && u.level >= s.unlock);
const sideHasPassive = (p, name) => p.field.some(u => hasPassive(u, name));
const foeHasPassive = (p, name) => p?.foe ? sideHasPassive(p.foe, name) : false;
const findPassiveUnit = (p, name) => p.field.find(u => hasPassive(u, name));

export function refreshAll(p) { if (!p) return; refreshSide(p); if (p.foe) refreshSide(p.foe); }
function refreshSide(p) {
  const cnt = {};
  p.field.forEach(u => { cnt[u.card.class] = (cnt[u.card.class] || 0) + 1; });
  p.activeSyn = Object.entries(cnt).filter(([, n]) => n >= 2).map(([cls, n]) => ({ cls, n, pct: SK.SYNERGY[Math.min(5, n)] }));
  const ids = new Set(p.field.map(u => String(u.base.id)));
  p.activeCombos = COMBOS.filter(c => c.cards.every(id => ids.has(id)));
  const nullus = foeHasPassive(p, 'Nullus Deus est');
  const symph = foeHasPassive(p, '자수정 눈물의 지옥 교향곡');
  const male = foeHasPassive(p, 'Maledictio vel benedictio');
  const lvAura = (side, name, base) => side.field.filter(x => hasPassive(x, name)).reduce((t, x) => t + base + 0.002 * (x.level - 1), 0);
  const auraA = lvAura(p, '비오는 밤', 0.03) - (p.foe ? lvAura(p.foe, '응? 어쩌라고?', 0.02) : 0);
  const auraD = (p.foe ? lvAura(p.foe, '마지막 바람', 0.02) : 0) - (foeHasPassive(p, '넌 안 된다니까?') ? 0.05 : 0);
  // 스토리 리더 스킬: 리더가 내 필드에 있는 동안 아군 ATK·DEF·HP %, 상대 리더의 적 전체 감소(eAtk·eDef)는 여기서 뺌
  const lsOn = side => side && side.leaderSkill && side.field.some(x => x.isLeader) ? side.leaderSkill : null;
  const ls = lsOn(p), fls = lsOn(p.foe);
  const lA = (ls?.atk || 0) - (fls?.eAtk || 0), lD = (ls?.def || 0) - (fls?.eDef || 0), lH = ls?.hp || 0;
  for (const u of p.field) {
    let a = lA, d = lD, h = lH;
    const syn = p.activeSyn.find(s => s.cls === u.card.class); if (syn) { a += syn.pct; d += syn.pct; }
    for (const c of p.activeCombos) if (c.scope === 'all' || c.cards.includes(String(u.base.id))) { if (c.atk) a += c.value; if (c.def) d += c.value; if (c.hp) h += c.value; }
    for (const s of Object.values(u.st)) { a += s.atk || 0; d += s.def || 0; }
    if (u.st.esoteric) a -= 0.03 * (u.st.esoteric.stack || 0);
    if (nullus && u.card.class !== 'LIGHT') d -= 0.2;
    a += auraA; d += auraD;
    if (male) { a -= 0.5; d -= 0.5; }
    if (symph && u.curse) { a -= 0.02 * u.curse; d -= 0.02 * u.curse; }
    if (u.cry) { a += 0.05 * u.cry; d += 0.05 * u.cry; }
    if (hasPassive(u, '부덕의 괴력')) a += 0.1;   // 서태우
    if (hasPassive(u, '마르쉐')) d += 0.05;       // 유아리
    u.mods = { atk: a, def: d, hp: h };
    u.card.ATK = Math.max(1, Math.round(u.raw.ATK * Math.max(0.1, 1 + a)));
    u.card.DEF = Math.max(0, Math.round(u.raw.DEF * Math.max(0, 1 + d)));
    const wantHp = Math.round(u.base.HP * h);
    if (wantHp !== u.comboHp) { const dlt = wantHp - u.comboHp; u.comboHp = wantHp; u.maxHp += dlt; u.hp = Math.max(1, u.hp + dlt); }
    u.card.HP = u.maxHp;
  }
}

// ---- 피해 / 회복 / 사망 ----
let noCounter = 0;
/** 스킬 타격: pct = 공격력 배율. DEF는 배율만큼 비례 차감 (10회×20% = 1회×200%) */
export function skillDamage(src, target, pct, { ignoreDef = 0, extra = 1 } = {}) {
  const mult = target ? elementMultiplier(src.card.class, target.card.class) : 1;
  const def = target ? target.card.DEF * (1 - ignoreDef) : 0;
  return Math.max(1, Math.floor(src.card.ATK * pct * RULES.DAMAGE_MULT * mult * extra - def / 2 * pct));
}
/** 유닛에 피해 (면역·흡혈 처리). 반환: 실제 피해 */
// ===== 스킬 레벨 (E-6): 스토리·탑·소탕의 내 카드만. card.skillLv = { "1": 3 } (스킬 순번 1부터). 아케이드·적 카드는 Lv1 =====
export const SKILL_LV_MAX = 10, SKILL_LV_STEP = 0.03;
export const skillLvMult = lv => 1 + SKILL_LV_STEP * (Math.min(SKILL_LV_MAX, Math.max(1, lv | 0 || 1)) - 1);
export const skillCdAt = (cd, lv) => cd <= 0 ? cd : Math.max(1, cd - (lv >= 5 ? 1 : 0) - (lv >= 10 ? 1 : 0));
/** 유닛의 스킬 레벨 (액티브만, 패시브는 항상 1) */
export function skillLvOf(u, s) {
  if (!s || s.mode !== 'active') return 1;
  const i = (u.sk || []).indexOf(s), m = u.base?.skillLv || u.card?.skillLv;
  return i < 0 || !m ? 1 : Math.min(SKILL_LV_MAX, Math.max(1, m[i + 1] | 0 || 1));
}
export const skillCd = (u, s) => skillCdAt(s.cooldown, skillLvOf(u, s));
/** 스킬 실행 중 배율 ({ u: 시전자, m: 배율 }). 시전자가 주는 피해·자기 편 회복·ATK/DEF 버프/디버프 수치에만 적용 */
let SKC = null;
const skScale = v => SKC ? v * SKC.m : v;

export function damageUnit(target, dmg, src = null, { silent = false } = {}) {
  if (!target.owner.field.includes(target)) return 0;
  if (target.noDamage) { emit({ type: 'immune', unit: target }); return 0; }   // 스토리 규칙: 피해를 입지 않음 (챕터 4 각성 이민채)
  if (SKC && src === SKC.u && src.owner !== target.owner && dmg > 0) dmg = Math.max(1, Math.round(skScale(dmg)));   // 스킬 레벨
  if (target.st.immune) { emit({ type: 'immune', unit: target }); return 0; }
  // 성별 간 피해 (모든 모드·기본 공격·스킬·반격 공통): 남→여 85%, 여→남 105%
  if (src?.card && src.owner !== target.owner && dmg > 0) { const gm = genderMult(src.card, target.card); if (gm !== 1) dmg = Math.max(1, Math.round(dmg * gm)); }
  if (src?.card && src.owner !== target.owner && dmg > 0) {
    if (chance(critRate(src.card))) { dmg = Math.round(dmg * RULES.CRIT_MULT); emit({ type: 'crit', unit: target, src }); stats.count('치명타'); }   // 치명타: 기본 공격·스킬·반격
    if (src.st?.burn) dmg = Math.max(1, Math.round(dmg * (1 - RULES.BURN_DOWN)));   // 화상: 주는 피해 -5%
    if (RULES.EL_PASSIVE_ON && target.card?.class === 'ICE' && chance(RULES.ICE_GUARD_P)) { dmg = Math.max(1, Math.round(dmg * RULES.ICE_GUARD_MULT)); emit({ type: 'elfx', unit: target, kind: 'guard' }); }   // 얼음 방어
  }
  if (target.st.pleading) dmg = Math.round(dmg * 0.5);
  if (target.st.thorns?.red) dmg = Math.round(dmg * (1 - target.st.thorns.red));   // 이게 프로야·에메랄드 쇼크
  target.hp -= dmg;
  if (target.undying && target.hp < 1) target.hp = 1;   // 스토리 보스: 쓰러지지 않음
  if (target.st.endure && target.hp < 1) target.hp = 1;   // 불사 (언니니까!·카르밀라...사랑해)
  if (src && dmg > 0 && src.owner !== target.owner) emit({ type: 'dealt', src, dmg });
  if (!silent) emit({ type: 'dmg', unit: target, dmg });
  if (src && src.hp > 0 && hasPassive(src, '우습네요') && heal(src, Math.round(dmg * 0.3), '흡혈')) stats.count('우습네요');
  if (src && src.hp > 0 && src.owner !== target.owner && hasPassive(src, '플레쉬') && heal(src, Math.round(dmg * 0.1), '플레쉬')) stats.count('플레쉬');
  return dmg;
}
export function heal(u, amt, why = '') {
  if (!u.owner.field.includes(u) || amt <= 0 || u.st.noheal) return 0;
  if (SKC && u.owner === SKC.u.owner) amt = skScale(amt);   // 스킬 레벨
  const h = Math.min(u.maxHp - u.hp, Math.round(amt)); if (h <= 0) return 0;
  u.hp += h; emit({ type: 'heal', unit: u, amt: h, why }); return h;
}
export function healHero(p, amt) { if (SKC && p === SKC.u.owner) amt = skScale(amt); const b = p.hp; p.hp = Math.min((p.maxHp || RULES.HERO_HP), p.hp + Math.round(amt)); if (p.hp > b) emit({ type: 'heroHeal', p, amt: p.hp - b }); return p.hp - b; }

/** 본진 피해. srcOwner가 자기 첫 N턴이면 차단 (자기 본진 강제 공격은 예외) */
export function damageHero(p, dmg, srcOwner, kind = 'hit', srcUnit = null) {
  if (p.noBase) {   // 스토리 일반전: 진영 없음. 진영을 노린 피해는 상대 카드(HP 가장 낮은 카드)에게, 초과·자기 피해는 무효
    if (kind === 'overflow' || kind === 'self' || !srcOwner || srcOwner === p) return 0;
    const t = p.field.filter(u => u.hp > 0 && !u.undying).sort((a, b) => a.hp - b.hp)[0];
    if (t) { damageUnit(t, Math.round(dmg), srcUnit); checkDeath(t, srcUnit); }
    return 0;
  }
  if (srcOwner && srcOwner !== p && heroLocked(srcOwner)) return 0;
  if (p.st.heroInvuln) { emit({ type: 'heroImmune', p }); return 0; }
  if (SKC && srcOwner === SKC.u.owner && srcOwner !== p && kind !== 'self' && dmg > 0) dmg = Math.max(1, Math.round(skScale(dmg)));   // 스킬 레벨 (보스 진영)
  if (srcUnit && srcOwner && srcOwner !== p && srcUnit.card?.grade === 'MYTHIC RARE') dmg = Math.max(1, Math.round(dmg * RULES.MR_HERO_DMG_RATIO));
  if (p.st.heroShield) dmg = Math.max(1, Math.round(dmg / (1 + p.st.heroShield.def)));
  p.hp -= dmg;
  if (srcUnit && dmg > 0 && srcUnit.owner !== p) emit({ type: 'dealt', src: srcUnit, dmg });
  if (kind !== 'attack' && kind !== 'overflow') emit({ type: 'hero', p, dmg, kind });
  if (srcUnit && srcUnit.hp > 0 && hasPassive(srcUnit, '우습네요')) heal(srcUnit, Math.round(dmg * 0.3), '흡혈');
  if (srcUnit && srcUnit.hp > 0 && hasPassive(srcUnit, '플레쉬')) heal(srcUnit, Math.round(dmg * 0.1), '플레쉬');
  if (p.hp <= 0) {
    const zen = !p.once['참선'] && findPassiveUnit(p, '참선');
    if (zen) {
      p.once['참선'] = 1; stats.count('참선'); p.hp = Math.min((p.maxHp || RULES.HERO_HP), Math.max(0, p.hp) + 300);
      p.st.heroInvuln = { t: 1 + (TURN.p === p ? 1 : 0) };
      emit({ type: 'passive', unit: zen, name: '참선', text: '본진 붕괴 직전! 1턴 무적 + HP 300 회복' });
    } else p.hp = 0;
  }
  return dmg;
}
/** HP 0 이하 유닛 정리 → 무덤, 사망 트리거, 처치 보상 */
export function checkDeath(u, killer = null) {
  const p = u.owner;
  if (u.hp > 0 || !p.field.includes(u)) return false;
  if (u.undying) { u.hp = 1; return false; }   // 스토리 보스: 즉사·스킬로도 쓰러지지 않음
  if (u.st.endure) { u.hp = 1; emit({ type: 'resist', unit: u, text: '불사' }); return false; }
  // 하지은 나는 쓰러지지 않아: 사망 시 1회 즉시 부활 (HP 50%), 1턴 피해 면역
  if (hasPassive(u, '나는 쓰러지지 않아') && !u.fired['나는 쓰러지지 않아:rev']) {
    u.fired['나는 쓰러지지 않아:rev'] = 1; stats.count('나는 쓰러지지 않아');
    u.hp = Math.max(1, Math.round(u.maxHp * JIEUN_REVIVE_HP));
    addStatus(u, 'immune', 1, {}, 'immune');
    emit({ type: 'passive', unit: u, name: '나는 쓰러지지 않아', text: `부활! HP ${JIEUN_REVIVE_HP * 100}% · 1턴 피해 면역` });
    emit({ type: 'heal', unit: u, amt: u.hp, why: '나는 쓰러지지 않아' }); refreshAll(p);
    return false;
  }
  // 제발…그만 (문유선): 사망 시 1회 부활, HP 100%, 디버프 제거, 1턴 면역 + 도발
  if (hasPassive(u, '제발…그만') && !u.fired['제발…그만']) {
    u.fired['제발…그만'] = 1; stats.count('제발…그만');
    emit({ type: 'passive', unit: u, name: '제발…그만', skill: (u.sk || []).find(s => s.name === '제발…그만') });
    for (const [k, s] of Object.entries(u.st)) if (STATUS[s.kind]?.debuff || s.atk < 0 || s.def < 0) delete u.st[k];
    u.curse = 0; u.hp = u.maxHp;
    addStatus(u, 'immune', 1, {}, 'immune'); addStatus(u, 'taunt', 1, {}, 'taunt');
    emit({ type: 'heal', unit: u, amt: u.maxHp, why: '제발…그만' }); refreshAll(p);
    return false;
  }
  if (u.swap) unswap(u, false);   // 선미영이 쓰러지면 선나영이 쓰러진 것으로 처리
  p.field.splice(p.field.indexOf(u), 1);
  p.grave.push(u.base);
  // 문지철 너..는..데리고..갈게: 사망 시 품성 최저 적 250 고정 피해, 처치하면 양 옆 80
  if (p.foe && hasPassive(u, '너..는..데리고..갈게')) {
    const f = p.foe, t = by(live(f).filter(x => !x.undying), x => x.base.MOR || 0);
    if (t) {
      emit({ type: 'passive', unit: u, name: '너..는..데리고..갈게', text: `${t.card.name}에게 250 고정 피해` }); stats.count('너..는..데리고..갈게');
      const nb = sides(f, t);
      damageUnit(t, 250, null);
      if (checkDeath(t, null)) { nb.forEach(x => damageUnit(x, 80, null)); nb.forEach(x => checkDeath(x, null)); }
    }
  }
  p.lastDead = u.base;
  // 유가을 [도저히 용서 못해!]: 민유연이 쓰러지면 (전투당 1회, 유가을이 필드에 있을 때) 상대 전체 2턴 DEF -20% + 1턴 출혈
  if (p.foe && String(u.base.id) === '2000100008' && !p.gaeulRage) {
    const g = p.field.find(x => x !== u && x.hp > 0 && hasPassive(x, '도저히 용서 못해!'));
    if (g) { p.gaeulRage = true; emit({ type: 'passive', unit: g, name: '도저히 용서 못해!' }); stats.count('도저히 용서 못해!'); debuffAll(p.foe, '도저히 용서 못해!', 2, { def: -0.2, label: 'DEF -20%' }); live(p.foe).forEach(t => bleedOn(t, g, 1)); }
  }
  if (p.foe && hasPassive(u, '지아는 약하지 않아!')) { emit({ type: 'passive', unit: u, name: '지아는 약하지 않아!' }); stats.count('지아는 약하지 않아!'); live(p.foe).forEach(t => addStatus(t, '지아는 약하지 않아!', 1, { atk: -0.7, label: 'ATK -70%' }, 'mod')); }
  if (p.foe && hasPassive(u, '나는 멈춘다')) { emit({ type: 'passive', unit: u, name: '나는 멈춘다' }); stats.count('나는 멈춘다'); live(p.foe).forEach(t => addStatus(t, 'para', 1, {}, 'para')); }
  if (p.foe && hasPassive(u, '더는 나를 밀지마')) { emit({ type: 'passive', unit: u, name: '더는 나를 밀지마' }); stats.count('더는 나를 밀지마'); live(p.foe).forEach(t => bleedOn(t, u, 2)); }
  emit({ type: 'destroy', unit: u });
  // 이명진 지킨다: 맹세 중 이영아가 쓰러지면 쿨타임 전부 초기화 + 3턴 ATK +60%
  if (String(u.base.id) === YOUNGA_ID) for (const a of p.field) if (a.st.vow) vowBroken(a);
  // MP 흡수: 처치한 카드가 상대의 현재 MP 20% 흡수 (최소 3)
  if (killer && killer.owner !== p && killer.hp > 0 && killer.owner.field.includes(killer)) gainMp(killer, Math.max(SK.MP_ABSORB_MIN, Math.round((u.mp || 0) * SK.MP_ABSORB_RATIO)), '흡수');
  // 표식: 사망 시 시전자 MP 회복
  for (const s of Object.values(u.st)) if (s.mpOnDeath && s.caster && s.caster.owner.field.includes(s.caster)) gainMp(s.caster, s.caster.maxMp * s.mpOnDeath, s.label);
  // 천사의 절규: 아군 사망마다
  for (const a of p.field) if (hasPassive(a, '천사의 절규')) { stats.count('천사의 절규'); a.cry++; heal(a, a.maxHp * 0.2, '천사의 절규'); emit({ type: 'passive', unit: a, name: '천사의 절규' }); }
  if (killer && killer.owner !== p) {
    const o = killer.owner, before = o.mana || 0;
    o.mana = Math.min(RULES.MANA_MAX, before + Math.round(u.card.cost * RULES.KILL_MANA_RATIO));
    const refund = o.mana - before;
    o.killMana = (o.killMana || 0) + refund;
    emit({ type: 'refund', owner: o, killer, refund });
    gainXp(killer, killXp(u));
  }
  if (u.isLeader && !p.once.leaderDown) leaderDown(p, u);
  refreshAll(p);
  return true;
}
/** 스토리 리더가 쓰러짐 (1전투 1번): 아군 진영 HP −(최대의 30%). 진영이 없는 스토리 내 진영은 남은 아군 카드 전체가 각자 최대 HP의 30%를 잃음 (쓰러질 수 있음) */
function leaderDown(p, u) {
  p.once.leaderDown = 1;
  const pct = p.leaderSkill?.deathPenalty ?? 0.3;
  if (!p.noBase) {
    const dmg = Math.round((p.maxHp || RULES.HERO_HP) * pct);
    p.hp = Math.max(0, p.hp - dmg);
    emit({ type: 'leaderDown', p, unit: u, dmg, pct, base: true });
    return;
  }
  const hit = p.field.filter(a => a.hp > 0 && !a.noDamage).map(a => { const dmg = Math.max(1, Math.round(a.maxHp * pct)); a.hp -= dmg; emit({ type: 'dmg', unit: a, dmg }); return [a, dmg]; });
  emit({ type: 'leaderDown', p, unit: u, pct, dmg: hit.reduce((t, [, d]) => t + d, 0), n: hit.length });
  for (const [a] of hit) checkDeath(a, null);
}
export function gainMp(u, amt, why = '') { const b = u.mp; u.mp = Math.min(u.maxMp, Math.round(u.mp + amt)); if (u.mp > b) emit({ type: 'mp', unit: u, amt: u.mp - b, why }); }

// ---- 레벨 변화 → 해금 패시브 발동 ----
export function onLevelChange(u) { if (u.owner) { emit({ type: 'levelup', unit: u, level: u.level }); refreshAll(u.owner); onUnlockCheck(u); } }
/** 효과가 계속 켜져 있어 따로 발동 이벤트가 없는 패시브: 해금(또는 해금된 채 소환)될 때 한 번 연출 */
export const AURA_PASSIVES = new Set(['Nullus Deus est', '우습네요', 'Maledictio vel benedictio', '넌 안 된다니까?', '검은 늪', '비오는 밤', '응? 어쩌라고?', '마지막 바람', '이게 반격이야', '마르쉐', '플레쉬', '부덕의 괴력', '내가 지켜준다', '너도 언젠간 죽어', '나는 쓰러지지 않아']);
function onUnlockCheck(u) {
  for (const s of u.sk || []) {
    if (s.mode === 'passive' && u.level >= s.unlock && AURA_PASSIVES.has(s.name) && !u.fired['aura:' + s.name]) {
      u.fired['aura:' + s.name] = 1; emit({ type: 'passive', unit: u, name: s.name, skill: s, text: '활성화' });
    }
    if (s.mode !== 'passive' || u.level < s.unlock || !PASSIVE_ONCE[s.name]) continue;
    const onceGame = /최초|게임 당/.test(s.note) || s.name === '강북대장';
    if (u.fired[s.name] || (onceGame && u.owner.once[s.name])) continue;
    u.fired[s.name] = 1; if (onceGame) u.owner.once[s.name] = 1;
    emit({ type: 'passive', unit: u, name: s.name, skill: s });
    PASSIVE_ONCE[s.name](u, u.owner, u.owner.foe, s);
    stats.count(s.name);
    refreshAll(u.owner);
  }
}

// ---- 시뮬 통계 ----
export const stats = { counts: {}, count(n) { this.counts[n] = (this.counts[n] || 0) + 1; } };

// ===== 패시브: 해금 시 1회 발동 =====
const PASSIVE_ONCE = {
  // 최초 필드 출연 후 2턴(출연 턴 포함) → 3번째 자기 턴 시작 전에 해제
  '강북대장': u => { u.st['강북대장'] = { kind: 'mod', atk: 0.2, label: '강북대장 ATK +20%', t: 2 }; u.st.debuffImmune = { kind: 'debuffImmune', t: 2 }; },
  '본투킬': u => { addStatus(u, 'taunt', 2, {}, 'taunt'); addStatus(u, 'immune', 2, {}, 'immune'); },
  'Noli spem tibi erigere': (u, p, f) => { for (const t of [...f.field]) { damageUnit(t, Math.ceil(t.maxHp * 0.95), null); checkDeath(t, u); } },
  '진멸의 여제': (u, p) => { p.st.heroShield = { def: 3, t: 2 + (TURN.p === p ? 1 : 0) }; for (const a of p.field) addStatus(a, 'immune', 2, {}, 'immune'); },
  // 이민채: 해금(소환) 후 2턴 간 쓰러지지 않음
  '카르밀라...사랑해': u => addStatus(u, 'endure', 2, { label: '불사 2턴' }, 'endure'),
  // 10/25 신규·변경 패시브 (출전·해금 시 1회)
  '미쳐간다': u => addStatus(u, 'evade', 2, { p: 0.2, label: '회피 +20%' }, 'evade'),   // 조윤하
  '잔상': (u, p) => { for (const a of p.field) addStatus(a, 'endure', 2, { label: '잔상: 사망하지 않음 (즉사 포함)' }, 'endure'); },   // 이영아
  '언니는 강해요!': (u, p) => immuneAllies(p, a => a !== u && a.base.gender === 'FEMALE' && a.card.cost < u.card.cost, 2, '언니는 강해요!'),   // 정지선
  '몸은 약해요. 하지만 정신은 그렇지 않아!': u => { addStatus(u, 'taunt', 1, {}, 'taunt'); addStatus(u, 'endure', 1, { label: '최소 HP 1 유지' }, 'endure'); },   // 예유진
  '반야': u => { for (const [k, s] of Object.entries(u.st)) if (STATUS[s.kind]?.debuff || s.atk < 0 || s.def < 0) delete u.st[k]; u.curse = 0; },
  '존재의 증명': (u, p) => { for (const a of [...p.field]) for (let i = 0; i < 2 && a.level < RULES.LEVEL_MAX; i++) { levelUpOnce(a); onLevelChange(a); } healHero(p, (p.maxHp || RULES.HERO_HP) * 0.5); },
};

// ===== 액티브 스킬 =====
// 대상 제외 (스토리): SPARE = { 공격자 카드id: [보호 카드id...] } → 그 공격자는 기본 공격·스킬·반격·광역 모두 그 카드를 대상으로 삼지 않음
let SPARE = null, ACTOR = null;
export function setSpare(m) { SPARE = m && Object.keys(m).length ? m : null; }
export function spares(a, t) { if (!SPARE || !a || !t || a.owner === t.owner) return false; const l = SPARE[String(a.card?.id)]; return !!l && l.includes(String(t.card?.id)); }
/** 보호 규칙 때문에 칠 수 있는 상대가 하나도 없음 → 이번 턴 행동 없음 */
export function spareBlocked(u) { if (!SPARE || !SPARE[String(u?.card?.id)] || !u.owner?.foe) return false; const fs = u.owner.foe.field.filter(x => x.hp > 0); return fs.length > 0 && fs.every(x => spares(u, x)); }
const live = p => ACTOR ? p.field.filter(x => !spares(ACTOR, x)) : [...p.field];
const by = (arr, f, dir = 1) => arr.slice().sort((a, b) => dir * (f(a) - f(b)))[0];
const GRADE_ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];
const gradeIdx = x => GRADE_ORDER.indexOf(typeof x === 'string' ? x : x.base.grade);
const immuneAllies = (p, pred, turns) => { for (const a of live(p)) if (pred(a)) addStatus(a, 'immune', turns, {}, 'immune'); };
// 선나영 [언니...도와줘요.]: 2턴 간 선미영(같은 레벨)으로 교체. 끝나면 선나영으로 돌아와 HP 100%. 선미영이 쓰러지면 선나영도 쓰러짐
export const MIYOUNG_ID = '2000400094';
const LV_RATE = { 'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06 };
function swapSister(u) {
  const mc = poolCard(MIYOUNG_ID); if (!mc || u.swap) return;
  const L = Math.max(1, u.base.slv || u.base.qLevel || 1), m = 1 + (LV_RATE[mc.grade] || 0.01) * (L - 1);
  const nb = { ...mc, HP: Math.round(+mc.HP * m), ATK: Math.round(+mc.ATK * m), DEF: Math.round(+mc.DEF * m), slv: L };
  u.swap = { base: u.base, card: u.card, raw: u.raw, sk: u.sk, maxHp: u.maxHp, hp: u.hp, comboHp: u.comboHp };
  Object.assign(u, { base: nb, card: { ...nb }, raw: { ATK: nb.ATK, DEF: nb.DEF }, sk: skillsOf(MIYOUNG_ID), maxHp: nb.HP, hp: nb.HP, comboHp: 0 });
  addStatus(u, 'sisterSwap', 2, {}, 'sisterSwap');
  emit({ type: 'log', text: `${u.swap.base.name} → ${nb.name} 교체 (Lv.${L}, 2턴)` });
  refreshAll(u.owner); onUnlockCheck(u);
}
function unswap(u, healFull = true) {
  const o = u.swap; if (!o) return; u.swap = null; delete u.st.sisterSwap;
  Object.assign(u, { base: o.base, card: o.card, raw: o.raw, sk: o.sk, maxHp: o.maxHp, comboHp: o.comboHp });
  u.hp = healFull ? u.maxHp : Math.min(u.hp, 0);
  if (healFull) { emit({ type: 'heal', unit: u, amt: u.maxHp, why: '언니...도와줘요.' }); refreshAll(u.owner); }
}
export const chance = p => rng() < p;
/** 자기 디버프 1개 해제 (빛 정화). 해제했으면 true */
export function cleanseOne(u) {
  for (const [k, s] of Object.entries(u.st)) { const d = STATUS[s.kind]; if (d?.debuff || (s.kind === 'mod' && ((s.atk || 0) < 0 || (s.def || 0) < 0))) { delete u.st[k]; if (u.owner) refreshAll(u.owner); return true; } }
  return false;
}
/** 다회 타격: 대상 하나에 n회. 반환: 죽였는지 */
function multiHit(src, t, n, pct, opt = {}) {
  for (let i = 0; i < n; i++) { if (!t.owner.field.includes(t) || t.hp <= 0) break; damageUnit(t, skillDamage(src, t, pct, opt), src); }
  return checkDeath(t, src);
}
/** 적 전체 n회 타격. 반환: 사망자 수 */
function hitAll(src, f, n, pct, opt = {}) {
  const targets = live(f); let dead = 0;
  for (let i = 0; i < n; i++) for (const t of targets) if (f.field.includes(t) && t.hp > 0) damageUnit(t, skillDamage(src, t, pct, opt), src);
  for (const t of targets) if (checkDeath(t, src)) dead++;
  return dead;
}
const heroHit = (src, f, pct) => damageHero(f, skillDamage(src, null, pct), src.owner, 'skill', src);
const debuffAll = (f, key, turns, data) => live(f).forEach(t => addStatus(t, key, turns, data, data.kind || 'mod'));
const bleedOn = (t, src, turns = 1) => { if (addStatus(t, 'bleed', turns, { atk: -0.05, def: -0.05 }, 'bleed')) { damageUnit(t, Math.max(1, Math.round(t.maxHp * 0.05)), null); checkDeath(t, src); } };
/** 현재 HP의 pct 제거 (카드당 최대 cap) */
const hpCut = (u, f, pct, cap) => { const ts = live(f); ts.forEach(t => damageUnit(t, Math.min(cap, Math.max(1, Math.round(t.hp * pct))), u)); ts.forEach(t => checkDeath(t, u)); };
/** 필드 양 옆 카드 */
const sides = (side, t) => { const i = side.field.indexOf(t); return [side.field[i - 1], side.field[i + 1]].filter(Boolean); };
/** 도발 + DEF 상승 (+ 종료 시 회복) */
const tauntSelf = (u, name, turns, def, endHeal = 0) => { addStatus(u, 'taunt', turns, {}, 'taunt'); addStatus(u, name, turns, { def, endHeal, label: `${name}: DEF +${Math.round(def * 100)}%${endHeal ? `, 종료 시 HP ${endHeal * 100}% 회복` : ''}` }, 'mod'); };
/** 고정 피해 + 양 옆 고정 피해, 사망자 있으면 MP 회복 */
const fixedBlast = (u, f, t, main, side, mp) => { if (!t) return; const nb = sides(f, t); damageUnit(t, main, u); nb.forEach(x => damageUnit(x, side, u)); let d = 0; [t, ...nb].forEach(x => { if (checkDeath(x, u)) d++; }); if (d) gainMp(u, u.maxMp * mp, '사망자 발생'); };
/** 주 대상 피해 + 양 옆에 그 피해의 r */
const splash = (u, f, t, pct, r) => { if (!t) return; const nb = sides(f, t); const d = damageUnit(t, skillDamage(u, t, pct), u); nb.forEach(x => damageUnit(x, Math.max(1, Math.round(d * r)), u)); [t, ...nb].forEach(x => checkDeath(x, u)); };
/** 적 전체 1회 타격, 처치된 카드의 초과 피해는 본진으로 (본진 공격 불가 턴·일반전은 무효) */
function hitAllOverflow(src, f, pct) {
  let over = 0; const ts = live(f);
  for (const t of ts) { if (!f.field.includes(t)) continue; const before = t.hp, d = damageUnit(t, skillDamage(src, t, pct), src); if (t.hp <= 0) over += Math.max(0, d - before); }
  ts.forEach(t => checkDeath(t, src));
  if (over > 0) { const d = damageHero(f, over, src.owner, 'overflow', src); if (d > 0) emit({ type: 'log', text: `${src.card.name} 초과 피해 ${d} → ${f.name || '상대'} 진영` }); }
}
/** 다회 타격 + 중간에 대상이 쓰러지면 다음 대상으로 (전이마다 남은 횟수 -1) */
function retargetHits(src, f, n, pct, pick) {
  let t = pick(live(f)), left = n;
  while (t && left > 0) {
    damageUnit(t, skillDamage(src, t, pct), src); left--;
    if (checkDeath(t, src)) { left--; t = pick(live(f)); if (t && left > 0) emit({ type: 'log', text: `${src.card.name}: ${t.card.name}에게 전이 (남은 ${left}회)` }); }
  }
}
/** 적 전체 고정 피해 */
const fixedAll = (u, f, n) => { const ts = live(f); ts.forEach(t => damageUnit(t, n, u)); ts.forEach(t => checkDeath(t, u)); };
/** 하지혜 [죽지 않으려면 죽여] 1회분: 대상들에게 30%×4, 그 뒤 HP 50% 미만이면 1턴 출혈 */
function jihyeStrike(u, ts) {
  for (let i = 0; i < 4; i++) ts.forEach(t => { if (t.owner.field.includes(t) && t.hp > 0) damageUnit(t, skillDamage(u, t, 0.3), u); });
  ts.forEach(t => { if (!checkDeath(t, u) && t.owner.field.includes(t) && t.hp < t.maxHp * 0.5) bleedOn(t, u, 1); });
}
const pickRandom = arr => arr.length ? arr[Math.floor(rng() * arr.length)] : null;
const yuriKiss = (u, f, prob, kind) => { if (chance(prob)) live(f).forEach(t => addStatus(t, kind, 1, {}, kind)); else emit({ type: 'miss', unit: u, text: '확률 실패' }); f.actionLock = Math.max(f.actionLock, 1); emit({ type: 'log', text: `${f.name || '상대'}: 다음 턴 고유기술(셔플·보강·강화·필드 회복) 봉인` }); };

export const ACTIVE = {
  // [각성] 이민채 (NPC, 챕터 4 보스): 랜덤 2인을 공격력 15%로 5회씩 타격
  // [염원] 이민채 (NPC, 챕터 4 보스 분신): 적 전체 공격력 30%
  '이건 사랑이야': (u, p, f) => { hitAll(u, f, 1, 0.3); },
  '사랑해!!!': (u, p, f) => { const pool = [...live(f)]; for (let k = 0; k < 2 && pool.length; k++) { const t = pool.splice(Math.floor(rng() * pool.length), 1)[0]; multiHit(u, t, 5, 0.15); } },
  // 지세강
  '절망하라': (u, p, f, s) => { const t = by(live(f), x => x.card.cost); if (t && multiHit(u, t, 5, 0.3)) u.cd[s.name] = 0; },
  '아파하라': (u, p, f, s) => { const t = by(live(f), x => x.card.cost, -1); if (t && multiHit(u, t, 5, 0.4)) u.cd[s.name] = 0; },
  // 김성진
  'Da nunc': (u, p, f, s) => { const d = hitAll(u, f, 10, 0.2); u.cd[s.name] = Math.max(0, u.cd[s.name] - d); },
  'Tempus est discerpi': (u, p, f) => { live(f).forEach(t => addStatus(t, 'disrupt', 1, {}, 'disrupt')); p.actionLock = Math.max(p.actionLock, 2); },
  // 최창민
  '잘린다': (u, p, f) => { const ts = live(f); hitAll(u, f, 3, 0.2); ts.forEach(t => f.field.includes(t) && chance(0.2) && bleedOn(t, u)); },
  '러시안룰렛': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t) { t.hp = 0; emit({ type: 'dmg', unit: t, dmg: '즉사' }); checkDeath(t, u); }
    if (u.hp > 1) damageUnit(u, Math.floor(u.hp * 0.99), null); },   // 대가: 자신의 현재 HP 99% 하락 (피해 면역·불사는 뚫지 않음, 최소 1 남음)
  // 10/25 신규 액티브
  '핑핑 돌지?': (u, p) => { for (const a of live(p)) addStatus(a, 'evade', 1, { p: 0.1, label: '회피 +10%' }, 'evade'); },   // 서진성
  '무시하지 마세요.': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && gradeIdx(a) <= gradeIdx('RARE'), 2),   // 류하예
  '약육강식? 웃기지 마세요.': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && gradeIdx(a) <= gradeIdx('HIGH RARE'), 2),   // 지세련
  '부드러움은 강함을 이깁니다': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && gradeIdx(a) <= gradeIdx('HIGH RARE'), 2),   // 홍다영
  '당하고만 살진 않아요': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && gradeIdx(a) <= gradeIdx('HIGH RARE'), 2),   // 신아린
  '더 이상의 비극은 없어!': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && gradeIdx(a) <= gradeIdx('HIGH RARE'), 2),   // 이윤이
  '귀족이...전부 악인은 아니랍니다.': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && (a.base.MOR || 0) >= 50, 2),   // 허유희
  '약해 보인다고 무시하지 마!': (u, p) => immuneAllies(p, a => a.base.gender === 'FEMALE' && a.card.cost < 35, 1),   // 남태은
  '내가 누군지 아냐?': u => addStatus(u, 'immune', 2, {}, 'immune'),   // 최국선
  '언니...도와줘요.': u => swapSister(u),   // 선나영 → 선미영 2턴
  // 최창원
  '웃자!': (u, p, f) => { const t = by(live(f), x => x.card.DEF); if (t) multiHit(u, t, 10, t.base.gender === 'FEMALE' ? 0.25 : 0.2); },
  '나약하네..': (u, p, f) => debuffAll(f, '나약하네..', 2, { def: -0.2, label: 'DEF -20%' }),
  '울자!': (u, p, f) => { const t = by(live(f), x => x.card.ATK, -1); if (t) multiHit(u, t, 5, t.base.gender === 'FEMALE' ? 0.35 : 0.3); },
  // 서성민
  '반야': (u, p) => live(p).forEach(a => heal(a, a.maxHp * 0.2)),
  '열반': (u, p) => { live(p).forEach(a => heal(a, a.maxHp * 0.1)); healHero(p, (p.maxHp || RULES.HERO_HP) * 0.1); },
  // 이성호
  'Fiat Lux': (u, p, f) => { const full = f.field.length >= RULES.FIELD_MAX; hitAll(u, f, 2, 0.3); if (!full) heroHit(u, f, 0.3); },
  'Sperandum Est Infestis': (u, p, f) => { const ts = live(f); for (let i = 0; i < 2; i++) ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.2, { extra: t.card.cost < 30 ? 2 : 1 }), u)); ts.forEach(t => checkDeath(t, u)); },
  'Memento Mori': (u, p, f) => { const ts = live(f); hitAll(u, f, 3, 0.2); ts.forEach(t => f.field.includes(t) && chance(0.2) && addStatus(t, 'para', 1, {}, 'para')); },
  // 임유리
  '아름다운 고통의 키스': (u, p, f) => { hpCut(u, f, 0.08, 120); yuriKiss(u, f, 0.3, 'confuse'); },
  '더 울어, 예쁘게!': (u, p, f) => { hpCut(u, f, 0.12, 180); yuriKiss(u, f, 0.3, 'disrupt'); },
  '천천히 찢는 사랑': (u, p, f) => { const ts = live(f); hitAll(u, f, 2, 0.4); ts.forEach(t => f.field.includes(t) && chance(0.5) && bleedOn(t, u)); },
  // 임나리
  'Seductive Whisper': (u, p, f) => { if (hitAll(u, f, 3, 0.2)) gainMp(u, u.maxMp * 0.1, '사망자 발생'); },
  'Alluring Dance': (u, p, f) => { if (hitAll(u, f, 3, 0.3)) gainMp(u, u.maxMp * 0.15, '사망자 발생'); },
  'Fatal Temptation': (u, p, f) => { const d = heroHit(u, f, 2.0); if (d > 0) { const ts = live(f); ts.forEach(t => damageUnit(t, Math.max(1, Math.round(d * 0.2)), u)); ts.forEach(t => checkDeath(t, u)); } },
  // 임규리
  '천사의 시': (u, p, f) => hitAll(u, f, 3, 0.2, { ignoreDef: 1 }),
  '천사의 자장가': (u, p, f) => { const d = hitAll(u, f, 5, 0.2); if (d) heal(u, u.maxHp * 0.1 * d, '자장가'); },
  // 정아람
  '人鬼相半': (u, p, f) => { const d = hitAll(u, f, 2, 0.3); if (d) heal(u, u.maxHp * 0.1 * d, '人鬼相半'); },
  '夜不談鬼': (u, p, f) => { let died = false; for (let i = 0; i < 5; i++) { if (died || !f.field.length) heroHit(u, f, 0.2); else { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.2), u)); ts.forEach(t => { if (checkDeath(t, u)) died = true; }); } } },
  // 김신현
  '신기하네요': (u, p, f, s) => { const t = by(live(f), x => x.card.ATK, -1); if (t && multiHit(u, t, 10, 0.2)) u.cd[s.name] = 0; },
  // 임예리
  '달빛 속 배신의 속삭임': (u, p, f) => (hitAll(u, f, 1, 0.1), debuffAll(f, '달빛 속 배신의 속삭임', 2, { def: -0.2, label: '달빛: DEF -20%', mpOnDeath: 0.1, caster: u })),
  '장미가시의 세레나데': (u, p, f) => { hitAll(u, f, 1, 0.1); debuffAll(f, '장미가시의 세레나데', 3, { atk: -0.2, label: '장미가시: ATK -20%', rose: u }); addStatus(u, 'taunt', 1, {}, 'taunt'); },
  // 임혜리
  '주님 저희를 구하소서': (u, p) => live(p).forEach(a => { heal(a, a.maxHp * 0.2); cleanse(a); }),
  '하느님의 영광': (u, p) => { if (!p.grave.length) return; const c = by(p.grave, x => x.cost, -1); p.grave.splice(p.grave.indexOf(c), 1); if (!owns(p, c)) { p.hand.push(c); emit({ type: 'revive', p, card: c }); } },
  // 이지영
  'Incipit nunc sic': (u, p, f) => { const d = hitAll(u, f, 1, 0.5); if (d) gainMp(u, u.maxMp * 0.15 * d, '사망자 수'); },
  'Divina tibi poena adveniat': (u, p) => { addStatus(u, 'Divina', 2, { atk: 2.0, label: 'ATK +200%' }, 'mod'); live(p).filter(a => a !== u).forEach(a => addStatus(a, 'Divina', 2, { atk: 0.3, label: 'ATK +30%' }, 'mod')); },
  'Cum amicis meis sacris sum': (u, p, f) => debuffAll(f, 'Cum amicis', 2, { atk: -0.3, def: -0.3, label: 'ATK·DEF -30%', mpOnDeath: 0.1, caster: u }),
  // 이진경
  'My Black Sun': (u, p, f) => live(f).filter(t => t.card.cost < 40).forEach(t => addStatus(t, 'disrupt', 1, {}, 'disrupt')),
  'Esoteric Method': (u, p, f) => live(f).forEach(t => addStatus(t, 'esoteric', 3, { stack: 0 }, 'esoteric')),
  // 김백중
  '다친다': (u, p, f) => hitAll(u, f, 5, 0.2, { ignoreDef: 0.5 }),
  '죽을지도 몰라': (u, p, f, s) => { let d = 0; for (let i = 0; i < 5; i++) { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.2, { ignoreDef: 0.3 }), u)); ts.forEach(t => { if (checkDeath(t, u)) d++; }); heroHit(u, f, 0.2); } if (d) { u.cd[s.name] = 0; gainMp(u, u.maxMp * 0.3, '사망자 발생'); } },
  '죽는다…': (u, p, f) => { heroHit(u, f, 2.0); live(f).forEach(t => bleedOn(t, u)); },
  // [각성] 윤진아
  '여기는 뇌입니다': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (!t) return; let killed = false, heroHits = 0; for (let i = 0; i < 3; i++) { if (!killed) { damageUnit(t, skillDamage(u, t, 0.5, { ignoreDef: 0.3 }), u); killed = checkDeath(t, u); } else { heroHit(u, f, 0.5); heroHits++; } } if (killed && !heroHits) heroHit(u, f, 0.5); },
  '이게 심장인가요?': (u, p, f) => { let t = by(live(f), x => x.card.cost); for (let i = 0; i < 4 && t; i++) { damageUnit(t, skillDamage(u, t, 0.5, { ignoreDef: 0.3 }), u); if (checkDeath(t, u)) t = by(live(f), x => x.card.cost); } },
  '감당…해주세요.': (u, p, f) => { const t = by(live(f), x => x.card.ATK, -1); if (t && multiHit(u, t, 5, 0.5, { ignoreDef: 0.3 })) { u.mp = u.maxMp; emit({ type: 'mp', unit: u, amt: 'MAX' }); } },
  // [각성] 임유리
  '아름다운 고통의 키스(眞)': (u, p, f) => { fixedAll(u, f, 120); yuriKiss(u, f, 0.7, 'confuse'); },
  '더 울어, 예쁘게!(眞)': (u, p, f) => { fixedAll(u, f, 300); yuriKiss(u, f, 0.7, 'disrupt'); },
  '천천히 찢는 사랑(眞)': (u, p, f) => { const ts = live(f); const d = hitAll(u, f, 1, 2.0); ts.forEach(t => f.field.includes(t) && bleedOn(t, u)); if (d) gainMp(u, u.maxMp * 0.2, '사망자 발생'); },
  // 정석윤
  '분리한다': (u, p, f) => debuffAll(f, '분리한다', 2, { atk: -0.1, def: -0.1, label: 'ATK·DEF -10%' }),
  '결합한다': (u, p, f) => live(f).forEach(t => addStatus(t, 'disrupt', 2, { mixed: true }, 'disrupt')),
  '파괴한다': (u, p, f) => live(f).forEach(t => { for (let i = 0; i < 2 && t.level > 1; i++) levelDown(t); const m = Math.round(t.mp * 0.4); t.mp -= m; emit({ type: 'mp', unit: t, amt: -m }); onLevelChange(t); }),
  // ===== v2 신규 =====
  // 민홍기 [용서는 없다]: 적 전체 20%×2, 각 30% 확률 1턴 출혈
  '용서는 없다': (u, p, f) => { const ts = live(f); hitAll(u, f, 2, 0.2); ts.forEach(t => { if (f.field.includes(t) && t.hp > 0 && chance(0.3)) bleedOn(t, u, 1); }); },
  '무답무용': (u, p, f) => { const t = by(live(f), x => x.card.ATK, -1); if (t && !multiHit(u, t, 5, 0.3) && chance(0.3)) bleedOn(t, u); },
  '껌밟기': (u, p, f) => { const t = by(females(f), x => x.card.cost); if (t) multiHit(u, t, 5, 0.3); },
  '되겠냐?': (u, p, f) => { const t = by(females(f), x => x.card.cost, -1); if (t && multiHit(u, t, 5, 0.4)) gainMp(u, u.maxMp * 0.2, '처치'); },
  '고갈될 예정입니다.': (u, p, f) => { if (chance(0.2)) live(f).forEach(t => addStatus(t, 'confuse', 1, {}, 'confuse')); else emit({ type: 'miss', unit: u, text: '확률 실패' }); },
  '이건 내분입니다.': (u, p, f) => debuffAll(f, '이건 내분입니다.', 2, { atk: -0.05, def: -0.05, label: 'ATK·DEF -5%' }),
  '나 좀 내버려둬': u => addStatus(u, 'decoy', 1, { pick: 'cost', male: true, label: '대신 맞기(코스트 최고)' }, 'decoy'),
  '소녀의 거래': u => addStatus(u, 'decoy', 1, { pick: 'hp', male: true, label: '대신 맞기(HP 최고)' }, 'decoy'),
  '영원한 유혹의 굴레': (u, p, f) => { const t = by(live(f).filter(x => x.card.cost < 40), x => x.card.cost, -1); if (t) addStatus(u, 'decoy', 1, { proxy: t, label: `${t.card.name} 대신 맞기` }, 'decoy'); else emit({ type: 'miss', unit: u, text: '대상 없음' }); },
  '배신의 향연': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0); if (t) addStatus(u, 'decoy', 1, { proxy: t, healOnKill: 1, label: `${t.card.name} 대신 맞기` }, 'decoy'); },
  '제발 그냥 가줘': (u, p, f) => { const t = by(males(f), x => x.card.cost, -1); if (!t) return; damageUnit(t, Math.ceil(t.hp * 0.8), u); checkDeath(t, u); },
  '피눈물': (u, p, f) => { const t = by(males(f), x => x.base.MOR || 0); if (!t) return; const i = f.field.indexOf(t); const nb = [f.field[i - 1], f.field[i + 1]].filter(Boolean); damageUnit(t, Math.round(u.maxHp * 0.4), u); nb.forEach(x => damageUnit(x, Math.max(1, Math.round(u.maxHp * 0.16)), u)); [t, ...nb].forEach(x => checkDeath(x, u)); },
  '너는 몰라': (u, p, f) => debuffAll(f, '너는 몰라', 1, { atk: -0.15, def: -0.15, label: 'ATK·DEF -15%' }),
  '너의 이름은?': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0, -1); if (t && chance(0.4) && addStatus(t, 'para', 2, {}, 'para')) addStatus(t, '너의 이름은?', 2, { def: -0.15, label: 'DEF -15%' }, 'mod'); else emit({ type: 'miss', unit: u, text: '확률 실패' }); },
  '달빛 아래 파멸의 포옹': (u, p, f) => hitAll(u, f, 2, 0.2),
  '은은한 베일의 재앙': (u, p, f) => { const top = by(live(f), x => x.card.ATK, -1); hitAll(u, f, 2, 0.3); if (top && f.field.includes(top)) { damageUnit(top, skillDamage(u, top, 0.2), u); checkDeath(top, u); } },
  '꼭 이래야해?': u => { addStatus(u, 'taunt', 1, {}, 'taunt'); addStatus(u, 'pleading', 1, {}, 'pleading'); },
  '쾌락의 씨앗': u => { addStatus(u, 'taunt', 1, {}, 'taunt'); addStatus(u, 'immune', 1, {}, 'immune'); addStatus(u, 'seed', 1, {}, 'seed'); },
  '광기의 신음': (u, p, f) => live(f).forEach(t => addStatus(t, 'dot', 3, { pct: 0.05, minOne: true, label: '광기의 신음' }, 'dot')),
  '이리 올래?': (u, p, f) => males(f).forEach(t => chance(0.4) && addStatus(t, 'para', 1, {}, 'para')),
  '짜릿하니?': (u, p, f) => males(f).forEach(t => addStatus(t, 'dot', 3, { pct: 0.05, caster: u, label: '짜릿하니?' }, 'dot')),
  '드와트': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t && !multiHit(u, t, 3, 0.2) && chance(0.2)) bleedOn(t, u); },
  '프리즈 드 페르': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0); if (t) multiHit(u, t, 3, 0.3, { ignoreDef: 0.2 }); },
  '사랑해': (u, p, f) => live(f).forEach(t => addStatus(t, 'dot', 2, { pct: 0.05, caster: u, label: '사랑해' }, 'dot')),
  '다 괜찮아': (u, p, f) => live(f).forEach(t => { if (t.level > 1) { levelDown(t); onLevelChange(t); } }),
  '헤에~ 그게 최선이야?': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (!t) return; const i = f.field.indexOf(t); const nb = [f.field[i - 1], f.field[i + 1]].filter(Boolean); damageUnit(t, 150, u); if (checkDeath(t, u)) { nb.forEach(x => damageUnit(x, 40, u)); nb.forEach(x => checkDeath(x, u)); } },
  'variable smash': (u, p, f) => { const ts = live(f).sort((a, b) => a.card.cost - b.card.cost).slice(0, 2); if (ts.length === 1) multiHit(u, ts[0], 4, 0.3); else ts.forEach(t => multiHit(u, t, 2, 0.3)); },
  'deep database': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0); if (t) multiHit(u, t, 3, 0.4); addStatus(u, 'immune', 1, {}, 'immune'); },
  '달빛 아래서…': (u, p, f) => live(f).forEach(t => addStatus(t, 'noheal', 1, {}, 'noheal')),
  '마지막 랠리': (u, p) => live(p).forEach(a => addStatus(a, 'regen', 2, { pct: 0.02 }, 'regen')),
  '사라지지 않는 약속': (u, p) => live(p).forEach(a => addStatus(a, 'immune', 1, {}, 'immune')),
  '마지막 대답': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (!t) return; if (chance(0.02)) { t.hp = 0; emit({ type: 'dmg', unit: t, dmg: '즉사' }); } else damageUnit(t, 100, u); checkDeath(t, u); },
  'Moral Drain': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0); if (!t) return; emit({ type: 'log', text: `${t.card.name} 품성 -30` }); if ((t.base.MOR || 0) - 30 < 0) { damageUnit(t, 100, u); if (!checkDeath(t, u)) addStatus(t, 'para', 1, {}, 'para'); } },
  '귀여운 고문자': (u, p, f, s) => { const t = by(females(f), x => x.card.cost); if (!t) return; if (multiHit(u, t, 3, 0.2)) u.cd[s.name] = 0; else addStatus(t, 'para', 1, {}, 'para'); },
  'WHO AM I': (u, p, f) => hitAll(u, f, 3, 0.15, { ignoreDef: 0.1 }),
  '사랑하는 마음': (u, p) => live(p).forEach(a => addStatus(a, 'regen', 3, { pct: 0.2 / 3 }, 'regen')),
  '쾌락의 착각': (u, p) => live(p).forEach(a => heal(a, a.maxHp * 0.05)),
  '기무라 락': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t) multiHit(u, t, 5, 0.3); },
  '이번만이야': (u, p) => { const c = p.lastDead; if (!c || !p.grave.includes(c)) return; p.grave.splice(p.grave.lastIndexOf(c), 1); p.lastDead = null;
    if (!owns(p, c)) { p.hand.push(c); emit({ type: 'revive', p, card: c }); } },
  '촉촉한가요?': (u, p) => males(p).forEach(a => heal(a, a.maxHp * 0.03)),
  '이게 공격이야!': (u, p, f) => { const t = by(live(f), x => x.card.DEF); if (t) multiHit(u, t, 5, 0.2, { ignoreDef: 0.1 }); },
  // 안리: 적 전체 10%×5회, 처치 시 아군 전체 1턴 ATK +2%
  '머신건': (u, p, f) => { if (hitAll(u, f, 5, 0.1)) { live(p).forEach(a => addStatus(a, '머신건', 1, { atk: 0.02, label: '머신건: ATK +2%' }, 'mod')); emit({ type: 'log', text: `${u.card.name} [머신건] 처치! 아군 전체 ATK +2% (1턴)` }); } },
  // 이명진: 이영아를 지키는 맹세 (맹세는 이영아가 필드를 떠날 때까지 유지). 사용한 턴에 첫 1회분 바로 적용
  '지킨다': u => { u.st.vow = { kind: 'vow', t: 999, stack: 0, def: 0 }; emit({ type: 'status', unit: u, kind: 'vow', key: 'vow', text: '지킨다' }); vowTick(u); },
  // 김후: 적마다 40% 확률로 2턴 도발당함(김후만 공격·스킬 불가). 2턴(상대 턴 기준) 뒤 김후 HP 30% 회복
  '나는 약하지 않아': (u, p, f) => {
    let n = 0;
    for (const t of live(f)) { if (chance(NOTWEAK.CHANCE)) { if (addStatus(t, 'provoked', NOTWEAK.TURNS, { by: u }, 'provoked')) n++; } else emit({ type: 'miss', unit: t, text: '도발 저항' }); }
    emit({ type: 'log', text: `${u.card.name}: "나는 약하지 않아!" — 도발 ${n}/${f.field.length}명 성공` });
    f.st['notweak:' + u.uid] = { t: NOTWEAK.TURNS + (TURN.p === f ? 1 : 0), notweak: u };
    u.st.notweak = { kind: 'notweak', t: 99 };
  },
  // ===== SR 스킬 =====
  // 금어진
  '건드리지마!': (u, p, f) => { const t = by(live(f), x => x.base.MOR || 0); if (t) multiHit(u, t, 3, 0.4); },
  '너는 내가 끝낸다!': (u, p, f) => { const t = live(f).find(x => String(x.base.id) === CHANGWON_ID); if (t && multiHit(u, t, 1, 2.0)) gainMp(u, u.maxMp * 0.5, '최창원 처치'); },
  // 선우민철
  '한 번 들어와봐': u => tauntSelf(u, '한 번 들어와봐', 1, 0.05, 0.1),
  '이게 프로야.': u => addStatus(u, 'thorns', 2, { red: 0.5, cm: 1.2, label: '이게 프로야: 피해 -50%, 반격 +20%' }, 'thorns'),
  // 민지은
  '감당 못할걸요?': (u, p, f) => { const t = by(live(f), x => x.hp, -1); if (!t) return; for (let i = 0; i < 3 && f.field.includes(t) && t.hp > 0; i++) damageUnit(t, skillDamage(u, t, 0.4, { extra: t.hp < t.maxHp * 0.5 ? 1.1 : 1 }), u); checkDeath(t, u); },
  '이런 경험 있나요?': (u, p, f) => retargetHits(u, f, 5, 0.3, arr => by(arr, x => x.level * 1000 + x.card.cost, -1)),
  // 오설화
  '이게 진짜거든요?': (u, p, f) => { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, Math.max(0.01, (101 - (t.base.MOR || 0)) / 100)), u)); ts.forEach(t => checkDeath(t, u)); },
  // 장무영
  '단 한방에 끝낸다.': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (t) multiHit(u, t, 1, 1.5, { ignoreDef: 0.2 }); },
  '이게 연격이야.': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (t) multiHit(u, t, 5, 0.35, { ignoreDef: 0.3 }); },
  // 문재
  '으흐흐…반갑다': (u, p, f) => { const t = by(live(f), x => x.hp); if (t) multiHit(u, t, 5, 0.3); },
  '으흐흐흐…잘가라': (u, p, f) => { const t = by(live(f), x => x.hp); if (t && multiHit(u, t, 10, 0.2)) gainMp(u, u.maxMp * 0.1, '처치'); },
  // 양겨울
  '공부만 잘하는 게 아니에요': (u, p, f) => fixedBlast(u, f, by(live(f), x => x.card.ATK, -1), 80, 25, 0.1),
  '저는 다치게 하고싶지 않아요': (u, p, f) => fixedBlast(u, f, by(live(f), x => x.card.ATK, -1), 150, 50, 0.15),
  // 윤믿음
  '자주봐요!': (u, p, f) => splash(u, f, by(live(f), x => x.base.MOR || 0), 0.8, 0.2),
  '느낌이..오나요?': (u, p, f) => splash(u, f, by(live(f), x => x.base.MOR || 0), 1.0, 0.3),
  // 고세린 (2스킬 [아..기분좋아~]는 종료 시 자동 발동)
  '때리지 말라니까!': u => tauntSelf(u, '때리지 말라니까!', 1, 0.2),
  // 김재신
  '아이돌 파워!': (u, p, f) => { if (hitAll(u, f, 2, 0.2)) gainMp(u, u.maxMp * 0.1, '처치'); },
  // 강준철
  '빠르게 돌진': (u, p, f) => { const t = pickRandom(live(f)); if (t && multiHit(u, t, 1, 1.3)) heal(u, u.maxHp * 0.1, '빠르게 돌진'); },
  '전광석화': (u, p, f) => { const t = pickRandom(live(f)); if (t && multiHit(u, t, 5, 0.3, { ignoreDef: 0.2 })) gainMp(u, u.maxMp * 0.1, '처치'); },
  // 김재섭
  '싸이코의 부활': (u, p, f) => hitAll(u, f, 2, 0.2),
  '싸이코의 복수': (u, p, f) => { const top = by(live(f), x => x.card.ATK, -1); hitAll(u, f, 2, 0.3); if (top && f.field.includes(top)) { damageUnit(top, skillDamage(u, top, 0.2), u); checkDeath(top, u); } },
  // 인창수
  '피를 부른다': (u, p, f) => { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.3, { extra: t.base.gender === 'FEMALE' ? 1.1 : 1 }), u)); ts.forEach(t => checkDeath(t, u)); },
  '심장이 뛴다': (u, p, f) => { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.4, { extra: t.base.gender === 'FEMALE' ? 1.15 : 1 }), u)); ts.forEach(t => checkDeath(t, u)); },
  // 선미영
  '에메랄드 쇼크': u => addStatus(u, 'thorns', 2, { red: 0.5, cm: 2, label: '에메랄드 쇼크: 피해 -50%, 반격 ×2' }, 'thorns'),
  '다이아 크래시': u => tauntSelf(u, '다이아 크래시', 1, 0.15),
  // 서태우
  '고릴라 파워': (u, p, f) => { const t = by(live(f), x => x.hp); if (t) multiHit(u, t, 5, 0.3); },
  // 고정태
  '불을 훔친 자': u => addStatus(u, 'thorns', 2, { cm: 2, leech: 0.1, label: '불을 훔친 자: 반격 ×2, 반격 흡혈 10%' }, 'thorns'),
  '불을 꺼뜨린 자': u => tauntSelf(u, '불을 꺼뜨린 자', 1, 0.1),
  // 임창열
  '일격으로!': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t && !multiHit(u, t, 3, 0.2) && chance(0.2)) bleedOn(t, u); },
  '천재의 일격': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t && !multiHit(u, t, 3, 0.4) && chance(0.4)) bleedOn(t, u); },
  // 문지철
  '너..는..끝났..어': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (t) multiHit(u, t, 1, 1.5); },
  // 정치욱
  '그렇게 약해서 되겠어?': u => tauntSelf(u, '그렇게 약해서 되겠어?', 1, 0.1, 0.1),
  '그렇게 느려도 되겠어?': u => addStatus(u, 'evade', 2, { p: 0.4, label: '회피 40%' }, 'evade'),
  // 김소영
  '이거…마셔볼래?': (u, p, f) => live(f).forEach(t => addStatus(t, 'dot', 2, { pct: 0.05, caster: u, label: '이거…마셔볼래?' }, 'dot')),
  '저기…나랑 갈래?': (u, p, f) => live(f).forEach(t => addStatus(t, 'dot', 2, { pct: 0.03, caster: u, mpDrainEnd: 0.3, label: '저기…나랑 갈래?' }, 'dot')),
  // 정다윤
  '영혼을 유혹합니다': u => tauntSelf(u, '영혼을 유혹합니다', 2, 0.1, 0.1),
  '영혼을 강탈합니다': u => { addStatus(u, 'taunt', 1, {}, 'taunt'); addStatus(u, 'soulsteal', 1, { pct: 0.2 }, 'soulsteal'); },
  // 서오성
  '나쁜 남자': (u, p, f) => { const ts = females(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.4), u)); ts.forEach(t => checkDeath(t, u)); },
  '진짜 악당': (u, p, f) => { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.4, { extra: t.base.gender === 'FEMALE' ? 1.3 : 1 }), u)); ts.forEach(t => checkDeath(t, u)); },
  // ===== 2026-10-22 신규 =====
  // 황예영
  '누나니까!': u => tauntSelf(u, '누나니까!', 1, 0.2, 0.2),
  '언니니까!': u => { addStatus(u, 'thorns', 2, { cm: 2.4, label: '언니니까!: 반격 +140%' }, 'thorns'); addStatus(u, 'endure', 2, { label: '언니니까!: 불사' }, 'endure'); },
  '내 동생 건드리지마!': (u, p) => addStatus(u, 'guard', 2, { ids: [YEEUN_ID, JUNTAE_ID], heal: { [YEEUN_ID]: 0.1 }, label: '예은·준태 대신 맞기' }, 'guard'),
  // 하지혜
  '죽이지 않으면 죽어': u => { addStatus(u, 'taunt', 2, {}, 'taunt'); addStatus(u, 'thorns', 2, { cm: 2.4, endHeal: 0.3, label: '죽이지 않으면 죽어: 반격 = 피해의 120%, 종료 시 HP 30% 회복' }, 'thorns'); },
  '죽지 않으려면 죽여': (u, p, f) => jihyeStrike(u, live(f)),
  // 하지은
  '너가 할 수 있겠어?': u => { addStatus(u, 'taunt', 2, {}, 'taunt'); addStatus(u, '너가 할 수 있겠어?', 2, { endHeal: 0.2, label: '너가 할 수 있겠어?: 종료 시 HP 20% 회복' }, 'mod'); },
  // 박인영
  '내가 간다': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (t) multiHit(u, t, 3, 0.35, { ignoreDef: 0.3 }); },
  '정의는 승리한다': (u, p, f, s) => {
    let t = by(live(f), x => x.base.MOR || 0), left = 5, killed = false;
    while (t && left > 0) {
      const nb = sides(f, t);
      damageUnit(t, skillDamage(u, t, 0.2), u); left--;
      if (checkDeath(t, u)) { killed = true; t = nb.find(x => f.field.includes(x)) || null; if (t && left > 0) emit({ type: 'log', text: `${u.card.name}: 옆의 ${t.card.name}에게 이어서 타격 (남은 ${left}회)` }); }
    }
    if (killed) u.cd[s.name] = 0;
  },
  // 정하루
  '드론 폭격!': (u, p, f) => hitAllOverflow(u, f, 0.3),
  '드론 연사!': (u, p, f) => { if (!f.noBase && !heroLocked(p)) heroHit(u, f, 1.5); else hitAll(u, f, 1, 0.3); },
};
export const CHANGWON_ID = '1002100371';
export const YEEUN_ID = '2000200053', JUNTAE_ID = '1000200052', JIEUN_REVIVE_HP = 0.5;
const owns = (p, c) => [...p.deck, ...p.hand, ...p.field.map(u => u.base)].some(x => String(x.id) === String(c.id));
const females = side => live(side).filter(x => x.base.gender === 'FEMALE');
const males = side => live(side).filter(x => x.base.gender === 'MALE');
function cleanse(a) { for (const [k, s] of Object.entries(a.st)) if (STATUS[s.kind]?.debuff || s.atk < 0 || s.def < 0) delete a.st[k]; a.curse = 0; }
// ---- 이명진 [지킨다] · 김후 [나는 약하지 않아] ----
export const YOUNGA_ID = '2000600132';
export const VOW = { DEF_STEP: 0.004, HEAL: 0.02, RAGE_ATK: 0.6, RAGE_TURNS: 3 };
export const NOTWEAK = { CHANCE: 0.4, TURNS: 2, HEAL: 0.3 };
const younga = side => side.field.find(x => String(x.base.id) === YOUNGA_ID);
/** 맹세 1회분: DEF +0.4% 누적, 최대 HP 2% 회복 */
function vowTick(u) {
  const v = u.st.vow; if (!v) return;
  v.stack = (v.stack || 0) + 1; v.def = VOW.DEF_STEP * v.stack;
  emit({ type: 'log', text: `${u.card.name} [지킨다] DEF +${(v.def * 100).toFixed(1)}% (누적 ${v.stack})` });
  heal(u, u.maxHp * VOW.HEAL, '지킨다');
}
function vowBroken(u) {
  delete u.st.vow;
  for (const k in u.cd) u.cd[k] = 0;
  addStatus(u, '지킨다 분노', VOW.RAGE_TURNS, { atk: VOW.RAGE_ATK, label: `지킨다: ATK +${VOW.RAGE_ATK * 100}%` }, 'mod');
  emit({ type: 'passive', unit: u, name: '지킨다', text: `이영아가 쓰러졌다! 쿨타임 초기화 · ${VOW.RAGE_TURNS}턴 ATK +${VOW.RAGE_ATK * 100}%` });
  stats.count('지킨다 분노');
}
/** 도발당한 카드가 공격해야 하는 대상 (도발한 카드가 상대 필드에 살아 있고 보스가 아닐 때) */
export function provoker(u) {
  const b = u?.st?.provoked?.by;
  return b && b.hp > 0 && u.owner?.foe?.field.includes(b) && !b.undying ? b : null;
}
/** 대상 조건이 있는 스킬 (상대 필드에 해당 성별이 없으면 비활성) */
const REQ = { '껌밟기': f => females(f).length, '나쁜 남자': f => females(f).length, '진짜 악당': f => females(f).length,
  '너는 내가 끝낸다!': f => f.field.some(x => String(x.base.id) === CHANGWON_ID), '되겠냐?': f => females(f).length, '귀여운 고문자': f => females(f).length,
  '지킨다': (f, u) => younga(u.owner) && !u.st.vow,
  '내 동생 건드리지마!': (f, u) => u.owner.field.some(x => [YEEUN_ID, JUNTAE_ID].includes(String(x.base.id))),
  '나 좀 내버려둬': f => males(f).length, '제발 그냥 가줘': f => males(f).length, '소녀의 거래': f => males(f).length, '피눈물': f => males(f).length, '이리 올래?': f => males(f).length, '짜릿하니?': f => males(f).length };

/** 남성 기본 공격 유도: [나 좀 내버려둬]/[소녀의 거래] 시전 중(decoy.male)인 카드 중 코스트 최고. 마비·혼란 시 미발동 */
export function maleLure(attacker, side) {
  if (attacker.base.gender !== 'MALE') return null;
  const c = side.field.filter(x => x.st.decoy?.male && !x.st.para && !x.st.confuse);
  return c.length ? by(c, x => x.card.cost, -1) : null;
}
/** 기본 공격 대상 재지정: 대신 맞기(decoy) → 수호(사랑하는 친구거든!·튀 므 망크). 반환 { target, ratio, proxyOf } */
const GUARD = { '사랑하는 친구거든!': '2000100008', '튀 므 망크': '2000600116', '내가 오빠잖아.': '2002000354' };   // 내가 오빠잖아: 강준철 → 강재아
export function redirectAttack(attacker, target) {
  const tp = target.owner;
  const dc = target.st.decoy;
  if (dc && (!dc.male || attacker.base.gender === 'MALE')) {
    const side = attacker.owner;
    let proxy = dc.proxy && side.field.includes(dc.proxy) ? dc.proxy : null;
    if (!proxy && dc.pick) proxy = by(live(side).filter(x => x !== attacker), x => dc.pick === 'cost' ? x.card.cost : x.hp, -1) || null;
    if (proxy) { emit({ type: 'passive', unit: target, name: '대신 맞기', text: `${proxy.card.name}이(가) 대신 맞음` }); stats.count('대신 맞기'); return { target: proxy, decoyOf: target }; }
  }
  // 황예영 [내 동생 건드리지마!]: 예은·준태 대신 맞기
  const gd = tp.field.find(x => x !== target && x.st.guard?.ids?.includes(String(target.base.id)) && !x.st.para && !x.st.confuse);
  if (gd) { emit({ type: 'passive', unit: gd, name: '내 동생 건드리지마!', text: `${target.card.name} 대신 피격` }); stats.count('내 동생 건드리지마!'); return { target: gd }; }
  // 하지은 [내가 지켜준다]: 코스트가 가장 낮은 아군 여성을 대신 맞고 MP 20%
  if (target.base.gender === 'FEMALE') {
    const je = tp.field.find(x => x !== target && hasPassive(x, '내가 지켜준다') && !x.st.para && !x.st.confuse);
    const low = je && by(tp.field.filter(x => x !== je && x.base.gender === 'FEMALE'), x => x.card.cost);
    if (je && low === target) { emit({ type: 'passive', unit: je, name: '내가 지켜준다', text: `${target.card.name} 대신 피격` }); stats.count('내가 지켜준다'); gainMp(je, je.maxMp * 0.2, '내가 지켜준다'); return { target: je }; }
  }
  for (const [name, protectId] of Object.entries(GUARD)) {
    if (String(target.base.id) !== protectId) continue;
    const g = tp.field.find(x => x !== target && hasPassive(x, name) && !x.st.para && !x.st.confuse);
    const nc = name === '사랑하는 친구거든!';   // 유가을: 반격 없음
    if (g) { emit({ type: 'passive', unit: g, name, text: `${target.card.name} 대신 피격${nc ? '' : ' 후 반격'}` }); stats.count(name); return { target: g, ratio: 0.7, noCounter: nc }; }
  }
  return { target };
}
/** 장미가시: 표식된 공격자가 임예리를 기본 공격 → 일반 반격 대신 기본 공격 100% (= 50% × 2) */
export const roseCounter = (target, attacker) => !!attacker?.st?.['장미가시의 세레나데'] && String(attacker.st['장미가시의 세레나데'].rose?.base?.id) === String(target.base.id);
export const counterMult = (target, attacker) => (target.st.pleading ? 2.5 : 1) * (hasPassive(target, '이게 반격이야') ? 1.5 : 1) * (target.st.thorns?.cm || 1) * (roseCounter(target, attacker) ? 2 : 1);
/** 정치욱 [그렇게 느려도 되겠어?]: 기본 공격 회피 판정 */
export function evadeChance(target) {
  return Math.min(RULES.EVADE_CAP, baseEvade(target.card) + (target.st.evade?.p || 0));
}
/** 기본 공격 회피: 속성 기본 회피(바람 7%, 그 외 4%) + 스킬 회피(정치욱 [그렇게 느려도 되겠어?] 40%), 상한 60% */
export function rollEvade(target, attacker) {
  const p = evadeChance(target); if (!p || !chance(p)) return false;
  const sk = !!target.st.evade;
  if (sk) emit({ type: 'passive', unit: target, name: '회피', text: `${attacker.card.name}의 공격을 회피!` });
  else emit({ type: 'evade', unit: target, attacker, p });
  stats.count(sk ? '회피' : '속성 회피');
  return true;
}

// ---- 스킬 사용 가능 여부 ----
export function skillState(u, s) {
  if (s.mode !== 'active') return { ok: false, reason: '패시브' };
  if (u.level < s.unlock) return { ok: false, reason: `Lv${s.unlock} 해금` };
  if (provoker(u)) return { ok: false, reason: '도발당함 (스킬 불가)' };
  if (/게임 당 1회/.test(s.note) && u.owner.once['a:' + s.name]) return { ok: false, reason: '게임 당 1회 (사용함)' };
  if (u.cd[s.name] > 0) return { ok: false, reason: `쿨타임 ${u.cd[s.name]}턴` };
  if (u.mp < s.mp) return { ok: false, reason: `MP 부족 (${u.mp}/${s.mp})` };
  if (!u.canAttack) return { ok: false, reason: '이번 턴 행동함' };
  if (!ACTIVE[s.name]) return { ok: false, reason: '미구현' };
  if (REQ[s.name] && !REQ[s.name](u.owner.foe, u)) return { ok: false, reason: s.name === '지킨다' ? (u.st.vow ? '맹세 유지 중' : '이영아가 필드에 없음') : s.name === '너는 내가 끝낸다!' ? '상대 필드에 최창원 없음' : '대상 없음' };
  return { ok: true };
}
/** 액티브 스킬 사용 (그 턴 공격 대신) */
export function useSkill(u, s) {
  const st = skillState(u, s); if (!st.ok) return st;
  const p = u.owner;
  u.mp -= s.mp; u.cd[s.name] = skillCd(u, s); u.canAttack = false;
  if (/게임 당 1회/.test(s.note)) p.once['a:' + s.name] = 1;
  emit({ type: 'skill', unit: u, skill: s });
  stats.count(s.name);
  refreshAll(p);
  const prevSKC = SKC, slv = skillLvOf(u, s); SKC = slv > 1 ? { u, m: skillLvMult(slv) } : null;
  const prevA = ACTOR; ACTOR = u;
  try { ACTIVE[s.name](u, p, p.foe, s); } finally { SKC = prevSKC; ACTOR = prevA; }
  refreshAll(p);
  return { ok: true };
}

// ---- 기본 공격 시 반격 패시브 ----
export function afterBasicHit(attacker, target) {
  if (noCounter) return;
  noCounter++;
  try {
    const tp = target.owner;
    // 정아람 水火相剋: 불속성 적이 아군 공격 → 人鬼相半 반격 (MP 30 소모, 30 미만이면 미발동)
    if (attacker.card.class === 'FIRE') for (const a of [...tp.field]) if (hasPassive(a, '水火相剋') && a.mp >= 30 && attacker.owner.field.includes(attacker)) {
      a.mp -= 30; emit({ type: 'passive', unit: a, name: '水火相剋' }); stats.count('水火相剋'); ACTIVE['人鬼相半'](a, tp, tp.foe);
    }
    // 임예리 장미가시 반격은 resolveAttack의 반격 배율(×2 = 기본 공격 100%)로 처리 — 일반 반격을 대체
    if (roseCounter(target, attacker)) { emit({ type: 'passive', unit: target, name: '장미가시 반격', text: '일반 반격 대신 기본 공격 100%' }); stats.count('장미가시 반격'); }
    // 하지혜 [너도 언젠간 죽어]: 아군 여성이 기본 공격을 받으면 공격자에게 [죽지 않으려면 죽여] (MP·쿨타임 무관)
    if (target.base.gender === 'FEMALE' && attacker.owner.field.includes(attacker)) {
      const jh = tp.field.find(x => x !== target && hasPassive(x, '너도 언젠간 죽어') && !x.st.para && !x.st.confuse);
      if (jh) { emit({ type: 'passive', unit: jh, name: '너도 언젠간 죽어', text: `${attacker.card.name}에게 [죽지 않으려면 죽여] 반격` }); stats.count('너도 언젠간 죽어'); jihyeStrike(jh, [attacker]); }
    }
    // 정다윤 영혼을 강탈합니다: 기본 공격한 상대 MP 20% 제거
    const ss = target.st.soulsteal;
    if (ss && attacker.owner.field.includes(attacker) && attacker.mp > 0) { const m = Math.round(attacker.mp * (ss.pct || 0.2)); if (m > 0) { attacker.mp -= m; emit({ type: 'mp', unit: attacker, amt: -m }); emit({ type: 'passive', unit: target, name: '영혼을 강탈합니다', text: `${attacker.card.name} MP -${m}` }); stats.count('영혼 강탈'); } }
  } finally { noCounter--; }
}

// ---- 턴 시작 / 종료 ----
/** 자기 턴 시작 (마나 충전·드로우·canAttack 설정 후 호출) */
export function turnStart(p) {
  TURN.p = p; const f = p.foe;
  if (foeHasPassive(p, 'Nullus Deus est') && p.field.some(u => u.card.class !== 'LIGHT')) stats.count('Nullus Deus est');
  for (const u of p.field) {
    for (const k in u.cd) if (u.cd[k] > 0) u.cd[k]--;
    u.mp = Math.min(u.maxMp, u.mp + u.mpRegen);
  }
  // 이명진 지킨다: 이영아가 같은 필드에 있으면 매 턴 DEF +0.4% 누적·HP 2% 회복, 없으면(회수 등) 맹세 해제
  for (const u of p.field) if (u.st.vow) { if (younga(p)) vowTick(u); else { delete u.st.vow; emit({ type: 'expire', unit: u, key: 'vow' }); } }
  // 황예영 [내 동생 건드리지마!]: 다음 턴 시작 시 예은 HP 10% 회복
  for (const u of p.field) { const g = u.st.guard; if (g?.heal) for (const a of [...p.field]) { const r = g.heal[String(a.base.id)]; if (r) heal(a, a.maxHp * r, '내 동생 건드리지마!'); } }
  // 임혜리 주님의 기적: 아군·본진 5% 회복
  const hy = findPassiveUnit(p, '주님의 기적');
  if (hy) { emit({ type: 'passive', unit: hy, name: '주님의 기적' }); stats.count('주님의 기적'); p.field.forEach(a => heal(a, a.maxHp * 0.05)); healHero(p, (p.maxHp || RULES.HERO_HP) * 0.05); }
  // Esoteric Method: 매 턴 HP -10%, ATK -3% 누적
  for (const u of [...p.field]) if (u.st.esoteric) { u.st.esoteric.stack = (u.st.esoteric.stack || 0) + 1; damageUnit(u, Math.max(1, Math.round(u.maxHp * 0.1)), null); checkDeath(u, u.st.esoteric.caster || null); }
  // v2: 체력 고갈 / 재생
  for (const u of [...p.field]) {
    const dt = u.st.dot; if (dt) { let d = Math.max(1, Math.round(u.maxHp * dt.pct)); if (dt.minOne) d = Math.min(d, u.hp - 1); if (d > 0) { damageUnit(u, d, null); checkDeath(u, dt.caster || null); } }
    const rg = u.st.regen; if (rg && p.field.includes(u)) heal(u, u.maxHp * rg.pct, '재생');
  }
  // 윤진아 검은 늪: 가장 많이 다친 아군 20% 회복
  if (findPassiveUnit(p, '검은 늪') && p.field.length) { const a = by(p.field, x => x.hp / x.maxHp); if (heal(a, a.maxHp * 0.2, '검은 늪')) stats.count('검은 늪'); }
  // 임예리 지옥 교향곡 (상대 필드): 매 턴 ATK·DEF -2% 누적, HP -5%
  const yeri = findPassiveUnit(f, '자수정 눈물의 지옥 교향곡');
  if (yeri) { emit({ type: 'passive', unit: yeri, name: '자수정 눈물의 지옥 교향곡' }); stats.count('자수정 눈물의 지옥 교향곡'); for (const u of [...p.field]) { if (u.st.debuffImmune) continue; u.curse++; damageUnit(u, Math.max(1, Math.round(u.maxHp * 0.05)), null); checkDeath(u, yeri); } }
  refreshAll(p);
  // [각성] 임유리 공허의 제왕: 턴 시작 시 적 전체 + 본진 20% 자동 공격
  for (const u of [...p.field]) if (hasPassive(u, '공허의 제왕') && p.field.includes(u)) {
    emit({ type: 'passive', unit: u, name: '공허의 제왕' }); stats.count('공허의 제왕');
    hitAll(u, f, 1, 0.2); heroHit(u, f, 0.2);
  }
  // 오설화 [이래서 제가 유명해요]·김재신 [리얼 아이돌!]: 턴 시작 시 적 전체 8% 자동 타격
  for (const u of [...p.field]) for (const nm of ['이래서 제가 유명해요', '리얼 아이돌!']) if (hasPassive(u, nm) && p.field.includes(u) && f.field.length) {
    emit({ type: 'passive', unit: u, name: nm }); stats.count(nm);
    if (hitAll(u, f, 1, 0.08) && nm === '리얼 아이돌!') gainMp(u, u.maxMp * 0.1, '처치');
  }
  // 유아리 마르쉐: 매 턴 HP 3% 회복
  for (const u of p.field) if (hasPassive(u, '마르쉐')) heal(u, u.maxHp * 0.03, '마르쉐');
  // 마비 / 혼란 / 교란 → 강제 행동
  for (const u of [...p.field]) {
    if (!p.field.includes(u)) continue;
    if (u.st.para) { u.canAttack = false; emit({ type: 'log', text: `${u.card.name} 마비! 행동 불가` }); continue; }
    if (u.st.confuse || u.st.disrupt) {
      u.canAttack = false;
      const allies = p.field.filter(a => a !== u);
      const toHero = u.st.confuse ? false : (u.st.disrupt.mixed ? (!allies.length || chance(0.5)) : true);
      if (!toHero && allies.length) {
        const t = allies[Math.floor(rng() * allies.length)];
        emit({ type: 'forced', unit: u, target: t, text: `${u.card.name} 혼란! 아군 ${t.card.name} 공격` });
        damageUnit(t, calcDamage(u.card, t.card), u); checkDeath(t, null);
      } else if (toHero) {
        emit({ type: 'forced', unit: u, hero: p, text: `${u.card.name} 교란! 자기 본진 공격` });
        damageHero(p, calcDamage(u.card, null), p, 'self');
      }
    }
  }
  refreshAll(p);
}
/** 상태 종료 시 효과: 종료 회복, MP 하락(저기…나랑 갈래?), 고세린 [아..기분좋아~] */
function onExpire(u, k, s) {
  if (k === 'sisterSwap') unswap(u, true);
  if (s.endHeal) heal(u, u.maxHp * s.endHeal, k);
  if (s.mpDrainEnd && u.mp > 0) { const m = Math.round(u.mp * s.mpDrainEnd); if (m > 0) { u.mp -= m; emit({ type: 'mp', unit: u, amt: -m }); emit({ type: 'log', text: `${u.card.name} [${s.label || k}] 종료 · MP -${m}` }); } }
  if (k === '때리지 말라니까!' && hasPassive(u, '아..기분좋아~')) { u.st.regen = { kind: 'regen', pct: 0.07, t: 3 }; emit({ type: 'passive', unit: u, name: '아..기분좋아~', text: '3턴 간 매 턴 HP 7% 회복' }); stats.count('아..기분좋아~'); }
}
/** 자기 턴 종료 (endTurnXp 다음에 호출) */
export function turnEnd(p) {
  const f = p.foe;
  // 이진경 SATAN: 적 필드 HP 3% 흡수 → 본진 회복
  const jk = findPassiveUnit(p, 'the incarnation of SATAN');
  if (jk && f.field.length) {
    emit({ type: 'passive', unit: jk, name: 'the incarnation of SATAN' }); stats.count('the incarnation of SATAN');
    let sum = 0; for (const t of [...f.field]) { sum += damageUnit(t, Math.max(1, Math.round(t.maxHp * 0.03)), null); checkDeath(t, jk); }
    healHero(p, sum);
  }
  // 상태 지속 감소 (자기 턴 종료 기준)
  for (const u of p.field) {
    if (u.paraBlock) u.paraBlock--;
    for (const [k, s] of Object.entries(u.st)) if (--s.t <= 0) { delete u.st[k]; if (k === 'seed') heal(u, u.maxHp * 0.05, '쾌락의 씨앗'); if (k === 'pleading') heal(u, u.maxHp * 0.3, '꼭 이래야해?'); if (k === 'para') u.paraBlock = 2; emit({ type: 'expire', unit: u, key: k }); onExpire(u, k, s); }
  }
  for (const [k, s] of Object.entries(p.st)) if (--s.t <= 0) {
    delete p.st[k];
    // 김후 나는 약하지 않아: 도발 효과 종료 → HP 30% 회복
    const kh = s.notweak; if (kh) { delete kh.st.notweak; if (heal(kh, kh.maxHp * NOTWEAK.HEAL, '나는 약하지 않아')) { emit({ type: 'passive', unit: kh, name: '나는 약하지 않아', text: `도발 종료 · HP ${NOTWEAK.HEAL * 100}% 회복` }); stats.count('나는 약하지 않아 회복'); } }
  }
  if (p.actionLock > 0) p.actionLock--;
  refreshAll(p);
}

// ===== AI: 스킬 선택 =====
export function aiPickSkill(u) {
  const p = u.owner, f = p.foe;
  if (spareBlocked(u)) return null;
  const cands = [];
  // MP 저축: 해금된 최상위 액티브가 MP 부족이면 50% 확률로 하위 스킬을 아끼고 기본 공격
  const top = (u.sk || []).filter(s => s.mode === 'active' && u.level >= s.unlock && ACTIVE[s.name]).sort((a, b) => b.unlock - a.unlock)[0];
  const saving = top && u.mp < top.mp && !(u.cd[top.name] > 0) && rng() < 0.5;
  for (const s of u.sk || []) {
    if (!skillState(u, s).ok) continue;
    if (saving && s !== top) continue;
    const n = f.field.length, lowHp = p.field.filter(a => a.hp < a.maxHp * 0.7).length;
    let sc = 0;
    const heroOk = !heroLocked(p) && !f.noBase;   // 진영 없는 전투(스토리 일반전·퀘스트): 진영 전용 스킬은 쓰지 않음
    // 기본 공격으로 처치 가능한 대상이 있으면 보조 스킬보다 공격 우선
    const canKill = f.field.some(t => calcDamage(u.card, t.card) >= t.hp);   // 처치하면 반격 없음
    switch (s.name) {
      case '반야': case '주님 저희를 구하소서': sc = lowHp >= 2 ? 90 + lowHp * 5 : 0; break;
      case '열반': sc = (lowHp >= 2 || p.hp < (p.maxHp || RULES.HERO_HP) * 0.6) ? 95 : 0; break;
      case '하느님의 영광': sc = p.grave.length && p.hand.length < 10 ? 80 + Math.max(...p.grave.map(c => c.cost)) : 0; break;
      case 'Divina tibi poena adveniat': sc = p.field.length >= 2 && n ? 120 : 0; break;
      case 'Fatal Temptation': case '죽는다…': sc = heroOk ? 115 : 0; break;
      case 'Tempus est discerpi': case '결합한다': sc = n >= 2 ? 110 + n * 5 : 0; break;
      case 'My Black Sun': { const k = f.field.filter(t => t.card.cost < 40).length; sc = k >= 2 ? 100 + k * 5 : 0; break; }
      case '아름다운 고통의 키스(眞)': case '더 울어, 예쁘게!(眞)': case 'Cum amicis meis sacris sum': sc = n >= 2 ? 100 + n * 5 : 0; break;
      case '파괴한다': sc = f.field.reduce((a, t) => a + (t.level - 1), 0) >= 3 ? 105 : 0; break;
      case '사라지지 않는 약속': case '쾌락의 씨앗': sc = n >= 2 ? 85 : 0; break;
      case '마지막 랠리': case '사랑하는 마음': case '쾌락의 착각': case '촉촉한가요?': sc = lowHp >= 2 ? 85 + lowHp * 4 : 0; break;
      case '이번만이야': sc = p.lastDead && p.grave.includes(p.lastDead) ? 90 + p.lastDead.cost : 0; break;
      case '나 좀 내버려둬': case '소녀의 거래': case '영원한 유혹의 굴레': case '배신의 향연': sc = n >= 2 ? 80 : 0; break;
      case '제발 그냥 가줘': sc = 110; break;
      case '이건 사랑이야': sc = n ? 90 + n * 5 : 0; break;
      case '용서는 없다': sc = n >= 2 ? 92 + n * 4 : n ? 70 : 0; break;
      case '사랑해!!!': sc = n ? 105 + Math.min(n, 2) * 5 : 0; break;
      case '지킨다': sc = 88; break;   // 조건(이영아 필드·맹세 전)은 skillState에서 확인
      case '나는 약하지 않아': sc = n >= 2 ? 92 + n * 4 : n ? 70 : 0; break;
      case '한 번 들어와봐': case '때리지 말라니까!': case '다이아 크래시': case '불을 꺼뜨린 자': case '그렇게 약해서 되겠어?': case '영혼을 유혹합니다':
        sc = n && p.field.length >= 2 && !canKill ? 78 + p.field.length * 3 : 0; break;
      case '영혼을 강탈합니다': sc = n && !canKill ? 80 + n * 3 : 0; break;
      case '누나니까!': case '죽이지 않으면 죽어': case '너가 할 수 있겠어?':
        sc = n && p.field.length >= 2 && !canKill ? 78 + p.field.length * 3 : 0; break;
      case '내 동생 건드리지마!': sc = n ? 84 : 0; break;
      case '언니니까!': case '이게 프로야.': case '에메랄드 쇼크': case '불을 훔친 자': case '그렇게 느려도 되겠어?': sc = n >= 2 && !canKill ? 82 + n * 3 : 0; break;
      case '이거…마셔볼래?': case '저기…나랑 갈래?': sc = n >= 2 ? 82 + n * 4 : 0; break;
      case '핑핑 돌지?': sc = n && p.field.length >= 2 ? 80 + p.field.length * 3 : 0; break;
      case '무시하지 마세요.': case '약육강식? 웃기지 마세요.': case '부드러움은 강함을 이깁니다': case '당하고만 살진 않아요': case '더 이상의 비극은 없어!': case '귀족이...전부 악인은 아니랍니다.': case '약해 보인다고 무시하지 마!': {
        const k = { '무시하지 마세요.': a => gradeIdx(a) <= 1, '귀족이...전부 악인은 아니랍니다.': a => (a.base.MOR || 0) >= 50, '약해 보인다고 무시하지 마!': a => a.card.cost < 35 }[s.name] || (a => gradeIdx(a) <= 2);
        const c = p.field.filter(a => a.base.gender === 'FEMALE' && !a.st.immune && k(a)).length; sc = n && c >= 2 && !canKill ? 80 + c * 4 : 0; break; }
      case '내가 누군지 아냐?': sc = n && !u.st.immune && u.hp < u.maxHp * 0.7 ? 88 : 0; break;
      case '언니...도와줘요.': sc = n && !u.swap && poolCard(MIYOUNG_ID) ? 92 : 0; break;
      case '러시안룰렛': sc = n ? 90 + by(f.field, x => x.card.cost).card.cost : 0; break;
      default:
        if (s.type === '디버프') sc = n >= 3 && !canKill ? 80 + n * 3 : 0;
        else if (s.type === '공격') sc = n || (/본진/.test(s.desc) && heroOk) ? (/적 전체|전체/.test(s.target + s.desc) ? 95 + n * 6 : 100) : 0;
    }
    // 상대 카드가 없으면 적 카드 대상 스킬은 무의미 (진영을 치는 스킬은 예외)
    if (sc && !n && /적/.test(s.target || '') && !/본진|진영/.test(s.desc || '')) sc = 0;
    if (sc && canKill && s.type !== '공격' && s.type !== '회복' && !/眞|Cum amicis/.test(s.name)) sc -= 30;
    if (sc) sc += s.unlock * 6;
    if (sc > 0) cands.push([s, sc]);
  }
  if (!cands.length) return null;
  // 점수 비례(제곱) 확률 선택: 대체로 최선이지만 다양한 스킬을 섞어 씀
  const tot = cands.reduce((t, [, sc]) => t + sc * sc, 0);
  let r = rng() * tot;
  for (const [s, sc] of cands) if ((r -= sc * sc) <= 0) return s;
  return cands[cands.length - 1][0];
}
