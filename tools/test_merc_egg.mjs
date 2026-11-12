// 용병 이스터에그(보기 전용): 0.1% 확률·판마다 한 번·엔진 행동 없음·테섭 ?egg=1 강제 — 2026-11-12
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
const g = await readFile('js/game.js', 'utf8'), core = await readFile('js/arcade-core.js', 'utf8');
const i = g.indexOf('const MERC_EGG_IDS'), j = g.indexOf('function mercEggHTML', i); assert(i > 0 && j > i);
const NPC = [{ id: '10335', name: '장서현', grade: 'MYTHIC RARE' }, { id: '10334', name: '장서아', grade: 'LEGENDARY RARE' }];
const c = vm.createContext({ NPC, crypto: globalThis.crypto, URLSearchParams, location: { search: '' }, window: {} });
vm.runInContext(g.slice(i, j) + ';this.pick=mercEggPick;this.forced=mercEggForced', c);
// 확률: 0.001 미만만 당첨, 판(S)마다 한 번만 굴림
let n = 0; const seq = v => () => v;
assert.equal(c.pick({}, { rand: seq(0.0011) }), null);
const b1 = {}; assert.equal(c.pick(b1, { rand: seq(0.0009) }).id, '10335'); assert.equal(c.pick(b1, { rand: seq(0.9) }).id, '10335', 'same battle keeps result');
assert.equal(c.pick({}, { rand: (() => { const a = [0.0001, 0.7]; return () => a[n++ % 2]; })() }).id, '10334', '50/50 second roll');
assert.equal(c.pick({ story: {} }, { force: true }), null, 'never in story'); assert.equal(c.pick({ at: {} }, { force: true }), null, 'never in tutorial');
let hits = 0; for (let k = 0; k < 200000; k++) if (c.pick({})) hits++; assert(hits > 100 && hits < 320, `~0.1% (${hits}/200000)`);
// 강제: 테섭 + ?egg=1 일 때만
c.location.search = '?egg=1'; assert.equal(c.forced(), false, 'not staging → off'); c.window.VRCloud = { isStaging: true }; assert.equal(c.forced(), true);
c.location.search = '?egg=0'; assert.equal(c.forced(), false);
// 고용 불가·엔진 무관: 버튼 disabled, data-merc 없음, 엔진(arcade-core)에 이스터에그 흔적 없음
const html = g.slice(g.indexOf('function mercEggHTML'), g.indexOf('function renderMerc'));
assert.match(html, /<button type="button" disabled/); assert.doesNotMatch(html, /data-merc/);
assert.doesNotMatch(core, /MERC_EGG|10334|10335/);
assert.match(g, /\}\)\.join\(''\) \+ \(egg \? mercEggHTML\(egg\) : ''\)/, 'ghost card appended after the real 3 offers');
assert.match(g, /playVoiceKey\(`\$\{e\.currentTarget\.dataset\.egg\}_0`\)/, 'tap plays _0 via normal voice path');
console.log(`Merc easter egg: look-only 4th card, ${hits}/200000 ≈0.1%, once per battle, staging ?egg=1 force, no engine action OK`);
