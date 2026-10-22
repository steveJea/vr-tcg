// 퀘스트 모드 검증: node tools/test_quest.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, RULES } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, skillsOf, aiPickSkill, refreshAll, TURN } from '../js/skills.js';
await import('../js/quest-gen.js');
const G = globalThis.VRQuestGen;
const pool = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')), combos = JSON.parse(fs.readFileSync('data/combos.json')), cfg = JSON.parse(fs.readFileSync('data/quest.json'));
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), combos);
let fails = 0; const ok = (n, c, extra = '') => { console.log((c ? 'PASS ' : 'FAIL ') + n + (extra ? ' — ' + extra : '')); if (!c) fails++; };
const ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];

// 1) quest.json
ok('350층, 1부터 연속', cfg.floors.length === 350 && cfg.floors.every((f, i) => f.floor === i + 1));
ok('시트 값 샘플', cfg.floors[0].power === 800 && cfg.floors[0].grade === 'NORMAL' && cfg.floors[79].grade === 'RARE' && cfg.floors[79].others === 'weak' && cfg.floors[209].bond && cfg.floors[349].power === 450000 && cfg.floors[349].grade === 'MYTHIC RARE');
// 2) 보상: 10층마다 5, 50층마다 10, 나머지 없음
ok('보상 규칙', G.rewardOf(cfg, cfg.floors[9]).tickets === 5 && G.rewardOf(cfg, cfg.floors[49]).tickets === 10 && G.rewardOf(cfg, cfg.floors[99]).tickets === 10 && G.rewardOf(cfg, cfg.floors[10]) === null && G.rewardOf(cfg, cfg.floors[349]).tickets === 10);
ok('층 rewards 덮어쓰기 (골드 훅)', G.rewardOf(cfg, { floor: 7, rewards: { gold: 500 } }).gold === 500);
// 3) 생성기: 고정(시드) · 5장 · 등급 · 리더 목표 · 범위
const all = cfg.floors.map(f => [f, G.generate(cfg, f, pool, combos)]);
ok('같은 층은 항상 같은 적', JSON.stringify(G.generate(cfg, cfg.floors[122], pool, combos).enemies.map(c => [c.id, c.qLevel])) === JSON.stringify(all[122][1].enemies.map(c => [c.id, c.qLevel])));
ok('모든 층 적 5장, 중복 없음', all.every(([, g]) => g.enemies.length === 5 && new Set(g.enemies.map(c => c.id)).size === 5));
ok('리더 = 시트 등급, 목표 이하', all.every(([f, g]) => g.leader.grade === f.grade && g.leader.power <= f.power));
const near = all.filter(([f, g]) => g.leader.power >= f.power * 0.9).length;
ok('리더가 목표의 90% 이상인 층 ≥ 95%', near >= 333, `${near}/350`);
ok('나머지 등급 ≤ 리더 등급', all.every(([f, g]) => g.enemies.every(c => ORDER.indexOf(c.grade) <= ORDER.indexOf(f.grade))));
const inR = all.filter(([f, g]) => g.enemies.slice(1).every(c => c.power >= g.range[0] && c.power <= g.range[1])).length;
ok('나머지 4장이 범위(90~100% / 60~80%) 안인 층 ≥ 85%', inR >= 298, `${inR}/350`);
ok('레벨 반영 스탯', (() => { const e = all[100][1].leader, b = pool.find(c => c.id === e.id), m = 1 + G.lvPct(b.grade, e.qLevel) / 100; return e.HP === Math.round(b.HP * m) && e.ATK === Math.round(b.ATK * m); })());
ok('적 레벨 ≤ 최대 레벨 + EX', all.every(([, g]) => g.enemies.every(c => c.qLevel >= 1 && c.qLevel <= G.capOf(c.grade))));
const bond = all.filter(([f]) => f.bond), withCombo = bond.filter(([, g]) => g.combo);
ok('인연 층은 조합 포함', withCombo.length === bond.length, `${withCombo.length}/${bond.length}`);
ok('조합 멤버가 실제로 다 들어감', withCombo.every(([, g]) => combos.find(c => c.name === g.combo).cards.every(id => g.enemies.some(e => String(e.id) === String(id)))));
ok('인연 x 층은 조합 표시 없음', all.filter(([f]) => !f.bond).every(([, g]) => !g.combo));
ok('수동 고정 적 (덮어쓰기)', (() => { const g = G.generate(cfg, { floor: 3, grade: 'NORMAL', power: 800, others: 'same', enemies: [{ id: '1000000001', level: 5 }, { id: '1000000002' }] }, pool, combos); return g.manual && g.enemies.length === 2 && g.enemies[0].qLevel === 5; })());
// 4) AI: 진영 없는 전투에서 진영 전용 스킬 안 씀
{
  const C = id => pool.find(c => String(c.id) === id), mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
  const run = noBase => { const a = { name: 'A', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9, noBase }, b = { name: 'B', field: [], hand: [], deck: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 9, noBase };
    initPlayers(a, b); TURN.p = a; const u = placeUnit(a, C('2000300083'), mk); placeUnit(b, C('1000100012'), mk); u.level = 10; u.mp = u.maxMp; u.canAttack = true; refreshAll(a);
    return aiPickSkill(u)?.name; };
  const cnt = nb => Array.from({ length: 200 }, () => run(nb)).filter(n => n === 'Fatal Temptation').length;
  const withBase = cnt(false), noBase = cnt(true);
  ok('진영 있음: Fatal Temptation 사용함', withBase > 0, `${withBase}/200`);
  ok('진영 없음: Fatal Temptation 안 씀', noBase === 0, `${noBase}/200`);
}
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS'); process.exit(fails ? 1 : 0);
