// 스페셜 소환 (픽업 하지혜 10440): 확률 합 100% · 50회 천장 · 풀(프리미엄 UR − 픽업, MR 없음) · 가드/반복 실행/RLS · 상점 소환권 SKU · 확률 팝업 — 2026-11-13
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { PGlite } from '@electric-sql/pglite';
const rd = f => readFile(new URL(`../${f}`, import.meta.url), 'utf8');
const ids = ['7703759698107299042', '7692130048193495360'];
const files = await Promise.all(['staging', 'production'].map(e => rd(`supabase/special_summon_${e}.sql`)));
const body = s => s.slice(s.indexOf('-- ===== SPECIAL SUMMON'));
assert.equal(body(files[0]), body(files[1]), 'staging/production bodies identical');
for (const [i, s] of files.entries()) { assert.match(s, new RegExp(`is distinct from '${ids[i]}'`)); assert.match(s, /notify pgrst, 'reload schema';\s*$/); }
assert.doesNotMatch(files[0], /\b(?:truncate|delete from|drop table|drop function|alter table [^;]* drop)\b/i, 'add-only');
// ----- 설정: SQL ↔ js/special-summon.js ↔ 데이터 -----
const js = await rd('js/special-summon.js');
const win = { STORY_DATA: { gacha: {} } }; vm.runInNewContext(js, { window: win, document: {}, console });
const S = win.VRSpecial, C = JSON.parse(JSON.stringify(S.CONFIG)), SPU = [...S.PREMIUM_UR];
const sum = Object.values(C.rates).reduce((a, b) => a + b, 0);
assert.equal(sum, 10000, 'rates sum 100%');
assert.deepEqual(C.rates, { 'NORMAL': 5000, 'RARE': 3000, 'HIGH RARE': 1000, 'SUPER RARE': 800, pickup: 100, other_ur: 100 }, 'N50 R30 HR10 SR8 pickup1 otherUR1');
const ins = /insert into public\.special_banners\(id,pickup_id,starts_at,ends_at,pity_limit,rates\)\s*values\('([^']+)','([^']+)','([^']+)',null,(\d+),'([^']+)'\)/.exec(files[0]);
assert.ok(ins, 'banner insert'); assert.equal(ins[1], C.banner_id); assert.equal(ins[2], C.pickup_id); assert.equal(+ins[4], C.pity); assert.equal(C.pity, 50);
assert.deepEqual(JSON.parse(ins[5]), C.rates, 'SQL rates = client rates');
assert.equal(new Date(ins[3].replace(' ', 'T').replace(/\+09$/, '+09:00')).getTime(), new Date(C.starts_at).getTime());
const prem = await rd('supabase/gacha_premium_ur.sql');
const premIds = [...prem.slice(prem.indexOf('insert into public.story_premium_ur')).split(';')[0].matchAll(/\('(\d+)'/g)].map(m => m[1]);
assert.deepEqual(SPU, premIds, 'client PREMIUM_UR = story_premium_ur');
assert.ok(!premIds.includes('10440'), 'pickup is not in premium UR');
const csv = (await rd('data/cards.csv')).split('\n'); const row = id => csv.find(l => l.startsWith(id + ',')).split(',');
assert.equal(row('10440')[1], '하지혜'); assert.equal(row('10440')[5], 'ULTRA RARE');
for (const id of premIds) assert.equal(row(id)[5], 'ULTRA RARE', `${id} UR`);
const shop = await rd('js/shop.js'); assert.match(shop, /data-sp-rates/); assert.doesNotMatch(shop, /일반 소환권으로|픽업 소환은 아직/);
const story = await rd('js/story.js'); assert.match(story, /key: 'pickup', label: '스페셜', img: 'special'/); assert.match(story, /준비 중/);
assert.match(await rd('index.html'), /<script src="js\/special-summon\.js"><\/script>/);
{ // _shop_apply = 원본 + special_tickets 분기만
  const orig = /create or replace function public\._shop_apply[\s\S]*?end \$\$;/.exec(await rd('supabase/shop_bm_staging.sql'))[0];
  const mine = /create or replace function public\._shop_apply[\s\S]*?end \$\$;/.exec(files[0])[0]
    .replace(/ n_special int := [^\n]*\n/, '').replace(/ if n_special < 0 [^\n]*\n/, '').replace(/ if n_special <> 0 then[\s\S]*?end if;\n/, '');
  assert.equal(mine, orig, '_shop_apply unchanged except special_tickets');
}
// ----- DB: PGlite -----
const N = Array.from({ length: 4 }, (_, i) => `2000${i}`), R = ['30001', '30002'], H = ['40001'], SR = ['50001', '50002'];
for (const [i, sql] of files.entries()) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
    create table story_card_pool(id text primary key, name text, grade text, gacha boolean);
    create table story_premium_ur(id text primary key, name text);
    create table story_gacha_log(user_id uuid, card_id text, grade text, kind text);
    create table story_gacha(user_id uuid primary key, tickets int default 0, last_draw date, updated_at timestamptz);
    create table story_save(user_id uuid primary key, data jsonb);
    create function _story_lock(u uuid) returns jsonb language sql as $$ insert into story_save values(u,'{"owned":[]}') on conflict do nothing; select data from story_save where user_id=u $$;
    create function _story_owned(d jsonb) returns jsonb language sql as $$ select coalesce(d->'owned','[]') $$;
    create function _story_new_card(c text) returns jsonb language sql as $$ select jsonb_build_object('id',c,'uid',gen_random_uuid()::text) $$;
    create function _story_save(u uuid, d jsonb) returns jsonb language sql as $$ update story_save set data=d where user_id=u returning data $$;
    create table shop_products(sku text primary key, reward jsonb);
    insert into shop_products values ('ticket_10','{"tickets":10}'),('ticket_45','{"tickets":45}'),('ticket_160','{"tickets":160}'),('ticket_220','{"tickets":220}'),('pass_1','{"daily":{"tickets":1}}');
    create function public._shop_apply(p_uid uuid, p_grant jsonb, p_reason text, p_ref text) returns jsonb language plpgsql as $$ begin return '{}'; end $$;`);
  const pool = [...N.map(x => [x, 'NORMAL']), ...R.map(x => [x, 'RARE']), ...H.map(x => [x, 'HIGH RARE']), ...SR.map(x => [x, 'SUPER RARE']),
    ...premIds.map(x => [x, 'ULTRA RARE']), ['10440', 'ULTRA RARE'], ['90001', 'ULTRA RARE'], ['91001', 'MYTHIC RARE']];
  for (const [id, g] of pool) await db.query('insert into story_card_pool values($1,$1,$2,true)', [id, g]);
  await db.query("insert into story_card_pool values('29999','hidden','NORMAL',false)");
  for (const id of premIds) await db.query('insert into story_premium_ur values($1,$1)', [id]);
  const guarded = sql.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
  await assert.rejects(db.exec(guarded), /STOP: .* only/);
  await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[i]}'::text$$;`);
  await db.exec(guarded); await db.exec(guarded);   // idempotent
  assert.deepEqual((await db.query("select sku, reward from shop_products order by sku")).rows.map(r => [r.sku, r.reward]),
    [['pass_1', { daily: { tickets: 1 } }], ['ticket_10', { special_tickets: 10 }], ['ticket_160', { special_tickets: 160 }], ['ticket_220', { special_tickets: 220 }], ['ticket_45', { special_tickets: 45 }]], 'ticket SKUs → special tickets, passes untouched');
  // 등급 경계 (만분율)
  const gr = async r => (await db.query("select public._special_grade($1, rates) g from special_banners", [r])).rows[0].g;
  for (const [r, g] of [[0, 'NORMAL'], [0.4999, 'NORMAL'], [0.5, 'RARE'], [0.7999, 'RARE'], [0.8, 'HIGH RARE'], [0.9, 'SUPER RARE'], [0.9799, 'SUPER RARE'], [0.98, 'pickup'], [0.9899, 'pickup'], [0.99, 'other_ur'], [0.99999, 'other_ur']]) assert.equal(await gr(r), g, `r=${r}`);
  await assert.rejects(db.query(`select public._special_grade(0.1, '{"NORMAL":5000}')`), /invalid rates/);
  const a = crypto.randomUUID(), b = crypto.randomUUID(); await db.query('insert into auth.users values($1),($2)', [a, b]);
  const as = async (uid, q, p = [], keep = true) => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${uid}';`); try { const r = await db.query(q, p); await db.exec(keep ? 'commit' : 'rollback'); return r.rows[0]?.r; } catch (e) { await db.exec('rollback'); throw e; } };
  let st = await as(a, 'select public.special_summon_status() r');
  assert.equal(st.ok, true); assert.equal(st.tickets, 0); assert.equal(st.misses, 0); assert.equal(st.banner.pickup_id, '10440'); assert.equal(st.banner.open, true); assert.equal(st.banner.pity, 50);
  assert.ok(!st.pool.some(c => c.id === '29999' || c.grade === 'MYTHIC RARE' || c.grade === 'ULTRA RARE'), 'status pool N~SR gacha only');
  assert.deepEqual(st.premium_ur.map(c => c.id), premIds);
  let d = await as(a, "select public.special_summon_draw('hajihye-20261113', 1) r"); assert.equal(d.ok, false); assert.equal(d.reason, 'special_tickets');
  await assert.rejects(as(a, "select public.special_summon_draw('hajihye-20261113', 5) r"), /invalid count/);
  await assert.rejects(as(a, "select public._shop_apply($1, '{\"special_tickets\":999}', 'x', 'y') r", [a]), /permission denied/);
  await assert.rejects(as(a, 'update special_wallet set tickets = 999'), /permission denied/);
  await assert.rejects(as(a, 'insert into special_pity values ($1, $2, 0)', [a, C.banner_id]), /permission denied/);
  await assert.rejects(db.exec(`begin; set local role anon; select public.special_summon_status();`), /permission denied/); await db.exec('rollback');
  // 상점 지급 경로 (_shop_apply special_tickets)
  const g = (await db.query("select public._shop_apply($1, (select reward from shop_products where sku='ticket_220'), 'shop:ticket_220', 'r1') o", [a])).rows[0].o;
  assert.equal(g.special_tickets, 220); assert.equal((await db.query('select count(*)::int n from story_gacha')).rows[0].n, 0, 'no normal tickets granted');
  await db.query("select public._shop_apply($1, '{\"special_tickets\":3000}', 'test', 'r2')", [a]);
  await assert.rejects(db.query("select public._shop_apply($1, '{\"special_tickets\":-1}', 'test', 'r3')", [a]), /invalid grant/);
  assert.equal(await as(b, 'select count(*)::int r from special_wallet'), 0, 'RLS: others hidden');
  assert.equal(await as(a, 'select count(*)::int r from special_wallet'), 1, 'RLS: own visible');
  // 천장: 픽업 확률 0으로 두고 49회 미획득 → 50회째 확정, 횟수 초기화
  await db.query(`update special_banners set rates='{"NORMAL":5000,"RARE":3000,"HIGH RARE":1000,"SUPER RARE":800,"pickup":0,"other_ur":200}'`);
  let seen = [];
  for (let k = 0; k < 4; k++) { d = await as(a, "select public.special_summon_draw('hajihye-20261113', 10) r"); assert.equal(d.ok, true); seen.push(...d.cards); }
  for (let k = 0; k < 9; k++) { d = await as(a, "select public.special_summon_draw('hajihye-20261113', 1) r"); seen.push(...d.cards); }
  assert.equal(seen.length, 49); assert.ok(!seen.some(c => c.card_id === '10440')); assert.equal(d.misses, 49);
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 1) r");
  assert.equal(d.cards[0].card_id, '10440'); assert.equal(d.cards[0].guaranteed, true); assert.equal(d.misses, 0, 'pity resets');
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 10) r"); assert.equal(d.misses, 10); assert.ok(!d.cards.some(c => c.guaranteed));
  assert.equal((await as(b, 'select public.special_summon_status() r')).misses, 0, 'pity per user');
  // 분포 (실제 확률): 3000회
  await db.query(`update special_banners set rates='{"NORMAL":5000,"RARE":3000,"HIGH RARE":1000,"SUPER RARE":800,"pickup":100,"other_ur":100}'`);
  await db.query("update special_pity set misses=0");
  const cnt = {}, ur = new Set(); let total = 0;
  for (let k = 0; k < 316; k++) { d = await as(a, "select public.special_summon_draw('hajihye-20261113', 10) r"); assert.equal(d.ok, true, JSON.stringify(d));
    for (const c of d.cards) { total++; const key = c.card_id === '10440' ? 'pickup' : c.grade; cnt[key] = (cnt[key] || 0) + 1; if (c.grade === 'ULTRA RARE' && c.card_id !== '10440') ur.add(c.card_id); assert.ok(!['29999', '90001', '91001'].includes(c.card_id), `pool leak ${c.card_id}`); } }
  for (const [k, p] of [['NORMAL', .5], ['RARE', .3], ['HIGH RARE', .1], ['SUPER RARE', .08]]) assert.ok(Math.abs(cnt[k] / total - p) < 0.035, `${k} ${cnt[k]}/${total}`);
  assert.ok([...ur].every(id => premIds.includes(id)), 'other UR from premium list only');
  assert.ok((cnt.pickup || 0) >= 2 && (cnt['ULTRA RARE'] || 0) < 80, `UR counts ${cnt.pickup}/${cnt['ULTRA RARE']}`);
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 10) r"); assert.equal(d.ok, false); assert.equal(d.reason, 'special_tickets');
  assert.equal(d.tickets, 0);
  const logs = (await db.query("select count(*)::int n from special_summon_log")).rows[0].n, glog = (await db.query("select count(*)::int n from story_gacha_log where kind='special'")).rows[0].n;
  assert.equal(logs, 3220); assert.equal(glog, 3220);
  assert.equal((await db.query('select jsonb_array_length(data->\'owned\') n from story_save where user_id=$1', [a])).rows[0].n, 3220, 'cards saved');
  await db.query("update special_banners set ends_at = now() - interval '1 minute', starts_at = now() - interval '2 day'");
  await db.query("select public._shop_apply($1, '{\"special_tickets\":10}', 'test', 'r4')", [a]);
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 1) r"); assert.equal(d.reason, 'closed');
  await db.close();
}
// ----- 확률 팝업 (클라이언트 계산): 인재별 확률 = 등급 확률 / 인원 -----
const POOL = [...N.map(id => ({ id, name: `n${id}`, grade: 'NORMAL' })), ...R.map(id => ({ id, name: `r${id}`, grade: 'RARE' })), { id: '40001', name: 'h', grade: 'HIGH RARE' }, { id: '50001', name: 's', grade: 'SUPER RARE' }];
const w2 = { STORY_DATA: { gacha: { rates: [0.7, 0.2, 0.065, 0.03, 0.005], special: [0.5, 0.3, 0.16, 0.032, 0.008] } }, TCG: { POOL, cardById: id => ({ id, name: `u${id}` }) } };
vm.runInNewContext(js, { window: w2, document: {}, console });
const html = w2.VRSpecial.ratesHtml();
for (const t of ['스페셜 소환', '프리미엄 소환', '일반 소환', 'UR 픽업 하지혜', '50회째', '1명당 12.5%', '1명당 1%', `${premIds.length}명 · 1명당 ${+(1 / premIds.length).toFixed(4)}%`]) assert.ok(html.includes(t), `popup has ${t}`);
console.log(`Special summon: rates 100% (N50 R30 HR10 SR8 pickup1 UR1), pity 50 resets, per-user, pool = premium UR − pickup (no MR/hidden), shop SKUs → special tickets, guards/idempotent/RLS, popup per-character OK`);
