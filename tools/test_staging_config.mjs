import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const configSource = await readFile(new URL('../js/config.js', import.meta.url), 'utf8');
const { resolveConfig, showTestBadge, STAGING } = await import('data:text/javascript;base64,' + Buffer.from(configSource).toString('base64'));
const select = (hostname, search = '', test = STAGING) => resolveConfig({ hostname, search }, test);
const prod = select('tcg.mbbs.kr');
assert.equal(prod.enabled, true);
assert.equal(prod.supabaseUrl, 'https://htarwisgkkphutxxnuak.supabase.co');
assert.equal(prod.isStaging, false);
assert.deepEqual(select('tcg.mbbs.kr', '?vrEnv=staging'), prod);
for (const host of ['unknown.example', 'tcg.mbbs.kr.evil.test', 'fake.workers.dev', 'stevejea.github.io', '', 'localhost', '127.0.0.1', '[::1]']) {
  const c = select(host);
  assert.equal(c.enabled, false, host);
  assert.equal(c.supabaseUrl, '', host);
  assert.equal(c.anonKey, '', host);
}
assert.equal(select('unknown.example', '?vrEnv=production').enabled, false);
assert.equal(select('dev-tcg.mbbs.kr').isStaging, true);
assert.equal(select('dev-tcg.mbbs.kr').enabled, false, '설정 전 테스트 DB 요청 차단');
const jwt = role => `eyJhbGciOiJub25lIn0.${btoa(JSON.stringify({ role, ref: 'abcdefghijklmnopqrst' }))}.FAKE_NOT_A_REAL_KEY`;
const test = { hostnames: ['dev-tcg.mbbs.kr', 'vr-tcg-staging.example.workers.dev'], supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co', anonKey: jwt('anon') };
for (const host of test.hostnames) {
  const c = select(host, '?vrEnv=production', test);
  assert.equal(c.enabled, true); assert.equal(c.isStaging, true);
  assert.equal(c.supabaseUrl, test.supabaseUrl); assert.equal(c.anonKey, test.anonKey);
}
for (const host of ['localhost', '127.0.0.1', '[::1]']) {
  assert.equal(select(host, '?vrEnv=staging', test).supabaseUrl, test.supabaseUrl);
  assert.equal(select(host, '?vrEnv=production', test).supabaseUrl, prod.supabaseUrl);
}
for (const bad of [
  { supabaseUrl: prod.supabaseUrl }, { anonKey: prod.anonKey },
  { supabaseUrl: 'http://abcdefghijklmnopqrst.supabase.co' },
  { supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co@evil.test' },
  { supabaseUrl: test.supabaseUrl + '/rest/v1' },
  { anonKey: jwt('service_role') }, { anonKey: 'sb_secret_NOT_FOR_BROWSER' },
  { anonKey: 'bad-placeholder' }, { supabaseUrl: '' },
]) assert.equal(select(test.hostnames[0], '', { ...test, ...bad }).enabled, false, JSON.stringify(bad));
assert.equal(select(test.hostnames[0], '', { ...test, anonKey: 'sb_publishable_FAKE_PUBLIC_TEST_VALUE' }).enabled, true);
const elements = [];
const doc = { getElementById: id => elements.find(e => e.id === id), createElement: () => ({ style: {}, setAttribute() {} }), body: { appendChild: e => elements.push(e) } };
showTestBadge(doc, prod); assert.equal(elements.length, 0);
showTestBadge(doc, select('unknown.example')); assert.equal(elements.length, 0);
showTestBadge(doc, select('dev-tcg.mbbs.kr')); assert.equal(elements[0].textContent, 'TEST · DB 미설정');
showTestBadge(doc, select('dev-tcg.mbbs.kr')); assert.equal(elements.length, 1, '중복 배지 없음');
const cloud = await readFile(new URL('../js/cloud.js', import.meta.url), 'utf8');
const ranking = await readFile(new URL('../js/ranking.js', import.meta.url), 'utf8');
for (const text of [cloud, ranking]) {
  assert.match(text, /import \{ config \} from '\.\/config\.js'/);
  assert.doesNotMatch(text, /htarwisgkkphutxxnuak|eyJhbGci/);
}
assert.match(cloud, /if \(!config\.enabled\)/);
assert.equal((ranking.match(/if \(!config\.enabled\)/g) || []).length, 2);
const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
assert.match(html, /<script type="module" src="js\/ranking.js"><\/script>/);
console.log('호스트 격리·운영 유지·잘못된 키 차단·TEST 표시: OK');
