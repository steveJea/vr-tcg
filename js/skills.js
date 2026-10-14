// ===== 스킬 · 상태이상 · 시너지 엔진 (게임·시뮬레이션 공용) =====
// 스킬 데이터: data/skills.json (카드 id → 스킬 목록), 조합: data/combos.json
// 각 스킬 효과는 '효과 내용' 기준으로 아래 ACTIVE / PASSIVE 표에 스킬 이름별로 구현
import { RULES, elementMultiplier, calcDamage, gainXp, heroLocked, killXp, levelDown, levelUpOnce } from './rules.js';

export const SK = {
  MP_BASE: 50, MP_PER_MEN: 1,           // 최대 MP = 50 + MEN (51~150)
  MP_REGEN_BASE: 4, MP_REGEN_PER_MOR: 0.16, // 턴당 MP 회복 = 4 + MOR × 0.16 (약 4~20)
  MP_START_RATIO: 0.5,                  // 소환 시 MP 50%로 시작
  SYNERGY: { 2: 0.10, 3: 0.15, 4: 0.20, 5: 0.30 }, // 같은 속성 필드 장수별 ATK·DEF 보너스
};

let SKILL_DB = {}, COMBOS = [];
export function setSkillData(skills, combos) { SKILL_DB = skills || {}; COMBOS = combos || []; }
export const skillsOf = id => SKILL_DB[String(id)] || [];
export const combos = () => COMBOS;

// ---- 이벤트 (UI 로그·연출, 시뮬 통계) ----
let emitFn = () => {};
export function setEmitter(fn) { emitFn = fn || (() => {}); }
const emit = ev => emitFn(ev);
let rng = Math.random;
export function setRng(f) { rng = f; }

// ---- 플레이어 / 유닛 초기화 ----
let uidSeq = 1;
export function initPlayers(a, b) {
  for (const [p, f] of [[a, b], [b, a]]) Object.assign(p, { foe: f, grave: [], once: {}, st: {}, actionLock: 0, activeSyn: [], activeCombos: [] });
}
/** 필드에 카드 배치 (소환). 게임·시뮬 공용 */
export function placeUnit(p, card, makeUnit) {
  const u = makeUnit(card, uidSeq++);
  initUnit(u, p);
  p.field.push(u);
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
  bleed:   { icon: '🩸', label: '출혈', debuff: true, desc: 'ATK·DEF -5%, 걸릴 때 최대 HP 5% 손실' },
  para:    { icon: '⚡', label: '마비', debuff: true, desc: '행동 불가 (연속 2턴 마비 불가)' },
  confuse: { icon: '💫', label: '혼란', debuff: true, desc: '자기 턴에 아군을 강제 공격' },
  disrupt: { icon: '🌀', label: '교란', debuff: true, desc: '자기 턴에 자기 본진을 강제 공격' },
  immune:  { icon: '🔰', label: '피해 면역', desc: '모든 피해 무효' },
  debuffImmune: { icon: '✳️', label: '디버프 면역', desc: '디버프에 걸리지 않음' },
  taunt:   { icon: '🎯', label: '도발', desc: '상대는 이 카드부터 공격해야 함' },
  esoteric:{ icon: '☠️', label: 'Esoteric', debuff: true, desc: '매 턴 HP -10%, ATK -3% 누적' },
  mod:     { icon: '', label: '' },
};
const MOD_ICON = (atk, def) => (atk > 0 || def > 0) ? '🔺' : '🔻';

/** 상태 부여. turns: '자기 턴' 기준 지속. 대상 소유자의 턴 중에 걸리면 현재 턴은 세지 않음 */
export function addStatus(u, key, turns, data = {}, kind = key) {
  const def = STATUS[kind] || {};
  const isDebuff = def.debuff || (data.atk < 0 || data.def < 0);
  if (isDebuff && u.st.debuffImmune) { emit({ type: 'resist', unit: u, text: '디버프 면역' }); return false; }
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
    if (s.kind === 'mod') out.push({ icon: MOD_ICON(s.atk || 0, s.def || 0), title: `${s.label || k} (${s.t}턴)` });
    else if (STATUS[s.kind]) out.push({ icon: STATUS[s.kind].icon, title: `${STATUS[s.kind].label} (${s.t}턴)` });
  }
  if (u.curse && foeHasPassive(u.owner, '자수정 눈물의 지옥 교향곡')) out.push({ icon: '🥀', title: `지옥 교향곡 ×${u.curse}` });
  if (u.cry) out.push({ icon: '😇', title: `천사의 절규 ×${u.cry}` });
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
  for (const u of p.field) {
    let a = 0, d = 0, h = 0;
    const syn = p.activeSyn.find(s => s.cls === u.card.class); if (syn) { a += syn.pct; d += syn.pct; }
    for (const c of p.activeCombos) if (c.scope === 'all' || c.cards.includes(String(u.base.id))) { if (c.atk) a += c.value; if (c.def) d += c.value; if (c.hp) h += c.value; }
    for (const s of Object.values(u.st)) { a += s.atk || 0; d += s.def || 0; }
    if (u.st.esoteric) a -= 0.03 * (u.st.esoteric.stack || 0);
    if (nullus && u.card.class !== 'LIGHT') d -= 0.2;
    if (symph && u.curse) { a -= 0.02 * u.curse; d -= 0.02 * u.curse; }
    if (u.cry) { a += 0.05 * u.cry; d += 0.05 * u.cry; }
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
export function damageUnit(target, dmg, src = null, { silent = false } = {}) {
  if (!target.owner.field.includes(target)) return 0;
  if (target.st.immune) { emit({ type: 'immune', unit: target }); return 0; }
  target.hp -= dmg;
  if (!silent) emit({ type: 'dmg', unit: target, dmg });
  if (src && src.hp > 0 && hasPassive(src, '우습네요') && heal(src, Math.round(dmg * 0.3), '흡혈')) stats.count('우습네요');
  return dmg;
}
export function heal(u, amt, why = '') {
  if (!u.owner.field.includes(u) || amt <= 0) return 0;
  const h = Math.min(u.maxHp - u.hp, Math.round(amt)); if (h <= 0) return 0;
  u.hp += h; emit({ type: 'heal', unit: u, amt: h, why }); return h;
}
export function healHero(p, amt) { const b = p.hp; p.hp = Math.min(RULES.HERO_HP, p.hp + Math.round(amt)); if (p.hp > b) emit({ type: 'heroHeal', p, amt: p.hp - b }); return p.hp - b; }

/** 본진 피해. srcOwner가 자기 첫 N턴이면 차단 (자기 본진 강제 공격은 예외) */
export function damageHero(p, dmg, srcOwner, kind = 'hit', srcUnit = null) {
  if (srcOwner && srcOwner !== p && heroLocked(srcOwner)) return 0;
  if (p.st.heroInvuln) { emit({ type: 'heroImmune', p }); return 0; }
  if (p.st.heroShield) dmg = Math.max(1, Math.round(dmg / (1 + p.st.heroShield.def)));
  p.hp -= dmg;
  if (kind !== 'attack' && kind !== 'overflow') emit({ type: 'hero', p, dmg, kind });
  if (srcUnit && srcUnit.hp > 0 && hasPassive(srcUnit, '우습네요')) heal(srcUnit, Math.round(dmg * 0.3), '흡혈');
  if (p.hp <= 0) {
    const zen = !p.once['참선'] && findPassiveUnit(p, '참선');
    if (zen) {
      p.once['참선'] = 1; stats.count('참선'); p.hp = Math.min(RULES.HERO_HP, Math.max(0, p.hp) + 300);
      p.st.heroInvuln = { t: 1 + (TURN.p === p ? 1 : 0) };
      emit({ type: 'passive', unit: zen, name: '참선', text: '본진 붕괴 직전! 1턴 무적 + 체력 300 회복' });
    } else p.hp = 0;
  }
  return dmg;
}
/** HP 0 이하 유닛 정리 → 무덤, 사망 트리거, 처치 보상 */
export function checkDeath(u, killer = null) {
  const p = u.owner;
  if (u.hp > 0 || !p.field.includes(u)) return false;
  p.field.splice(p.field.indexOf(u), 1);
  p.grave.push(u.base);
  emit({ type: 'destroy', unit: u });
  // 표식: 사망 시 시전자 MP 회복
  for (const s of Object.values(u.st)) if (s.mpOnDeath && s.caster && s.caster.owner.field.includes(s.caster)) gainMp(s.caster, s.caster.maxMp * s.mpOnDeath, s.label);
  // 천사의 절규: 아군 사망마다
  for (const a of p.field) if (hasPassive(a, '천사의 절규')) { stats.count('천사의 절규'); a.cry++; heal(a, a.maxHp * 0.2, '천사의 절규'); emit({ type: 'passive', unit: a, name: '천사의 절규' }); }
  if (killer && killer.owner !== p) {
    const refund = Math.ceil(u.card.cost * RULES.KILL_MANA_REFUND_RATIO);
    killer.owner.bonusMana = (killer.owner.bonusMana || 0) + refund;
    emit({ type: 'refund', owner: killer.owner, killer, refund });
    gainXp(killer, killXp(u));
  }
  refreshAll(p);
  return true;
}
export function gainMp(u, amt, why = '') { const b = u.mp; u.mp = Math.min(u.maxMp, Math.round(u.mp + amt)); if (u.mp > b) emit({ type: 'mp', unit: u, amt: u.mp - b, why }); }

// ---- 레벨 변화 → 해금 패시브 발동 ----
export function onLevelChange(u) { if (u.owner) { emit({ type: 'levelup', unit: u, level: u.level }); refreshAll(u.owner); onUnlockCheck(u); } }
function onUnlockCheck(u) {
  for (const s of u.sk || []) {
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
  '존재의 증명': (u, p) => { for (const a of [...p.field]) for (let i = 0; i < 2 && a.level < RULES.LEVEL_MAX; i++) { levelUpOnce(a); onLevelChange(a); } healHero(p, RULES.HERO_HP * 0.5); },
};

// ===== 액티브 스킬 =====
const live = p => [...p.field];
const by = (arr, f, dir = 1) => arr.slice().sort((a, b) => dir * (f(a) - f(b)))[0];
const chance = p => rng() < p;
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
const yuriKiss = (u, f, prob, kind) => { if (chance(prob)) live(f).forEach(t => addStatus(t, kind, 1, {}, kind)); else emit({ type: 'miss', unit: u, text: '확률 실패' }); f.actionLock = Math.max(f.actionLock, 1); emit({ type: 'log', text: `${f.name || '상대'}: 다음 턴 고유기술(셔플·보강·강화·필드 회복) 봉인` }); };

export const ACTIVE = {
  // 지세강
  '절망하라': (u, p, f, s) => { const t = by(live(f), x => x.card.cost); if (t && multiHit(u, t, 5, 0.3)) u.cd[s.name] = 0; },
  '아파하라': (u, p, f, s) => { const t = by(live(f), x => x.hp); if (t && multiHit(u, t, 5, 0.4)) u.cd[s.name] = 0; },
  // 김성진
  'Da nunc': (u, p, f, s) => { const d = hitAll(u, f, 10, 0.2); u.cd[s.name] = Math.max(0, u.cd[s.name] - d); },
  'Tempus est discerpi': (u, p, f) => { live(f).forEach(t => addStatus(t, 'disrupt', 1, {}, 'disrupt')); p.actionLock = Math.max(p.actionLock, 2); },
  // 최창민
  '잘린다': (u, p, f) => { const ts = live(f); hitAll(u, f, 3, 0.2); ts.forEach(t => f.field.includes(t) && chance(0.2) && bleedOn(t, u)); },
  '러시안룰렛': (u, p, f) => { const t = by(live(f), x => x.card.cost); if (t) { t.hp = 0; emit({ type: 'dmg', unit: t, dmg: '즉사' }); checkDeath(t, u); } },
  // 최창원
  '웃자!': (u, p, f) => { const t = by(live(f), x => x.card.DEF); if (t) multiHit(u, t, 10, t.base.gender === 'FEMALE' ? 0.25 : 0.2); },
  '나약하네..': (u, p, f) => debuffAll(f, '나약하네..', 2, { def: -0.2, label: 'DEF -20%' }),
  '울자!': (u, p, f) => { const t = by(live(f), x => x.card.ATK, -1); if (t) multiHit(u, t, 5, t.base.gender === 'FEMALE' ? 0.35 : 0.3); },
  // 서성민
  '반야': (u, p) => live(p).forEach(a => heal(a, a.maxHp * 0.2)),
  '열반': (u, p) => { live(p).forEach(a => heal(a, a.maxHp * 0.1)); healHero(p, RULES.HERO_HP * 0.1); },
  // 이성호
  'Fiat Lux': (u, p, f) => { const full = f.field.length >= RULES.FIELD_MAX; hitAll(u, f, 1, 0.3); if (!full) heroHit(u, f, 0.3); },
  'Sperandum Est Infestis': (u, p, f) => { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.2, { extra: t.card.cost < 30 ? 2 : 1 }), u)); ts.forEach(t => checkDeath(t, u)); },
  'Memento Mori': (u, p, f) => { const ts = live(f); hitAll(u, f, 1, 0.2); ts.forEach(t => f.field.includes(t) && chance(0.2) && addStatus(t, 'para', 1, {}, 'para')); },
  // 임유리
  '아름다운 고통의 키스': (u, p, f) => yuriKiss(u, f, 0.3, 'confuse'),
  '더 울어, 예쁘게!': (u, p, f) => yuriKiss(u, f, 0.3, 'disrupt'),
  '천천히 찢는 사랑': (u, p, f) => { const ts = live(f); hitAll(u, f, 1, 0.4); ts.forEach(t => f.field.includes(t) && chance(0.5) && bleedOn(t, u)); },
  // 임나리
  'Seductive Whisper': (u, p, f) => { if (hitAll(u, f, 3, 0.2)) gainMp(u, u.maxMp * 0.1, '사망자 발생'); },
  'Alluring Dance': (u, p, f) => { if (hitAll(u, f, 3, 0.3)) gainMp(u, u.maxMp * 0.15, '사망자 발생'); },
  'Fatal Temptation': (u, p, f) => { const d = heroHit(u, f, 2.0); if (d > 0) { const ts = live(f); ts.forEach(t => damageUnit(t, Math.max(1, Math.round(d * 0.2)), u)); ts.forEach(t => checkDeath(t, u)); } },
  // 임규리
  '천사의 시': (u, p, f) => hitAll(u, f, 1, 0.2, { ignoreDef: 1 }),
  '천사의 자장가': (u, p, f) => { const d = hitAll(u, f, 1, 0.2); if (d) heal(u, u.maxHp * 0.1 * d, '자장가'); },
  // 정아람
  '人鬼相半': (u, p, f) => { const d = hitAll(u, f, 1, 0.2); if (d) heal(u, u.maxHp * 0.1 * d, '人鬼相半'); },
  '夜不談鬼': (u, p, f) => { let died = false; for (let i = 0; i < 5; i++) { if (died || !f.field.length) heroHit(u, f, 0.1); else { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.1), u)); ts.forEach(t => { if (checkDeath(t, u)) died = true; }); } } },
  // 김신현
  '신기하네요': (u, p, f, s) => { const t = by(live(f), x => x.card.ATK, -1); if (t && multiHit(u, t, 10, 0.2)) u.cd[s.name] = 0; },
  // 임예리
  '달빛 속 배신의 속삭임': (u, p, f) => debuffAll(f, '달빛 속 배신의 속삭임', 2, { def: -0.1, label: '달빛: DEF -10%', mpOnDeath: 0.1, caster: u }),
  '장미가시의 세레나데': (u, p, f) => debuffAll(f, '장미가시의 세레나데', 3, { atk: -0.1, label: '장미가시: ATK -10%', rose: u }),
  // 임혜리
  '주님 저희를 구하소서': (u, p) => live(p).forEach(a => heal(a, a.maxHp * 0.2)),
  '하느님의 영광': (u, p) => { if (!p.grave.length) return; const c = by(p.grave, x => x.cost, -1); p.grave.splice(p.grave.indexOf(c), 1); p.hand.push(c); emit({ type: 'revive', p, card: c }); },
  // 이지영
  'Incipit nunc sic': (u, p, f) => { const d = hitAll(u, f, 1, 0.5); if (d) gainMp(u, u.maxMp * 0.15 * d, '사망자 수'); },
  'Divina tibi poena adveniat': (u, p) => { addStatus(u, 'Divina', 2, { atk: 2.0, label: 'ATK +200%' }, 'mod'); live(p).filter(a => a !== u).forEach(a => addStatus(a, 'Divina', 2, { atk: 0.3, label: 'ATK +30%' }, 'mod')); },
  'Cum amicis meis sacris sum': (u, p, f) => debuffAll(f, 'Cum amicis', 2, { atk: -0.3, def: -0.3, label: 'ATK·DEF -30%', mpOnDeath: 0.1, caster: u }),
  // 이진경
  'My Black Sun': (u, p, f) => live(f).filter(t => t.card.cost < 40).forEach(t => addStatus(t, 'disrupt', 1, {}, 'disrupt')),
  'Esoteric Method': (u, p, f) => live(f).forEach(t => addStatus(t, 'esoteric', 3, { stack: 0 }, 'esoteric')),
  // 김백중
  '다친다': (u, p, f) => hitAll(u, f, 5, 0.2, { ignoreDef: 0.5 }),
  '죽을지도 몰라': (u, p, f, s) => { let d = 0; for (let i = 0; i < 5; i++) { const ts = live(f); ts.forEach(t => damageUnit(t, skillDamage(u, t, 0.1), u)); ts.forEach(t => { if (checkDeath(t, u)) d++; }); heroHit(u, f, 0.1); } if (d) { u.cd[s.name] = 0; gainMp(u, u.maxMp * 0.1, '사망자 발생'); } },
  '죽는다…': (u, p, f) => { heroHit(u, f, 2.0); live(f).forEach(t => bleedOn(t, u)); },
  // [각성] 윤진아
  '여기는 뇌입니다': (u, p, f) => { const t = by(live(f), x => x.card.cost, -1); if (!t) return; let killed = false, heroHits = 0; for (let i = 0; i < 3; i++) { if (!killed) { damageUnit(t, skillDamage(u, t, 0.5, { ignoreDef: 1 }), u); killed = checkDeath(t, u); } else { heroHit(u, f, 0.5); heroHits++; } } if (killed && !heroHits) heroHit(u, f, 0.5); },
  '이게 심장인가요?': (u, p, f) => { let t = by(live(f), x => x.card.cost); for (let i = 0; i < 4 && t; i++) { damageUnit(t, skillDamage(u, t, 0.5, { ignoreDef: 1 }), u); if (checkDeath(t, u)) t = by(live(f), x => x.card.cost); } },
  '감당….해주세요.': (u, p, f) => { const t = by(live(f), x => x.card.ATK, -1); if (t && multiHit(u, t, 5, 0.5, { ignoreDef: 1 })) { u.mp = u.maxMp; emit({ type: 'mp', unit: u, amt: 'MAX' }); } },
  // [각성] 임유리
  '아름다운 고통의 키스(眞)': (u, p, f) => yuriKiss(u, f, 0.7, 'confuse'),
  '더 울어, 예쁘게!(眞)': (u, p, f) => yuriKiss(u, f, 0.7, 'disrupt'),
  '천천히 찢는 사랑(眞)': (u, p, f) => { const ts = live(f); const d = hitAll(u, f, 1, 2.0); ts.forEach(t => f.field.includes(t) && bleedOn(t, u)); if (d) gainMp(u, u.maxMp * 0.2, '사망자 발생'); },
  // 정석윤
  '분리한다': (u, p, f) => debuffAll(f, '분리한다', 2, { atk: -0.1, def: -0.1, label: 'ATK·DEF -10%' }),
  '결합한다': (u, p, f) => live(f).forEach(t => addStatus(t, 'disrupt', 2, { mixed: true }, 'disrupt')),
  '파괴한다': (u, p, f) => live(f).forEach(t => { for (let i = 0; i < 2 && t.level > 1; i++) levelDown(t); const m = Math.round(t.mp * 0.4); t.mp -= m; emit({ type: 'mp', unit: t, amt: -m }); onLevelChange(t); }),
};

// ---- 스킬 사용 가능 여부 ----
export function skillState(u, s) {
  if (s.mode !== 'active') return { ok: false, reason: '패시브' };
  if (u.level < s.unlock) return { ok: false, reason: `Lv${s.unlock} 해금` };
  if (u.cd[s.name] > 0) return { ok: false, reason: `쿨타임 ${u.cd[s.name]}턴` };
  if (u.mp < s.mp) return { ok: false, reason: `MP 부족 (${u.mp}/${s.mp})` };
  if (!u.canAttack) return { ok: false, reason: '이번 턴 행동함' };
  if (!ACTIVE[s.name]) return { ok: false, reason: '미구현' };
  return { ok: true };
}
/** 액티브 스킬 사용 (그 턴 공격 대신) */
export function useSkill(u, s) {
  const st = skillState(u, s); if (!st.ok) return st;
  const p = u.owner;
  u.mp -= s.mp; u.cd[s.name] = s.cooldown; u.canAttack = false;
  emit({ type: 'skill', unit: u, skill: s });
  stats.count(s.name);
  refreshAll(p);
  ACTIVE[s.name](u, p, p.foe, s);
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
    // 임예리 장미가시: 표식된 적이 임예리를 피격 → 기본 공격 반격
    if (attacker.st['장미가시의 세레나데'] && target.base.id === attacker.st['장미가시의 세레나데'].rose?.base.id && tp.field.includes(target) && attacker.owner.field.includes(attacker)) {
      emit({ type: 'passive', unit: target, name: '장미가시 반격' }); stats.count('장미가시 반격');
      damageUnit(attacker, calcDamage(target.card, attacker.card), target); checkDeath(attacker, target);
    }
    // 이지영 Lv10: 피격 시 Incipit nunc sic 반격 (MP 소모 없음)
    if (hasPassive(target, 'Maledictio vel benedictio') && tp.field.includes(target)) {
      emit({ type: 'passive', unit: target, name: 'Maledictio vel benedictio' }); stats.count('Maledictio vel benedictio'); ACTIVE['Incipit nunc sic'](target, tp, tp.foe);
    }
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
  // 임혜리 주님의 기적: 아군·본진 5% 회복
  const hy = findPassiveUnit(p, '주님의 기적');
  if (hy) { emit({ type: 'passive', unit: hy, name: '주님의 기적' }); stats.count('주님의 기적'); p.field.forEach(a => heal(a, a.maxHp * 0.05)); healHero(p, RULES.HERO_HP * 0.05); }
  // Esoteric Method: 매 턴 HP -10%, ATK -3% 누적
  for (const u of [...p.field]) if (u.st.esoteric) { u.st.esoteric.stack = (u.st.esoteric.stack || 0) + 1; damageUnit(u, Math.max(1, Math.round(u.maxHp * 0.1)), null); checkDeath(u, u.st.esoteric.caster || null); }
  // 임예리 지옥 교향곡 (상대 필드): 매 턴 ATK·DEF -2% 누적, HP -5%
  const yeri = findPassiveUnit(f, '자수정 눈물의 지옥 교향곡');
  if (yeri) { emit({ type: 'passive', unit: yeri, name: '자수정 눈물의 지옥 교향곡' }); stats.count('자수정 눈물의 지옥 교향곡'); for (const u of [...p.field]) { if (u.st.debuffImmune) continue; u.curse++; damageUnit(u, Math.max(1, Math.round(u.maxHp * 0.05)), null); checkDeath(u, yeri); } }
  refreshAll(p);
  // [각성] 임유리 공허의 제왕: 턴 시작 시 적 전체 + 본진 50% 자동 공격
  for (const u of [...p.field]) if (hasPassive(u, '공허의 제왕') && p.field.includes(u)) {
    emit({ type: 'passive', unit: u, name: '공허의 제왕' }); stats.count('공허의 제왕');
    hitAll(u, f, 1, 0.5); heroHit(u, f, 0.5);
  }
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
    for (const [k, s] of Object.entries(u.st)) if (--s.t <= 0) { delete u.st[k]; if (k === 'para') u.paraBlock = 2; emit({ type: 'expire', unit: u, key: k }); }
  }
  for (const [k, s] of Object.entries(p.st)) if (--s.t <= 0) delete p.st[k];
  if (p.actionLock > 0) p.actionLock--;
  refreshAll(p);
}

// ===== AI: 스킬 선택 =====
export function aiPickSkill(u) {
  const p = u.owner, f = p.foe;
  const cands = [];
  // MP 저축: 해금된 최상위 액티브가 MP 부족이면 50% 확률로 하위 스킬을 아끼고 기본 공격
  const top = (u.sk || []).filter(s => s.mode === 'active' && u.level >= s.unlock && ACTIVE[s.name]).sort((a, b) => b.unlock - a.unlock)[0];
  const saving = top && u.mp < top.mp && !(u.cd[top.name] > 0) && rng() < 0.5;
  for (const s of u.sk || []) {
    if (!skillState(u, s).ok) continue;
    if (saving && s !== top) continue;
    const n = f.field.length, lowHp = p.field.filter(a => a.hp < a.maxHp * 0.7).length;
    let sc = 0;
    const heroOk = !heroLocked(p);
    // 기본 공격으로 처치 가능한 대상이 있으면 보조 스킬보다 공격 우선
    const canKill = f.field.some(t => calcDamage(u.card, t.card) >= t.hp && calcDamage(t.card, u.card) < u.hp);
    switch (s.name) {
      case '반야': case '주님 저희를 구하소서': sc = lowHp >= 2 ? 90 + lowHp * 5 : 0; break;
      case '열반': sc = (lowHp >= 2 || p.hp < RULES.HERO_HP * 0.6) ? 95 : 0; break;
      case '하느님의 영광': sc = p.grave.length && p.hand.length < 10 ? 80 + Math.max(...p.grave.map(c => c.cost)) : 0; break;
      case 'Divina tibi poena adveniat': sc = p.field.length >= 2 && n ? 120 : 0; break;
      case 'Fatal Temptation': case '죽는다…': sc = heroOk ? 115 : 0; break;
      case 'Tempus est discerpi': case '결합한다': sc = n >= 2 ? 110 + n * 5 : 0; break;
      case 'My Black Sun': { const k = f.field.filter(t => t.card.cost < 40).length; sc = k >= 2 ? 100 + k * 5 : 0; break; }
      case '아름다운 고통의 키스(眞)': case '더 울어, 예쁘게!(眞)': case 'Cum amicis meis sacris sum': sc = n >= 2 ? 100 + n * 5 : 0; break;
      case '파괴한다': sc = f.field.reduce((a, t) => a + (t.level - 1), 0) >= 3 ? 105 : 0; break;
      case '러시안룰렛': sc = n ? 90 + by(f.field, x => x.card.cost).card.cost : 0; break;
      default:
        if (s.type === '디버프') sc = n >= 3 && !canKill ? 80 + n * 3 : 0;
        else if (s.type === '공격') sc = n || (/본진/.test(s.desc) && heroOk) ? (/적 전체|전체/.test(s.target + s.desc) ? 95 + n * 6 : 100) : 0;
    }
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
