// 방치 보상 무료 드링크 SQL (PGlite): 2시간당 1 (귀속) · 8시간 최대 4 · 나머지 이월 · 빠른 보상 4시간 = 2 · 기존 골드 등 그대로 · 예전 attend_claim() 끄기 · 가드/반복 실행
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { PGlite } from '@electric-sql/pglite';
const rd = f => readFile(new URL(`../${f}`, import.meta.url), 'utf8');
const ids = ['7703759698107299042', '7692130048193495360'];
const files = await Promise.all(['staging', 'production'].map(e => rd(`supabase/idle_drink_${e}.sql`)));
const body = s => s.slice(s.indexOf('-- ===== IDLE DRINK'));
assert.equal(body(files[0]), body(files[1]), 'staging/production bodies identical');
for (const [i, s] of files.entries()) { assert.match(s, new RegExp(`is distinct from '${ids[i]}'`)); assert.match(s, /notify pgrst, 'reload schema';\s*$/); }
assert.doesNotMatch(files[0], /\b(?:truncate|delete from|drop table|drop function|drop column)\b/i, 'add-only');
const idle = await rd('supabase/idle_box.sql'), fix = await rd('supabase/batch_ui_bugs.sql');
const boostFix = fix.slice(fix.indexOf('create or replace function public.idle_box_boost'), fix.indexOf('-- 2) dispatch_start'));
for (const [i, sql] of files.entries()) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
    create table player_state(user_id uuid primary key, level int); create table grants(user_id uuid, k text, n bigint, ref text);
    create function _gem_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
    create function _wallet_add(u uuid, d jsonb, r text) returns jsonb language sql as $$ insert into grants select u,k,v::text::bigint,r from jsonb_each(d) e(k,v); select d $$;
    create function _gear_dust_add(u uuid, n bigint) returns bigint language sql as $$ insert into grants values(u,'dust',n,null); select n $$;
    create function _gem_spend(u uuid, n int, r text, m jsonb) returns jsonb language sql as $$ insert into grants values(u,'gem_spend',n,r); select jsonb_build_object('gem',0) $$;
    create function _drink_grant_bound(u uuid, n int, r text, p_ref text) returns jsonb language plpgsql as $$ begin
      if exists(select 1 from grants g where g.ref=p_ref and g.k='drink') then return null; end if;
      insert into grants values(u,'drink',n,p_ref); return jsonb_build_object('bound',n); end $$;
    create function attend_claim() returns jsonb language sql as $$ select '{"ok":true}'::jsonb $$; grant execute on function attend_claim() to authenticated;
    create function attend_claim(p_track text) returns jsonb language sql as $$ select '{"new":true}'::jsonb $$; grant execute on function attend_claim(text) to authenticated;`);
  await db.exec(idle); await db.exec(boostFix);
  const guarded = sql.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
  await assert.rejects(db.exec(guarded), /STOP: .* only/);
  await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[i]}'::text$$;`);
  await db.exec(guarded); await db.exec(guarded);   // idempotent
  const u = crypto.randomUUID(); await db.query('insert into auth.users values($1)', [u]); await db.query('insert into player_state values($1, 100)', [u]);
  const as = async q => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${u}';`); try { const r = (await db.query(q)).rows[0].r; await db.exec('commit'); return r; } catch (e) { await db.exec('rollback'); throw e; } };
  const ago = (h, carry = null) => db.query(`update idle_box set last_claim = now() - make_interval(secs => $1::float8 * 3600)${carry == null ? '' : ', drink_carry = ' + carry} where user_id = $2`, [h, u]);
  const drinks = async () => (await db.query("select coalesce(sum(n),0)::int n from grants where user_id=$1 and k='drink'", [u])).rows[0].n;
  let s = await as('select public.idle_box_status() r');
  assert.deepEqual(JSON.parse(JSON.stringify(s.rate)), { gold: 2400, shard: 11, blood: 6, dust: 5, drink_every_h: 2 }, 'Lv100 rates unchanged + drink');
  assert.equal(s.boost.reward.drink, 2, '빠른 보상 4시간 = 드링크 2'); assert.equal(s.boost.reward.gold, 9600); assert.equal(s.drink.max_per_claim, 4);
  // 8시간 넘게 → 상한 8시간 = 4개, 나머지 0
  await ago(30); s = await as('select public.idle_box_status() r'); assert.equal(s.pending.drink, 4); assert.equal(s.pending.gold, 19200); assert.equal(s.full, true);
  let r = await as('select public.idle_box_claim() r'); assert.equal(r.got.drink, 4); assert.equal(await drinks(), 4); assert.equal(r.drink_item.bound, 4);
  // 3.5시간 → 1개, 1.5시간 이월
  await ago(3.5); r = await as('select public.idle_box_claim() r'); assert.equal(r.got.drink, 1); assert.equal(await drinks(), 5);
  let c = Number((await db.query('select drink_carry from idle_box where user_id=$1', [u])).rows[0].drink_carry); assert.ok(Math.abs(c - 1.5) < 0.01, `carry ${c}`);
  // 이월 1.5 + 0.6시간 → 1개 (2시간 안 되는 묶음은 이월로만)
  await ago(0.6); s = await as('select public.idle_box_status() r'); assert.equal(s.pending.drink, 1); assert.ok(Math.abs(s.drink.carry_h - 1.5) < 0.01);
  r = await as('select public.idle_box_claim() r'); assert.equal(r.got.drink, 1); assert.equal(await drinks(), 6);
  c = Number((await db.query('select drink_carry from idle_box where user_id=$1', [u])).rows[0].drink_carry); assert.ok(Math.abs(c - 0.1) < 0.01, `carry ${c}`);
  // 1시간 → 0개 (골드만), 이월 1.1
  await ago(1, 0); r = await as('select public.idle_box_claim() r'); assert.equal(r.got.drink, 0); assert.equal(r.drink_item, null); assert.equal(await drinks(), 6);
  // 이월 1.99 + 8시간 상한 → 4개 (최대)
  await ago(20, 1.99); r = await as('select public.idle_box_claim() r'); assert.equal(r.got.drink, 4); assert.equal(await drinks(), 10);
  // 빠른 보상: 2개씩, 하루 2번
  r = await as('select public.idle_box_boost() r'); assert.equal(r.got.drink, 2); assert.equal(r.got.gold, 9600); assert.equal(await drinks(), 12);
  r = await as('select public.idle_box_boost() r'); assert.equal(await drinks(), 14);
  await assert.rejects(as('select public.idle_box_boost() r'), /daily limit/); assert.equal(await drinks(), 14);
  // 예전 일일 미션 출석 끄기 (새 출석은 그대로)
  await assert.rejects(as('select public.attend_claim() r'), /permission denied|old attendance removed/);
  await assert.rejects(db.query('select public.attend_claim()'), /old attendance removed/);
  assert.equal((await as("select public.attend_claim('monthly') r")).new, true, 'new attendance untouched');
  await assert.rejects(as('select public._idle_drink_every() r'), /permission denied/);
  await db.close();
}
// ----- 클라이언트 표시 -----
const js = await rd('js/idle-box.js');
assert.match(js, /드링크 \$\{rate\.drink_every_h\}시간당 1/); assert.match(js, /r\?\.drink && `🥤 드링크/);
console.log('Idle drink SQL: 2h/1 bound drink, 8h max 4, remainder carried, boost 4h = 2, rates unchanged, old attend_claim() off, new attend untouched, guards/idempotent OK');
