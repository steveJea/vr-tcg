// 퀘스트 모드 검증: node tools/test_quest.mjs
import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, RULES } from '../js/rules.js';
import { setSkillData, initPlayers, placeUnit, skillsOf, aiPickSkill, refreshAll, TURN } from '../js/skills.js';
await import('../js/quest-gen.js');
const G = globalThis.VRQuestGen;
const pool = parseCSV(fs.readFileSync('data/cards.csv', 'utf8')), combos = JSON.parse(fs.readFileSync('data/combos.json')), cfg = JSON.parse(fs.readFileSync('data/quest.json'));
const npc = parseCSV(fs.readFileSync('data/npc_cards.csv', 'utf8'));
const nm = id => (pool.find(c => c.id === id) || npc.find(c => c.id === id)).name;
for (const [t, cls] of [['light','LIGHT'],['dark','DARK']]) for (const fl of [0, 9]) { const g = G.generateAttr(cfg, cfg.floors[fl], pool, { tower: t, cls, npc, levelOffset: 10 }); console.log(t, fl+1, g.grade, g.enemies.map(c => nm(c.id)+'('+c.grade[0]+')').join(', ')); }
