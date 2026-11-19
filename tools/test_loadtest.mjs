import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  parseStagingConfig, assertSafeTarget, estimateRun, shouldStop, quantile, summarize, DEFAULT_STAGES
} from './loadtest/run.mjs';

const root = new URL('../', import.meta.url);
const cfg = await readFile(new URL('js/config.js', root), 'utf8');
const staging = parseStagingConfig(cfg);
assert.equal(staging.ref, 'cuyqchmdcnsgzkwyclji');
assert.match(staging.supabaseUrl, /^https:\/\/cuyqchmdcnsgzkwyclji\.supabase\.co$/);
assert.ok(staging.anonKey.length > 20);
assert.doesNotMatch(JSON.stringify(estimateRun()), new RegExp(staging.anonKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));

assert.doesNotThrow(() => assertSafeTarget('https://vr-tcg-staging.notcold.workers.dev', staging.supabaseUrl));
assert.throws(() => assertSafeTarget('https://ag.violenceroyale.com', staging.supabaseUrl), /production/);
assert.throws(() => assertSafeTarget('https://vr-tcg-prod.notcold.workers.dev', staging.supabaseUrl), /production/);
assert.throws(() => assertSafeTarget('https://vr-tcg-staging.notcold.workers.dev', 'https://htarwisgkkphutxxnuak.supabase.co'), /production|staging/);

const est = estimateRun({ stages: DEFAULT_STAGES, thinkSec: 12, assets: 11, verify: false });
assert.equal(est.uniqueVu, 500);
assert.equal(est.verifyInvocations, 0);
assert.ok(est.totalReqs > 1000);
assert.ok(est.minutes > 5 && est.minutes < 15);

assert.equal(quantile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5), 5);
assert.equal(shouldStop({ errorRate: 0.02, p95: 400, baselineP95: 300, minSamples: 80 }), null);
assert.match(shouldStop({ errorRate: 0.06, p95: 400, baselineP95: 300, minSamples: 80 }), /error rate/);
assert.match(shouldStop({ errorRate: 0.01, p95: 9000, baselineP95: 300, minSamples: 80 }), /p95/);
assert.match(shouldStop({ errorRate: 0.01, p95: 5000, baselineP95: 200, minSamples: 80 }), /exploded/);
assert.equal(shouldStop({ errorRate: 0.2, p95: 9000, baselineP95: 100, minSamples: 10 }), null);

const sum = summarize([
  { ok: true, ms: 10, status: 200 },
  { ok: true, ms: 20, status: 200 },
  { ok: false, ms: 30, status: 500 }
]);
assert.equal(sum.n, 3);
assert.equal(sum.errors, 1);
assert.ok(Math.abs(sum.errorRate - 1 / 3) < 1e-9);

const src = await readFile(new URL('loadtest/run.mjs', new URL('./', import.meta.url)), 'utf8');
assert.match(src, /STAGING ONLY/);
assert.doesNotMatch(src, /htarwisgkkphutxxnuak\.supabase\.co['"]\s*,\s*['"]eyJ/);
assert.match(src, /story-direct-verify-v7/);
assert.match(src, /Refusing --verify/);

console.log('test_loadtest ok');
