import assert from 'node:assert/strict';
import { createHandler, isAtLeast19, sha256hex, STAGING } from '../supabase/functions/age-verify-v1/handler.mjs';
import { publicConfig, isVerificationId, STAGING_PORTONE, STAGE_HOST, STAGE_DB } from '../js/age-verify-config.js';
import { readReturn, verifyError } from '../js/age-verify.js';

const vid = 'identity-verification-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const uid = '11111111-1111-4111-8111-111111111111';
assert.equal(isVerificationId(vid), true);
assert.equal(isVerificationId('nope'), false);
assert.equal(STAGING_PORTONE.storeId, '');
assert.equal(STAGING_PORTONE.channelKey, '');
const empty = publicConfig({ isStaging: true, supabaseUrl: STAGE_DB }, { hostname: STAGE_HOST });
assert.equal(empty.ready, false);
assert.equal(readReturn('https://'+STAGE_HOST+'/age-verify-return.html?identityVerificationId='+vid).identityVerificationId, vid);
assert.equal(readReturn('https://'+STAGE_HOST+'/age-verify-return.html?code=USER_CANCEL').failed, true);
assert.match(verifyError('underage'), /만 19세/);

// 만 19세: 한국 시간 기준 생일 당일 포함
assert.equal(isAtLeast19('2007-11-14', new Date('2026-11-14T00:30:00+09:00')), true);
assert.equal(isAtLeast19('2007-11-15', new Date('2026-11-14T23:30:00+09:00')), false);
assert.equal(isAtLeast19('2007-11-14', new Date('2026-11-13T15:30:00Z')), true); // 11/14 00:30 KST
assert.equal(isAtLeast19('2007-11-14', new Date('2026-11-13T14:30:00Z')), false); // still 11/13 KST
assert.equal(isAtLeast19('bad'), false);
assert.equal((await sha256hex('ci-example')).length, 64);

function env(extra = {}) {
  return {
    SUPABASE_URL: STAGING,
    PORTONE_API_SECRET: 'portone_test_secret_value_xxxxxxxx',
    SUPABASE_ANON_KEY: 'sb_publishable_test_anon_key_value',
    SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test_service_role_value',
    ...extra,
  };
}
function req(body, headers = {}) {
  return new Request('https://cuyqchmdcnsgzkwyclji.supabase.co/functions/v1/age-verify-v1', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: 'https://'+STAGE_HOST, authorization: 'Bearer sess', ...headers },
    body: JSON.stringify(body),
  });
}
async function json(res) { return { status: res.status, body: await res.json() }; }

const missing = createHandler({ SUPABASE_URL: STAGING, SUPABASE_ANON_KEY: 'a', SUPABASE_SERVICE_ROLE_KEY: 'b' });
assert.equal((await json(await missing(req({ identityVerificationId: vid })))).status, 503);
assert.equal((await json(await missing(req({ identityVerificationId: vid })))).body.error, 'age verification configuration required');

const blocked = createHandler(env());
assert.equal((await blocked(new Request('https://example/x', { method: 'POST', headers: { origin: 'https://evil.example', 'content-type': 'application/json' }, body: '{}' }))).status, 403);
assert.equal((await blocked(new Request('https://example/x', { method: 'OPTIONS', headers: { origin: 'https://'+STAGE_HOST } }))).status, 204);

let portone, rpcArgs;
const fetcher = async (url, opts = {}) => {
  if (String(url).includes('/auth/v1/user')) return new Response(JSON.stringify({ id: uid }), { status: 200, headers: { 'content-type': 'application/json' } });
  if (String(url).startsWith('https://api.portone.io/identity-verifications/')) {
    assert.match(opts.headers.Authorization, /^PortOne /);
    return new Response(JSON.stringify(portone), { status: 200, headers: { 'content-type': 'application/json' } });
  }
  if (String(url).includes('/rest/v1/rpc/age_verify_apply')) {
    rpcArgs = JSON.parse(opts.body);
    return new Response(JSON.stringify({ ok: true, verified: true, idempotent: false }), { status: 200, headers: { 'content-type': 'application/json' } });
  }
  throw Error('unexpected ' + url);
};

portone = { status: 'VERIFIED', id: vid, verifiedCustomer: { birthDate: '2000-01-01', ci: 'CIVALUE_TEST_XXXXXXXXXXXXXXXX' } };
rpcArgs = null;
const ok = await json(await createHandler(env(), fetcher)(req({ identityVerificationId: vid })));
assert.equal(ok.status, 200); assert.equal(ok.body.ok, true); assert.equal(ok.body.verified, true);
assert.equal(rpcArgs.p_uid, uid); assert.equal(rpcArgs.p_vid, vid);
assert.equal(rpcArgs.p_ci_hash, await sha256hex('CIVALUE_TEST_XXXXXXXXXXXXXXXX'));

portone = { status: 'VERIFIED', id: vid, verifiedCustomer: { birthDate: '2015-01-01', ci: 'CIVALUE_TEST_XXXXXXXXXXXXXXXX' } };
rpcArgs = null;
const young = await json(await createHandler(env(), fetcher)(req({ identityVerificationId: vid })));
assert.equal(young.status, 403); assert.equal(young.body.error, 'underage'); assert.equal(rpcArgs, null);

portone = { status: 'VERIFIED', id: vid, verifiedCustomer: { birthDate: '2000-01-01' } };
const noCi = await json(await createHandler(env(), fetcher)(req({ identityVerificationId: vid })));
assert.equal(noCi.status, 409); assert.equal(noCi.body.error, 'identity incomplete');

portone = { status: 'FAILED', id: vid, verifiedCustomer: { birthDate: '2000-01-01', ci: 'CIVALUE_TEST_XXXXXXXXXXXXXXXX' } };
const fail = await json(await createHandler(env(), fetcher)(req({ identityVerificationId: vid })));
assert.equal(fail.status, 409);

console.log('Age-verify handler: inert without secret, CORS, 19+ KST, CI hash only, underage/incomplete rejected OK');
