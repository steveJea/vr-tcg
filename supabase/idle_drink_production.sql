-- PRODUCTION ONLY (htarwisgkkphutxxnuak). Single atomic DO block for SQL Editor; idempotent (add-only column, function replace only, no data deleted).
-- 방치 보상 무료 드링크 (2시간당 1 · 8시간 최대 4 · 빠른 보상 4시간 = 2) + 예전 일일 미션 7일 출석 attend_claim() 끄기.
-- Requires: idle_box.sql (+ batch_ui_bugs.sql) · trade_drink.sql (_drink_grant_bound). Production file is for the later approved release only.
-- Note: re-running idle_box.sql / batch_ui_bugs.sql / security_phase1_rewards.sql restores the old functions → run this file again after them.
do $install$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
  raise exception 'STOP: production htarwisgkkphutxxnuak only'; end if;
 if to_regclass('public.idle_box') is null or to_regprocedure('public._idle_rate(integer)') is null or to_regprocedure('public._gem_spend(uuid,integer,text,jsonb)') is null
    or to_regprocedure('public._drink_grant_bound(uuid,integer,text,text)') is null then
  raise exception 'install idle_box and trade_drink first'; end if;
-- ===== IDLE DRINK =====

-- (1) 방치 보상 무료 드링크: 쌓인 시간 2시간당 1개 (귀속·거래 불가). 2시간이 안 되는 나머지는 drink_carry 로 다음에 이어짐 (드링크에만 적용)
alter table public.idle_box add column if not exists drink_carry numeric not null default 0 check (drink_carry >= 0 and drink_carry < 2);
execute $ddl$create or replace function public._idle_drink_every() returns numeric language sql immutable as $fn$ select 2::numeric $fn$;$ddl$;
execute $ddl$create or replace function public._idle_json(p_uid uuid, p_r idle_box) returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
declare lv int := _idle_plv(p_uid); rate jsonb := _idle_rate(lv); hrs numeric; got jsonb;
  today date := _gem_day(); boost_left int; boost_n int; ev numeric := _idle_drink_every(); dk int; acc numeric;
begin
  hrs := _idle_hours(p_r.last_claim);
  got := _idle_amt(rate, hrs);
  acc := hrs + coalesce(p_r.drink_carry, 0); dk := floor(acc / ev)::int;
  got := got || jsonb_build_object('drink', dk);
  boost_n := case when p_r.boost_day = today then p_r.boost_n else 0 end;
  boost_left := greatest(0, _idle_boost_max() - boost_n);
  return jsonb_build_object('ok', true, 'now', now(), 'level', lv, 'rate', rate || jsonb_build_object('drink_every_h', ev), 'hours', round(hrs::numeric, 3),
    'max_hours', _idle_max_hours(), 'full', hrs >= _idle_max_hours(),
    'pending', got, 'ready', (got->>'gold')::int > 0 or (got->>'shard')::int > 0 or (got->>'blood')::int > 0 or (got->>'dust')::int > 0 or dk > 0,
    'last_claim', p_r.last_claim,
    'drink', jsonb_build_object('every_h', ev, 'pending', dk, 'carry_h', round(coalesce(p_r.drink_carry, 0), 3),
      'next_in_h', round(ev - (acc - dk * ev), 3), 'max_per_claim', floor((_idle_max_hours() + ev) / ev)::int - 1),
    'boost', jsonb_build_object('cost', _idle_boost_cost(), 'hours', _idle_boost_hours(), 'left', boost_left, 'max', _idle_boost_max(),
      'reward', _idle_amt(rate, _idle_boost_hours()) || jsonb_build_object('drink', floor(_idle_boost_hours() / ev)::int)));
end $fn$;$ddl$;
execute $ddl$create or replace function public.idle_box_claim() returns jsonb language plpgsql security definer set search_path = public as $fn$
declare uid uuid := auth.uid(); r idle_box; j jsonb; got jsonb; res jsonb; dk int; acc numeric; ev numeric := _idle_drink_every(); dr jsonb := null;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  r := _idle_row(uid);
  j := _idle_json(uid, r);
  if not coalesce((j->>'ready')::boolean, false) then raise exception 'not done'; end if;
  got := j->'pending';
  res := _idle_grant(uid, got, 'idle_box');
  acc := _idle_hours(r.last_claim) + coalesce(r.drink_carry, 0); dk := floor(acc / ev)::int;
  if dk > 0 then dr := _drink_grant_bound(uid, dk, 'idle_box', 'idle:' || uid::text || ':' || r.last_claim::text); end if;
  update idle_box set last_claim = now(), drink_carry = least(acc - dk * ev, ev - 0.000001), updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got, 'drink_item', dr);
end $fn$;$ddl$;
execute $ddl$create or replace function public.idle_box_boost() returns jsonb language plpgsql security definer set search_path = public as $fn$
declare uid uuid := auth.uid(); r idle_box; today date := _gem_day(); v_n int; got jsonb; res jsonb; gem jsonb; dk int; dr jsonb := null;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  r := _idle_row(uid);
  v_n := case when r.boost_day = today then r.boost_n else 0 end;
  if v_n >= _idle_boost_max() then raise exception 'daily limit'; end if;
  got := _idle_amt(_idle_rate(_idle_plv(uid)), _idle_boost_hours());
  dk := floor(_idle_boost_hours() / _idle_drink_every())::int;
  gem := _gem_spend(uid, _idle_boost_cost(), 'idle_boost', jsonb_build_object('hours', _idle_boost_hours()));
  res := _idle_grant(uid, got, 'idle_boost');
  if dk > 0 then dr := _drink_grant_bound(uid, dk, 'idle_boost', 'idle-boost:' || uid::text || ':' || today || ':' || (v_n + 1)); end if;
  update idle_box set boost_day = today, boost_n = v_n + 1, updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got || jsonb_build_object('drink', dk), 'gem', gem, 'drink_item', dr);
end $fn$;$ddl$;
revoke all on function public._idle_drink_every(), public._idle_json(uuid, idle_box) from public, anon, authenticated;
revoke all on function public.idle_box_claim(), public.idle_box_boost() from public, anon;
grant execute on function public.idle_box_claim(), public.idle_box_boost() to authenticated;

-- (2) 예전 일일 미션 7일 출석 끄기: attend_claim() (인자 없음)만. 새 출석 attend_claim(text) 은 그대로. 테이블·기록 삭제 없음
if to_regprocedure('public.attend_claim()') is not null then
  execute $ddl$create or replace function public.attend_claim() returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fn$
  begin raise exception 'old attendance removed'; end $fn$;$ddl$;
  revoke all on function public.attend_claim() from public, anon, authenticated;
end if;
end $install$;
notify pgrst, 'reload schema';
