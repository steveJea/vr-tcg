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
ok('리더 = 시트 등급', all.every(([f, g]) => g.leader.grade === f.grade));
ok('나머지 등급 ≤ 리더 등급', all.every(([f, g]) => g.enemies.every(c => ORDER.indexOf(c.grade) <= ORDER.indexOf(f.grade))));
ok('레벨 반영 스탯', (() => { const e = all[100][1].leader, b = pool.find(c => c.id === e.id), m = 1 + G.lvPct(b.grade, e.qLevel) / 100; return e.HP === Math.round(b.HP * m) && e.ATK === Math.round(b.ATK * m); })());
ok('고정 레벨: 5명 모두 5 + 5×⌊층/10⌋ (상한 무시)', all.every(([f, g]) => g.level === 5 + 5 * Math.floor(f.floor / 10) && g.enemies.every(c => c.qLevel === g.level)) && all[0][1].level === 5 && all[9][1].level === 10 && all[349][1].level === 180);
ok('levelOffset +10 (속성 탑용)', G.generate(cfg, cfg.floors[349], pool, combos, { levelOffset: 10 }).enemies.every(c => c.qLevel === 190));
{ const old = { ...cfg }; delete old.level;
  ok('카드 선택은 예전(전투력 목표 시드)과 같음', cfg.floors.every(f => JSON.stringify(G.generate(old, f, pool, combos).enemies.map(c => c.id)) === JSON.stringify(G.generate(cfg, f, pool, combos).enemies.map(c => c.id))));
  ok('level 없으면 예전 방식 (상한 이내)', cfg.floors.every(f => G.generate(old, f, pool, combos).enemies.every(c => c.qLevel >= 1 && c.qLevel <= G.capOf(c.grade)))); }
ok('Lv.180 MR 스탯 = 기본 × (1 + 6% × 179)', (() => { const e = all[349][1].leader, b = pool.find(c => c.id === e.id); return e.HP === Math.round(b.HP * (1 + G.lvPct(b.grade, 180) / 100)); })());
const bond = all.filter(([f]) => f.bond), withCombo = bond.filter(([, g]) => g.combo);
ok('인연 층은 조합 포함', withCombo.length === bond.length, `${withCombo.length}/${bond.length}`);
ok('조합 멤버가 실제로 다 들어감', withCombo.every(([, g]) => combos.find(c => c.name === g.combo).cards.every(id => g.enemies.some(e => String(e.id) === String(id)))));
ok('인연 x 층은 조합 표시 없음', all.filter(([f]) => !f.bond).every(([, g]) => !g.combo));
ok('수동 고정 적 (덮어쓰기)', (() => { const g = G.generate(cfg, { floor: 3, grade: 'NORMAL', power: 800, others: 'same', enemies: [{ id: '1000000001', level: 5 }, { id: '1000000002' }] }, pool, combos); return g.manual && g.enemies.length === 2 && g.enemies[0].qLevel === 5; })());
// 3b) 속성 탑 적 (PR-D)
{
  const npc = parseCSV(fs.readFileSync('data/npc_cards.csv', 'utf8')), T = { wind: 'WIND', ice: 'ICE', fire: 'FIRE', light: 'LIGHT', dark: 'DARK' };
  for (const [tower, cls] of Object.entries(T)) {
    const gs = cfg.floors.map(f => G.generateAttr(cfg, f, pool, { tower, cls, npc, levelOffset: 10 }));
    ok(`${tower}: 350층 · 적 5장 · 모두 ${cls}`, gs.length === 350 && gs.every(g => g.enemies.length === 5 && g.enemies.every(c => c.class === cls)));
    ok(`${tower}: Lv = 시련의 탑 + 10 (1층 15 · 10층 20 · 350층 190)`, gs.every((g, i) => g.level === 15 + 5 * Math.floor((i + 1) / 10) && g.enemies.every(c => c.qLevel === g.level)) && gs[349].level === 190);
    ok(`${tower}: 같은 층 같은 적 (시드 탑+층) · 리더 = 가장 센 카드 · 10층마다 보스`, JSON.stringify(G.generateAttr(cfg, cfg.floors[41], pool, { tower, cls, npc }).enemies.map(c => c.id)) === JSON.stringify(gs[41].enemies.map(c => c.id))
      && gs.every(g => g.leader.power === Math.max(...g.enemies.map(c => c.power))) && gs.every((g, i) => !!g.boss === ((i + 1) % 10 === 0)));
  }
  const w = cfg.floors.slice(0, 50).map(f => G.generateAttr(cfg, f, pool, { tower: 'wind', cls: 'WIND', npc }));
  ok('속성 탑마다 적이 다름 (wind vs fire 1층)', JSON.stringify(w[0].enemies.map(c => c.id)) !== JSON.stringify(G.generateAttr(cfg, cfg.floors[0], pool, { tower: 'fire', cls: 'FIRE', npc }).enemies.map(c => c.id)));
  ok('중복 카드·NPC 허용 (wind 1~50층 중 등장)', w.some(g => new Set(g.enemies.map(c => c.id)).size < 5) && w.some(g => g.enemies.some(c => npc.some(x => x.id === c.id))));
  ok('후보 3종 미만이면 등급 확장 (light·dark 1층 3종 이상 후보, 같은 카드 5장 아님)', ['light','dark'].every(t => { const g = G.generateAttr(cfg, cfg.floors[0], pool, { tower: t, cls: t.toUpperCase(), npc }); return new Set(g.enemies.map(c => c.id)).size > 1; }));
  ok('LIGHT NPC 없음 → 카드만', !npc.some(c => c.class === 'LIGHT') && cfg.floors.every(f => G.generateAttr(cfg, f, pool, { tower: 'light', cls: 'LIGHT', npc }).enemies.every(c => pool.some(x => x.id === c.id))));
}
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
