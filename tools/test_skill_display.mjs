// Display-only skill labels must not change auto-AI scores. aiType keeps the old type.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
import { setSkillData, setEmitter, setRng, initPlayers, placeUnit, aiSkillScores, aiType } from '../js/skills.js';

const skills = JSON.parse(readFileSync(new URL('../data/skills.json', import.meta.url), 'utf8'));
const find = (id, name) => {
  const s = (skills[id] || []).find(x => x.name === name);
  if (!s) throw new Error(`missing ${id} ${name}`);
  return s;
};
assert.equal(find('10311', 'Maledictio vel benedictio').desc, '상시. 적 전체의 공격력·방어력 50% 하락. HP는 그대로. 이지영이 필드에 있는 동안 지속.');
assert.equal(find('10312', 'My Black Sun').desc, '코스트 40 미만인 적 전체를 1턴 간 교란(자기 턴에 자기 본진을 공격).');
assert.equal(find('10322', '천사의 시').target, '적 전체');
assert.equal(find('10322', '천사의 자장가').target, '적 전체');
assert.equal(find('10301', '사랑해!!!').target, '적 2명 무작위');

const reclass = [
  ['10060', 'Tempus est discerpi', '디버프', '도발'],
  ['10312', 'My Black Sun', '디버프', '도발'],
  ['10331', '하느님의 영광', '보호', '회복'],
  ['10257', '이번만이야', '보호', '회복'],
  ['10334', '무극', '보호', '회복'],
  ['10465', '내 동생 건드리지마!', '보호', '도발'],
  ['10108', '제발…그만', '보호', '도발'],
  ['10439', '내가 지켜준다', '보호', '도발'],
  ['10267', '사랑하는 친구거든!', '보호', '도발'],
  ['10399', '튀 므 망크', '보호', '버프'],
  ['10013', '내가 오빠잖아.', '보호', '버프'],
  ['10439', '나는 쓰러지지 않아', '보호', '버프'],
  ['10301', '진짜 진짜 사랑해', '보호', '버프'],
  ['10491', '너무너무 사랑해', '보호', '버프'],
  ['10491', '절대 무너지지 마', '보호', '버프'],
];
for (const [id, name, type, old] of reclass) {
  const s = find(id, name);
  assert.equal(s.type, type, name);
  assert.equal(s.aiType, old, name);
  assert.equal(aiType(s), old);
}

setEmitter(() => {});
setRng(() => 0.99);
const cards = parseCSV(readFileSync(new URL('../data/cards.csv', import.meta.url), 'utf8'));
setCardPool(cards);
setSkillData(skills, []);
const byId = new Map(cards.map(c => [String(c.id), c]));

const foeCard = cards.find(c => c.HP > 0);
function scores(id, skill) {
  const me = { name: 'me', field: [], deck: [], hand: [], hp: 3000, maxHp: 3000, mana: 0, maxMana: 0, once: {}, st: {}, grave: [] };
  const ai = { name: 'ai', field: [], deck: [], hand: [], hp: 3000, maxHp: 3000, mana: 0, maxMana: 0, once: {}, st: {}, grave: [], noBase: false };
  initPlayers(me, ai, me);
  const u = placeUnit(me, byId.get(String(id)) || foeCard, makeUnit);
  u.level = 70; u.mp = 999; u.canAttack = true; u.sk = [skill];
  placeUnit(ai, foeCard, makeUnit);
  return aiSkillScores(u, { noSave: true }).map(([s, sc]) => [s.name, sc]);
}
for (const [id, name] of reclass) {
  const live = find(id, name);
  if (live.mode !== 'active') continue;
  const old = { ...live, type: live.aiType };
  delete old.aiType;
  assert.deepEqual(scores(id, live), scores(id, old), name);
}
console.log('skill display labels do not change auto-AI scores');
