// ===== 장비·증표 전투 반영 (PR3) — 스토리·탑·토벌·PvP·세력전 공통 =====
// applyGear(card, { gear, sigil }, mode) → 장비 스탯이 들어간 카드 복사본. card.gear = 유닛 보정값, card.sigil = 증표 현재 단계(스킬 개조)
// 모드별 배율·증표 상한은 GEAR_MODE (사용자 조절값, gear_mode_config 와 같은 값)
export const GEAR_MODE = {
  story: { gear: 1, sigilMax: 5 }, tower: { gear: 1, sigilMax: 5 }, raid: { gear: 1, sigilMax: 5 },
  pvp: { gear: 0.5, sigilMax: 3 }, war: { gear: 0.5, sigilMax: 3 }, arcade: { gear: 0, sigilMax: -1 },
};
export const PLUS_MULT = [1, 1.10, 1.20, 1.35, 1.50, 1.70];
export const STAT_CAP = 45;   // 장비로 오르는 HP·ATK·DEF 각각 상한 (퍼센트, 모드 배율 적용 전)
// 증표 단계표 (supabase/gear_v1.sql sigil_defs 와 같은 값)
export const SIGILS = {"10118": [{"plus": 0, "skill": "무답무용", "hit_pct": 35, "hits": 6, "bleed_pct": 40}, {"plus": 1, "skill": "무답무용", "hit_pct": 40, "hits": 6, "bleed_pct": 45}, {"plus": 2, "skill": "무답무용", "hit_pct": 40, "hits": 7, "bleed_pct": 50, "cooldown": 3}, {"plus": 3, "skill": "무답무용", "hit_pct": 45, "hits": 7, "bleed_pct": 60, "cooldown": 3}, {"plus": 4, "skill": "무답무용", "hit_pct": 50, "hits": 7, "bleed_pct": 70, "cooldown": 3}, {"plus": 5, "skill": "무답무용", "hit_pct": 50, "hits": 7, "bleed_pct": 70, "cooldown": 3, "vs_bleed_dmg_pct": 30, "on_kill_extra_hits": 3}], "10415": [{"plus": 0, "skill": "제발 그냥 가줘", "cooldown": 6, "mp": 75, "fallback_hp_pct": 40}, {"plus": 1, "skill": "제발 그냥 가줘", "cooldown": 6, "mp": 70, "fallback_hp_pct": 50}, {"plus": 2, "skill": "제발 그냥 가줘", "cooldown": 5, "mp": 65, "fallback_hp_pct": 50, "also": {"skill": "나 좀 내버려둬", "cooldown": 4}}, {"plus": 3, "skill": "제발 그냥 가줘", "cooldown": 4, "mp": 60, "fallback_hp_pct": 60, "also": {"skill": "나 좀 내버려둬", "cooldown": 4}}, {"plus": 4, "skill": "제발 그냥 가줘", "cooldown": 4, "mp": 55, "fallback_hp_pct": 60, "also": {"skill": "나 좀 내버려둬", "cooldown": 4, "duration": 2}}, {"plus": 5, "skill": "제발 그냥 가줘", "cooldown": 3, "mp": 50, "fallback_hp_pct": 60, "targets": 2, "also": {"skill": "나 좀 내버려둬", "cooldown": 4, "duration": 2}}], "10325": [{"plus": 0, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 55, "hits": 2, "bleed_pct": 70}, "b": {"hp_pct": [10, 15], "cap": [160, 240], "cc_pct": 40}}, {"plus": 1, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 60, "hits": 2, "bleed_pct": 75}, "b": {"hp_pct": [10, 15], "cap": [180, 270], "cc_pct": 45}}, {"plus": 2, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 50, "hits": 3, "bleed_pct": 80}, "b": {"hp_pct": [12, 18], "cap": [200, 300], "cc_pct": 50}}, {"plus": 3, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 55, "hits": 3, "bleed_pct": 80, "bleed_dmg_pct": 8}, "b": {"hp_pct": [12, 18], "cap": [200, 300], "cc_pct": 50, "mp": 35}}, {"plus": 4, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 60, "hits": 3, "bleed_pct": 90, "bleed_dmg_pct": 8}, "b": {"hp_pct": [14, 20], "cap": [230, 340], "cc_pct": 55, "mp": 35}}, {"plus": 5, "a": {"skill": "천천히 찢는 사랑", "hit_pct": 65, "hits": 3, "bleed_pct": 100, "bleed_dmg_pct": 8, "vs_bleed_dmg_pct": 30}, "b": {"hp_pct": [15, 22], "cap": [230, 340], "cc_pct": 60, "mp": 35, "cc_then_bleed": true}}]};
const KISS = ['아름다운 고통의 키스', '더 울어, 예쁘게!'];
/** 유닛 u 가 스킬 name 에 쓰는 증표 개조값 (없으면 null) */
export function sigilFor(u, name) {
  const s = u?.base?.sigil || u?.card?.sigil; if (!s) return null;
  if (s.skill === name) return s;
  if (s.also?.skill === name) return s.also;
  if (s.a?.skill === name) return s.a;
  if (s.b && KISS.includes(name)) return s.b;
  return null;
}
const OPTK = { crit: 'crit', evade: 'evade', crit_dmg: 'critDmg', elem_dmg: 'elem', dmg_reduce: 'dr', debuff_resist: 'debRes', mp_regen: 'mpRegen', kill_mp: 'killMp', cooldown: 'cd' };
/** gear: [{ stat, pct, plus, opts:[{opt,v}] }], sigil: 증표 강화 단계(null = 없음) */
export function applyGear(c, { gear = [], sigil = null } = {}, mode = 'story') {
  if (!c) return c;
  const M = GEAR_MODE[mode] || GEAR_MODE.story, f = M.gear;
  const out = { ...c };
  if (f > 0 && gear?.length) {
    const up = { ATK: 0, HP: 0, DEF: 0 }, g = { crit: 0, evade: 0, critDmg: 0, elem: 0, dr: 0, debRes: 0, mpStart: 0, mpRegen: 0, killMp: 0, cd: 0 };
    for (const it of gear) {
      const v = (+it.pct || 0) * (PLUS_MULT[it.plus | 0] || 1);
      if (it.stat === 'atk') up.ATK += v; else if (it.stat === 'hp') up.HP += v; else if (it.stat === 'def') up.DEF += v;
      else if (it.stat === 'crit') g.crit += v; else if (it.stat === 'evade') g.evade += v; else if (it.stat === 'mp') g.mpStart += v;
      for (const o of it.opts || []) { const k = OPTK[o.opt]; if (k) g[k] += +o.v || 0; }
    }
    for (const s of ['ATK', 'HP', 'DEF']) if (up[s] && out[s] != null) out[s] = Math.round(out[s] * (1 + Math.min(STAT_CAP, up[s]) * f / 100));
    const gg = {};
    for (const k in g) if (g[k]) gg[k] = k === 'cd' ? Math.min(1, Math.round(g[k])) : (k === 'crit' || k === 'evade') ? g[k] * f / 100 : g[k] * f;   // crit·evade = 확률(0~1), 나머지 = 퍼센트
    if (Object.keys(gg).length) out.gear = gg;
    const pw = ((out.ATK || 0) + (out.HP || 0) + (out.DEF || 0)) / Math.max(1, (c.ATK || 0) + (c.HP || 0) + (c.DEF || 0));
    if (c.power && pw > 1) out.power = Math.round(c.power * pw);
  }
  const st = SIGILS[String(c.id)];
  if (st && sigil != null && M.sigilMax >= 0) out.sigil = { ...st[Math.min(sigil | 0, M.sigilMax, 5)] };
  return out;
}
if (typeof window !== 'undefined') window.VRGearCore = { applyGear, sigilFor, GEAR_MODE, SIGILS };
