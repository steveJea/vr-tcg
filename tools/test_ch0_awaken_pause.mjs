// Regression: CH0 P3 awakening must not reach the lethal turn-start passive.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../js/game.js', import.meta.url), 'utf8');
const fn = name => {
  const start = source.indexOf(`function ${name}(`);
  return source.slice(start, source.indexOf('\n}', start) + 2);
};
const storyData = { chapters: [] };
vm.runInNewContext(readFileSync(new URL('../js/story-data-ch0.js', import.meta.url), 'utf8'), { window: { STORY_DATA: storyData } });
assert.equal(storyData.chapters[0].phases.find(p => p.no === 3).awaken.pauseOnEntrance, true);
const makeContext = () => {
  const c = {
    S: { story: { awaken: { on: 'yuri', card: { id: 'awake', name: 'Yuri' }, pauseOnEntrance: true } },
      me: { field: [] }, turn: 'ai', log: { played: new Set() }, meActed: true },
    autoOn: true, autoLocked: () => false, autoHeld: () => false,
    selected: null, fastForward: true, autoEndTimer: 1, fxQueue: [],
    makeUnit() {}, RULES: { LEVEL_MAX: 10 }, clearTimeout() {}, setTimeout() {},
    placeUnit(p, card) { const u = { card, level: 1, maxHp: 100, maxMp: 100 }; p.field.push(u); return u; },
    levelUpOnce(u) { u.level++; }, log() {}, render() {}, playSe() {}, runFxQueue() {},
    document: { createElement: () => ({ remove() {} }), body: { appendChild() {} } },
    escHtml: s => s, withTimeout: p => p, cutIn: async () => {}, TUT() {},
    turnScroll() { throw Error('turn advanced during entrance hold'); },
  };
  vm.createContext(c);
  vm.runInContext(['awakenPlayerControl', 'startTurn', 'awakenCheck', 'autoEndReady'].map(fn).join('\n') +
    '\nconst autoActive = ' + source.match(/const autoActive = ([^\n]+);/)[1] + ';', c);
  return c;
};
const c = makeContext();
vm.runInContext('awakenCheck()', c);
assert.equal(c.S.awakenPause, true);
assert.equal(c.S.busy, true);
assert.equal(c.S.autoHold, true);
assert.equal(c.S.me.field[0].mp, 100);
assert.equal(vm.runInContext('autoActive()', c), false);
assert.equal(vm.runInContext('autoEndReady()', c), false);
vm.runInContext("startTurn('me')", c); // Would fire 공허의 제왕 without the hold.
assert.equal(c.S.turn, 'me');
assert.equal(c.S.busy, true);
await c.fxQueue.shift()();
assert.equal(c.S.awakenPresenting, false);
assert.equal(c.S.busy, true, 'AI must unwind before accepting player input');
vm.runInContext('S.awakenAiPending = false; awakenPlayerControl()', c);
assert.equal(c.S.busy, false);
assert.equal(c.S.meActed, false);
assert.equal(c.S.me.field[0].canAttack, true);
assert.equal(c.S.awakenPause, true, 'presentation completion is not player input');
vm.runInContext('awakenCheck()', c);
assert.equal(c.S.me.field.length, 1, 'awakening happens once');
const normal = makeContext();
normal.S.story.awaken.pauseOnEntrance = false;
vm.runInContext('awakenCheck()', normal);
assert.equal(normal.S.awakenPause, undefined, 'other awakening configurations are unchanged');
// Two queued enemies: only the attack that defeats Yuri is allowed to resolve.
const ai = makeContext();
ai.S.ai = { field: [{ canAttack: true }, { canAttack: true }] };
ai.S.at = {};
let attacks = 0;
Object.assign(ai, {
  sleep: async () => {}, AI_DELAY: () => 0, aiScriptStep: () => null,
  vidWait: async () => {}, scrollBottom() {}, spareBlocked: () => false,
  aiPickTarget: () => null,
  attack: async () => { attacks++; vm.runInContext('awakenCheck()', ai); },
  reportError: (_, e) => { throw e; },
  endTurnXp() { throw Error('enemy turn-end ran while paused'); },
});
vm.runInContext('async ' + fn('aiTurn'), ai);
await vm.runInContext('aiTurn()', ai);
assert.equal(attacks, 1, 'remaining enemies must stop at awakening');
assert.equal(ai.S.turn, 'me');
assert.equal(ai.S.busy, true, 'entrance is still playing');
await ai.fxQueue.shift()();
assert.equal(ai.S.busy, false);
assert.equal(ai.S.awakenPause, true);
console.log('CH0 P3 awakening: entrance-only hold, no turn-start passive/AUTO/auto-end, manual control ready: OK');
