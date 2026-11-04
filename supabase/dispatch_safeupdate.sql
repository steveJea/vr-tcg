-- 파견 일괄 보내기 'DELETE requires a WHERE clause' 수정 (2026-11-04). dispatch.sql 뒤에 실행. create or replace 만 (데이터 변경 없음)
-- 원인: dispatch_start 안 임시표 비우기 'delete from _dsp_pick;' 에 WHERE 가 없어 pg_safeupdate 가 막음 → 'where true' 추가 (동작 같음)
create or replace function public.dispatch_start(p_slot int, p_uids text[], p_hours int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o dispatch_offers; z dispatch_zones; owned jsonb; n int; mx int; bon int := 0; ne int; nc int; over boolean; k text; v numeric; rw jsonb := '{}'::jsonb; f numeric; great boolean := false; cnt int; d dispatch_daily;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_hours not in (1, 4, 8, 12) then raise exception 'bad hours'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  select * into o from dispatch_offers where user_id = uid and slot = p_slot for update;
  if o.user_id is null or o.day <> _dsp_day() then raise exception 'no offer'; end if;
  if o.taken then raise exception 'taken'; end if;
  select * into z from dispatch_zones where id = o.zone;
  if (select count(*) from dispatch_runs where user_id = uid and claimed_at is null) >= _dsp_slots(_dsp_level(uid)) then raise exception 'slots full'; end if;
  select * into d from dispatch_daily where user_id = uid and day = _dsp_day();
  if coalesce(d.starts, 0) >= _dsp_cap() then raise exception 'daily cap'; end if;
  n := coalesce(array_length(p_uids, 1), 0);
  if n < 1 or n > z.size or (select count(distinct u) from unnest(p_uids) u) <> n then raise exception 'bad cards'; end if;
  owned := _dsp_owned(uid);
  -- 가진 카드인지 + 카드 정보
  create temp table if not exists _dsp_pick (uid text, grade int, el text, cls text) on commit drop; delete from _dsp_pick where true;
  insert into _dsp_pick select u, m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  if exists (select 1 from _dsp_pick where grade >= 5) then raise exception 'banned grade'; end if;
  select max(grade) into mx from _dsp_pick;
  if mx < z.min_grade then raise exception 'need grade'; end if;
  select count(*) filter (where el = o.el), count(*) filter (where cls = o.cls) into ne, nc from _dsp_pick;
  bon := least(60, 15 * (ne + nc)) + case when mx > z.min_grade then 10 else 0 end;
  great := least(60, 15 * (ne + nc)) >= 60 and random() < 0.10;
  f := _dsp_mult(p_hours) * (1 + bon / 100.0) * case when great then 2 else 1 end;
  for k, v in select key, value::numeric from jsonb_each_text(z.rw) loop
    v := v * f; cnt := floor(v)::int + case when random() < v - floor(v) then 1 else 0 end;
    if cnt > 0 then rw := rw || jsonb_build_object(k, cnt); end if;
  end loop;
  update dispatch_offers set taken = true where user_id = uid and slot = p_slot;
  insert into dispatch_daily (user_id, day, starts) values (uid, _dsp_day(), 1) on conflict (user_id, day) do update set starts = dispatch_daily.starts + 1;
  insert into dispatch_runs (user_id, zone, el, cls, hours, uids, bonus, great, reward, ends_at)
    values (uid, z.id, o.el, o.cls, p_hours, p_uids, bon, great, rw, now() + make_interval(hours => p_hours));
  return _dsp_json(uid);
end $$;
revoke all on function public.dispatch_start(int, text[], int) from public, anon;
grant execute on function public.dispatch_start(int, text[], int) to authenticated;
