// 관리자 점검 탭 + production/staging admin SQL 가드.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const production = await read('supabase/maintenance_admin_production.sql');
const checkP = await read('supabase/maintenance_admin_check_production.sql');
const staging = await read('supabase/maintenance_coming_soon_staging.sql');
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(staging, /7703759698107299042/);
assert.match(production, /maintenance_admin_set\(boolean, text, timestamptz, text, text, text\[\]\)/);
assert.match(production, /p_allow_emails/);
assert.match(production, /p_kind/);
assert.doesNotMatch(production, /grant execute on function[\s\S]*maintenance_admin_set[\s\S]*to anon/);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);
assert.match(checkP, /7692130048193495360/);

const html = await read('admin.html');
const js = await read('js/admin.js');
assert.match(js, /data-tab="maint"/);
assert.match(js, /p_allow_emails/);
assert.match(js, /coming_soon/);
assert.match(js, /허용 이메일/);

const { window, document } = parseHTML(html.includes('<body') ? html : `<!doctype html><html><body>
  <div id="ad-who"></div><div id="ad-root"></div><div id="ad-modal" class="hidden"><button id="ad-close"></button></div>
</body></html>`);
if (!document.getElementById('ad-root')) {
  document.body.innerHTML = '<div id="ad-who"></div><div id="ad-root"></div><div id="ad-modal" class="hidden"><button id="ad-close"></button></div>';
}
const rpcCalls = [];
let state = {
  ok: true,
  is_on: true,
  on: true,
  kind: 'coming_soon',
  title: '곧 오픈 / COMING SOON',
  message: 'Violence Royale : The Abyss Gate 곧 오픈합니다',
  ends_at: '2026-11-19T09:00:00.000Z',
  updated_at: '2026-11-19T01:00:00.000Z',
  allow_emails: []
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
      state = { ok: true, is_on: !!args.p_is_on, on: !!args.p_is_on, message: args.p_message, ends_at: args.p_ends_at, title: args.p_title || '', kind: args.p_kind, allow_emails: args.p_allow_emails || [], updated_at: '2026-11-19T01:10:00.000Z' };
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
assert.match(form.textContent, /곧 오픈/);
const mon = document.getElementById('ad-mon');
assert(mon.hasAttribute('checked') || mon.checked);
assert.match(document.getElementById('ad-mmsg').value, /곧 오픈합니다/);
assert.equal(document.getElementById('ad-mkind').value, 'coming_soon');
assert.match(document.getElementById('ad-mtitle').value, /COMING SOON/);
assert.equal(document.getElementById('ad-memails').value.trim(), '');
assert.equal(document.getElementById('ad-mends').value, '2026-11-19T18:00');

console.log('test_maintenance_admin ok');
