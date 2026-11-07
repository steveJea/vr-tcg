// Trusted verifier entry. Generated bundle includes the exact browser engine and canonical data.
import csv from '../data/cards.csv';
import skillData from '../data/skills.json';
import combos from '../data/combos.json';
import { parseCSV, setCardPool } from '../js/rules.js';
import { setSkillData } from '../js/skills.js';
import { snapCard, MODES, rngOf, stepper, matchGen, roundSeed } from '../js/pvp-core.js';
const pool = parseCSV(csv), cards = new Map(pool.map(c => [String(c.id), c]));
setCardPool(pool); setSkillData(skillData, combos);
const index = n => Number.isInteger(n) && n >= 0 && n < 6;
export function checkActions(actions) {
  if (!Array.isArray(actions) || actions.length < 1 || actions.length > 3) throw new Error('invalid rounds');
  for (const round of actions) {
    if (!Array.isArray(round) || round.length > 1600) throw new Error('invalid actions');
    for (const a of round) {
      if (!a || typeof a !== 'object' || Array.isArray(a)) throw new Error('invalid action');
      const keys = Object.keys(a).sort().join(',');
      if (a.k === 'end' && keys === 'k') continue;
      if (a.k === 'atk' && keys === 'i,k,t' && index(a.i) && (index(a.t) || a.t === -1)) continue;
      if (a.k === 'skill' && keys === 'i,k,s' && index(a.i) && typeof a.s === 'string' && a.s.length > 0 && a.s.length <= 160) continue;
      if (a.k === 'swap' && keys === 'f,g,k' && index(a.g) && index(a.f)) continue;
      throw new Error('invalid action');
    }
  }
}
export function verifyBattle(session, actions) {
  const M = MODES[session.mode]; if (!M) throw new Error('invalid mode');
  if (session.control === 'actions') checkActions(actions);
  else if (session.control !== 'auto' || actions !== null) throw new Error('invalid control');
  const decks = snap => {
    if (!Array.isArray(snap) || snap.length !== M.decks) throw new Error('invalid snapshot');
    return snap.map(d => {
      if (!Array.isArray(d) || d.length < (M.boss ? 2 : 1) || d.length > (M.boss ? 6 : 5)) throw new Error('invalid snapshot');
      return d.map(o => { const c = snapCard(o, id => cards.get(String(id))); if (!c) throw new Error('unknown card'); return c; });
    });
  };
  const A = decks(session.me), B = decks(session.opp), rounds = []; let wins = 0, losses = 0, skills = 0;
  for (let i = 0; i < M.decks && wins < M.need && losses < M.need; i++) {
    const log = [], r = rngOf(roundSeed(session.seed, i));
    const st = stepper(matchGen(A[i], B[i], r, log, session.control === 'actions', null, { boss: !!M.boss, strict: true }), r);
    let x = st.next(), at = 0, steps = 0;
    const acts = actions?.[i]; if (session.control === 'actions' && !acts) throw new Error('missing round');
    while (!x.done) {
      if (++steps > 20000 || !x.value?.ask || at >= acts.length) throw new Error('missing action');
      x = st.next(acts[at++]);
    }
    if (acts && at !== acts.length) throw new Error('extra actions');
    const result = x.value; if (!result || !Number.isInteger(result.turns)) throw new Error('engine incomplete');
    skills += log.filter(e => e.k === 'skill' && e.side === 'A').length;
    rounds.push(result); result.win ? wins++ : losses++;
  }
  if (actions && actions.length !== rounds.length) throw new Error('extra rounds');
  return { win: wins >= M.need, wins, losses, rounds, skills };
}
