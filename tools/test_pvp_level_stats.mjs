// Regression for #382's swallowed snapshot fields. No network or live accounts.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { parseCSV, setCardPool, skillLvPowerMult } from '../js/rules.js';
import { setSkillData, skillsOf } from '../js/skills.js';
import { snapCard, manualMatch, runSeries, MODES, roundSeed } from '../js/pvp-core.js';
import { verifyBattle } from '../supabase/functions/_shared/pvp-engine-v3.mjs';
const pool = parseCSV(fs.readFileSync('data/cards.csv', 'utf8'));
setCardPool(pool); setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
const rates = { NORMAL: 1, RARE: 2, 'HIGH RARE': 3, 'SUPER RARE': 4, 'ULTRA RARE': 5, 'MYTHIC RARE': 6, 'LEGENDARY RARE': 5 };
const point = (s, n) => { const k = s === 'HP' ? 5 : 1; return k * Math.min(n, 5) + Math.floor(k * Math.max(0, n - 5) / 2); };
function expected(c, o, stat) { return Math.round(c[stat] * (1 + (o.exb || 0) / 100) * (1 + rates[c.grade] * ((o.level || 1) - 1) / 100)) + point(stat, o.boost?.[stat] || 0); }
let grades = 0, upgradedSkills = 0;
// LR is normalized out of today's catalog; exercise its supported legacy rate
// with an MR-card copy, without inventing a playable server snapshot.
for (const grade of Object.keys(rates)) {
  const c = pool.find(c => c.grade === grade && c.ATK > 0 && c.HP > 0 && c.DEF > 0) || (grade === 'LEGENDARY RARE' ? { ...pool.find(c => c.grade === 'MYTHIC RARE'), grade } : null); assert(c, grade);
  const lookup = id => String(id) === String(c.id) ? c : byId(id);
  const original = structuredClone(c), base = snapCard({ id: c.id, level: 1 }, lookup);
  const activeIndex = skillsOf(c.id).findIndex(s => s.mode === 'active');
  const o = { id: c.id, level: 20, ex: 2, exb: 17.25, boost: { ATK: 9, HP: 8, DEF: 7 }, skillLv: activeIndex >= 0 ? { [activeIndex + 1]: 4 } : {} };
  const before = structuredClone(o), upgraded = snapCard(o, lookup);
  for (const stat of ['ATK', 'HP', 'DEF']) {
    assert.equal(upgraded[stat], expected(c, o, stat), `${grade} ${stat} exact level × EX bonus + diminished points`);
    assert(upgraded[stat] > base[stat]);
    const exOnly = snapCard({ id: c.id, ex: 2 }, lookup); assert.equal(exOnly[stat], c[stat], 'EX stage alone is display/cap metadata, not a second EX% multiplier');
  }
  const skillPower = activeIndex >= 0 ? 1.015 : 1; // active Lv4: three 0.5% increments
  assert.equal(skillLvPowerMult(skillsOf(c.id), o.skillLv), skillPower);
  assert.equal(upgraded.power, Math.round(c.power * 1.1725 * (1 + rates[grade] * 19 / 100) * skillPower));
  if (activeIndex >= 0) upgradedSkills++;
  assert.equal(upgraded.ex, 2); assert.equal(upgraded.slv, 20); assert.equal(upgraded.name, c.name);
  assert.deepEqual(upgraded.skillLv, o.skillLv); assert.notEqual(upgraded.skillLv, o.skillLv);
  assert.deepEqual(c, original); assert.deepEqual(o, before, 'input metadata cannot be mutated'); grades++;
}
assert(upgradedSkills > 0, 'real numeric skill-level maps must exercise the restored power multiplier');
// Gear stays AFTER progression scaling; PvP/war 50%, raid 100%, sigils capped.
{
  const id = '10118', c = byId(id), o = { id, level: 20, ex: 1, exb: 10, boost: { ATK: 7 }, gear: [{ stat: 'atk', pct: 10, plus: 0, opts: [] }], sigil: 5 };
  for (const mode of ['pvp', 'war', 'raid']) {
    const s = snapCard(o, byId, mode);
    assert.equal(s.ATK, Math.round(expected(c, o, 'ATK') * (mode === 'raid' ? 1.10 : 1.05)));
    assert.equal(s.sigil.plus, mode === 'raid' ? 5 : 3); assert.equal(s.slv, 20);
  }
}
const hr = pool.filter(c => ['NORMAL', 'RARE', 'HIGH RARE'].includes(c.grade));
const deck = (offset, n) => hr.slice(offset, offset + n).map(c => ({ id: String(c.id), level: 1 }));
const cards = d => d.map(o => snapCard(o, byId));
const publicResult = r => ({ win: r.win, wins: r.wins, losses: r.losses, rounds: r.rounds });
let battles = 0, changed = 0;
for (const mode of Object.keys(MODES)) for (const side of ['me', 'opp']) for (const control of ['auto', 'actions']) {
  const M = MODES[mode], n = M.boss ? 6 : 5;
  const base = { mode, control: 'auto', seed: 9182, me: Array.from({ length: M.decks }, (_, i) => deck(i * 6, n)), opp: Array.from({ length: M.decks }, (_, i) => deck(24 + i * 6, n)) };
  const s = structuredClone(base); s.control = control;
  s[side] = s[side].map(d => d.map(o => ({ ...o, level: 40, ex: 3, exb: 20, boost: { ATK: 9, HP: 8, DEF: 7 } })));
  const acts = [], rounds = []; let w = 0, l = 0;
  for (let i = 0; i < M.decks && w < M.need && l < M.need; i++) {
    const st = manualMatch(cards(s.me[i]), cards(s.opp[i]), roundSeed(s.seed, i), null, { boss: !!M.boss, view: true, manual: control === 'actions' });
    let x = st.next(); assert(!x.done);
    // Both roles, in both modes, reach actual field units with upgraded base stats.
    for (const [role, snap] of [['A', s.me[i]], ['B', s.opp[i]]]) for (const [j, o] of snap.entries()) {
      const u = x.value[role + '0'][j], c = byId(o.id);
      for (const stat of ['ATK', 'HP', 'DEF']) assert.equal(u.base[stat], expected(c, o, stat));
      assert.equal(u.base.slv, o.level); assert.equal(u.base.ex, o.ex || 0);
    }
    let steps = 0;
    while (!x.done) { assert(++steps < 20000); x = st.next(x.value.ask ? { k: 'auto' } : undefined); }
    acts.push(st.acts); rounds.push(x.value); x.value.win ? w++ : l++;
  }
  const server = verifyBattle(s, control === 'actions' ? acts : null);
  assert.deepEqual(publicResult(server), { win: w >= M.need, wins: w, losses: l, rounds });
  assert.deepEqual(publicResult(verifyBattle({ ...s, control: 'auto' }, null)), publicResult(server), 'AUTO and canonical manual action playback remain identical');
  assert.deepEqual(runSeries(mode, s.me.map(cards), s.opp.map(cards), s.seed), publicResult(server));
  if (JSON.stringify(publicResult(server)) !== JSON.stringify(publicResult(verifyBattle(base, null)))) changed++;
  battles++;
}
assert.equal(changed, battles, 'every selected side/mode/control fixture must change real combat, not just a displayed number');
const example = snapCard({ id: '10137', level: 40, ex: 3, exb: 20, boost: { ATK: 9, HP: 8, DEF: 7 } }, byId);
console.log(`PvP level stats: ${grades} grades exact progression/EX/points/power, gear order and metadata; ${battles} attacker/defender × AUTO/manual × all-mode browser/Edge replays (${changed} changed combat results). Example 10137: ${example.ATK}/${example.HP}/${example.DEF}`);
