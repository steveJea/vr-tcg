// 아케이드 패 섞기 썸네일 우선: 새 카드 썸네일이 다 뜰 때까지 큰 미디어(초상화·스킬 그림·보이스)를 미룸 (최대 1.2초) — 2026-11-12
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
const g = await readFile('js/game.js', 'utf8');
const i = g.indexOf('const thumbWarmed ='), j = g.indexOf('// 상세 창 초상화:', i); assert(i > 0 && j > i);
const made = [], fx = [], sk = [], timers = [];
class Image { constructor() { this.onload = null; this.onerror = null; made.push(this); } }
const S = { me: { hand: [{ id: 1 }, { id: 2 }], field: [], deck: [] }, ai: { hand: [], field: [], deck: [] } };
const c = vm.createContext({ Image, S, cardThumb: id => `img/thumb/${id}.webp`, preloadFx: cs => fx.push([...cs].map(x => x.id)), preloadSkillVoice: cs => sk.push([...cs].map(x => x.id)), setTimeout: f => { timers.push(f); return timers.length; }, clearTimeout() {} });
vm.runInContext(g.slice(i, j), c);
c.primeBattleMedia();
assert.equal(made.length, 2); assert(made.every(x => x.fetchPriority === 'high'));
assert.equal(fx.length, 0, 'heavy media waits for thumbs'); assert.equal(timers.length, 1, '1.2s safety timer');
made[0].onload(); assert.equal(fx.length, 0, 'still one thumb pending');
made[1].onerror(); assert.deepEqual(fx[0], [1, 2], 'heavy starts once thumbs settle'); assert.deepEqual(sk[0], [1, 2], 'hand skill voices after thumbs');
c.primeBattleMedia(); assert.equal(fx.length, 2, 'known thumbs → immediate like before');
S.me.hand = [{ id: 3 }]; c.primeBattleMedia(); assert.equal(fx.length, 2); timers.at(-1)(); assert.deepEqual(fx[2], [3], 'safety timer flushes slow thumbs');
assert.match(g, /im\.fetchPriority = 'low'; im\.src = portraitFull\(id\)/, 'portrait prefetch low priority');
assert.match(g, /img\.fetchPriority = 'low'; img\.src = `data\/fx\/\$\{s\.fx\}`/, 'skill fx prefetch low priority');
console.log('Thumbs first: new hand thumbs load before portraits/skill art/voices (≤1.2s wait), low priority for big prefetch OK');
