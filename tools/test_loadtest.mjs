import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  parseStagingConfig, assertSafeTarget, estimateRun, shouldStop, quantile, summarize, DEFAULT_STAGES,
  BATTLE_CAPS, extrapolateBattles, readEngineVersions, HOME_RPCS, DEFAULT_AUTH_FILE, DEFAULT_LOADTEST_EMAILS, loadAccountsFromEnv, redact
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
assert.match(src, /Refusing bare --verify/);


assert.equal(DEFAULT_AUTH_FILE, '/workspace/.loadtest-accounts.json');
assert.ok(!DEFAULT_AUTH_FILE.includes('vr-tcg-loadtest/tools'));
assert.equal(BATTLE_CAPS.maxTotalVerifies, 40);
assert.ok(BATTLE_CAPS.maxTotalVerifies <= 200);
assert.equal(BATTLE_CAPS.maxConcurrentAccounts, 3);
assert.ok(HOME_RPCS.map(x => x[0]).includes('global_notice_list'));
assert.ok(HOME_RPCS.map(x => x[0]).includes('camp_status'));
assert.ok(HOME_RPCS.map(x => x[0]).includes('mail_list'));
const ex = extrapolateBattles({ testedConcurrent: 3, verifyP95ms: 800, fullFightUnknown: true });
assert.ok(ex.conservativeSafeConcurrent >= 3 && ex.conservativeSafeConcurrent <= 20);
assert.match(ex.caveat, /giveup|forfeit/);
const ver = await readEngineVersions();
assert.match(ver.story, /^[a-f0-9]{64}$/);
assert.match(ver.arcade, /^[a-f0-9]{64}$/);
const prov = await readFile(new URL('loadtest/provision-accounts.mjs', new URL('./', import.meta.url)), 'utf8');
assert.match(prov, /chmod 600|0o600/);
assert.match(prov, /refusing to write credentials inside the repo/);
assert.match(prov, /email confirmation is required/);

assert.deepEqual([...DEFAULT_LOADTEST_EMAILS], [
  'loadtest1@example.test', 'loadtest2@example.test', 'loadtest3@example.test',
  'loadtest4@example.test', 'loadtest5@example.test'
]);
assert.deepEqual(loadAccountsFromEnv({}).accounts, []);
const envLoaded = loadAccountsFromEnv({ VR_LOADTEST_PASSWORD: 'unit-test-secret-xx', VR_LOADTEST_EMAILS: 'a@example.test,b@example.test' });
assert.equal(envLoaded.source, 'env');
assert.equal(envLoaded.accounts.length, 2);
assert.equal(envLoaded.accounts[0].email, 'a@example.test');
assert.equal(redact('bad unit-test-secret-xx login', ['unit-test-secret-xx']), 'bad * login');
assert.doesNotMatch(JSON.stringify({ n: envLoaded.accounts.length, source: envLoaded.source }), /unit-test-secret-xx/);


const runSrc = await readFile(new URL('loadtest/run.mjs', new URL('./', import.meta.url)), 'utf8');
assert.match(runSrc, /전투 기록이 맞지/);
assert.match(runSrc, /storyGiveupOk/);
assert.match(runSrc, /errorSamples/);
assert.match(runSrc, /VR_LOADTEST_PASSWORD/);

console.log('test_loadtest ok');
