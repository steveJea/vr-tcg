// 자동 전투 규칙 테스트 (고정 시드): node tools/test_auto_ai.mjs
import './seed_rng.mjs';
import { readFileSync } from 'fs';
import { setSkillData, initPlayers, placeUnit, refreshAll, isTauntSkill } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
import { autoNext, noteUsed } from '../js/auto-ai.js';
const rd = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const pool = parseCSV(rd('../data/cards.csv')); setCardPool(pool); setSkillData(JSON.parse(rd('../data/skills.json')), JSON.parse(rd('../data/combos.json')));
const C = id => ({ ...pool.find(c => c.id === id) });
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
function setup(mine, foes, { lv = 10, mp = 200 } = {}) {
  const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true, once: {} });
  const A = mk('me'), B = mk('ai'); initPlayers(A, B, A);
  mine.forEach(id => placeUnit(A, C(id), makeUnit)); foes.forEach(id => placeUnit(B, C(id), makeUnit));
  for (const u of A.field) { u.level = lv; u.mp = mp; u.canAttack = true; u.cd = {}; }
  for (const u of B.field) { u.canAttack = true; }
  refreshAll(A); refreshAll(B);
  return [A, B];
}
const T = () => ({ used: new Set(), scopes: new Set() });
const BIG = ['1000200030', '2000900234', '2001500316'];

// 1) 도발은 한 명만: 도발 카드 2장 → 첫 수가 도발이면 같은 턴 두 번째 도발 금지, 아군 도발 살아 있으면 안 씀
{ const [A, B] = setup(['2000000017', '1000200024'], BIG); A.field.forEach(u => u.mp = 200);
  const t = T(); let a = autoNext(A, B, t); const seen = [];
  for (let k = 0; a && k < 4; k++) { if (a.kind === 'skill') { seen.push(a.s); noteUsed(t, a.s); } a.u.canAttack = false; a = autoNext(A, B, t); }
  ok(seen.filter(isTauntSkill).length <= 1, `도발 한 턴 1회 (${seen.map(s => s.name).join(',') || '없음'})`);
  const [A2, B2] = setup(['2000000017', '1000200024'], BIG); A2.field[0].st.taunt = { turns: 2 };
  const t2 = T(); let b = autoNext(A2, B2, t2), any = false;
  for (let k = 0; b && k < 4; k++) { if (b.kind === 'skill' && isTauntSkill(b.s)) any = true; b.u.canAttack = false; b = autoNext(A2, B2, t2); }
  ok(!any, '아군 도발 유지 중엔 도발 재사용 안 함'); }

// 2) 한 방 처치 우선: MP 0, 적 하나 HP 1 → 그 적을 친다
{ const [A, B] = setup(['1000000001'], ['1000000002', '1000000005'], { lv: 1, mp: 0 }); B.field[1].hp = 1;
  const a = autoNext(A, B, T()); ok(a && a.kind === 'attack' && a.t === B.field[1], '처치 가능한 적 먼저'); }

// 3) 같은 스킬은 한 명만: 같은 카드 2장
{ const [A, B] = setup(['2000100001', '2000100001'], BIG, { lv: 5, mp: 200 });
  const t = T(); const a = autoNext(A, B, t);
  if (a?.kind === 'skill') { noteUsed(t, a.s); a.u.canAttack = false; const b = autoNext(A, B, t); ok(!(b?.kind === 'skill' && b.s.name === a.s.name), `같은 스킬 중복 금지 (${a.s.name})`); }
  else ok(false, '스킬 후보 없음'); }

// 4) 디버프 먼저, 공격 스킬은 그 다음: 임유리(디버프) + 지세강(공격)
{ const [A, B] = setup(['1000200018', '2000100001'], BIG, { lv: 5, mp: 200 });
  const a = autoNext(A, B, T()); ok(a?.kind === 'skill' && a.s.type === '디버프', `첫 수 디버프 (${a?.s?.name || a?.kind})`); }
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
