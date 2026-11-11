// Real workerd + asset-routing integration (not a mocked Fetch runtime).
// Run after npm run build:staging, or pass --production after its separate build.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { open, readFile, stat } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
const production = process.argv.includes('--production');
const port = production ? 18780 : 18779, origin = `http://127.0.0.1:${port}`;
const root = path.resolve(import.meta.dirname, '..');
const dist = path.join(root, production ? '.production-dist' : '.staging-dist');
const config = production ? 'wrangler.production.jsonc' : 'wrangler.jsonc';
const child = spawn(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'dev', '--config', config, '--local', '--ip', '127.0.0.1', '--port', String(port), '--inspector-port', '0', '--show-interactive-dev-session=false'], {
  cwd: root, env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' }, stdio: ['ignore', 'pipe', 'pipe'],
});
let logs = '', exited = false;
child.stdout.on('data', data => { logs += data; }); child.stderr.on('data', data => { logs += data; });
child.on('exit', () => { exited = true; });
const request = (url, options = {}) => fetch(origin + url, { ...options, signal: AbortSignal.timeout(15000) });
async function localBytes(name, offset, size) {
  const f = await open(path.join(dist, name));
  try { const buf = Buffer.alloc(size); const got = await f.read(buf, 0, size, offset); assert.equal(got.bytesRead, size); return buf; } finally { await f.close(); }
}
try {
  const deadline = Date.now() + 120000;
  while (!logs.includes('Ready on')) {
    if (exited || Date.now() > deadline) throw Error('workerd startup failed: ' + logs);
    await delay(100);
  }
  const files = execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n');
  const samples = ['video/opening.mp4', ...['video/story/', 'data/fx/mr/', 'img/gacha/video/v1/', 'audio/', 'data/voice/', 'data/event/'].map(prefix => files.find(p => p.startsWith(prefix) && /\.(mp3|mp4)$/.test(p)))];
  assert.equal(samples.length, 7); assert.ok(samples.every(Boolean));
  for (const name of samples) {
    const size = (await stat(path.join(dist, name))).size;
    const response = await request('/' + name, { headers: { Range: 'bytes=0-1' } });
    assert.equal(response.status, 206, name);
    assert.equal(response.headers.get('content-range'), `bytes 0-1/${size}`);
    assert.equal(response.headers.get('content-length'), '2', 'native FixedLengthStream length');
    assert.equal(response.headers.get('accept-ranges'), 'bytes');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), await localBytes(name, 0, 2));
    const tail = await request('/' + name, { headers: { Range: 'bytes=-5' } });
    assert.equal(tail.status, 206); assert.equal(tail.headers.get('content-length'), '5');
    assert.deepEqual(Buffer.from(await tail.arrayBuffer()), await localBytes(name, size - 5, 5));
    const head = await request('/' + name, { method: 'HEAD', headers: { Range: 'bytes=0-1' } });
    assert.equal(head.status, 200); assert.equal(head.headers.get('content-length'), String(size)); assert.equal(await head.text(), '');
    const unsat = await request('/' + name, { headers: { Range: `bytes=${size}-` } });
    assert.equal(unsat.status, 416); assert.equal(unsat.headers.get('content-range'), `bytes */${size}`); assert.equal(await unsat.text(), '');
    const etag = response.headers.get('etag'); assert.ok(etag);
    const match = await request('/' + name, { headers: { Range: 'bytes=0-1', 'If-Range': etag } });
    assert.equal(match.status, 206); await match.arrayBuffer();
    const stale = await request('/' + name, { headers: { Range: 'bytes=0-1', 'If-Range': '"old"' } });
    assert.equal(stale.status, 200); await stale.body.cancel();
    const unchanged = await request('/' + name, { headers: { Range: 'bytes=0-1', 'If-None-Match': etag } });
    assert.equal(unchanged.status, 304); assert.equal(await unchanged.text(), '');
    console.log(`${production ? 'prod' : 'stage'} workerd: ${name} — 206/HEAD/416/ETag/끝 범위 OK`);
  }
  const absent = await request('/video/not-real.mp4', { headers: { Range: 'bytes=0-1' } });
  assert.equal(absent.status, 404); await absent.body?.cancel();
  const html = await request('/index.html', { headers: { Range: 'bytes=0-1' } });
  assert.equal(html.status, 200); assert.ok((await html.text()).includes('<html'));
  for (const name of ['/supabase/production/01_install.sql', '/tools/build_production_assets.mjs', '/wrangler.production.jsonc', '/worker/media-range.mjs']) {
    const missing = await request(name); assert.equal(missing.status, 404, name); await missing.body?.cancel();
  }
  const admin = await request('/admin.html');
  assert.equal(admin.status, 200); assert.equal(new URL(admin.url).pathname, '/admin'); await admin.body.cancel();
  const built = await readFile(path.join(dist, 'js/config.js'), 'utf8');
  const { resolveConfig } = await import('data:text/javascript;base64,' + Buffer.from(built).toString('base64'));
  const cfg = resolveConfig({ hostname: production ? 'vr-tcg-prod.notcold.workers.dev' : 'vr-tcg-staging.notcold.workers.dev' });
  assert.equal(cfg.isStaging, !production); assert.equal(cfg.enabled, true);
  console.log('실제 workerd 통합 검사: OK (게임/DB 요청 없음)');
} catch (error) { console.error(logs); throw error; }
finally {
  if (!exited) { child.kill('SIGTERM'); await new Promise(resolve => child.once('exit', resolve)); }
}
