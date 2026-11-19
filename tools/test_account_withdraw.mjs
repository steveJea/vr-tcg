// 회원탈퇴: 가드·함수·확인 문구·로그인 유예 취소·약관 반영.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/account_withdraw_staging.sql');
const production = await read('supabase/account_withdraw_production.sql');
const checkS = await read('supabase/account_withdraw_check_staging.sql');
const checkP = await read('supabase/account_withdraw_check_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(staging, /STAGING ONLY/);
assert.match(production, /아직 실행하지 마세요/);
assert.match(production, /PRODUCTION ONLY/);
for (const sql of [staging, production]) {
  assert.match(sql, /account_withdraw_request\(p_confirm text\)/);
  assert.match(sql, /account_withdraw_cancel\(\)/);
  assert.match(sql, /account_withdraw_status\(\)/);
  assert.match(sql, /account_withdraw_purge_due/);
  assert.match(sql, /interval '30 days'/);
  assert.match(sql, /interval '7 days'/);
  assert.match(sql, /interval '5 years'/);
  assert.match(sql, /account_rejoin_blocklist/);
  assert.match(sql, /rejoin_blocked/);
  assert.match(sql, /pg_cron/);
  assert.match(sql, /delete from auth\.users/);
  assert.match(sql, /payment_orders/);
  assert.match(sql, /grant execute on function\s+public\.account_withdraw_status\(\)/i);
  assert.doesNotMatch(sql, /grant execute on function public\.account_withdraw_purge_due\(integer\) to authenticated/i);
  assert.match(sql, /p_confirm is distinct from '탈퇴'/);
}
assert.match(checkS, /7703759698107299042/);
assert.match(checkP, /7692130048193495360/);
assert.match(checkS, /account_withdraw_install_ok/);
assert.match(checkP, /account_withdraw_install_ok/);
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);

const js = await read('js/withdraw.js');
assert.match(js, /CONFIRM_WORD = '탈퇴'/);
assert.match(js, /30일/);
assert.match(js, /환불되지 않/);
assert.match(js, /ensureActive/);
assert.match(js, /탈퇴 예정 계정이에요/);
assert.match(js, /wipeLocal/);

const cloud = await read('js/cloud.js');
assert.match(cloud, /ensureWithdrawActive/);
assert.match(cloud, /from '\.\/withdraw\.js'/);

const oauth = await read('js/auth-oauth.js');
assert.match(oauth, /rejoin_blocked/);
assert.match(oauth, /7일이 지나야 다시 가입/);

const index = await read('index.html');
assert.match(index, /id="withdraw-settings"/);
assert.match(index, /<div id="consent-settings" class="hidden" data-clarity-mask="true"><\/div>/);

const store = new Map([['vrTcgIntroSeen', '1'], ['vrTcgSkipFx', '1'], ['other-key', 'keep']]);
const mem = (map = store) => ({
  get length() { return map.size; },
  key: i => [...map.keys()][i] ?? null,
  getItem: k => (map.has(k) ? map.get(k) : null),
  setItem: (k, v) => map.set(k, String(v)),
  removeItem: k => map.delete(k),
});
globalThis.localStorage = mem(store);
globalThis.sessionStorage = mem(new Map());

const { _test, CONFIRM_WORD } = await import(new URL('../js/withdraw.js', import.meta.url));
assert.equal(CONFIRM_WORD, '탈퇴');
assert.match(_test.kstDate('2026-12-19T00:00:00+09:00'), /2026년 12월 19일/);
assert.deepEqual(_test.localKeys(localStorage).sort(), ['vrTcgIntroSeen', 'vrTcgSkipFx']);
_test.wipeLocal();
assert.equal(localStorage.getItem('other-key'), 'keep');
assert.equal(localStorage.getItem('vrTcgIntroSeen'), null);

assert.match(_test.accountIntro(null), /30일 뒤/);
assert.match(_test.accountIntro(null), /환불되지 않/);
assert.match(_test.accountStep2(), /탈퇴/);
assert.match(_test.guestIntro(), /이 기기/);
assert.match(_test.guestStep2(), /확인 문구/);
assert.match(_test.accountIntro({ scheduled: true, purge_at: '2026-12-19T00:00:00+09:00', days_left: 29 }), /탈퇴 예정 계정이에요/);

const terms = await read('terms.html');
const privacy = await read('privacy.html');
assert.match(terms, /계정삭제 버튼/);
assert.match(terms, /30일/);
assert.match(privacy, /계정삭제 버튼/);
assert.match(privacy, /30일/);
assert.match(privacy, /5년/);
assert.doesNotMatch(terms, /현재 게임 설정에는 회원탈퇴·계정삭제 버튼이 없습니다/);
assert.doesNotMatch(privacy, /현재 설정에는 계정삭제 버튼이 없습니다/);

console.log('account withdraw tests: OK');
