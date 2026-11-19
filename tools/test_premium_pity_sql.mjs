// 프리미엄 소환 UR 천장 50 + pass_2 이름 '플러스 시즌패스'. 기본 확률·sku 그대로. 무료 뽑기는 천장 없음.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { PGlite } from '@electric-sql/pglite';
const rd = f => readFile(new URL(`../${f}`, import.meta.url), 'utf8');
const ids = ['7703759698107299042', '7692130048193495360'];
const files = await Promise.all(['staging', 'production'].map(e => rd(`supabase/premium_pity_plus_pass_${e}.sql`)));
const checks = await Promise.all(['staging', 'production'].map(e => rd(`supabase/premium_pity_plus_pass_check_${e}.sql`)));
const body = s => {
  const i = s.indexOf('alter table public.story_gacha add column');
  assert.ok(i > 0, 'body start');
  return s.slice(i);
};
assert.equal(body(files[0]), body(files[1]), 'staging/production bodies identical');
for (const [i, s] of files.entries()) {
  assert.match(s, new RegExp(`is distinct from '${ids[i]}'`));
  assert.doesNotMatch(s, new RegExp(ids[1 - i]));
  assert.match(s, /notify pgrst, 'reload schema';\s*$/);
  assert.match(s, /\bbegin;/); assert.match(s, /\bcommit;/);
  assert.doesNotMatch(s, /\b(?:truncate|delete from|drop table|drop function|price_krw\s*=)/i);
  assert.match(s, /sku = 'pass_2'/);
  assert.doesNotMatch(s, /create or replace function public\.story_daily_draw/);
}
for (const [i, c] of checks.entries()) {
  assert.equal((c.match(/^\s*select\b/gim) || []).length, 1, 'single SELECT check');
  assert.doesNotMatch(c, /\b(?:insert|update|delete|drop|alter|begin|commit)\b/i);
  assert.match(c, /premium_ur_count/);
  assert.match(c, /플러스 시즌패스/);
  if (i === 0) assert.match(c, /STAGING 확인/); else assert.match(c, /PRODUCTION 확인/);
}

const prem = await rd('supabase/gacha_premium_ur.sql');
const premIds = [...prem.slice(prem.indexOf('insert into public.story_premium_ur')).split(';')[0].matchAll(/\('(\d+)'/g)].map(m => m[1]);
assert.equal(premIds.length, 11, 'premium UR pool is 11');
assert.deepEqual(premIds, ['10051', '10053', '10054', '10058', '10176', '10312', '10323', '10324', '10325', '10331', '10358']);

const js = await rd('js/special-summon.js');
const win = { STORY_DATA: { gacha: {} } }; vm.runInNewContext(js, { window: win, document: { getElementById: () => null, createElement: () => ({}) }, console });
assert.deepEqual([...win.VRSpecial.PREMIUM_UR], premIds, 'client PREMIUM_UR = SQL list');
assert.match(js, /UR 천장: UR 없이 50회째 소환은 UR 확정/);
assert.match(js, /일반 소환\(하루 1회 무료\)에는 천장이 없어요/);

const story = await rd('js/story.js');
assert.match(story, /UR 확정까지 \$\{left\}회/);
assert.match(story, /다음 소환은 UR 확정/);
assert.match(story, /ticketMisses/);
assert.match(story, /UR 없이 50회째는 UR 확정/);
assert.match(story, /premPityLine\(\)/);
assert.doesNotMatch(story, /create or replace function public\.story_daily_draw/);

const shop = await rd('supabase/shop_v2_staging.sql');
assert.match(shop, /\('pass_2','pass','플러스 시즌패스'/);
assert.doesNotMatch(shop, /'pass_2','pass','스페셜 시즌패스'/);
assert.match(await rd('supabase/shop_v2_check_staging.sql'), /프리미엄 시즌패스\/플러스 시즌패스\/럭셔리 시즌패스/);

async function baseDb(db) {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
    create table story_card_pool(id text primary key, name text, grade text, gacha boolean default true);
    create table story_premium_ur(id text primary key, name text);
    create table story_gacha(
      user_id uuid primary key, tickets int not null default 0, last_draw date,
      ticket_chapters int[] not null default '{}', updated_at timestamptz default now());
    create table story_gacha_log(
      id bigint generated always as identity primary key,
      user_id uuid not null, card_id text, grade text, kind text not null default 'daily');
    create table story_save(user_id uuid primary key, data jsonb);
    create table shop_products(sku text primary key, name text, price_krw int);
    insert into shop_products values
      ('pass_1','프리미엄 시즌패스',5500),('pass_2','스페셜 시즌패스',22000),('pass_3','럭셔리 시즌패스',44000);
    create function public._story_ticket_sync(uid uuid) returns jsonb language plpgsql as $$
    begin
      insert into story_gacha(user_id, last_draw) values(uid, current_date-1) on conflict do nothing;
      perform 1 from story_gacha where user_id=uid for update;
      return jsonb_build_object('tickets', (select tickets from story_gacha where user_id=uid), 'added', 0);
    end $$;
    create function public._story_lock(u uuid) returns jsonb language plpgsql as $$
    begin
      insert into story_save values(u,'{"owned":[],"ch0Jieun":true}') on conflict do nothing;
      return (select data from story_save where user_id=u);
    end $$;
    create function public._story_owned(d jsonb) returns jsonb language sql as $$ select coalesce(d->'owned','[]') $$;
    create function public._story_new_card(c text) returns jsonb language sql as $$ select jsonb_build_object('id',c,'uid',gen_random_uuid()::text) $$;
    create function public._story_save(u uuid, d jsonb) returns jsonb language sql as $$ update story_save set data=d where user_id=u returning data $$;
    -- stubs so the guard sees existing functions; SQL replaces tickets/draw
    create function public.story_tickets() returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.story_ticket_draw(p_count int) returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.story_daily_draw() returns jsonb language plpgsql as $$ begin return jsonb_build_object('ok', true, 'src', 'daily-stub-no-pity'); end $$;
    grant execute on function public.story_tickets() to authenticated;
    grant execute on function public.story_ticket_draw(int) to authenticated;
  `);
  const grades = [
    ...['20001','20002'].map(id => [id,'NORMAL']),
    ...['30001','30002'].map(id => [id,'RARE']),
    ...['40001'].map(id => [id,'HIGH RARE']),
    ...['50001','10439'].map(id => [id,'SUPER RARE']),
    ...premIds.map(id => [id,'ULTRA RARE']),
    ['90001','ULTRA RARE'], // not in premium list
  ];
  for (const [id,g] of grades) await db.query('insert into story_card_pool values($1,$1,$2,true)', [id,g]);
  for (const id of premIds) await db.query('insert into story_premium_ur values($1,$1)', [id]);
}

function patch(sql, ident) {
  return sql.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
}

for (const [i, sql] of files.entries()) {
  const db = new PGlite(); await baseDb(db);
  const guarded = patch(sql, ids[i]);
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
  await assert.rejects(db.exec(guarded), /STOP: .* only/);
  await db.exec('rollback;');
  await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[i]}'::text$$;`);
  await db.exec(guarded); await db.exec(guarded); // idempotent

  const u = '11111111-1111-1111-1111-111111111111';
  await db.query('insert into auth.users values($1)', [u]);
  await db.exec(`select set_config('request.jwt.claim.sub','${u}',false)`);
  await db.query('insert into story_gacha(user_id, tickets) values($1, 200)', [u]);

  assert.equal((await db.query("select name, price_krw from shop_products where sku='pass_2'")).rows[0].name, '플러스 시즌패스');
  assert.equal((await db.query("select price_krw from shop_products where sku='pass_2'")).rows[0].price_krw, 22000);
  assert.equal((await db.query("select count(*)::int c from story_premium_ur")).rows[0].c, 11);

  // backfill: 3 ticket misses after last UR, daily pulls ignored
  const afterUr = premIds[0];
  await db.query("insert into story_gacha_log(user_id,card_id,grade,kind) values($1,'20001','NORMAL','ticket')", [u]);
  await db.query("insert into story_gacha_log(user_id,card_id,grade,kind) values($1,$2,'ULTRA RARE','ticket')", [u, afterUr]);
  await db.query("insert into story_gacha_log(user_id,card_id,grade,kind) values($1,'20001','NORMAL','daily')", [u]);
  for (let k=0;k<3;k++) await db.query("insert into story_gacha_log(user_id,card_id,grade,kind) values($1,'20001','NORMAL','ticket')", [u]);
  await db.exec(guarded); // recompute
  assert.equal((await db.query('select pity_misses from story_gacha where user_id=$1', [u])).rows[0].pity_misses, 3);

  const st = (await db.query('select public.story_tickets() r')).rows[0].r;
  assert.equal(st.tickets, 200);
  assert.equal(st.misses, 3);
  assert.equal(st.pity, 50);

  // force pity: 49 misses → next is UR from premium pool, reset
  await db.query('update story_gacha set pity_misses=49 where user_id=$1', [u]);
  const d1 = (await db.query('select public.story_ticket_draw(1) r')).rows[0].r;
  assert.equal(d1.ok, true);
  assert.equal(d1.cards.length, 1);
  assert.equal(d1.cards[0].grade, 'ULTRA RARE');
  assert.equal(d1.cards[0].guarantee, 'ur_pity');
  assert.equal(d1.cards[0].guaranteed, true);
  assert.ok(premIds.includes(d1.cards[0].card_id), `UR ${d1.cards[0].card_id} in premium pool`);
  assert.equal(d1.misses, 0);
  assert.equal(d1.pity, 50);
  assert.equal(d1.tickets, 199);
  assert.equal((await db.query('select pity_misses, tickets from story_gacha where user_id=$1', [u])).rows[0].pity_misses, 0);

  // 10-pull starting at 49: first card UR (ch0 already marked), then counter starts over
  await db.query('update story_gacha set pity_misses=49 where user_id=$1', [u]);
  const d10 = (await db.query('select public.story_ticket_draw(10) r')).rows[0].r;
  assert.equal(d10.ok, true);
  assert.equal(d10.cards.length, 10);
  assert.equal(d10.cards[0].grade, 'ULTRA RARE');
  assert.equal(d10.cards[0].guarantee, 'ur_pity');
  const laterForced = d10.cards.slice(1).filter(c => c.guarantee === 'ur_pity');
  assert.equal(laterForced.length, 0, 'no second pity in same 10 unless 50 more misses');
  assert.equal((await db.query('select pity_misses from story_gacha where user_id=$1', [u])).rows[0].pity_misses, d10.misses);

  // not enough tickets still reports misses
  await db.query('update story_gacha set tickets=0, pity_misses=7 where user_id=$1', [u]);
  const no = (await db.query('select public.story_ticket_draw(1) r')).rows[0].r;
  assert.equal(no.ok, false);
  assert.equal(no.reason, 'tickets');
  assert.equal(no.misses, 7);

  // daily function body not replaced
  assert.match((await db.query("select prosrc from pg_proc where oid=to_regprocedure('public.story_daily_draw()')")).rows[0].prosrc, /daily-stub-no-pity/);
  assert.doesNotMatch((await db.query("select prosrc from pg_proc where oid=to_regprocedure('public.story_daily_draw()')")).rows[0].prosrc, /pity_misses/);

  const chk = (await db.query(checks[i])).rows[0];
  assert.equal(chk.ok, true, JSON.stringify(chk));
  assert.equal(chk.premium_ur_count, 11);
  assert.equal(chk.pass_2_name, '플러스 시즌패스');
}

console.log('premium pity + plus pass sql ok');
