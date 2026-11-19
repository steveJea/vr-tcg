// 설정 창의 탈퇴/기록삭제 버튼과 확인 창을 390x844 로 찍음.
import http from 'node:http';
import { createReadStream, existsSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const outDir = process.argv[2] || '/workspace';
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.json': 'application/json', '.mp3': 'audio/mpeg', '.mp4': 'video/mp4', '.woff2': 'font/woff2', '.ico': 'image/x-icon' };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  let p = decodeURIComponent(url.pathname);
  if (p === '/') p = '/index.html';
  const file = join(root, p);
  if (!file.startsWith(root) || !existsSync(file) || !statSync(file).isFile()) { res.writeHead(404); res.end('no'); return; }
  res.writeHead(200, { 'content-type': mime[extname(file)] || 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
  headless: 'new',
  args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars', `--window-size=390,844`],
});
const page = await browser.newPage();
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.evaluate(() => { try { localStorage.setItem('vrTcgIntroSeen', '1'); } catch {} });
await page.reload({ waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => typeof window.VRSettings?.open === 'function' && typeof window.VRWithdraw?.openDialog === 'function', { timeout: 60000 });
await page.evaluate(() => {
  const boot = document.getElementById('vr-boot');
  if (boot) { boot.classList.add('vb-out'); boot.remove(); }
  document.getElementById('intro')?.classList.add('hidden');
  document.getElementById('start-screen')?.classList.remove('hidden');
  window.VRSettings.open();
});
await page.waitForSelector('#main-settings-pop:not(.hidden) #main-withdraw', { timeout: 15000 });
await page.evaluate(() => {
  const btn = document.getElementById('main-withdraw');
  btn?.scrollIntoView({ block: 'center' });
});
await new Promise(r => setTimeout(r, 400));
const shot = async (name) => {
  const path = join(outDir, name);
  await page.screenshot({ path, type: 'png' });
  console.log('wrote', path);
};
await shot('withdraw-settings-btn-mobile.png');
await page.click('#main-withdraw');
await page.waitForSelector('#withdraw-ov .wd-title', { timeout: 5000 });
await new Promise(r => setTimeout(r, 300));
await shot('withdraw-confirm-guest-mobile.png');
await page.evaluate(() => { document.getElementById('withdraw-ov')?.remove(); window.VRWithdraw.openDialog('account'); });
await page.waitForSelector('#withdraw-ov .wd-title', { timeout: 5000 });
await new Promise(r => setTimeout(r, 300));
await shot('withdraw-confirm-account-mobile.png');
await page.click('[data-wd="step2"]');
await page.waitForSelector('#wd-confirm', { timeout: 5000 });
await new Promise(r => setTimeout(r, 300));
await shot('withdraw-confirm-type-mobile.png');
await browser.close();
server.close();
