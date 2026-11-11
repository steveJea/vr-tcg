// Real mouse at 1280x800 against the local battle screen (the same field tower uses).
// A short drag that covers the card to the left must reorder it, and AUTO off must survive the next entry and a reload.
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import puppeteer from 'puppeteer-core';

const root = new URL('..', import.meta.url).pathname;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.csv': 'text/csv', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.png': 'image/png', '.mp3': 'audio/mpeg' };
const server = createServer((req, res) => {
  const path = normalize(join(root, decodeURIComponent(new URL(req.url, 'http://local').pathname)));
  if (!path.startsWith(root) || !existsSync(path)) { res.writeHead(404); res.end(); return; }
  try { res.writeHead(200, { 'content-type': types[extname(path)] || 'application/octet-stream' }); res.end(readFileSync(path)); }
  catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const chrome = ['/usr/local/bin/google-chrome', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable'].find(existsSync);
if (!chrome) throw new Error('chrome not found');
const browser = await puppeteer.launch({
  executablePath: chrome, headless: 'new',
  args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--window-size=1280,800'],
  defaultViewport: { width: 1280, height: 800 },
});

const ids = ['10051', '10118', '10256', '10333', '10045'];
async function boot(page, { autoLegacy = null, autoStable = '0', name = '2층' } = {}) {
  await page.evaluateOnNewDocument((legacy, stable) => {
    if (sessionStorage.getItem('mouse-seed')) return;
    sessionStorage.setItem('mouse-seed', '1');
    localStorage.clear();
    if (stable != null) localStorage.setItem('vrTcgAuto', stable);
    if (legacy != null) localStorage.setItem('vrTcgAuto:player-1', legacy);
    localStorage.setItem('vrBfx', '1');
  }, autoLegacy, autoStable);
  await page.goto(`http://127.0.0.1:${port}/index.html`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.TCG?.ready, { timeout: 30000 });
  await page.evaluate((ids, name) => {
    const cloud = window.VRCloud || {};
    window.VRCloud = new Proxy(cloud, { get: (t, k) => k === 'user' ? { id: 'player-1' } : t[k] });
    window.VRPlayer = { now: () => ({ level: 50 }), status: async () => ({ ok: true, level: 50 }) };
    const card = (id, uid) => ({ ...window.TCG.cardById(id), uid });
    window.TCG.startStory({
      me: ids.map((id, i) => card(id, 'm' + i)),
      ai: ids.map((id, i) => card(id, 'a' + i)),
      win: 'wipe', first: 'me', aiName: name, quest: true, seed: 4,
    });
  }, ids, name);
  await page.waitForFunction(() => {
    const s = window.TCG?.S;
    return s && s.turn === 'me' && !s.busy && document.querySelectorAll('#me-field .unit').length >= 5 && !document.getElementById('bfx-vs');
  }, { timeout: 20000 });
}
function namesOf(page) {
  return page.evaluate(() => [...document.querySelectorAll('#me-field .unit')].map(el => el.querySelector('.truncate')?.textContent));
}

const dragPage = await browser.newPage();
await boot(dragPage);
const before = await namesOf(dragPage);
const from = await dragPage.evaluate(() => {
  const cards = [...document.querySelectorAll('#me-field .unit')];
  const card = cards.at(-1).getBoundingClientRect();
  const neighbor = cards.at(-2).getBoundingClientRect();
  return { x: card.left + card.width / 2, y: card.top + card.height / 2, neighborRight: neighbor.right };
});
// The gesture that used to do nothing: the card body covers the neighbor, but the cursor is still on the dragged card.
const releaseX = from.neighborRight + 12;
await dragPage.mouse.move(from.x, from.y);
await dragPage.mouse.down();
await dragPage.mouse.move(releaseX, from.y, { steps: 16 });
await dragPage.mouse.up();
await new Promise(r => setTimeout(r, 250));
const after = await namesOf(dragPage);
if (after.join() === before.join()) throw new Error(`drag did not reorder ${before.join('·')} (release ${Math.round(releaseX)} from ${Math.round(from.x)})`);
if (after.at(-2) !== before.at(-1) || after.at(-1) !== before.at(-2)) throw new Error(`unexpected order ${after.join('·')}`);
const swaps = await dragPage.evaluate(() => (window.TCG.S.directLog || []).filter(a => a.k === 'swap'));
if (swaps.length !== 1 || swaps[0].i !== 4 || swaps[0].g !== 3) throw new Error(`swap log ${JSON.stringify(swaps)}`);
console.log(`PASS mouse drag ${before.at(-1)} onto ${before.at(-2)} at 1280x800, logged swap 4>3`);

const autoPage = await browser.newPage();
await boot(autoPage, { autoStable: '1', name: '3층' });
const first = await autoPage.$eval('#auto-btn', b => b.getAttribute('aria-pressed'));
if (first !== 'true') throw new Error(`new floor should start from the saved ON choice, got ${first}`);
await autoPage.click('#auto-btn');
const off = await autoPage.evaluate(() => ({
  pressed: document.getElementById('auto-btn').getAttribute('aria-pressed'),
  stable: localStorage.getItem('vrTcgAuto'),
  user: localStorage.getItem('vrTcgAuto:player-1'),
}));
if (off.pressed !== 'false' || off.stable !== '0' || (off.user != null && off.user !== '0')) throw new Error(`toggle off did not persist ${JSON.stringify(off)}`);
await autoPage.evaluate(ids => {
  const card = (id, uid) => ({ ...window.TCG.cardById(id), uid });
  window.TCG.startStory({ me: ids.map((id, i) => card(id, 'n' + i)), ai: ids.map((id, i) => card(id, 'b' + i)), win: 'wipe', first: 'me', aiName: '2층', quest: true, seed: 8 });
}, ids);
await autoPage.waitForFunction(() => window.TCG?.S?.story?.aiName === '2층' && window.TCG.S.turn === 'me' && !window.TCG.S.busy && !document.getElementById('bfx-vs'), { timeout: 20000 });
const second = await autoPage.$eval('#auto-btn', b => b.getAttribute('aria-pressed'));
if (second !== 'false') throw new Error(`next floor turned AUTO back on (${second})`);
await autoPage.reload({ waitUntil: 'domcontentloaded' });
await autoPage.waitForFunction(() => window.TCG?.ready, { timeout: 30000 });
await autoPage.evaluate(ids => {
  const cloud = window.VRCloud || {};
  window.VRCloud = new Proxy(cloud, { get: (t, k) => k === 'user' ? { id: 'player-1' } : t[k] });
  window.VRPlayer = { now: () => ({ level: 50 }), status: async () => ({ ok: true, level: 50 }) };
  const card = (id, uid) => ({ ...window.TCG.cardById(id), uid });
  window.TCG.startStory({ me: ids.map((id, i) => card(id, 'r' + i)), ai: ids.map((id, i) => card(id, 'q' + i)), win: 'wipe', first: 'me', aiName: '3층', quest: true, seed: 9 });
}, ids);
await autoPage.waitForFunction(() => window.TCG?.S?.turn === 'me' && !document.getElementById('bfx-vs'), { timeout: 20000 });
const reloaded = await autoPage.$eval('#auto-btn', b => b.getAttribute('aria-pressed'));
if (reloaded !== 'false') throw new Error(`reload turned AUTO back on (${reloaded})`);
console.log('PASS AUTO off survives the next floor and a reload');

await browser.close();
server.close();
