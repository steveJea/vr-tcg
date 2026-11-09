import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';

const read = p => readFile(new URL('../' + p, import.meta.url), 'utf8');
const story = await read('js/story.js');
const css = await read('css/story.css');
const tutCss = await read('css/tutorial.css');

assert.match(story, /const ch0Last = ch\.id === 0 && !nextPh/);
assert.match(story, /const hasNext = !ch0Last &&/);
assert.match(story, /nb\.textContent = '챕터1 시작하기'/);
assert.match(story, /function beginChapter1\(\) \{ const i = CH1\(\); curCh = i; hubC = i; return renderMap\(i\); \}/);
assert.match(story, /nb\.onclick = \(\) => beginChapter1\(\)/);
assert.match(story, /markPullDone\(\); return beginChapter1\(\)/);
assert.equal(story.includes('함께할 캐릭터 고르기'), false);
assert.match(story, /story-ovp-skip on/);
assert.equal(story.includes("skip.classList.remove('on')"), false);
assert.match(css, /\.story-ovp video\s*\{[^}]*pointer-events:\s*none/);
assert.match(css, /\.story-ovp-skip\s*\{[^}]*z-index:\s*4[^}]*pointer-events:\s*auto/);
assert.match(tutCss, /\.tut-ov\.info\{pointer-events:\s*auto\}/);
assert.match(tutCss, /\.tut-ov\.info \.tut-bub\{pointer-events:\s*auto\}/);

const { window, document } = parseHTML('<!doctype html><html><body></body></html>');
const rafs = [];
const store = new Map();
const ctx = vm.createContext({
  window, document, console, performance, URLSearchParams, CustomEvent: window.CustomEvent || globalThis.CustomEvent,
  innerHeight: 800, innerWidth: 400, location: window.location,
  requestAnimationFrame: fn => { rafs.push(fn); return rafs.length; },
  cancelAnimationFrame() {},
  setTimeout, clearTimeout,
  localStorage: { getItem: k => store.has(k) ? store.get(k) : null, setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k), key: i => [...store.keys()][i], get length() { return store.size; } },
  fetch: async () => { throw Error('no fetch'); },
});
window.TCG = { S: { turn: 'me', busy: false, over: false }, closeDetail() {} };
vm.runInContext(await read('js/tutorial.js'), ctx);
const flush = () => { for (let i = 0; i < 8 && rafs.length; i++) rafs.splice(0).forEach(fn => fn()); };
const started = await window.VRTutorial.start('sheet', { force: true, def: { steps: [
  { text: '첫번째', wait: 'tap' },
  { text: '두번째', wait: 'tap' },
  { text: '세번째', wait: 'tap' },
] } });
assert.equal(started, true);
flush();
const text = () => document.querySelector('.tut-bub p').textContent;
const tap = (type, sel) => document.querySelector(sel).dispatchEvent(new window.Event(type, { bubbles: true }));
assert.equal(text(), '첫번째');
assert.equal(document.querySelector('.tut-ov').classList.contains('info'), true);
window.TCG.S.busy = true;
tap('pointerup', '.tut-bub');
assert.equal(text(), '첫번째', 'busy queues the info tap');
window.TCG.S.busy = false;
flush();
assert.equal(text(), '두번째', 'queued tap advances when the battle is free');
await new Promise(r => setTimeout(r, 50));
const cut = document.createElement('div'); cut.id = 'cutin'; cut.className = 'cutin'; document.body.append(cut);
tap('pointerup', '.tut-ov');
assert.equal(text(), '두번째', 'cut-in queues the info tap');
cut.className = 'hidden';
flush();
assert.equal(text(), '세번째');
await new Promise(r => setTimeout(r, 50));
tap('pointerdown', '.tut-bub');
document.querySelector('.tut-bub').click();
assert.equal(!!document.querySelector('.tut-ov'), false, 'a click with no pointerup still finishes the last info step');

const cloud = await read('js/cloud.js');
const nick = cloud.slice(cloud.indexOf('const NICK_ERR'), cloud.indexOf('window.VRCloud'));
const dom = parseHTML('<!doctype html><html><head></head><body></body></html>');
if (typeof dom.window.dispatchEvent !== 'function') dom.window.dispatchEvent = () => true;
const CE = dom.window.CustomEvent || class CustomEvent extends dom.window.Event { constructor(type, init = {}) { super(type, init); this.detail = init.detail; } };
const calls = [];
let nickResolve;
const nctx = vm.createContext({
  window: dom.window, document: dom.document, console, setTimeout, clearTimeout, CustomEvent: CE,
  user: { id: 'u' }, profile: null,
  sb: { rpc: async (name, args) => { calls.push([name, args]); if (name === 'set_nickname') return new Promise(res => { nickResolve = res; }); return { data: 'ok' }; } },
  render() {},
  esc: s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
});
vm.runInContext(nick + '\nglobalThis.askNickname = askNickname;', nctx);
const pending = nctx.askNickname(true);
const inp = dom.document.querySelector('#nick-ov input');
const msg = () => dom.document.querySelector('.nk-msg').textContent;
inp.value = '가';
inp.dispatchEvent(new dom.window.Event('compositionstart'));
inp.dispatchEvent(new dom.window.Event('input'));
assert.equal(msg(), '', 'composition does not flash the short-name warning');
inp.onkeydown({ key: 'Enter', isComposing: false, keyCode: 13 });
assert.equal(calls.some(c => c[0] === 'set_nickname'), false, 'Enter during composition does not submit');
dom.document.querySelector('.go').click();
assert.equal(calls.some(c => c[0] === 'set_nickname'), false, 'save waits for compositionend');
inp.value = '가나';
inp.dispatchEvent(new dom.window.Event('compositionend'));
await new Promise(r => setTimeout(r, 0));
assert.equal(calls.filter(c => c[0] === 'set_nickname').length, 1);
assert.equal(calls[0][1].p_nick, '가나');
assert.equal(msg().includes('2글자'), false);
const frozen = msg();
inp.value = 'ㄱ';
inp.oninput({ isComposing: false });
assert.equal(msg(), frozen, 'messages stay frozen while saving');
nickResolve({ data: { nickname: '가나' } });
assert.equal(await pending, '가나');
assert.equal(dom.document.getElementById('nick-ov'), null, 'success closes without leaving a validation message');
console.log('sheet 23-29 static + tutorial queue + nickname composition: OK');
