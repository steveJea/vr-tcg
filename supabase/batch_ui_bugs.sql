-- 2026-11-05 batch UI bugs: 방치 빠른보상 · 파견 같은 인재 · 거래소 닉네임 · 스토리 소탕 미션
-- 선행: idle_box.sql · dispatch.sql · trade_direct.sql · gear_sigil.sql(story_sweep) · daily.sql · daily_social.sql
-- 여러 번 실행해도 안전 (함수 교체만)

-- 1) idle_box_boost: boost_n 컬럼/변수 모호함 → 변수명 v_n
create or replace function public.idle_box_boost() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box; today date := _gem_day(); v_n int; got jsonb; res jsonb; gem jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  r := _idle_row(uid);
  v_n := case when r.boost_day = today then r.boost_n else 0 end;
  if v_n >= _idle_boost_max() then raise exception 'daily limit'; end if;
  got := _idle_amt(_idle_rate(_idle_plv(uid)), _idle_boost_hours());
  gem := _gem_spend(uid, _idle_boost_cost(), 'idle_boost', jsonb_build_object('hours', _idle_boost_hours()));
  res := _idle_grant(uid, got, 'idle_boost');
  update idle_box set boost_day = today, boost_n = v_n + 1, updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got, 'gem', gem);
end $$;

revoke all on function public.idle_box_boost() from public, anon;
grant execute on function public.idle_box_boost() to authenticated;

-- 2) dispatch_start: 같은 카드 id(사본 포함) 한 파티·진행 중 파견에 중복 금지
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
  create temp table if not exists _dsp_pick (uid text, id text, grade int, el text, cls text) on commit drop; delete from _dsp_pick;
  insert into _dsp_pick select u, ox.x->>'id', m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if (select count(*) from _dsp_pick) <> (select count(distinct id) from _dsp_pick) then raise exception 'duplicate card'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  -- 이미 파견 나간 인재(같은 카드 id, 다른 사본)도 막음
  if exists (
    select 1 from dispatch_runs r, unnest(r.uids) ru
      join lateral (select x->>'id' as id from jsonb_array_elements(owned) x where x->>'uid' = ru limit 1) ox on true
      join _dsp_pick p on p.id = ox.id
    where r.user_id = uid and r.claimed_at is null
  ) then raise exception 'busy'; end if;
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

-- 3) 거래소 게시판: 일반 글에도 올린 사람 닉네임
create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'want_ids', l.want_ids,
    'direct', l.target is not null, 'give_drinks', l.give_drinks, 'to_me', l.target = uid,
    'seller_name', (select nickname from profiles where id = l.seller),
    'target_name', case when l.target is not null and l.seller = uid then (select nickname from profiles where id = l.target) end,
    'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;

revoke all on function public._trade_listing_json(trade_listings, uuid) from public, anon, authenticated;

-- 4) 스토리 소탕 → 일일·주간 '스토리 스테이지 클리어'
-- 클라(js/story.js · js/daily.js)가 vr:daily { mode:story, n:runs, sweep:true } 로 daily_track/weekly_track 호출.
-- 서버 story_sweep 은 건드리지 않음 (중복 카운트·함수 드리프트 방지).

notify pgrst, 'reload schema';
