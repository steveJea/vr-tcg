// 점검 모드: 가드·상태 함수·폴링 없음·관리자 우회·전투 시작 차단.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/maintenance_staging.sql');
const production = await read('supabase/maintenance_production.sql');
const checkS = await read('supabase/maintenance_check_staging.sql');
const checkP = await read('supabase/maintenance_check_production.sql');
const onS = await read('supabase/maintenance_on_staging.sql');
const offS = await read('supabase/maintenance_off_staging.sql');
const onP = await read('supabase/maintenance_on_production.sql');
const offP = await read('supabase/maintenance_off_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(production, /아직 실행하지 마세요/);
assert.match(onP, /아직 실행하지 마세요/);
assert.match(offP, /아직 실행하지 마세요/);
for (const sql of [staging, production]) {
  assert.match(sql, /create table if not exists public.maintenance/);
  assert.match(sql, /maintenance_status\(\)/);
  assert.match(sql, /grant execute on function public.maintenance_status\(\), public.maintenance_install_ok\(\) to anon, authenticated/);
  assert.match(sql, /ends_at/);
  assert.doesNotMatch(sql, /setInterval/);
}
assert.match(checkS, /7703759698107299042/);
assert.match(checkP, /7692130048193495360/);
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);
assert.match(onS, /set is_on = true/);
assert.match(offS, /set is_on = false/);
assert.match(onS, /7703759698107299042/);
assert.match(offP, /7692130048193495360/);

const js = await read('js/maintenance.js');
assert.doesNotMatch(js, /setInterval/);
assert.match(js, /FOCUS_GAP = 60000/);
assert.match(js, /ensureOk/);
assert.match(js, /admin_check/);
assert.match(js, /관리자로 들어가기/);
assert.match(js, /vr:user/);
assert.match(js, /visibilitychange/);
assert.match(js, /start-screen/);

const index = await read('index.html');
assert.match(index, /src="js\/maintenance\.js"/);

const game = await read('js/game.js');
assert.match(game, /VRMaint && !await window\.VRMaint\.ensureOk\(\)/);
assert.equal((game.match(/VRMaint\.ensureOk/g) || []).length, 2);

const { window, document } = parseHTML('<!doctype html><html><body><div id="start-screen"></div><div id="game" class="hidden"></div></body></html>');
const toasts = [];
const calls = [];
window.VRCloud = { get user() { return { id: 'u1' }; }, get sb() { return {}; } };
window.VRGem = { toast: m => toasts.push(m) };
window.__MAINT_MOCK = async (fn) => {
  calls.push(fn);
  if (fn === 'maintenance_status') return { on: true, message: '서버 점검입니다.', ends_at: '2026-11-19T18:00:00+09:00' };
  if (fn === 'admin_check') return { admin: false };
  return null;
};
Object.assign(globalThis, { window, document, setTimeout, clearTimeout, addEventListener: (...a) => window.addEventListener(...a) });
window.Date = Date;
const src = await read('js/maintenance.js');
window.eval(src);
assert.equal(typeof window.VRMaint.ensureOk, 'function');
assert.match(window.VRMaint._kstUntil('2026-11-19T18:00:00+09:00'), /2026년 11월 19일 18:00까지/);
window.VRMaint.show({ on: true, message: '서버 점검입니다.', ends_at: '2026-11-19T18:00:00+09:00' }, false);
const ov = document.getElementById('vr-maint');
assert(ov); assert(!ov.classList.contains('hidden'));
assert.match(ov.textContent, /점검 중/);
assert.match(ov.textContent, /서버 점검입니다/);
assert.match(ov.textContent, /18:00까지/);
assert(document.getElementById('mt-admin').classList.contains('hidden'));
window.VRMaint.hide();
assert(ov.classList.contains('hidden'));

const ok = window.VRMaint._apply({ on: true, message: 'x' }, true);
assert.equal(ok, true);
assert.match(toasts[0] || '', /관리자라서/);

console.log('maintenance tests: OK');
