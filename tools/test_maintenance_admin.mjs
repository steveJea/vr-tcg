// 관리자 점검 켜기/끄기: admin_guard RPC, anon 실행 금지, 기존 admin 페이지 탭.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/maintenance_admin_staging.sql');
const production = await read('supabase/maintenance_admin_production.sql');
const checkS = await read('supabase/maintenance_admin_check_staging.sql');
const checkP = await read('supabase/maintenance_admin_check_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(production, /아직 실행하지 마세요/);
assert.match(checkP, /아직 실행하지 마세요/);
for (const sql of [staging, production]) {
  assert.match(sql, /perform public\._admin_guard\(\)/);
  assert.match(sql, /maintenance_admin_get\(\)/);
  assert.match(sql, /maintenance_admin_set\(/);
  assert.match(sql, /grant execute on function\s+public.maintenance_admin_get\(\),\s+public.maintenance_admin_set\(boolean, text, timestamptz\)\sto authenticated/s);
  assert.match(sql, /not has_function_privilege\('anon'/);
  assert.match(sql, /revoke all on function[\s\S]*from public, anon, authenticated/);
}
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);

const js = await read('js/admin.js');
assert.match(js, /data-tab="maint"/);
assert.match(js, />점검</);
assert.match(js, /maintenance_admin_get/);
assert.match(js, /maintenance_admin_set/);
assert.match(js, /Asia\/Seoul/);
assert.match(js, /datetime-local/);
assert.match(js, /\+09:00/);
assert.match(js, /점검을 켜면 일반 플레이어는 게임에 들어가지 못해요/);

const maint = await read('js/maintenance.js');
assert.match(maint, /admin_check/);
assert.match(maint, /관리자라서 들어왔어요/);

const { window, document } = parseHTML(await read('admin.html'));
const rpcCalls = [];
let state = {
  ok: true, is_on: true, on: true,
  message: '지금은 점검 중이에요. 잠시 후 다시 와 주세요.',
  ends_at: '2026-11-19T09:00:00.000Z',
  updated_at: '2026-11-19T01:00:00.000Z'
};
window.__ADMIN_NO_BOOT = true;
window.__ADMIN_MOCK = {
  cloud: { ready: true, user: { email: 'stevejean77@gmail.com' }, sb: {}, login() {} },
  rpc: async (name, args) => {
    rpcCalls.push({ name, args });
    if (name === 'admin_check') return { admin: true, email: 'stevejean77@gmail.com' };
    if (name === 'admin_list_users') return [];
    if (name === 'maintenance_admin_get') return { ...state };
    if (name === 'maintenance_admin_set') {
      state = { ok: true, is_on: !!args.p_is_on, on: !!args.p_is_on, message: args.p_message, ends_at: args.p_ends_at, updated_at: '2026-11-19T01:10:00.000Z' };
      return { ...state };
    }
    return null;
  }
};
window.VRCloud = window.__ADMIN_MOCK.cloud;
Object.assign(globalThis, { window, document, localStorage: { getItem() { return null; }, setItem() {} } });
window.alert = () => {};
window.confirm = () => true;
window.fetch = async () => ({ text: async () => 'id,name,grade\n' });
window.eval(js);
assert.equal(typeof window.VRAdmin.boot, 'function');
await window.VRAdmin.boot();
await new Promise(r => setTimeout(r, 0));
await new Promise(r => setTimeout(r, 0));
const maintBtn = [...document.querySelectorAll('[data-tab]')].find(b => b.dataset.tab === 'maint');
assert(maintBtn, '점검 탭이 있어야 해요');
maintBtn.click();
await new Promise(r => setTimeout(r, 0));
await new Promise(r => setTimeout(r, 0));
const form = document.getElementById('ad-mform');
assert(form, '점검 폼이 있어야 해요');
assert.match(form.textContent, /지금 켜짐/);
const mon = document.getElementById('ad-mon');
assert(mon.hasAttribute('checked') || mon.checked);
assert.match(document.getElementById('ad-mmsg').value, /점검 중/);
assert.equal(document.getElementById('ad-mends').value, '2026-11-19T18:00');

console.log('test_maintenance_admin ok');
