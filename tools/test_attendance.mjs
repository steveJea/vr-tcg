// 출석 보상 2종 SQL: 7일 간의 행운(신규 가입 한정·7회·14일 기간·출석 순서) + 30일 접속 선물(월 누적 N회째 = N번 칸, 29~31 소환권 5, 다음 달 1번부터)
// 하루 1번(트랙별) · 같은 날 두 트랙 · 가드/반복 실행/RLS · 지급처(골드·피·조각 / 무료 심연석 / 귀속 드링크 / 소환권 / 스페셜 소환권) — 2026-11-13
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { PGlite } from '@electric-sql/pglite';
const rd = f => readFile(new URL(`../${f}`, import.meta.url), 'utf8');
const ids = ['7703759698107299042', '7692130048193495360'];
const files = await Promise.all(['staging', 'production'].map(e => rd(`supabase/attendance_${e}.sql`)));
const body = s => s.slice(s.indexOf('-- ===== ATTENDANCE'));
assert.equal(body(files[0]), body(files[1]), 'staging/production bodies identical');
for (const [i, s] of files.entries()) { assert.match(s, new RegExp(`is distinct from '${ids[i]}'`)); assert.match(s, /notify pgrst, 'reload schema';\s*$/); }
assert.doesNotMatch(files[0], /\b(?:truncate|delete from|drop table|drop function|update public\.attend_config)\b/i, 'add-only');
const LUCKY = [{ gold: 10000 }, { drink: 2 }, { tickets: 3 }, { gem_free: 100 }, { tickets: 10 }, { gold: 20000, blood: 20000 }, { special_tickets: 10 }];
for (const [i, sql] of files.entries()) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key, created_at timestamptz not null default now());
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
    create table grants(user_id uuid, k text, n int, ref text);
    create function _gem_add(u uuid, f int, p int, r text, ref text, m jsonb) returns jsonb language sql as $$ insert into grants values(u,'gem_free',f,ref); select jsonb_build_object('free',f) $$;
    create function _wallet_add(u uuid, d jsonb, r text) returns jsonb language sql as $$ insert into grants select u,k,v::text::int,r from jsonb_each(d) e(k,v); select d $$;
    create function _drink_grant_bound(u uuid, n int, r text, ref text) returns jsonb language sql as $$ insert into grants values(u,'drink_bound',n,ref); select jsonb_build_object('bound',n) $$;
    create table story_gacha(user_id uuid primary key, tickets int not null default 0, last_draw date, updated_at timestamptz);
    create table special_wallet(user_id uuid primary key, tickets int not null default 0);`);
  const guarded = sql.replace('pg_catalog.pg_control_system()', 'public.test_control()').replace("notify pgrst, 'reload schema';", '');
  await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
  await assert.rejects(db.exec(guarded), /STOP: .* only/);
  await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${ids[i]}'::text$$;`);
  await db.exec(guarded);
  await db.query("update attend_config set launch_at = '2026-11-13 00:00+09'");   // 운영자가 바꿀 수 있는 한 줄 설정
  await db.exec(guarded);   // idempotent: config row kept
  const cfg = (await db.query('select * from attend_config')).rows[0];
  assert.equal(new Date(cfg.launch_at).toISOString(), '2026-11-12T15:00:00.000Z', 'rerun keeps config'); assert.equal(cfg.lucky_window_days, 14);
  assert.deepEqual(JSON.parse(JSON.stringify(cfg.lucky)), LUCKY, '7일 간의 행운 보상');
  const setDay = d => db.exec(`create or replace function public._attend_day() returns date language sql stable as $$ select '${d}'::date $$;`);
  const NEW = crypto.randomUUID(), OLD = crypto.randomUUID(), LATE = crypto.randomUUID();
  await db.query("insert into auth.users values ($1, '2026-11-13 10:00+09'), ($2, '2026-11-01 10:00+09'), ($3, '2026-11-13 09:00+09')", [NEW, OLD, LATE]);
  const as = async (uid, q) => { await db.exec(`begin; set local role authenticated; set local request.jwt.claim.sub = '${uid}';`); try { const r = (await db.query(q)).rows[0].r; await db.exec('commit'); return r; } catch (e) { await db.exec('rollback'); throw e; } };
  const claim = (u, t) => as(u, `select public.attend_claim('${t}') r`), status = u => as(u, 'select public.attend_status() r');
  await assert.rejects(db.exec(`begin; set local role anon; select public.attend_status();`), /permission denied/); await db.exec('rollback');
  await assert.rejects(claim(NEW, 'other'), /invalid track/);
  // 7일 행운: 출석 순서(빠진 날 건너뛰지 않음) · 7회 끝 · 하루 1번 · 같은 날 월간도
  await setDay('2026-11-13');
  let st = await status(NEW); assert.equal(st.lucky.open, true); assert.equal(st.lucky.ends, '2026-11-26'); assert.equal(st.monthly.days, 30);
  assert.equal((await status(OLD)).lucky.reason, 'old_account'); assert.equal((await claim(OLD, 'lucky')).reason, 'old_account');
  const days = ['2026-11-13', '2026-11-15', '2026-11-16', '2026-11-20', '2026-11-21', '2026-11-25', '2026-11-26'];
  for (const [k, d] of days.entries()) {
    await setDay(d); const r = await claim(NEW, 'lucky'); assert.equal(r.ok, true, d); assert.equal(r.slot, k + 1); assert.deepEqual(r.reward, LUCKY[k]);
    assert.equal((await claim(NEW, 'lucky')).reason, 'already', 'one per day');
    const m = await claim(NEW, 'monthly'); assert.equal(m.ok, true, 'both tracks same day'); assert.equal(m.slot, k + 1); assert.equal(m.status.monthly.claims, k + 1); assert.equal(m.status.monthly.claimed_today, true); assert.equal(m.status.lucky.claimed_today, true);
  }
  assert.equal((await claim(NEW, 'lucky')).reason, 'already'); await setDay('2026-11-27'); assert.equal((await claim(NEW, 'lucky')).reason, 'done');
  st = await status(NEW); assert.equal(st.lucky.claims, 7); assert.equal(st.lucky.open, false); assert.equal(st.lucky.eligible, false);
  const g = k => db.query('select coalesce(sum(n),0)::int n from grants where user_id=$1 and k=$2', [NEW, k]).then(r => r.rows[0].n);
  // 지급처: 7일(골드 30000, 피 20000, 드링크 2 귀속, 심연석 100, 소환권 13, 스페셜 10) + 월간 1~7칸(골드 3000+3000, 피 3000+3000, 심연석 20, 드링크 1, 조각 2000, 소환권 1)
  assert.equal(await g('gold'), 36000); assert.equal(await g('blood'), 26000); assert.equal(await g('shard'), 2000);
  assert.equal(await g('gem_free'), 120); assert.equal(await g('drink_bound'), 3);
  assert.equal((await db.query('select tickets from story_gacha where user_id=$1', [NEW])).rows[0].tickets, 14);
  assert.equal((await db.query('select tickets from special_wallet where user_id=$1', [NEW])).rows[0].tickets, 10);
  // 14일 기간: 13일 가입 → 26일까지. 27일 첫 출석이면 만료
  await setDay('2026-11-27'); assert.equal((await claim(LATE, 'lucky')).reason, 'expired'); assert.equal((await status(LATE)).lucky.reason, 'expired');
  // 월간: 날짜 무관 N회째 = N번 칸 · 1~28 순환 · 29~31 소환권 5 · 다음 달 1번부터
  const U = crypto.randomUUID(); await db.query("insert into auth.users values ($1, '2026-10-01')", [U]);
  const got = [];
  for (let d = 1; d <= 31; d++) { await setDay(`2026-12-${String(d).padStart(2, '0')}`); const r = await claim(U, 'monthly'); assert.equal(r.slot, d); got.push(r.reward); assert.equal((await claim(U, 'monthly')).reason, 'already'); }
  const cyc = JSON.parse(JSON.stringify(cfg.monthly_cycle));
  assert.deepEqual(cyc, [{ gold: 3000 }, { blood: 3000 }, { gem_free: 20 }, { drink: 1 }, { shard: 2000 }, { gold: 3000, blood: 3000 }, { tickets: 1 }]);
  for (let s = 1; s <= 28; s++) assert.deepEqual(got[s - 1], cyc[(s - 1) % 7], `slot ${s}`);
  for (const s of [29, 30, 31]) assert.deepEqual(got[s - 1], { tickets: 5 }, `slot ${s}`);
  await setDay('2027-01-05'); st = await status(U); assert.equal(st.monthly.claims, 0, 'month reset'); assert.equal(st.monthly.month, '2027-01-01');
  let r = await claim(U, 'monthly'); assert.equal(r.slot, 1); assert.deepEqual(r.reward, cyc[0]);
  await setDay('2027-01-20'); r = await claim(U, 'monthly'); assert.equal(r.slot, 2, 'cumulative, not date');
  await setDay('2027-02-01'); assert.equal((await status(U)).monthly.days, 28); assert.equal((await status(U)).monthly.rewards.length, 28);
  // RLS: 본인 기록만, 직접 쓰기 불가
  assert.equal(await as(U, 'select count(*)::int r from attend_log'), 33); assert.equal(await as(OLD, 'select count(*)::int r from attend_log'), 0);
  await assert.rejects(as(U, "insert into attend_log(user_id,track,day,month,slot,reward) values (auth.uid(),'monthly','2027-03-01','2027-03-01',1,'{}') returning 1 r"), /permission denied/);
  await assert.rejects(as(U, 'update attend_config set lucky_window_days = 60 returning 1 r'), /permission denied/);
  await assert.rejects(as(U, "select public._attend_grant(auth.uid(), '{\"gold\":1}', 'x', 'y') r"), /permission denied/);
  await assert.rejects(db.query("select public._attend_grant($1, '{\"soul\":1}', 'x', 'y')", [U]), /invalid reward key/);
  await db.close();
}
// ----- 클라이언트 (js/attendance.js): 보상 글자, 서버 없으면 조용히 꺼짐 -----
const js = await rd('js/attendance.js');
const w = { VRCloud: null, addEventListener() {}, setTimeout() {}, localStorage: { getItem() { return null; }, setItem() {} } };
vm.runInNewContext(js, { window: w, document: { querySelectorAll: () => [], addEventListener() {}, body: {} }, console, setTimeout() {}, setInterval() {}, MutationObserver: class { observe() {} }, localStorage: w.localStorage });
assert.equal(w.VRAttend.rwText({ gold: 20000, blood: 20000 }), '골드 20,000 · 피 20,000');
assert.equal(w.VRAttend.rwText({ special_tickets: 10 }), '스페셜 소환권 10');
assert.equal(w.VRAttend.rwText({ drink: 2 }), '무료 드링크 2 (거래 불가)');
assert.match(await rd('index.html'), /<script src="js\/attendance\.js"><\/script>/); assert.match(await rd('index.html'), /data-attendbtn/);
console.log('Attendance SQL: guards/idempotent config, 7일 행운 신규 한정·출석 순·7회·14일, 월간 N회째=N칸·29~31 소환권5·월 리셋, 하루 1번·두 트랙 같은 날, RLS, 지급처 OK');
