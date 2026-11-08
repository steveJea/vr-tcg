import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
const read = name => readFile(new URL('../' + name, import.meta.url), 'utf8');
const parse = text => JSON.parse(text.replace(/^\s*\/\/.*$/gm, ''));
const stage = parse(await read('wrangler.jsonc')), prod = parse(await read('wrangler.production.jsonc'));
assert.equal(stage.name, 'vr-tcg-staging'); assert.equal(prod.name, 'vr-tcg-prod');
for (const cfg of [stage, prod]) {
  assert.equal(cfg.account_id, 'a7cf57f7e3db3f2d94466da0c79c70b5');
  assert.equal(cfg.main, 'worker/media-range.mjs'); assert.equal(cfg.assets.binding, 'ASSETS');
  assert.deepEqual(cfg.assets.run_worker_first, ['/*.mp4', '/*.mp3']); assert.equal(cfg.workers_dev, true);
}
assert.equal(stage.assets.directory, './.staging-dist'); assert.equal(prod.assets.directory, './.production-dist');
assert.deepEqual(prod.routes, [{ pattern: 'ag.violenceroyale.com', custom_domain: true }]); assert.equal(prod.preview_urls, false);
assert.ok(!prod.zone_id && !prod.route && !prod.domains, 'no broad/top-level routes or extra domains');
// All tracked videos, including skill/gacha/story videos, must enter the handler.
const media = execFileSync('git', ['ls-files'], { encoding: 'utf8' }).trim().split('\n').filter(p => /\.(mp4|mp3)$/.test(p));
assert.ok(media.length > 600);
for (const p of media) assert.ok(stage.assets.run_worker_first.some(glob => new RegExp('^' + glob.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replaceAll('*', '.*') + '$').test('/' + p)), p);
const source = await read('js/config.js');
const { resolveConfig, showTestBadge } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
for (const hostname of ['vr-tcg-prod.notcold.workers.dev', 'ag.violenceroyale.com']) {
  const candidate = resolveConfig({ hostname, search: '?vrEnv=staging' });
  assert.equal(candidate.environment, 'production'); assert.equal(candidate.isStaging, false);
  assert.equal(candidate.supabaseUrl, 'https://htarwisgkkphutxxnuak.supabase.co');
  showTestBadge({ getElementById() { throw Error('production must never render TEST'); } }, candidate);
}
for (const host of ['bad-vr-tcg-prod.notcold.workers.dev', 'vr-tcg-prod.notcold.workers.dev.evil.test', 'preview-vr-tcg-prod.notcold.workers.dev', 'ag.violenceroyale.com.evil.test', 'evil.ag.violenceroyale.com', 'violenceroyale.com', 'www.violenceroyale.com']) assert.equal(resolveConfig({ hostname: host }).enabled, false);
const builder = await read('tools/build_production_assets.mjs');
assert.doesNotMatch(builder, /Disallow: \/|\.staging-dist/); assert.doesNotMatch(builder, /['"]supabase['"]|['"]tools['"]|['"]docs['"]/);
assert.match(builder, /https:\/\/vr-tcg-prod\.notcold\.workers\.dev\/\*/);
console.log(`분리 호스팅 설정·운영 DB·TEST 없음·${media.length}개 미디어 라우팅 OK`);
