// 곧 오픈 화면 모바일 스크린샷 (390x844).
import { createReadStream, existsSync, mkdirSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const outDir = process.env.SHOT_OUT || '/workspace';
mkdirSync(outDir, { recursive: true });
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };

const server = createServer((req, res) => {
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
      return {
        on: true,
        kind: 'coming_soon',
        title: '곧 오픈 / COMING SOON',
        message: 'Violence Royale : The Abyss Gate 곧 오픈합니다',
        ends_at: null,
        allowed: false
      };
    }
    return null;
  };
  try { localStorage.setItem('vrTcgIntroSeen', '1'); } catch {}
});
await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => typeof window.VRMaint?.show === 'function', { timeout: 60000 });
await page.evaluate(() => document.getElementById('vr-boot')?.remove());
await page.waitForSelector('#vr-maint:not(.hidden) .mt-title', { timeout: 15000 });
await page.waitForFunction(() => /COMING SOON|곧 오픈/.test(document.querySelector('#mt-title')?.textContent || ''), { timeout: 5000 });
await new Promise(r => setTimeout(r, 800));
const path = join(outDir, 'coming-soon-mobile.png');
await page.screenshot({ path, type: 'png' });
console.log('wrote', path);
await browser.close();
server.close();
