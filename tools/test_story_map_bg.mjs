// 챕터 맵은 화면 종류에 맞는 배경을 한 장만 요청하고, PC 허브 배너는 ch_bg_pc 한 장만 쓴다.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {readFile, readdir, mkdir, writeFile} from 'node:fs/promises';
import {extname} from 'node:path';
import {parseHTML} from 'linkedom';

const root = new URL('..', import.meta.url);
const read = rel => readFile(new URL(rel, root), 'utf8');
const storySrc = await read('js/story.js');
const css = await read('css/story.css');

const files = await readdir(new URL('img/story/', root));
const disk = kind => new Set(files.filter(f => kind === 'pc' ? f.startsWith('ch_bg_pc_') && f.endsWith('.webp') : /^ch_bg_(?!pc_)/.test(f) && f.endsWith('.webp'))
  .map(f => f.slice(kind === 'pc' ? 'ch_bg_pc_'.length : 'ch_bg_'.length, -'.webp'.length)));
const listed = name => new Set(storySrc.match(new RegExp("const " + name + " = new Set\\('([^']+)'"))[1].split(' '));
assert.deepEqual([...listed('BG_M')].sort(), [...disk('m')].sort(), 'BG_M 가 img/story 세로 배경과 같다');
assert.deepEqual([...listed('BG_PC')].sort(), [...disk('pc')].sort(), 'BG_PC 가 img/story 가로 배경과 같다');
assert.equal(listed('BG_M').has('1'), false);
assert.equal(listed('BG_PC').has('1'), false);
const focusBlock = storySrc.match(/const BG_FOCUS = \{([\s\S]*?)\};/)[1];
const focusKeys = [...focusBlock.matchAll(/'([^']+)':\s*'(\d+% \d+%)'/g)];
assert.deepEqual(focusKeys.map(m => m[1]).sort(), [...disk('pc')].sort(), '얼굴 초점이 가로 배경마다 있다');
assert.match(storySrc, /bgFile\(keys, sets\.pc, 'ch_bg_pc_'\) \|\| bgFile\(keys, sets\.m, 'ch_bg_'\)/);
assert.match(css, /\.hub-ch-slot::after\{[^}]*linear-gradient\(180deg,rgba\(0,0,0,0\) 30%,rgba\(0,0,0,\.85\)\)/);
assert.match(css, /\.hub-ch-slot\.small::after\{[^}]*linear-gradient\(90deg/);
assert.match(css, /\.story-map-bg\{[^}]*#4a2414/);
assert.doesNotMatch(css, /story-map-bg-pc\{display:\s*none\}/);

const dataFiles = ['js/story-data.js', 'js/story-data-ch0.js', 'js/story-data-ch2.js', 'js/story-data-ch3.js', 'js/story-data-ch4.js', 'js/story-data-ch5.js', 'js/story-data-ch6.js', 'js/story-data-ch7.js', 'js/story-data-ch8.js', 'js/story-data-ch9.js', 'js/story-data-ch10.js', 'js/story-data-ch11.js', 'js/story-data-ch12.js', 'js/story-data-ch13.js', 'js/story-data-ch14.js', 'js/story-data-ch15.js'];
const loads = [];
const pcMode = {on: true};
const {window} = parseHTML('<html><body><div id="start-screen"></div><div id="story-screen" class="hidden"></div><div id="game" class="hidden"></div></body></html>');
const store = new Map();
const localStorage = {getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k)};
class FakeImage { set src(v) { this._src = v; loads.push(v); } get src() { return this._src; } }
const ctx = vm.createContext({
  window, document: window.document, console, localStorage, navigator, performance, crypto,
  setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
  addEventListener() {}, removeEventListener() {},
  requestAnimationFrame: f => f(),
  getComputedStyle: () => ({display: 'block'}),
  history: {pushState() {}, replaceState() {}, back() {}},
  location: {search: '', hash: '', pathname: '/'},
  matchMedia: q => ({matches: q.includes('901px') ? pcMode.on : false, addEventListener() {}, removeEventListener() {}}),
  innerWidth: 1920, innerHeight: 1080, Image: FakeImage,
});
Object.defineProperty(ctx, 'innerWidth', {get: () => pcMode.on ? 1920 : 390, set() {}});
Object.defineProperty(ctx, 'innerHeight', {get: () => pcMode.on ? 1080 : 844, set() {}});
window.TCG = {ready: true, POOL: [], NPC: [], skillsOf: () => [], RULES: {MAX_TURNS: 40}};
window.VRCloud = {user: {id: 'tester'}};
window.cardThumb = id => `img/x/${id}.webp`;
for (const f of dataFiles) vm.runInContext(await read(f), ctx);
vm.runInContext(storySrc, ctx);
const D = window.STORY_DATA;
const ch0 = D.chapters.find(c => c.id === 0);
const saveOf = (extra = {}) => ({v: 1, openingSeen: true, startSeen: true, ch0Pull: true, starter: '10111', owned: [{uid: 'u1', id: '10111', level: 1, boost: {}}], leader: 'u1', points: 0, statV: 2, cleared: {'0': ch0.phases.map(p => p.no)}, ...extra});
store.set('vrTcgStory.v1:tester', JSON.stringify(saveOf()));
const urls = style => [...String(style || '').matchAll(/url\(([^)]+)\)/g)].map(m => m[1]);
const screen = () => window.document.getElementById('story-screen');
const iOf = id => D.chapters.findIndex(c => c.id === id);

await window.VRStory.enter('quiet');
window.VRStory.renderMap(iOf(1));
const bgs = [...screen().querySelectorAll('.story-map-bg')];
assert.equal(bgs.length, 1);
assert.deepEqual(urls(bgs[0].getAttribute('style')), ['img/story/ch_bg_pc_1_10111.webp']);
assert.equal(bgs[0].getAttribute('style').includes(','), false);
assert.equal(bgs[0].classList.contains('pc'), true);
assert.doesNotMatch(screen().innerHTML, /ch_bg_1\.webp|ch_bg_pc_1\.webp/);
assert.match(screen().innerHTML, /브레이크/);

loads.length = 0;
window.VRStory.renderHub();
const slots = [...screen().querySelectorAll('.hub-ch-slot:not(.empty) .hub-ch-img')];
assert.equal(slots.length, 3);
assert.deepEqual(slots.map(el => urls(el.getAttribute('style'))), [
  ['img/story/ch_bg_pc_2.webp'],
  ['img/story/ch_bg_pc_1_10111.webp'],
  ['img/story/ch_bg_pc_0.webp'],
]);
assert.equal(slots[1].getAttribute('style').includes('background-position:50% 30%'), true);
assert.equal(slots[0].getAttribute('style').includes('background-position:50% 18%'), true);
assert.equal(slots[2].getAttribute('style').includes('background-position:50% 44%'), true);
assert.equal(slots.every(el => !el.getAttribute('style').includes(',')), true);
assert.equal(slots.some(el => el.getAttribute('style').includes('opening_poster') || el.getAttribute('style').includes('githubusercontent')), false);
assert.deepEqual([...loads].sort(), ['img/story/ch_bg_pc_0.webp', 'img/story/ch_bg_pc_1_10111.webp', 'img/story/ch_bg_pc_2.webp'].sort());
assert.equal(loads.some(u => /ch_bg_pc_1[0-5]/.test(u) || /ch_bg_(?!pc_)/.test(u)), false);

pcMode.on = false;
window.VRStory.renderMap(iOf(1));
const mob = screen().querySelector('.story-map-bg');
assert.deepEqual(urls(mob.getAttribute('style')), ['img/story/ch_bg_1_10111.webp']);
assert.equal(mob.classList.contains('pc'), false);
assert.equal(mob.getAttribute('style').includes('ch_bg_pc_'), false);
loads.length = 0;
window.VRStory.renderHub();
const mobSlot = screen().querySelector('.hub-ch-slot.big .hub-ch-img');
assert.deepEqual(urls(mobSlot.getAttribute('style')), ['https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/10111.webp']);
assert.equal(mobSlot.getAttribute('style').includes('ch_bg'), false);
assert.deepEqual([...loads].sort(), ['img/story/ch_bg_0.webp', 'img/story/ch_bg_1_10111.webp', 'img/story/ch_bg_2.webp'].sort());

// 가로 파일이 없고 세로 파일만 있으면 맵은 세로 한 장, 허브 배너는 초상화 한 장.
pcMode.on = true;
const cleared = {};
for (const c of D.chapters) if (c.id < 7) cleared[c.id] = c.phases.map(p => p.no);
store.set('vrTcgStory.v1:tester', JSON.stringify(saveOf({cleared})));
store.set('vrTcgStoryRouteStart:tester:7:main', '1');
window.__STORY_BG_FILES = {m: new Set(['7']), pc: new Set()};
loads.length = 0;
await window.VRStory.enter('quiet');
window.VRStory.renderMap(iOf(7));
const fall = screen().querySelector('.story-map-bg');
assert.equal(screen().querySelectorAll('.story-map-bg').length, 1);
assert.deepEqual(urls(fall.getAttribute('style')), ['img/story/ch_bg_7.webp']);
assert.equal(fall.getAttribute('style').includes(','), false);
window.VRStory.renderHub();
const fallSlot = screen().querySelector('.hub-ch-slot.big .hub-ch-img');
assert.deepEqual(urls(fallSlot.getAttribute('style')), ['https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/10115.webp']);
assert.equal(loads.filter(u => u.includes('ch_bg')).every(u => u === 'img/story/ch_bg_7.webp'), true);

// 시작 캐릭터 그림도 공용 그림도 없으면 요청하지 않고 밤색 그라데이션만 남긴다.
delete window.__STORY_BG_FILES;
store.set('vrTcgStory.v1:tester', JSON.stringify(saveOf({starter: '99999', owned: [{uid: 'u1', id: '99999', level: 1, boost: {}}]})));
loads.length = 0;
await window.VRStory.enter('quiet');
window.VRStory.renderMap(iOf(1));
const none = screen().querySelector('.story-map-bg');
assert.equal(none.getAttribute('style'), null);
assert.equal(none.classList.contains('story-map-bg'), true);
assert.equal(loads.length, 0);
assert.doesNotMatch(screen().innerHTML, /ch_bg_/);
console.log('story map bg: one url per viewport, hub banner uses ch_bg_pc on PC OK');

if (process.env.SKIP_CHROME === '1') process.exit(0);

const mime = {'.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp', '.png': 'image/png'};
const harness = `<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/css/story.css">
<div id="start-screen"></div><div id="story-screen" class="hidden"></div><div id="game" class="hidden"></div>
${dataFiles.map(f => `<script src="/${f}"></script>`).join('')}
<script>
window.TCG={ready:true,POOL:[],NPC:[],skillsOf:()=>[],RULES:{MAX_TURNS:40}};
window.VRCloud={user:{id:'tester'}};
window.cardThumb=id=>'img/x/'+id+'.webp';
const ch0=STORY_DATA.chapters.find(c=>c.id===0);
localStorage.setItem('vrTcgStory.v1:tester', JSON.stringify({v:1,openingSeen:true,startSeen:true,ch0Pull:true,starter:'10111',owned:[{uid:'u1',id:'10111',level:1,boost:{}}],leader:'u1',points:0,statV:2,cleared:{'0':ch0.phases.map(p=>p.no)}}));
</script>
<script src="/js/story.js"></script>`;
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/harness.html') { res.writeHead(200, {'content-type': 'text/html; charset=utf-8'}); res.end(harness); return; }
    const buf = await readFile(new URL(decodeURIComponent(url.pathname).replace(/^\//, ''), root));
    res.writeHead(200, {'content-type': mime[extname(url.pathname)] || 'application/octet-stream', 'cache-control': 'no-store'});
    res.end(buf);
  } catch { res.writeHead(404); res.end('no'); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const chrome = spawn('google-chrome', ['--headless=new', '--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage', '--remote-debugging-port=9444', '--user-data-dir=/tmp/story-map-bg-chrome', 'about:blank'], {stdio: 'ignore'});
const sleep = ms => new Promise(r => setTimeout(r, ms));
let ver;
try {
  for (let i = 0; i < 40 && !ver; i++) { try { ver = await (await fetch('http://127.0.0.1:9444/json/version')).json(); } catch { await sleep(150); } }
  if (!ver) throw new Error('chrome did not start');
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let seq = 0; const pending = new Map(); const evs = [];
  ws.addEventListener('message', ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) pending.get(m.id)(m); if (m.method) evs.push(m); });
  const send = (method, params = {}, sessionId) => new Promise(res => { const msg = {id: ++seq, method, params}; if (sessionId) msg.sessionId = sessionId; pending.set(msg.id, res); ws.send(JSON.stringify(msg)); });
  const {result: {targetId}} = await send('Target.createTarget', {url: 'about:blank'});
  const {result: {sessionId}} = await send('Target.attachToTarget', {targetId, flatten: true});
  const sessionEvs = () => evs.filter(e => e.sessionId === sessionId);
  await send('Network.enable', {}, sessionId);
  await send('Network.setCacheDisabled', {cacheDisabled: true}, sessionId);
  await send('Page.enable', {}, sessionId);
  await send('Runtime.enable', {}, sessionId);
  const setView = (width, height) => send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: false}, sessionId);
  const go = async () => {
    evs.length = 0;
    await send('Page.navigate', {url: `http://127.0.0.1:${port}/harness.html`}, sessionId);
    for (let i = 0; i < 50 && !sessionEvs().some(e => e.method === 'Page.loadEventFired'); i++) await sleep(100);
  };
  const evalJs = async expr => {
    const out = await send('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true}, sessionId);
    if (out.result?.exceptionDetails) throw new Error(JSON.stringify(out.result.exceptionDetails));
    return out.result?.result?.value;
  };
  const chReqs = () => sessionEvs().filter(e => e.method === 'Network.requestWillBeSent').map(e => e.params.request.url).filter(u => /\/ch_bg_/.test(u)).map(u => u.replace(`http://127.0.0.1:${port}`, ''));
  const shot = async (expr, file) => {
    const box = JSON.parse(await evalJs(expr));
    const png = await send('Page.captureScreenshot', {format: 'png', clip: {x: box.x, y: box.y, width: box.width, height: box.height, scale: 1}, captureBeyondViewport: true}, sessionId);
    await mkdir('/tmp/faces', {recursive: true});
    await writeFile(file, Buffer.from(png.result.data, 'base64'));
  };
  await setView(1920, 1080);
  await go();
  evs.length = 0;
  await evalJs(`(async()=>{await VRStory.enter('quiet'); VRStory.renderMap(STORY_DATA.chapters.findIndex(c=>c.id===1));})()`);
  await sleep(700);
  const mapReqs = chReqs();
  assert.deepEqual([...new Set(mapReqs)], ['/img/story/ch_bg_pc_1_10111.webp'], `PC map requests ${mapReqs.join(' ')}`);
  await shot(`JSON.stringify(document.querySelector('.story-map-bg').getBoundingClientRect())`, '/tmp/faces/live-pc-map.png');
  await go();
  evs.length = 0;
  await evalJs(`(async()=>{await VRStory.enter('quiet'); VRStory.renderHub();})()`);
  await sleep(700);
  const hubReqs = [...new Set(chReqs())].sort();
  assert.deepEqual(hubReqs, ['/img/story/ch_bg_pc_0.webp', '/img/story/ch_bg_pc_1_10111.webp', '/img/story/ch_bg_pc_2.webp']);
  const look = JSON.parse(await evalJs(`(()=>{const el=document.querySelector('.hub-ch-slot.big .hub-ch-img'); const s=getComputedStyle(el); const g=getComputedStyle(el.parentElement,'::after'); return JSON.stringify({img:s.backgroundImage,pos:s.backgroundPosition,size:s.backgroundSize,grad:g.backgroundImage,box:el.getBoundingClientRect()});})()`));
  assert.equal(look.img.includes('ch_bg_pc_1_10111.webp'), true);
  assert.equal(look.img.includes(','), false);
  assert.equal(look.pos, '50% 30%');
  assert.equal(look.size, 'cover');
  assert.match(look.grad, /linear-gradient/);
  assert.ok(look.box.width >= 900 && look.box.width <= 980 && look.box.height >= 280 && look.box.height <= 310, JSON.stringify(look.box));
  await shot(`JSON.stringify(document.querySelector('.hub-ch-slot.big').getBoundingClientRect())`, '/tmp/faces/live-pc-hub.jpg'.replace('.jpg', '.png'));

  await setView(390, 844);
  evs.length = 0;
  await evalJs(`VRStory.renderMap(STORY_DATA.chapters.findIndex(c=>c.id===1))`);
  await sleep(700);
  const mReqs = [...new Set(chReqs())];
  assert.deepEqual(mReqs, ['/img/story/ch_bg_1_10111.webp'], `mobile map requests ${mReqs.join(' ')}`);
  evs.length = 0;
  await evalJs(`VRStory.renderHub()`);
  await sleep(400);
  const mHub = JSON.parse(await evalJs(`(()=>{const el=document.querySelector('.hub-ch-slot.big .hub-ch-img'); const s=getComputedStyle(el); return JSON.stringify({img:s.backgroundImage,pos:s.backgroundPosition,box:el.parentElement.getBoundingClientRect(),w:innerWidth,h:innerHeight,pc:matchMedia('(min-aspect-ratio: 4/3) and (min-width: 901px)').matches});})()`));
  assert.equal(mHub.img.includes('10111.webp'), true);
  assert.equal(mHub.img.includes('ch_bg'), false);
  assert.equal(mHub.img.includes(','), false);
  await writeFile('/tmp/faces/live-mobile-hub.json', JSON.stringify(mHub));
  await shot(`JSON.stringify(document.querySelector('.hub-ch-slot.big').getBoundingClientRect())`, '/tmp/faces/live-mobile-hub.png');
  ws.close();
  console.log('chrome 1920x1080 map requests', mapReqs.length, mapReqs[0]);
  console.log('chrome hub unique ch_bg', hubReqs.join(' '));
  console.log('chrome mobile map', mReqs[0], 'inner', mHub.w + 'x' + mHub.h, 'slot', Math.round(mHub.box.width) + 'x' + Math.round(mHub.box.height), 'pcMedia', mHub.pc);
} finally {
  chrome.kill();
  server.close();
}
