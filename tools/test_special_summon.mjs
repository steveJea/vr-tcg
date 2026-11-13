// 스페셜 소환 (픽업 하지혜 10440): 확률 합 100% · UR 50회 천장 · 그 외 UR 2번 뒤 하지혜 확정 · 풀(프리미엄 UR − 픽업, MR 없음) · 가드/반복 실행/RLS · 상점 소환권 SKU · 확률 팝업 — 2026-11-13
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { execSync } from 'node:child_process';
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
const ins = /insert into public\.special_banners\(id,pickup_id,starts_at,ends_at,pity_limit,rates\)\s*values\('([^']+)','([^']+)','([^']+)','([^']+)',(\d+),'([^']+)'\)/.exec(files[0]);
assert.ok(ins, 'banner insert'); assert.equal(ins[1], C.banner_id); assert.equal(ins[2], C.pickup_id); assert.equal(+ins[5], C.pity); assert.equal(C.pity, 50);
assert.deepEqual(JSON.parse(ins[6]), C.rates, 'SQL rates = client rates');
assert.equal(new Date(ins[3].replace(' ', 'T').replace(/\+09$/, '+09:00')).getTime(), new Date(C.starts_at).getTime());
const kst = t => new Date(t.replace(' ', 'T').replace(/\+09$/, '+09:00')).getTime();
assert.equal(kst(ins[4]), new Date(C.ends_at).getTime(), 'SQL ends_at = client ends_at'); assert.equal(new Date(C.ends_at).toISOString(), '2026-11-30T14:59:59.000Z', '하지혜 픽업 11/30 23:59:59 KST 마감');
for (const f of files) assert.match(f, /update public\.special_banners set ends_at='2026-11-30 23:59:59\+09' where id='hajihye-20261113' and ends_at is null;/, 'existing row gets the end date once');
{ const e = await rd('supabase/special_summon_end_20261130_staging.sql'); assert.match(e, /'7703759698107299042'/); assert.doesNotMatch(e, /7692130048193495360/); assert.match(e, /set ends_at='2026-11-30 23:59:59\+09' where id='hajihye-20261113'/); }
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
async function baseDb(db) {
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
}
for (const [i, sql] of files.entries()) {
  const db = new PGlite(); await baseDb(db);
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
  const setRates = r => db.query('update special_banners set rates=$1', [JSON.stringify(r)]);
  const rates = (o = {}) => ({ 'NORMAL': 0, 'RARE': 0, 'HIGH RARE': 0, 'SUPER RARE': 0, pickup: 0, other_ur: 0, ...o });
  const setPity = (m, o) => db.query('update special_pity set misses=$1, off_urs=$2 where user_id=$3', [m, o, a]);
  const pull = async n => { const r = await as(a, `select public.special_summon_draw('hajihye-20261113', ${n}) r`); assert.equal(r.ok, true, JSON.stringify(r)); return r; };
  // (1) UR 천장 50: UR 없이 49회 → 50회째 UR 확정, 어떤 UR이든 초기화
  await setRates(rates({ 'NORMAL': 5000, 'RARE': 3000, 'HIGH RARE': 1000, 'SUPER RARE': 1000 }));
  let seen = [];
  for (let k = 0; k < 4; k++) seen.push(...(d = await pull(10)).cards);
  for (let k = 0; k < 9; k++) seen.push(...(d = await pull(1)).cards);
  assert.equal(seen.length, 49); assert.ok(!seen.some(c => c.grade === 'ULTRA RARE' || c.guaranteed)); assert.equal(d.misses, 49);
  d = await pull(1); assert.equal(d.cards[0].grade, 'ULTRA RARE'); assert.equal(d.cards[0].guarantee, 'ur_pity'); assert.equal(d.misses, 0, 'UR pity resets');
  // (2) 천장 UR도 평소 비율 픽업:그 외 = 1:1
  await setRates(rates({ 'NORMAL': 5000, 'RARE': 3000, 'HIGH RARE': 1000, 'SUPER RARE': 998, pickup: 1, other_ur: 1 }));
  let pk = 0;
  for (let k = 0; k < 200; k++) { await setPity(49, 0); d = await pull(1); const c = d.cards[0];
    assert.equal(c.grade, 'ULTRA RARE'); assert.equal(c.guarantee, 'ur_pity'); assert.equal(d.misses, 0); assert.ok(c.card_id === '10440' || premIds.includes(c.card_id));
    if (c.card_id === '10440') { pk++; assert.equal(d.off_urs, 0); } else assert.equal(d.off_urs, 1); }
  assert.ok(pk > 65 && pk < 135, `pity UR pickup share ${pk}/200`);
  // 천장 UR이 픽업 확정과 겹치면 하지혜
  await setPity(49, 2); d = await pull(1); assert.equal(d.cards[0].card_id, '10440'); assert.equal(d.off_urs, 0);
  // (3) 픽업 확정: 그 외 UR 2번 → 3번째 UR 하지혜, 하지혜면 0
  await setRates(rates({ other_ur: 10000 })); await setPity(0, 0);
  d = await pull(10);
  assert.deepEqual(d.cards.map(c => c.card_id === '10440' ? 'P' : 'o').join(''), 'ooPooPooPo');
  assert.deepEqual(d.cards.map(c => c.guarantee), [null, null, 'pickup', null, null, 'pickup', null, null, 'pickup', null]);
  assert.equal(d.misses, 0); assert.equal(d.off_urs, 1);
  st = await as(a, 'select public.special_summon_status() r'); assert.equal(st.off_urs, 1); assert.equal(st.banner.pickup_after, 2);
  // 운 좋으면 하지혜가 먼저 (확정 아님) → 0
  await setRates(rates({ pickup: 10000 })); d = await pull(1); assert.equal(d.cards[0].card_id, '10440'); assert.equal(d.cards[0].guaranteed, false); assert.equal(d.off_urs, 0);
  assert.equal((await as(b, 'select public.special_summon_status() r')).misses, 0, 'pity per user');
  // 분포 (실제 확률) + 규칙 불변식: UR 사이 50회 넘게 안 비고, 그 외 UR 3연속 없음, 서버 카운터 = 로컬 계산
  await setRates(C.rates); await setPity(0, 0);
  const cnt = {}, ur = new Set(); let total = 0, mm = 0, oo = 0;
  const left = async () => (await db.query('select tickets from special_wallet where user_id=$1', [a])).rows[0].tickets;
  while (await left() >= 10) { d = await pull(10);
    for (const c of d.cards) { total++; const key = c.card_id === '10440' ? 'pickup' : c.grade; cnt[key] = (cnt[key] || 0) + 1; assert.ok(!['29999', '90001', '91001'].includes(c.card_id), `pool leak ${c.card_id}`);
      if (c.grade === 'ULTRA RARE') { mm = 0; if (c.card_id === '10440') oo = 0; else { ur.add(c.card_id); oo++; } } else mm++;
      assert.ok(mm < 50 && oo <= 2, 'rule invariant'); }
    assert.equal(d.misses, mm); assert.equal(d.off_urs, oo); }
  for (const [k, p] of [['NORMAL', .5], ['RARE', .3], ['HIGH RARE', .1], ['SUPER RARE', .08]]) assert.ok(Math.abs(cnt[k] / total - p) < 0.035, `${k} ${cnt[k]}/${total}`);
  assert.ok([...ur].every(id => premIds.includes(id)), 'other UR from premium list only');
  assert.ok((cnt.pickup || 0) >= 2 && (cnt['ULTRA RARE'] || 0) < 90, `UR counts ${cnt.pickup}/${cnt['ULTRA RARE']}`);
  while (await left() >= 1) await pull(1);
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 10) r"); assert.equal(d.ok, false); assert.equal(d.reason, 'special_tickets');
  assert.equal(d.tickets, 0);
  const logs = (await db.query("select count(*)::int n from special_summon_log")).rows[0].n, glog = (await db.query("select count(*)::int n from story_gacha_log where kind='special'")).rows[0].n;
  assert.equal(logs, 3220); assert.equal(glog, 3220);
  assert.equal((await db.query("select count(*)::int n from special_summon_log where guaranteed <> (guarantee is not null)")).rows[0].n, 0);
  assert.equal((await db.query('select jsonb_array_length(data->\'owned\') n from story_save where user_id=$1', [a])).rows[0].n, 3220, 'cards saved');
  await db.query("update special_banners set ends_at = now() - interval '1 minute', starts_at = now() - interval '2 day'");
  await db.query("select public._shop_apply($1, '{\"special_tickets\":10}', 'test', 'r4')", [a]);
  d = await as(a, "select public.special_summon_draw('hajihye-20261113', 1) r"); assert.equal(d.reason, 'closed');
  await db.close();
}
// ----- v1(#583) 설치 위에 v2 다시 실행: 컬럼 추가만, 카운터는 로그로 한 번 다시 계산 -----
{
  const db = new PGlite(); await baseDb(db);
  const prep = q => q.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[0]}'::text$$;`);
  await db.exec(prep(execSync('git show 86a6388b01aa1741eeda724b8b257c98177a429e:supabase/special_summon_staging.sql', { cwd: new URL('..', import.meta.url), encoding: 'utf8' })));   // #583 v1
  const a = crypto.randomUUID(); await db.query('insert into auth.users values($1)', [a]);
  await db.query("select public._shop_apply($1, '{\"special_tickets\":20}', 'test', 'r')", [a]);
  const pull = async n => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${a}';`); const r = (await db.query(`select public.special_summon_draw('hajihye-20261113', ${n}) r`)).rows[0].r; await db.exec('commit'); return r; };
  const R0 = { 'NORMAL': 0, 'RARE': 0, 'HIGH RARE': 0, 'SUPER RARE': 0, pickup: 0, other_ur: 0 };
  await db.query('update special_banners set rates=$1', [JSON.stringify({ ...R0, other_ur: 10000 })]); for (let k = 0; k < 5; k++) await pull(1);
  await db.query('update special_banners set rates=$1', [JSON.stringify({ ...R0, 'NORMAL': 10000 })]); for (let k = 0; k < 3; k++) await pull(1);
  assert.equal((await db.query('select misses from special_pity')).rows[0].misses, 8, 'v1 counted since pickup');
  await db.exec(prep(files[0])); await db.exec(prep(files[0]));
  assert.deepEqual((await db.query('select misses, off_urs from special_pity')).rows[0], { misses: 3, off_urs: 5 }, 'v2 recomputed from log once');
  await db.query('update special_banners set rates=$1', [JSON.stringify({ ...R0, other_ur: 10000 })]);
  const d = await pull(1); assert.equal(d.cards[0].card_id, '10440'); assert.equal(d.cards[0].guarantee, 'pickup'); assert.equal(d.off_urs, 0);
  await db.close();
}
// ----- 확률 팝업 (클라이언트 계산): 인재별 확률 = 등급 확률 / 인원 -----
const POOL = [...N.map(id => ({ id, name: `n${id}`, grade: 'NORMAL' })), ...R.map(id => ({ id, name: `r${id}`, grade: 'RARE' })), { id: '40001', name: 'h', grade: 'HIGH RARE' }, { id: '50001', name: 's', grade: 'SUPER RARE' }];
const w2 = { STORY_DATA: { gacha: { rates: [0.7, 0.2, 0.065, 0.03, 0.005], special: [0.5, 0.3, 0.16, 0.032, 0.008] } }, TCG: { POOL, cardById: id => ({ id, name: `u${id}` }) } };
vm.runInNewContext(js, { window: w2, document: {}, console });
const html = w2.VRSpecial.ratesHtml();
for (const t of ['스페셜 소환', '프리미엄 소환', '일반 소환', 'UR 픽업 하지혜', '50회째 소환은 UR 확정', '어떤 UR이든 나오면 초기화', '픽업 아닌 UR이 2번 나오면 다음 UR은', '1명당 12.5%', '1명당 1%', `${premIds.length}명 · 1명당 ${+(1 / premIds.length).toFixed(4)}%`]) assert.ok(html.includes(t), `popup has ${t}`);
console.log(`Special summon: rates 100% (N50 R30 HR10 SR8 pickup1 UR1), UR pity 50 (any UR resets, pity UR 1:1), pickup after 2 other URs, v1→v2 rerun safe, per-user, pool = premium UR − pickup (no MR/hidden), shop SKUs → special tickets, guards/idempotent/RLS, popup per-character OK`);
