-- =====================================================================
-- PvP 보스리그 덱 = 리더 1장(수비대장 · HR 이하) + 멤버 1~5장 (총 2~6장). 여러 번 실행해도 안전. 삭제 없음.
-- 필요: pvp.sql · gem.sql · gear_snap.sql · pvp_boss_league.sql 다음에 실행
-- 바뀌는 것: _pvp_snap_mode(새) · 보스 덱 트리거 · pvp_set_deck · pvp_start (보스 덱 스냅샷만 _pvp_snap_mode 로, 1v1·3v3 은 그대로 _pvp_snap)
--   ※ 나중에 gem.sql 을 다시 실행하면 pvp_start 가 예전 것으로 돌아가니 이 파일도 다시 실행
-- =====================================================================

-- 1) 덱 스냅샷 (모드별): boss = 리더 1장 + 멤버 1~5장 → _pvp_snap 을 두 번 불러 이어 붙임 (장비·증표 규칙 그대로)
create or replace function public._pvp_snap_mode(p_user uuid, p_uids jsonb, p_league text, p_mode text) returns jsonb language plpgsql stable set search_path = public as $$
declare a jsonb; b jsonb; n int; cost int;
begin
  if p_mode is distinct from 'boss' then return _pvp_snap(p_user, p_uids, p_league); end if;
  if jsonb_typeof(p_uids) <> 'array' then raise exception 'deck size'; end if;
  n := jsonb_array_length(p_uids);
  if n < 2 then raise exception 'boss members'; end if;   -- 멤버 1장 이상
  if n > 6 then raise exception 'deck size'; end if;      -- 멤버 최대 5장
  a := _pvp_snap(p_user, jsonb_build_array(p_uids->0), p_league);
  b := _pvp_snap(p_user, (select jsonb_agg(x order by i) from jsonb_array_elements(p_uids) with ordinality t(x, i) where i > 1), p_league);
  if exists (select 1 from jsonb_array_elements(b->'cards') x where x->>'id' = a->'cards'->0->>'id') then raise exception 'duplicate card'; end if;
  cost := (a->>'cost')::int + (b->>'cost')::int;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', (a->'cards') || (b->'cards'), 'cost', cost);
end $$;
revoke all on function public._pvp_snap_mode(uuid, jsonb, text, text) from public, anon, authenticated;

-- 2) 보스리그 덱 트리거: 첫 장(리더) HR 이하 + 멤버 1~5장
create or replace function public._pvp_boss_deck_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare g text; n int;
begin
  if new.mode <> 'boss' then return new; end if;
  select grade into g from pvp_card_meta where id = new.snap->0->>'id';
  if g is null or g not in ('NORMAL','RARE','HIGH RARE') then raise exception 'guard grade'; end if;
  n := jsonb_array_length(coalesce(new.snap, '[]'::jsonb));
  if n < 2 then raise exception 'boss members'; end if;
  if n > 6 then raise exception 'deck size'; end if;
  return new;
end $$;
revoke all on function public._pvp_boss_deck_chk() from public, anon, authenticated;
drop trigger if exists pvp_boss_deck_chk on public.pvp_decks;
create trigger pvp_boss_deck_chk before insert or update on public.pvp_decks for each row execute function public._pvp_boss_deck_chk();

-- 3) 덱 등록 (pvp.sql 과 같음 · 스냅샷만 모드별)
create or replace function public.pvp_set_deck(p_league text, p_mode text, p_slot int, p_uids jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); s jsonb; other text[];
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot is null or p_slot < 0 or p_slot >= n then raise exception 'bad slot'; end if;
  if p_uids is null or jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) = 0 then
    delete from pvp_decks where user_id = uid and league = p_league and mode = p_mode and slot = p_slot;
    return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', '[]'::jsonb);
  end if;
  s := _pvp_snap_mode(uid, p_uids, p_league, p_mode);
  -- 3v3: 같은 카드는 세 덱 중 한 곳에만
  select coalesce(array_agg(x->>'id'), '{}') into other from pvp_decks d, jsonb_array_elements(d.snap) x
    where d.user_id = uid and d.league = p_league and d.mode = p_mode and d.slot <> p_slot;
  if exists (select 1 from jsonb_array_elements(s->'cards') x where x->>'id' = any(other)) then raise exception 'card used in another deck'; end if;
  insert into pvp_decks (user_id, league, mode, slot, uids, snap, cost, updated_at)
  values (uid, p_league, p_mode, p_slot, p_uids, s->'cards', (s->>'cost')::int, now())
  on conflict (user_id, league, mode, slot) do update set uids = excluded.uids, snap = excluded.snap, cost = excluded.cost, updated_at = now();
  return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', s->'cards', 'cost', (s->>'cost')::int);
end $$;

-- 4) 매칭 시작 (gem.sql 과 같음 · 내 덱 다시 읽기만 모드별)
create or replace function public.pvp_start(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; me pvp_ratings; mine jsonb := '[]'::jsonb; d record;
        opp uuid; oname text; orat int; osnap jsonb := '[]'::jsonb; seed bigint; ex numeric; dw int; dl int; aid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('pvp:' || uid::text));
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  if used >= 10 + _pvp_extra(uid, p_league, p_mode) then raise exception 'no attempts left'; end if;
  if (select count(*) from pvp_decks where user_id = uid and league = p_league and mode = p_mode) < n then raise exception 'deck required'; end if;
  for d in select * from pvp_decks where user_id = uid and league = p_league and mode = p_mode order by slot loop
    mine := mine || jsonb_build_array(_pvp_snap_mode(uid, d.uids, p_league, p_mode)->'cards');
  end loop;
  me := _pvp_rating(uid, p_league, p_mode);
  -- 상대: 덱을 다 등록한 다른 유저 중 레이팅이 가까운 쪽 (약간의 무작위)
  select x.user_id, coalesce(r.rating, 1000) into opp, orat from (
      select user_id from pvp_decks where league = p_league and mode = p_mode and user_id <> uid group by user_id having count(*) >= n) x
    left join pvp_ratings r on r.user_id = x.user_id and r.league = p_league and r.mode = p_mode and r.season = _pvp_season()
    order by abs(coalesce(r.rating, 1000) - me.rating) + random() * 60 limit 1;
  if opp is not null then
    select coalesce(jsonb_agg(snap order by slot), '[]'::jsonb) into osnap from pvp_decks where user_id = opp and league = p_league and mode = p_mode and slot < n;
    select coalesce(nickname, '플레이어') into oname from profiles where id = opp;
    oname := coalesce(oname, '플레이어');
  else
    -- 상대 없음: 내 덱 거울 봇 (레벨 -10%)
    select coalesce(jsonb_agg((select coalesce(jsonb_agg(c || jsonb_build_object('level', greatest(1, round(coalesce((c->>'level')::int, 1) * 0.9)::int), 'boost', '{}'::jsonb)), '[]'::jsonb)
                               from jsonb_array_elements(dk) c)), '[]'::jsonb) into osnap from jsonb_array_elements(mine) dk;
    oname := '봇'; orat := me.rating;
  end if;
  ex := 1 / (1 + power(10, (orat - me.rating) / 400.0));
  dw := greatest(1, round(32 * (1 - ex))::int); dl := greatest(1, round(32 * ex)::int);
  if opp is null then dw := greatest(1, dw / 2); dl := greatest(1, dl / 2); end if;   -- 봇전은 절반
  seed := floor(random() * 2147483647)::bigint;
  insert into pvp_attempts (user_id, league, mode, season, day, opp_user, opp_name, seed, my_snap, opp_snap, my_rating, opp_rating, dw, dl)
  values (uid, p_league, p_mode, _pvp_season(), _pvp_day(), opp, oname, seed, mine, osnap, me.rating, orat, dw, dl) returning id into aid;
  update pvp_ratings set rating = rating - dl, losses = losses + 1, updated_at = now() where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season();
  if opp is not null then perform _pvp_rating(opp, p_league, p_mode);
    update pvp_ratings set rating = rating + dl / 2, def_wins = def_wins + 1, updated_at = now() where user_id = opp and league = p_league and mode = p_mode and season = _pvp_season(); end if;
  return jsonb_build_object('id', aid, 'seed', seed, 'me', mine, 'opp', osnap, 'opp_name', oname, 'opp_rating', orat, 'rating', me.rating, 'dw', dw, 'dl', dl, 'left', 9 + _pvp_extra(uid, p_league, p_mode) - used, 'bot', opp is null);
end $$;

revoke all on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_start(text, text) from public, anon;
grant execute on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_start(text, text) to authenticated;

-- 확인: 보스리그 덱 저장 — HR 1장만이면 'boss members', HR 리더 + 멤버 1~5장이면 저장
