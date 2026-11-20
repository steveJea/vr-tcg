// 첫 로그인 동의 창·흐름: 필수 3개 → 시작 가능, 전체 동의, 동의 안 함=로그아웃, SQL 없을 때 로컬 저장·재시도, 설정 알림 토글 — 2026-11-12
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';
const { window, document } = parseHTML('<!doctype html><html><head></head><body><div id="consent-settings" class="hidden"></div></body></html>');
const store = new Map(); const ls = { getItem: k => store.has(k) ? store.get(k) : null, setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
Object.assign(globalThis, { window, document, localStorage: ls, CustomEvent: window.CustomEvent });
window.addEventListener = window.addEventListener.bind(window);
const C = await import('../js/consent.js');
const tick = () => new Promise(r => setTimeout(r, 0));
// 1) 창: 처음엔 시작 버튼 꺼짐, 필수 3개면 켜짐, 선택은 상관없음, 전체 동의
let p = C.showModal(); const ov = document.getElementById('consent-ov'); assert(ov, 'modal shown');
const go = ov.querySelector('.go'), ck = k => ov.querySelector(`[data-ck="${k}"]`), fire = el => el.onchange();
assert.equal(go.disabled, true);
assert.equal(ov.querySelectorAll('a[href="/terms.html"]').length, 1); assert.equal(ov.querySelectorAll('a[href="/privacy.html"]').length, 1);
assert.match(ov.textContent, /\[필수\]이용약관 동의/); assert.match(ov.textContent, /\[필수\]만 19세 이상입니다/); assert.match(ov.textContent, /\[선택\]이벤트·혜택 알림 수신/);
ck('terms').checked = true; fire(ck('terms')); ck('privacy').checked = true; fire(ck('privacy')); assert.equal(go.disabled, true, 'age14 still missing');
ck('age14').checked = true; fire(ck('age14')); assert.equal(go.disabled, false, 'all required → enabled');
const all = ov.querySelector('[data-all]'); all.checked = true; all.onchange(); assert.equal(ck('marketing').checked, true);
all.checked = false; all.onchange(); assert.equal(go.disabled, true, 'uncheck all → disabled');
all.checked = true; all.onchange(); go.onclick(); assert.deepEqual({ ...(await p) }, { terms: true, privacy: true, age14: true, marketing: true });
assert.equal(document.getElementById('consent-ov'), null);
p = C.showModal(); document.querySelector('#consent-ov .no').onclick(); assert.equal(await p, null, 'decline');
// 2) SQL 아직 없음: 창 → 로컬 저장(synced false) → 나중에 서버 생기면 올라감
const calls = []; let live = false, srv = null;
const sb = { rpc: async (fn, args) => { calls.push([fn, args]); if (!live) return { error: { code: 'PGRST202', message: 'Could not find the function' } };
  if (fn === 'consent_status') return { data: srv ? { current: true, record: srv } : { current: false, record: null } };
  if (fn === 'consent_accept') { srv = { terms_version: args.p_terms, privacy_version: args.p_privacy, age14: true, marketing: args.p_marketing, agreed_at: 'x' }; return { data: { current: true, record: srv } }; }
  if (fn === 'consent_set_marketing') { srv = { ...srv, marketing: args.p_marketing }; return { data: { current: true, record: srv } }; } } };
const u = { id: 'u1' }; let shown = 0, declined = 0;
assert.equal(await C.ensureConsent(sb, u, { store: ls, show: async () => { shown++; return { terms: true, privacy: true, age14: true, marketing: false }; } }), true);
assert.equal(shown, 1); let rec = C.readLocal('u1', ls); assert.equal(rec.synced, false); assert.equal(rec.terms_version, C.TERMS_VERSION);
assert.equal(await C.ensureConsent(sb, u, { store: ls, show: async () => { shown++; return null; } }), true); assert.equal(shown, 1, 'local consent → no second modal');
live = true; assert.equal(await C.pushLocal(sb, 'u1', ls), true); assert.equal(C.readLocal('u1', ls).synced, true); assert.equal(srv.marketing, false);
assert(calls.some(([f, a]) => f === 'consent_accept' && a.p_age14 === true && a.p_terms === C.TERMS_VERSION));
// 3) 서버에 이미 있음 → 창 없음 (다른 기기)
srv = { terms_version: C.TERMS_VERSION, privacy_version: C.PRIVACY_VERSION, age14: true, marketing: true, agreed_at: 'y' };
assert.equal(await C.ensureConsent(sb, { id: 'u2' }, { store: ls, show: async () => { shown++; return null; } }), true); assert.equal(shown, 1); assert.equal(C.readLocal('u2', ls).marketing, true);
// 4) 예전 버전 기록 → 다시 묻기, 동의 안 함 → 로그아웃
srv = { terms_version: 'old', privacy_version: 'old', age14: true, marketing: false }; const sbOld = { rpc: async fn => fn === 'consent_status' ? { data: { current: false, record: srv } } : { error: { message: 'x' } } };
assert.equal(await C.ensureConsent(sbOld, { id: 'u3' }, { store: ls, onDecline: async () => { declined++; }, show: async () => { shown++; return null; } }), false);
assert.equal(shown, 2); assert.equal(declined, 1); assert.equal(C.readLocal('u3', ls), null);
// 5) 설정: 알림 토글 → 로컬 즉시, 서버 consent_set_marketing
live = true; srv = { ...C.readLocal('u1', ls) }; window.VRCloud = { user: { id: 'u1' }, sb };
C.paintSettings(); const box = document.getElementById('consent-settings'); assert(!box.classList.contains('hidden')); assert.match(box.textContent, /동의 완료/);
assert.equal(await C.setMarketing(true, { store: ls }), true); assert.equal(C.readLocal('u1', ls).marketing, true); assert(calls.some(([f, a]) => f === 'consent_set_marketing' && a.p_marketing === true));
assert.match(document.getElementById('main-marketing').textContent, /ON/);
window.VRCloud = { user: null }; C.paintSettings(); assert(box.classList.contains('hidden'), 'guest → hidden');
// 6) 연결: 로그인 직후·닉네임 전에, 동의 안 함은 로그아웃
const cloud = await readFile('js/cloud.js', 'utf8'), html = await readFile('index.html', 'utf8');
assert.match(cloud, /import \{ ensureConsent \} from '\.\/consent\.js';/);
assert.match(cloud, /import \{ ensureAgeGate \} from '\.\/age-gate\.js';/);
assert.match(cloud, /if \(!await ensureConsent\(sb, u, \{ onDecline: logout \}\)\) return;\n\s*if \(version !== userVersion\) return;\n\s*if \(!await ensureAgeGate\(sb, u\)\) return;\n\s*if \(version !== userVersion\) return;\n\s*if \(profile && profile\.nick_set === false\) askNickname\(true\);/);
assert.match(html, /<div id="consent-settings" class="hidden" data-clarity-mask="true"><\/div>/);
await tick();
console.log('Consent UI: required 3 gate, 전체 동의, decline→logout, SQL-missing local save + later sync, re-ask on new version, settings marketing toggle OK');
process.exit(0);
