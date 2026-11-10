// UI regression without a browser: execute the actual field-render callback,
// end-turn handler and cardHTML against a tiny DOM stub. Engine-only tests miss
// render exceptions that abort endTurn() before startTurn('ai').
// node tools/test_battle_render.mjs [optional js/game.js source path]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { RULES, ELEMENTS, ITEMS, SKILLS, parseCSV, makeUnit, endTurnXp } from '../js/rules.js';
import { setSkillData, setEmitter, initPlayers, placeUnit, turnEnd, refreshAll, skillsOf } from '../js/skills.js';

const source = fs.readFileSync(process.argv[2] || 'js/game.js', 'utf8');
const section = (from, to) => {
  const start = source.indexOf(from), end = source.indexOf(to, start);
  assert(start >= 0 && end > start, `source markers: ${from}`);
  return source.slice(start, end);
};
const fieldLoop = section('    S[who].field.forEach(u => {', '    const oldOrder =');
const cardHTML = section('function cardHTML(', '// ===== DOM 차이');
const endTurn = section('function endTurn() {', '// ===== 엔딩');
const requestEndTurn = section('function requestEndTurn() {', "$('attack-all').onclick");
setEmitter(() => {});
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv', 'utf8'));
const card = cards.find(c => c.name === '김백중');
assert(card);

class Element {
  dataset = {}; className = ''; innerHTML = ''; children = []; checked = false;
  appendChild(el) { this.children.push(el); }
}
function harness({ mine = true, foe = true, ready = true, story = false, guard = false } = {}) {
  const player = name => ({ name, field: [], deck: [], hand: [], mana: 99, hp: 3000, maxHp: 3000, turnsTaken: 3 });
  const me = player('me'), ai = player('ai');
  initPlayers(me, ai, me);
  for (const [p, include] of [[me, mine], [ai, foe]]) if (include) {
    const u = placeUnit(p, card, makeUnit);
    // One deterministic available/unavailable skill for the presentation test.
    u.sk = [{ name: 'test', mode: 'active', ready }];
    u.canAttack = true;
    if (guard) { u.guard = true; u.undying = true; }
  }
  const nodes = new Map(), getNode = id => { if (!nodes.has(id)) nodes.set(id, new Element()); return nodes.get(id); };
  const ctx = vm.createContext({
    S: { me, ai, turn: 'me', totalTurns: 1, myTurns: 1, over: false, busy: false, story: story ? {} : null },
    selected: null, RULES, ELEMENTS, ITEMS, SKILLS, endTurnXp, turnEnd,
    document: { createElement: () => new Element() },
    window: { VRCosmo: { borderId: () => null } },
    $: getNode, CONFIRM_KEY: 'confirm', localStorage: { getItem: () => null, setItem: () => {} },
    modal: null, showModal: id => { ctx.modal = id; }, hideModal: () => { ctx.modal = null; },
    idleUnits: () => me.field.filter(u => u.canAttack),
    rarityOf: () => ({ cls: 'rar-sr', short: 'SR', label: '슈퍼 레어' }),
    skillsOf, skillState: (u, s) => ({ ok: s.ready }),
    statusClasses: () => '', statusIcons: () => [], statusDecor: () => '',
    cardThumb: id => `img/thumb/${id}.webp`, ic: () => '', icOf: () => '', fmt: String,
    BFX: () => false, hpPrev: new Map(), sameCheck: () => {},
    guardWait: () => 0, guardSwapPool: () => [], baseHpBar: () => '<div class="base-hp"></div>',
    checkEnd: () => false, checkTimeout: () => false,
    startTurn: who => { ctx.S.turn = who; ctx.S.totalTurns++; },
  });
  vm.runInContext(cardHTML + endTurn + requestEndTurn + `
    function renderField(who) {
      const p = S[who], box = new ElementStub(), bossBox = new ElementStub();
      const nb = new ElementStub(), nbb = new ElementStub(), binds = [];
      const myTurn = S.turn === 'me' && !S.over && !S.busy, atkSel = null, tg = { units: [] };
      ${fieldLoop}
      return { units: nb.children, bosses: nbb.children };
    }
    function render() { rendered = { me: renderField('me'), ai: renderField('ai') }; }
  `, Object.assign(ctx, { ElementStub: Element, rendered: null }));
  return ctx;
}

let checks = 0;
const test = (name, run) => { run(); console.log(`PASS ${name}`); checks++; };
for (const story of [false, true]) for (const scenario of [
  { mine: true, foe: false }, { mine: false, foe: true }, { mine: true, foe: true },
  { mine: true, foe: true, guard: true }, { mine: false, foe: false },
]) test(`${story ? 'story' : 'arcade'} end turn ${JSON.stringify(scenario)}`, () => {
  const h = harness({ ...scenario, story });
  vm.runInContext('endTurn()', h);
  assert.equal(h.S.turn, 'ai');
  assert.equal(h.S.totalTurns, 2);
  assert(h.rendered);
});
for (const ready of [true, false]) test(`skill readiness ${ready}: own glow and badge only`, () => {
  const h = harness({ ready }); vm.runInContext('render()', h);
  const own = h.rendered.me.units[0], foe = h.rendered.ai.units[0];
  assert.equal(own.className.includes('sk-ready'), ready);
  assert.equal(own.__h.includes('sk-ready-badge'), ready);
  assert(!foe.className.includes('sk-ready'));
  assert(!foe.__h.includes('sk-ready-badge'));
});
test('confirmation -> cancel leaves turn unchanged -> confirm advances', () => {
  const h = harness(); h.$('end-turn').onclick();
  assert.equal(h.modal, 'endturn-confirm'); assert.equal(h.S.turn, 'me');
  h.$('endturn-cancel').onclick(); assert.equal(h.modal, null); assert.equal(h.S.turn, 'me');
  h.$('end-turn').onclick(); h.$('endturn-ok').onclick();
  assert.equal(h.modal, null); assert.equal(h.S.turn, 'ai');
});
for (const target of ['end_turn', '#end-turn']) test(`guided ${target} skips confirmation without changing preference`, () => {
  const h = harness({ story: true });
  h.window.VRTutorial = { active: { target, wait: 'tap_target' } };
  h.localStorage.setItem = () => assert.fail('guided turn must not change confirmation preference');
  h.$('end-turn').onclick(); assert.equal(h.S.turn, 'ai'); assert.equal(h.modal, null);
});
test('unrelated tutorial target retains confirmation', () => {
  const h = harness({ story: true });
  h.window.VRTutorial = { active: { target: 'enemy_card:0' } };
  h.$('end-turn').onclick(); assert.equal(h.modal, 'endturn-confirm'); assert.equal(h.S.turn, 'me');
});
test('exhausted cards skip confirmation and advance', () => {
  const h = harness(); h.S.me.field.forEach(u => { u.canAttack = false; });
  h.$('end-turn').onclick(); assert.equal(h.S.turn, 'ai'); assert.equal(h.modal, null);
});
test('busy and enemy turns do not advance', () => {
  const h = harness(); h.S.busy = true; h.$('end-turn').onclick(); assert.equal(h.S.turn, 'me');
  h.S.busy = false; h.S.turn = 'ai'; h.$('end-turn').onclick(); assert.equal(h.S.totalTurns, 1);
});
test('stagger expiry, XP and render complete before passing the turn', () => {
  const h = harness({ guard: true }); const u = h.S.me.field[0];
  u.st.stagger = { kind: 'stagger', atk: -.2, def: -.2, t: 1 }; refreshAll(h.S.me);
  vm.runInContext('endTurn()', h);
  assert(!u.st.stagger); assert.equal(u.xp, RULES.TURN_END_XP); assert.equal(h.S.turn, 'ai');
});
test('card border remains decorative; every equipped cosmetic stays supported', () => {
  const h = harness(); h.card = card;
  for (const id of ['border_alley', 'border_antnest', 'border_rift']) {
    h.window.VRCosmo.borderId = () => id;
    assert(vm.runInContext('cardHTML(card, { mine: true })', h).includes(`${id}.webp`));
    assert(!vm.runInContext('cardHTML(card)', h).includes('cosmo-bdr'));
  }
  h.window.VRCosmo.borderId = () => null;
  assert(!vm.runInContext('cardHTML(card, { mine: true })', h).includes('cosmo-bdr'));
  const css = fs.readFileSync('css/battle-polish.css', 'utf8');
  assert.match(css, /#game \.card-frame\s*\{[^}]*isolation:\s*isolate/);
  assert.match(css, /#game \.card-frame > \.cosmo-bdr\s*\{[^}]*mix-blend-mode:\s*screen/);
  assert.match(css, /html\.ios #game \.card-frame > \.cosmo-bdr\s*\{display:none\}/);
});
test('field drag lands on the card under the pointer, including a move to the left', () => {
  const h = harness();
  vm.runInContext(section('function fieldDropTo(', 'function moveFieldCard('), h);
  const rects = [{ left: 0, right: 80, width: 80 }, { left: 90, right: 170, width: 80 }, { left: 180, right: 260, width: 80 }];
  assert.equal(h.fieldDropTo(rects, 1, 40), 0);
  assert.equal(h.fieldDropTo(rects, 0, 130), 1);
  assert.equal(h.fieldDropTo(rects, 0, 400), 2);
  assert.equal(h.fieldDropTo(rects, 0, 175), 1);
  assert.equal(h.fieldDropTo(rects, 2, -10), 0);
});
console.log(`${checks} battle presentation regressions passed`);
