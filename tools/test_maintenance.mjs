// 점검/곧 오픈 모드: 가드·상태 함수·폴링 없음·관리자/허용 이메일 우회·전투 시작 차단·법적 링크.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const production = await read('supabase/maintenance_production.sql');
const checkP = await read('supabase/maintenance_check_production.sql');
const onP = await read('supabase/maintenance_on_production.sql');
const offP = await read('supabase/maintenance_off_production.sql');
const onCheck = await read('supabase/maintenance_on_check_production.sql');
const staging = await read('supabase/maintenance_coming_soon_staging.sql');
const checkS = await read('supabase/maintenance_coming_soon_check_staging.sql');

assert.match(production, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(staging, /7703759698107299042/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.match(production, /allow_emails/);
assert.match(production, /coming_soon/);
assert.match(production, /grant select \(id, is_on, message, ends_at, updated_at, title, kind\)/);
assert.doesNotMatch(production, /grant select on public\.maintenance to anon/);
for (const sql of [production, onP, offP]) {
  assert.match(sql, /7692130048193495360/);
}
assert.match(onP, /클라이언트/);
assert.match(onP, /Violence Royale : The Abyss Gate 곧 오픈합니다/);
assert.match(onP, /곧 오픈 \/ COMING SOON/);
assert.match(onP, /allow_emails/); // 목록은 건드리지 않는다는 주석 또는 select
assert.match(offP, /is_on = false/);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...onCheck.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.match(checkP, /7692130048193495360/);
assert.match(onCheck, /coming_soon/);
assert.match(checkS, /7703759698107299042/);

const js = await read('js/maintenance.js');
assert.doesNotMatch(js, /setInterval/);
assert.match(js, /FOCUS_GAP = 60000/);
assert.match(js, /ensureOk/);
assert.match(js, /allow_emails|allowed/);
assert.match(js, /사업자 정보/);
assert.match(js, /이용약관/);
assert.match(js, /개인정보처리방침/);
assert.match(js, /상품\/환불 안내/);
assert.match(js, /\/about\.html/);
assert.match(js, /\/terms\.html/);
assert.match(js, /\/privacy\.html/);
assert.match(js, /\/shop-info\.html/);
assert.match(js, /2026-서울성북-1401/);
assert.match(js, /intro-guest/);
assert.match(js, /vr:user/);
assert.doesNotMatch(js, /stevejean77@gmail\.com/); // 이메일은 서버 _is_admin 으로만

const index = await read('index.html');
assert.match(index, /src="js\/maintenance\.js"/);

const game = await read('js/game.js');
assert.match(game, /VRMaint && !await window\.VRMaint\.ensureOk\(\)/);
assert.equal((game.match(/VRMaint\.ensureOk/g) || []).length, 2);

const { window, document } = parseHTML('<!doctype html><html><body><div id="start-screen"></div><div id="game" class="hidden"></div></body></html>');
const toasts = [];
window.VRCloud = { get user() { return { id: 'u1' }; }, get sb() { return {}; } };
window.VRGem = { toast: m => toasts.push(m) };
window.VRCompany = { name: '엔터인코드', ceo: '장윤석', brn: '738-44-01302', address: '서울시 성북구 보국문로 95, 303호', phone: '070-5275-5361', mailOrderNo: '2026-서울성북-1401' };
window.__MAINT_MOCK = async (fn) => {
  if (fn === 'maintenance_status') {
    return { on: true, kind: 'coming_soon', title: '곧 오픈 / COMING SOON', message: 'Violence Royale : The Abyss Gate 곧 오픈합니다', ends_at: null, allowed: false };
  }
  return null;
};
Object.assign(globalThis, { window, document, setTimeout, clearTimeout, addEventListener: (...a) => window.addEventListener(...a) });
window.Date = Date;
window.eval(js);
assert.equal(typeof window.VRMaint.ensureOk, 'function');
assert.equal(window.VRMaint.isComingSoon({ kind: 'coming_soon' }), true);
assert.equal(window.VRMaint.isComingSoon({ message: '곧 오픈합니다' }), true);
assert.equal(window.VRMaint.isComingSoon({ kind: 'maintenance', message: '점검 중' }), false);
window.VRMaint.show({ on: true, kind: 'coming_soon', title: '곧 오픈 / COMING SOON', message: 'Violence Royale : The Abyss Gate 곧 오픈합니다' }, false);
const ov = document.getElementById('vr-maint');
assert(ov); assert(!ov.classList.contains('hidden'));
assert.match(ov.textContent, /곧 오픈 \/ COMING SOON/);
assert.match(ov.textContent, /Violence Royale : The Abyss Gate 곧 오픈합니다/);
assert.match(ov.textContent, /사업자 정보/);
assert.match(ov.textContent, /이용약관/);
assert.match(ov.textContent, /개인정보처리방침/);
assert.match(ov.textContent, /상품\/환불 안내/);
assert.match(ov.textContent, /통신판매업신고번호 2026-서울성북-1401/);
assert.match(ov.textContent, /엔터인코드/);
assert(ov.querySelector('a[href="/terms.html"]'));
assert(ov.querySelector('a[href="/privacy.html"]'));
assert(ov.querySelector('a[href="/shop-info.html"]'));
assert(ov.querySelector('a[href="/about.html"]'));
assert(document.getElementById('mt-admin').classList.contains('hidden'));
assert(ov.querySelector('#mt-login-toggle'));
window.VRMaint.hide();
assert(ov.classList.contains('hidden'));

const ok = window.VRMaint._apply({ on: true, message: 'x', allowed: true, kind: 'coming_soon' }, true);
assert.equal(ok, true);
assert.match(toasts[0] || '', /통과했어요|관리자라서/);

console.log('maintenance tests: OK');
