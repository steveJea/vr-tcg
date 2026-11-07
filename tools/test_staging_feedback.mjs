// Offline VM contract tests for the owner's five staging screenshots. No login/network.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const read = path => fs.readFileSync(path, 'utf8');
const section = (src, from, to) => {
  const start = src.indexOf(from), end = src.indexOf(to, start);
  assert(start >= 0 && end > start, `missing markers: ${from}`);
  return src.slice(start, end);
};
const game = read('js/game.js'), story = read('js/story.js');

// #1: execute real media height/lifecycle code with desktop/mobile viewport fixtures.
{
  const nodes = [], events = new Map(), viewportEvents = new Map(); let boxTop = 400;
  const classes = () => ({ add() {}, remove() {} });
  const box = { getBoundingClientRect: () => ({ top: boxTop }) };
  const document = {
    body: { classList: classes(), appendChild: el => nodes.push(el) },
    createElement: () => ({ style: {}, classList: classes(), setAttribute() {}, remove() {}, querySelector: () => ({}) }),
    querySelector: () => box, getElementById: () => null,
  };
  let observer;
  const ctx = vm.createContext({ document, innerHeight: 900, esc: String,
    window: { visualViewport: { height: 600, addEventListener: (n, f) => viewportEvents.set(n, f), removeEventListener: n => viewportEvents.delete(n) } },
    ResizeObserver: class { constructor(f) { this.callback = f; observer = this; } observe(el) { this.el = el; } disconnect() { this.el = null; } },
    addEventListener: (n, f) => events.set(n, f), removeEventListener: n => events.delete(n),
    requestAnimationFrame: f => f(), setTimeout: f => f(), zoom() {},
  });
  vm.runInContext(section(story, '  function storyMedia() {', '  function storyCutin(') + ';globalThis.media = storyMedia(); media.set("image", "fixture.webp");', ctx);
  const panel = nodes[0];
  assert.equal(panel.style.height, '388px');
  assert.equal(observer.el, box);
  for (const [height, top, expected] of [[390, 260, 248], [240, 50, 38], [240, -10, 0], [600, 900, 588]]) {
    ctx.window.visualViewport.height = height; boxTop = top; viewportEvents.get('resize')();
    assert.equal(panel.style.height, `${expected}px`);
  }
  ctx.window.visualViewport.height = 600; boxTop = 300; observer.callback();
  assert.equal(panel.style.height, '288px');
  ctx.media.dispose(); assert.equal(events.size, 0); assert.equal(viewportEvents.size, 0); assert.equal(observer.el, null);
  const css = read('css/story.css');
  assert.match(css, /\.story-media img, \.story-media video\s*\{[^}]*object-fit: contain/);
  assert(!css.includes('storyKenBurns'), 'no animated zoom recropping the fitted image');
  assert.match(css, /#story-screen \.story-dlg \{[^}]*height: calc\(100dvh/);
}

// #2: automatic turn end must yield to the guide; only guided end-turn bypasses confirm.
{
  const ctx = vm.createContext({ window: {}, S: { story: {}, turn: 'me', meActed: true }, autoActive: () => false, canStillAct: () => false });
  vm.runInContext(section(game, 'function autoEndReady() {', 'function maybeAutoEndTurn()'), ctx);
  assert.equal(ctx.autoEndReady(), true);
  ctx.window.VRTutorial = { active: { target: 'end_turn' } };
  assert.equal(ctx.autoEndReady(), false);
  ctx.window.VRTutorial.active = null; assert.equal(ctx.autoEndReady(), true);
  ctx.S.story = null; assert.equal(ctx.autoEndReady(), false);
  const tut = vm.createContext({ window: {}, URLSearchParams, location: { search: '' } });
  vm.runInContext(read('js/tutorial.js') + ';T = { id: "fixture", i: 0, def: { steps: [{ target: "end_turn", wait: "tap_target" }] } };', tut);
  assert.equal(tut.window.VRTutorial.active.target, 'end_turn');
}

// #3: results hide GNB even though game itself is already hidden; map restores navigation.
{
  let result = true;
  const hidden = { classList: { contains: () => true } };
  const ctx = vm.createContext({ window: {}, $: () => hidden, vis: el => el && !el.classList.contains('hidden'),
    document: { querySelector: selector => result && selector.includes('#story-screen:not(.hidden) .story-battle-result') ? {} : null },
  });
  const gnb = read('js/gnb.js');
  vm.runInContext(section(gnb, '  const busy = ', '  const active = ') + ';globalThis.busy = busy;', ctx);
  assert.equal(ctx.busy(), true); result = false; assert.equal(ctx.busy(), false);
  assert.equal((story.match(/show\(`<div class="story-battle-result /g) || []).length, 3, 'victory, defeat and result-save error');
  assert(story.includes('window.VRGnb?.paint?.(); window.VRTnb?.paint?.();'), 'synchronously update navigation before measuring dialogue');
}

// #4: eliminate the old BFX-only shrink while preserving viewport-based base cut-in rules.
assert(!/max-height:\s*40vh|height:\s*min\(32vh/.test(read('css/battle-fx3.css')));
assert.match(read('index.html'), /max-height: 70dvh/);
assert.match(read('index.html'), /height: min\(62dvh, 125vw\)/);

// #5: execute the actual idle-box UI, RPC routing and paid confirmation handlers.
{
  const calls = [], confirmations = [], nodes = []; let allow = false, hold = null;
  const status = { ok: true, level: 2, hours: 1, max_hours: 8, ready: true, pending: { gold: 440 }, rate: { gold: 440 }, boost: { left: 2, max: 2, cost: 30, hours: 4, reward: { gold: 1760 } } };
  class Node {
    children = new Map(); isConnected = true;
    set innerHTML(v) { this.html = v; this.children.clear(); }
    get innerHTML() { return this.html; }
    querySelector(q) { if (!this.children.has(q)) this.children.set(q, { disabled: false, addEventListener: function (name, f) { this[name] = f; } }); return this.children.get(q); }
    remove() { this.isConnected = false; }
  }
  const window = { VRCloud: { user: { id: 'fixture' }, sb: { rpc: async name => { calls.push(name); if (hold) await hold; return { data: status, error: null }; } } },
    VRAsk: async msg => { confirmations.push(msg); return allow; } };
  const ctx = vm.createContext({ window, document: { createElement: () => new Node(), querySelector: () => null, querySelectorAll: () => [], body: { appendChild: el => nodes.push(el) } },
    console, setTimeout: () => 0, MutationObserver: class { observe() {} },
  });
  vm.runInContext(read('js/idle-box.js'), ctx);
  await window.VRIdleBox.status(); window.VRIdleBox.open(); await new Promise(r => setImmediate(r));
  const pop = nodes[0];
  assert(pop.innerHTML.includes('쌓인 보상 받기 (무료)'));
  assert(pop.innerHTML.includes('심연석 30개로 4시간분 받기'));
  calls.length = 0;
  const click = async q => { const b = pop.querySelector(q); await b.click({ currentTarget: b }); };
  await click('[data-claim]'); assert.deepEqual(calls, ['idle_box_claim']); assert.equal(confirmations.length, 0);
  calls.length = 0; await click('[data-boost]'); assert.equal(calls.length, 0, 'cancel never spends');
  assert(confirmations[0].includes('심연석 30개를 사용'));
  allow = true; await click('[data-boost]'); assert.deepEqual(calls, ['idle_box_boost']);
  calls.length = 0; let release; hold = new Promise(r => { release = r; });
  const pending = click('[data-claim]'); await click('[data-claim]');
  assert.deepEqual(calls, ['idle_box_claim'], 'in-flight duplicate action is ignored');
  release(); await pending; hold = null;
  calls.length = 0; pop.isConnected = false; await click('[data-boost]'); assert.equal(calls.length, 0, 'leaving during confirmation never spends');
}
console.log('Staging feedback: viewport/lifecycle, guided turns, result GNB, cut-in size, idle free/paid confirmation: OK');
