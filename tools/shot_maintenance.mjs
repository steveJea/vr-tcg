// 점검 중 화면을 390x844 로 찍음. 로컬에는 점검 SQL 이 없으므로 상태 RPC 만 흉내 냄.
import http from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
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
  args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars', '--window-size=390,844'],
});
const page = await browser.newPage();
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
await page.evaluateOnNewDocument(() => {
  window.__MAINT_MOCK = async fn => {
    if (fn === 'maintenance_status') {
      return { on: true, message: '지금은 점검 중이에요. 잠시 후 다시 와 주세요.', ends_at: '2026-11-19T18:00:00+09:00' };
    }
    if (fn === 'admin_check') return { admin: false };
    return null;
  };
  try { localStorage.setItem('vrTcgIntroSeen', '1'); } catch {}
});
await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => typeof window.VRMaint?.show === 'function', { timeout: 60000 });
await page.evaluate(() => document.getElementById('vr-boot')?.remove());
await page.waitForSelector('#vr-maint:not(.hidden) .mt-title', { timeout: 15000 });
await new Promise(r => setTimeout(r, 500));
const path = join(outDir, 'maintenance-screen-mobile.png');
await page.screenshot({ path, type: 'png' });
console.log('wrote', path);
await browser.close();
server.close();
