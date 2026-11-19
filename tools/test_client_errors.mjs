// 오류 수집: 가드·길이 제한·중복 제거·세션 한도·샘플링·쿼리스트링 제거. 외부 서비스 없음.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/client_errors_staging.sql');
const production = await read('supabase/client_errors_production.sql');
const checkS = await read('supabase/client_errors_check_staging.sql');
const checkP = await read('supabase/client_errors_check_production.sql');
const topS = await read('supabase/client_errors_top_staging.sql');
const topP = await read('supabase/client_errors_top_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(production, /아직 실행하지 마세요/);
assert.match(checkP, /아직 실행하지 마세요/);
assert.match(topP, /아직 실행하지 마세요/);
for (const sql of [staging, production]) {
  assert.match(sql, /create table if not exists public.client_errors/);
  assert.match(sql, /client_error_report\(/);
  assert.match(sql, /grant execute on function public.client_error_report\(text, text, text, text, text\) to anon, authenticated/);
  assert.match(sql, /client_errors_purge\(/);
  assert.match(sql, /interval '30 days'/);
  assert.match(sql, /interval '1 minute'/);
  assert.doesNotMatch(sql, /sentry|bugsnag|datadog|logrocket|rollbar|sentry\.io/i);
  assert.match(sql, /left\(btrim\(coalesce\(p_message, ''\)\), 400\)/);
  assert.match(sql, /1200/);
}
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...topS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...topP.matchAll(/;\s*$/gm)].length, 1);
assert.match(topS, /24 hours/);
assert.match(checkS, /7703759698107299042/);
assert.match(checkP, /7692130048193495360/);

const index = await read('index.html');
assert.match(index, /src="js\/client-errors\.js"/);
const game = await read('js/game.js');
assert.match(game, /VRErrors\?\.capture/);

const { window, document } = parseHTML('<!doctype html><html><body></body></html>');
const rpcCalls = [];
window.location = { href: 'https://ag.violenceroyale.com/play?access_token=SECRET#home' };
try { Object.defineProperty(window, 'navigator', { value: { userAgent: 'TestUA' }, configurable: true }); } catch {}
window.VRCloud = { sb: { rpc: async (name, args) => { rpcCalls.push({ name, args }); return { data: { ok: true }, error: null }; } } };
window.Math = Math;
Object.assign(globalThis, { window, document, Math });
window.eval(await read('js/client-errors.js'));
assert.equal(typeof window.VRErrors.capture, 'function');

const first = window.VRErrors.capture('test', new Error('boom'));
assert.equal(first, true);
await window.VRErrors.flush();
assert.equal(rpcCalls.length, 1);
assert.equal(rpcCalls[0].name, 'client_error_report');
assert.equal(rpcCalls[0].args.p_message, 'boom');
assert.equal(rpcCalls[0].args.p_source, 'test');
assert.doesNotMatch(rpcCalls[0].args.p_url, /access_token|SECRET|\?/);
assert.equal(rpcCalls[0].args.p_url, '/play#home');

assert.equal(window.VRErrors.capture('test', new Error('boom')), false); // dedupe
assert.equal(rpcCalls.length, 1);

const long = 'x'.repeat(800);
window.VRErrors.capture('long', new Error(long));
await window.VRErrors.flush();
assert.equal(rpcCalls.at(-1).args.p_message.length, 400);

window.VRErrors.capture('secret', new Error('Authorization Bearer abc.def.ghi failed'));
await window.VRErrors.flush();
assert.doesNotMatch(rpcCalls.at(-1).args.p_message, /abc\.def\.ghi/);

// session cap: first 2 always + later unique sampled, max 8
const start = rpcCalls.length;
for (let i = 0; i < 40; i++) window.VRErrors.capture('cap' + i, new Error('e' + i));
await window.VRErrors.flush();
assert.ok(rpcCalls.length - start <= 7); // already sent some before the loop; total n <= 8
assert.ok(rpcCalls.length <= 8);

console.log('test_client_errors ok');
