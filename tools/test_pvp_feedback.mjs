// Owner feedback regressions: execute the actual controls/video/view-stepper
// against a minimal DOM. No network, database credentials or browser session.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { batchAttackReady, nextBatchAttack } from '../js/battle-view-controls.js';
import { parseCSV, setCardPool, attackTargets } from '../js/rules.js';
import { setSkillData } from '../js/skills.js';
import { snapCard, manualMatch, MODES } from '../js/pvp-core.js';
import { verifyBattle } from '../supabase/functions/_shared/pvp-engine-v3.mjs';
const game = fs.readFileSync('js/game.js', 'utf8'), pvp = fs.readFileSync('js/pvp.js', 'utf8');
function section(src, from, to) { const a = src.indexOf(from), b = src.indexOf(to, a); assert(a >= 0 && b > a, from); return src.slice(a, b); }
const pool = parseCSV(fs.readFileSync('data/cards.csv', 'utf8'));
setCardPool(pool); setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const byId = id => pool.find(c => String(c.id) === String(id));
const hr = pool.filter(c => ['NORMAL', 'RARE', 'HIGH RARE'].includes(c.grade));
const strong = hr.slice().sort((a, b) => b.ATK - a.ATK).slice(0, 6);
const weak = hr.filter(c => c.grade === 'NORMAL').sort((a, b) => a.ATK - b.ATK).slice(0, 2);
const toCards = deck => deck.map(o => snapCard(o, byId));
const fixture = { mode: 'boss', control: 'actions', seed: 37,
  me: [strong.map(c => ({ id: String(c.id), level: 70 }))],
  opp: [weak.map(c => ({ id: String(c.id), level: 1 }))] };

// Actual rules + sentinel wiring. A legal base target must NOT be discarded.
{
  const st = manualMatch(toCards(fixture.me[0]), toCards(fixture.opp[0]), fixture.seed, null, { boss: true, view: true });
  const x = st.next().value, { A, B, A0, B0 } = x;
  const member = A0[1], foe = B0[1]; member.canAttack = true; B.field = [B0[0]];
  for (const t of [1, 2]) { A.turnsTaken = t; assert.equal(batchAttackReady(A, B), false); assert.equal(nextBatchAttack({ batch: [member], A0, B0 }, A, B), null); }
  A.turnsTaken = 3; assert(batchAttackReady(A, B));
  assert.deepEqual(nextBatchAttack({ batch: [member], A0, B0 }, A, B), { k: 'atk', i: 1, t: -1 });
  B.field.push(foe); member.st.provoked = { by: foe };
  assert.equal(attackTargets(A, B, member).hero, false);
  assert.deepEqual(nextBatchAttack({ batch: [member], A0, B0 }, A, B), { k: 'atk', i: 1, t: 1 });
  member.canAttack = false; assert.equal(nextBatchAttack({ batch: [member], A0, B0 }, A, B), null);
}
console.log('PASS first-two-turn disable, base sentinel -1, provocation and exhausted-card targeting');

// Real selection filtering/sorting, including inclusive/zero caps and Korean names.
{
  const ctx = vm.createContext({ localStorage: { getItem: () => null }, card: byId, owned: [] });
  vm.runInContext(section(pvp, 'const PSORTS =', 'const sortChips =').replaceAll('export ', ''), ctx);
  const list = [{ uid: 'a', id: '1', power: 2, level: 1 }, { uid: 'b', id: '2', power: 3, level: 1 }, { uid: 'c', id: '3', power: 4, level: 1 }];
  const cards = { 1: { name: '김백중', cost: 0 }, 2: { name: '김후', cost: 20 }, 3: { name: 'Alice', cost: 35 } };
  const get = id => cards[id];
  assert.deepEqual(Array.from(ctx.filterPool(list, '', 20, get), o => o.uid), ['a', 'b']);
  assert.deepEqual(Array.from(ctx.filterPool(list, '', 0, get), o => o.uid), ['a']);
  assert.deepEqual(Array.from(ctx.filterPool(list, ' 김 ', '', get), o => o.uid), ['a', 'b']);
  assert.deepEqual(Array.from(ctx.filterPool(list, 'ALICE', '', get), o => o.uid), ['c']);
  assert.deepEqual(Array.from(ctx.filterPool(list, '김', 1, get), o => o.uid), ['a']);
  assert.equal(ctx.filterPool(list, '없는이름', '', get).length, 0);
  for (const desc of [false, true]) assert.deepEqual(Array.from(ctx.sortPool(list, get, list, { k: 'cost', desc }), o => o.uid), desc ? ['c', 'b', 'a'] : ['a', 'b', 'c']);
  assert.equal(list[0].uid, 'a', 'sorting cannot mutate selection order');
  assert(pvp.includes('input.oncompositionend = apply') && pvp.includes('!e.isComposing'), 'Korean IME must not be torn down mid-composition');
}
console.log('PASS cost sort, <=N filter, name search, zero/empty/combined filters, IME-safe wiring');

const tick = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
// Run the actual active/passive MR queue with controllable media and clock.
{
  let now = 0, tid = 0, maxShown = 0, missing = false;
  const timers = new Map(), videos = [], shown = new Set(), voices = [];
  const later = (fn, ms) => { timers.set(++tid, { fn, at: now + ms }); return tid; };
  const advance = async ms => { now += ms; for (const [id, t] of [...timers]) if (t.at <= now) { timers.delete(id); t.fn(); } await tick(); };
  class Node {
    handlers = {}; children = []; setAttribute() {} prepend(v) { this.children.unshift(v); }
    addEventListener(k, fn) { this.handlers[k] = fn; } remove() { shown.delete(this); }
  }
  class Video extends Node {
    duration = 60; currentTime = 0; pause() {} play() { this.onplaying?.(); return Promise.resolve(); }
    load() { queueMicrotask(() => missing ? this.onerror?.() : this.oncanplay?.()); }
  }
  const skills = [{ name: 'active' }, { name: 'passive' }];
  const make = id => ({ uid: id, card: { id, grade: 'MYTHIC RARE' }, sk: skills });
  const ctx = vm.createContext({
    S: { view: { skip: false }, fxSeen: new Set() }, FX_OFF: () => false, SWEEPING: () => false, skillsOf: () => skills,
    escHtml: String, playVoice: u => voices.push(u.uid), passiveCutInPlain: () => {},
    setTimeout: later, clearTimeout: id => timers.delete(id), window: { setTimeout: later },
    document: { createElement: tag => { const el = tag === 'video' ? new Video() : new Node(); if (tag === 'video') videos.push(el); return el; },
      body: { appendChild: el => { shown.add(el); maxShown = Math.max(maxShown, shown.size); } } },
  });
  vm.runInContext("let vidGate = Promise.resolve(), mrCancel = null; const vidWait = () => vidGate;" + section(game, 'function mrVideo(', 'async function castSkill(') + section(game, 'function passiveCutIn(', 'async function passiveCutInPlain('), ctx);
  const [a, b, c] = [make(1), make(2), make(3)];
  ctx.passiveCutIn(a, 'passive'); const active = ctx.mrVideo(b, skills[0]), next = ctx.mrVideo(c, skills[0]);
  await tick(); assert.equal(videos.length, 1); assert.equal(shown.size, 1);
  // Healthy playback beyond both old 15s/30s cutoffs must not advance the queue.
  for (let i = 0; i < 40; i++) { videos[0].currentTime++; videos[0].ontimeupdate(); await advance(1000); }
  assert.equal(videos.length, 1); assert.deepEqual(voices, [1]);
  videos[0].onended(); await tick(); assert.equal(videos.length, 2); assert.equal(shown.size, 1);
  [...shown][0].handlers.pointerdown({ preventDefault() {}, stopPropagation() {} });
  assert.equal(await active, true); await tick(); assert.equal(videos.length, 3);
  videos[2].onended(); assert.equal(await next, true); await vm.runInContext('vidWait()', ctx);
  assert.equal(maxShown, 1); assert.equal(shown.size, 0); assert.equal(timers.size, 0);
  assert.equal(await ctx.mrVideo(a, skills[1]), false, 'first-use-only behavior retained');
  missing = true; assert.equal(await ctx.mrVideo(make(4), skills[0]), false); missing = false;
  const canceled = ctx.mrVideo(make(5), skills[0]), skipped = ctx.mrVideo(make(6), skills[0]); await tick();
  ctx.S.view.skip = true; vm.runInContext('mrCancel?.()', ctx); await canceled; assert.equal(await skipped, false); assert.equal(shown.size, 0);
  ctx.S.view.skip = false; const stalled = ctx.mrVideo(make(7), skills[0]); await tick(); await advance(15001); assert.equal(await stalled, true);
  const before = videos.length;
  ctx.S.story = { chapter: 0 };
  assert.equal(await ctx.mrVideo(make('10326'), skills[0]), false, 'story 10326 uses image cut-in');
  assert.equal(videos.length, before, 'story 10326 does not open an MR video');
  ctx.S.story = { quest: true };
  const tower = ctx.mrVideo(make('10326'), skills[0]); await tick();
  assert.equal(videos.length, before + 1, 'tower still plays 10326 MR video');
  videos.at(-1).onended(); assert.equal(await tower, true);
  ctx.S.story = { view: true };
  const viewed = ctx.mrVideo(make('10326'), skills[0]); await tick();
  assert.equal(videos.length, before + 2, 'view battles still play 10326 MR video');
  videos.at(-1).onended(); assert.equal(await viewed, true);
  ctx.S.story = null;
  const arcade = ctx.mrVideo(make('10326'), skills[0]); await tick();
  assert.equal(videos.length, before + 3, 'arcade still plays 10326 MR video');
  videos.at(-1).onended(); assert.equal(await arcade, true);
}
console.log('PASS shared passive/active MR queue, 40s full playback, ended/tap/SKIP, first-use, missing/stalled-media recovery');

// Minimal DOM for running the real async view stepper and rendering result HTML.
class Node {
  style = {}; dataset = {}; parentElement = this; textContent = ''; innerHTML = ''; scrollTop = 0;
  classes = new Set(); classList = { add: (...s) => s.forEach(x => this.classes.add(x)), remove: (...s) => s.forEach(x => this.classes.delete(x)), contains: s => this.classes.has(s), toggle: (s, on) => on ? this.classes.add(s) : this.classes.delete(s) };
  before() {} remove() {} addEventListener() {} querySelector() { return new Node(); } setAttribute() {}
}
async function runView({ auto = false, stall = false, skip = false } = {}) {
  const st = manualMatch(toCards(fixture.me[0]), toCards(fixture.opp[0]), fixture.seed, null, { boss: true, view: true, manual: true });
  const nodes = new Map(), get = id => { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id); };
  let calls = 0, last, waits = 0, release, stateBeforeFinish;
  const gate = new Promise(res => { release = res; });
  const base = { me: { base: 'me' }, ai: { base: 'ai' } }, lunges = [], focuses = [], logs = [];
  const session = { events: st.events, next: inp => { calls++; const x = st.next(inp); if (!x.done) last = x.value; return x; } };
  const ctx = vm.createContext({
    session, S: null, selected: null, fastForward: false, mrCancel: null, fxQueue: [], vidGate: Promise.resolve(), hpPrev: new Map(),
    window: { TCG_FAST: true }, document: { querySelectorAll: () => [], createElement: () => new Node(), body: { appendChild() {} } },
    $: get, IMG: '', fmt: String, fitBoardSoon() {}, setBattleBg() {}, preloadHit() {}, preloadFx() {}, turnScroll() {},
    floatText() {}, TUT() {}, log: s => logs.push(s), sleep: async () => {}, fxMs: () => 0, AI_DELAY: () => 0,
    vidWait: () => { waits++; return stall && waits === 1 ? gate : Promise.resolve(); }, passiveWait: async () => {},
    mrVideo: async () => false, cutIn: async () => {}, onEngine() {}, reportError: (where, err) => { throw err; },
    heroEl: who => base[who], unitEl: (who, unit) => ({ who, unit }), whoOf: p => p === ctx.S.me ? 'me' : 'ai',
    peekBefore: async el => { assert(el); focuses.push(el); }, playSe() {},
    lunge: async (el, target) => { assert(el); assert(target, 'base attacks must have a lunge target'); lunges.push(target); return { back: async () => {} }; },
    withTimeout: async p => p, pendingDying: [], shake() {}, hitFx() {}, dmgNumber() {}, critSet: new Set(), elemFx() {}, critNum() {}, resetAnim() {}, fadeDying: async () => {}, dockStoryBuff() {}, clearInterval() {},
    nextBatchAttack,
    render: () => {
      if (!ctx.S) return;
      if (ctx.S.over) stateBeforeFinish = { a: ctx.S.me.hp, b: ctx.S.ai.hp, guardAlive: ctx.S.ai.field.some(u => u.guard && u.hp > 0) };
      queueMicrotask(() => {
        const v = ctx.S?.view; if (!v?.ask) return;
        if (skip) { get('skip').noop = true; v.skip = true; v.auto = true; v.ask({ k: 'auto' }); return; }
        if (!batchAttackReady(ctx.S.me, ctx.S.ai)) v.ask({ k: 'end' });
        else { v.batch = ctx.S.me.field.filter(u => u.canAttack && u.hp > 0); v.nextBatch(); }
      });
    },
  });
  vm.runInContext(section(game, 'async function viewBattle0(', 'window.TCG ='), ctx);
  const pending = ctx.viewBattle0({ session, manual: true, auto });
  if (stall) { await tick(); assert.equal(waits, 1); assert.equal(calls, 1, 'the engine must stop stepping while a queued video is playing'); release(); }
  const result = await pending;
  const verified = verifyBattle(fixture, [st.acts]);
  assert.deepEqual(result, verified.rounds[0], 'actual view transcript must replay identically in the unchanged Edge engine');
  assert(logs.includes('⚔️ 상대 진영 HP를 0으로 만들면 승리'));
  assert(!logs.some(s => /상대를 모두 쓰러뜨리면/.test(s)), 'boss UI cannot claim a wipe victory');
  assert.equal(ctx.S, null, 'view cleanup');
  return { result, acts: st.acts, lunges, focuses, last, stateBeforeFinish };
}
const manual = await runView({ stall: true });
assert(manual.acts.some(a => a.k === 'atk' && a.t === -1), 'batch must record an actual base attack');
assert(manual.lunges.some(t => t.base === 'ai')); assert(manual.focuses.some(t => t.base === 'ai'));
assert(manual.result.win && manual.stateBeforeFinish.b <= 0 && manual.stateBeforeFinish.guardAlive,
  'a boss WIN destroys base HP, not the immortal guard portrait');
await runView({ auto: true }); await runView({ skip: true });
console.log(`PASS real view stepper: batch base attack lunge/focus, video wait, AUTO/SKIP, strict server replay; WIN with base HP ${manual.stateBeforeFinish.b} and living guard is intentional`);

// Rule cue, legacy completion isolation, result rows and responsive layout.
{
  assert(game.includes('첫 2턴에는 보스를 공격할 수 없어요.'));
  const ctx = vm.createContext({ S: { over: false, view: {}, ai: { hp: 0 }, me: { hp: 1 } }, finish: () => { throw Error('legacy completion must not run'); } });
  vm.runInContext(section(game, 'function checkEnd() {', '/** 챕터 0 P3:'), ctx); assert.equal(ctx.checkEnd(), false);
  let html = '';
  const ui = vm.createContext({ clearPendingResult: () => {}, concealLobby: () => {}, backToMatch: () => {}, rwHtml: () => '', MODES, view: { mode: 'boss' }, tierOf: () => ({}), emb: () => '', esc: String, snapThumbs: d => d.map(x => `<span class="pvp-th">${x.id}</span>`).join(''), modal: (id, body) => { html = body; return new Node(); } });
  vm.runInContext(section(pvp, 'function showResult(', '// ---- 수동:'), ui);
  const deck = Array.from({ length: 6 }, (_, i) => ({ id: i }));
  ui.showResult({ mode: 'boss', me: [deck], opp: [deck] }, { win: true, delta: 16, rounds: [{ win: true }] });
  assert(html.includes('pvp-round-boss')); assert(html.indexOf('상대 · 진영 파괴') < html.indexOf('<strong>나'));
  assert.equal((html.match(/class="pvp-th"/g) || []).length, 12);
  ui.showResult({ mode: 'boss', me: [deck], opp: [deck] }, { win: false, delta: -16, rounds: [{ win: false }] });
  assert(!html.includes('진영 파괴'), 'a defender timeout win is not a claimed attacker base destruction');
  const css = fs.readFileSync('css/pvp.css', 'utf8');
  assert(css.includes('.pvp-round-boss{display:flex;flex-direction:column'));
  assert(css.includes('grid-template-columns:repeat(6,minmax(0,1fr))'));
  assert(css.includes('minmax(88px,1fr)')); assert(css.includes('.pvp-bmode{margin-top:24px'));
}
console.log('PASS exact cue, canonical-only completion, twelve-card top/bottom results, enlarged picker and lobby spacing');
