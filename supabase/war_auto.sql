-- 구역 전쟁 자동 참가·자동 배치 (2026-11-03). guild4.sql · guild4_ui.sql · war_manual.sql 뒤에 실행. 여러 번 실행해도 안전 (create or replace 만, 표·데이터 삭제 없음)
-- 1) 조직 레벨 3 이상이면 시즌마다 자동 참가 (조직 참가 버튼 없음) · 최소 인원 없음 (빈 칸은 동네 불량배 NPC, _war_build_side 그대로)
-- 2) 개인 신청 없음: 조직원 전원 자동 배치 (보스가 안 넣은 사람은 잠금 때 전투력 순으로 빈 칸)
-- 3) 아지트(14번)는 보스가 언제든 바꿀 수 있음 (시즌 중 전투 시간 09~23시 제외). 나머지 칸은 시즌 잠금(첫날 09시) 전까지
-- 4) war_auto_assign: 보스용 전투력 순 자동 배치 14 → 1~5 → 6~10 → 11~13 → 15~21
-- 5) 전쟁 덱이 없는 조직원: 전투력 상위 5장으로 자동 편성 (배치·잠금 때). war_meta.need_deck 으로 화면에 빨간 점
-- ※ 서버에는 클라이언트 '전투력' 값이 없어서 등급·레벨·한계돌파로 근사 (_war_card_score)

create or replace function public._war_min_level() returns int language sql immutable as $$ select 3 $$;

-- 카드 점수 (전투력 근사): 등급 가중 × 1000 + 레벨 × 20 + 한계돌파 × 50
create or replace function public._war_card_score(p_id text, p_level int, p_ex int) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select case m.grade when 'LEGENDARY RARE' then 7 when 'MYTHIC RARE' then 6 when 'ULTRA RARE' then 5 when 'SUPER RARE' then 4 when 'HIGH RARE' then 3 when 'RARE' then 2 else 1 end
                   from pvp_card_meta m where m.id = p_id), 0) * 1000 + coalesce(p_level, 1) * 20 + coalesce(p_ex, 0) * 50 $$;
-- 보유 카드 중 점수 상위 5장 uid (같은 인재는 1장)
create or replace function public._war_top5(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(uid order by sc desc), '[]'::jsonb) from (
    select uid, sc from (
      select x->>'uid' uid, x->>'id' id, _war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int) sc,
             row_number() over (partition by x->>'id' order by _war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int) desc) rn
      from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
      where sp.user_id = p_user and coalesce(x->>'uid', '') <> '' and x->>'uid' not like 'guest:%' and exists (select 1 from pvp_card_meta m where m.id = x->>'id')) t
    where rn = 1 order by sc desc limit 5) q $$;
-- 조직원 전투력 (상위 5장 합)
create or replace function public._war_power(p_user uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(_war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int)), 0) from story_progress sp,
    jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
  where sp.user_id = p_user and x->>'uid' in (select jsonb_array_elements_text(_war_top5(p_user))) $$;
-- 전쟁 덱 없으면 상위 5장으로 자동 편성 (방어 1 · 공격 1 중 빈 것만). 실패해도 조용히 넘어감
create or replace function public._war_auto_deck(p_user uuid) returns void language plpgsql security definer set search_path = public as $$
declare t jsonb; sn jsonb;
begin
  if p_user is null then return; end if;
  if exists (select 1 from war_decks where user_id = p_user and def1 is not null and atk1 is not null) then return; end if;
  t := _war_top5(p_user); if jsonb_array_length(t) = 0 then return; end if;
  begin sn := _pvp_snap(p_user, t, 'open')->'cards'; exception when others then return; end;
  insert into war_decks (user_id) values (p_user) on conflict do nothing;
  update war_decks set def1 = coalesce(def1, case when def2 is null or not exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(def2) b where a->>'id' = b->>'id') then sn end),
                       atk1 = coalesce(atk1, case when atk2 is null or not exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(atk2) b where a->>'id' = b->>'id') then sn end),
                       updated_at = now() where user_id = p_user;
end $$;
-- 자동 참가: 레벨 3 이상 조직 (잠금 전 시즌)
create or replace function public._war_auto_enter(p_season date) returns void language sql security definer set search_path = public as $$
  insert into war_entries (season, guild_id) select p_season, g.id from guilds g where g.level >= _war_min_level() on conflict do nothing $$;

create or replace function public._war_tick() returns date language plpgsql security definer set search_path = public as $$
declare s date := _war_season(); d int; m record;
begin
  if _war_now() < _war_at(s, 1, (_war_numbers()->>'open_hour')::int) then perform _war_auto_enter(s); return s; end if;
  perform pg_advisory_xact_lock(hashtext('war:' || s));
  perform _war_auto_enter(s);   -- 잠금 직전에 레벨 3 된 조직도 포함 (_war_lock 이 잠금)
  perform _war_lock(s);
  for d in 1..5 loop
    exit when _war_now() < _war_at(s, d, (_war_numbers()->>'open_hour')::int);
    perform _war_pair(s, d);
    if _war_now() >= _war_at(s, d, (_war_numbers()->>'close_hour')::int) then
      for m in select id from war_matches where season = s and day = d and not settled loop perform _war_settle(m.id); end loop;
    end if;
  end loop;
  return s;
end $$;

-- 시즌 잠금: 안 넣은 조직원 → 빈 칸 (전투력 순) · 덱 없으면 자동 편성 · 최소 인원 없음 (항상 'in')
create or replace function public._war_lock(p_season date) returns void language plpgsql security definer set search_path = public as $$
declare e record; u record; s int; sc numeric;
begin
  for e in select * from war_entries where season = p_season and not locked loop
    for u in select gm.user_id from guild_members gm where gm.guild_id = e.guild_id
               and not exists (select 1 from war_roster r where r.season = p_season and r.user_id = gm.user_id) order by _war_power(gm.user_id) desc, gm.joined_at loop
      select x into s from unnest(array[14,1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,21]) with ordinality t(x, o)
        where not exists (select 1 from war_roster r where r.season = p_season and r.guild_id = e.guild_id and r.slot = x and r.user_id is not null) order by o limit 1;
      exit when s is null;
      insert into war_roster (season, guild_id, slot, user_id) values (p_season, e.guild_id, s, u.user_id) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
    end loop;
    update war_roster r set user_id = null where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null
      and not exists (select 1 from guild_members gm where gm.user_id = r.user_id and gm.guild_id = e.guild_id);
    for u in select r.user_id from war_roster r where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null loop perform _war_auto_deck(u.user_id); end loop;
    update war_roster r set def_snap = (select case when d.def1 is null then null else jsonb_build_array(d.def1, coalesce(d.def2, '[]'::jsonb)) end from war_decks d where d.user_id = r.user_id)
      where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null;
    sc := _war_scale(p_season, e.guild_id);
    update war_entries set locked = true, scale = sc, status = 'in' where season = p_season and guild_id = e.guild_id;
  end loop;
end $$;

-- 배치 (보스): 잠금 전 = 모든 칸 · 잠금 뒤 = 14번(아지트)만, 시즌 중 전투 시간(live) 제외. 잠금 뒤 바꾼 아지트는 다음 날 경기부터
create or replace function public.war_set_slot(p_slot int, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick(); e war_entries;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if p_slot not between 1 and 21 then raise exception 'bad slot'; end if;
  select * into e from war_entries where season = s and guild_id = m.guild_id;
  if e.guild_id is null then raise exception 'not entered'; end if;
  if e.locked then
    if p_slot <> 14 then raise exception 'roster locked'; end if;
    if _war_phase(s) = 'live' then raise exception 'battle hours'; end if;
  end if;
  if p_user is not null and not exists (select 1 from guild_members where user_id = p_user and guild_id = m.guild_id) then raise exception 'not member'; end if;
  if p_user is not null then delete from war_roster where season = s and guild_id = m.guild_id and user_id = p_user; end if;
  insert into war_roster (season, guild_id, slot, user_id) values (s, m.guild_id, p_slot, p_user) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
  if p_user is not null then perform _war_auto_deck(p_user); end if;
  if e.locked then   -- 잠금 뒤: 방어 덱 스냅 즉시 (다음 경기에 반영)
    update war_roster r set def_snap = (select case when d.def1 is null then null else jsonb_build_array(d.def1, coalesce(d.def2, '[]'::jsonb)) end from war_decks d where d.user_id = r.user_id)
      where r.season = s and r.guild_id = m.guild_id and r.slot = 14;
    if p_user is null then update war_roster set def_snap = null where season = s and guild_id = m.guild_id and slot = 14; end if;
  end if;
  return war_status();
end $$;

-- 자동 배치 (보스, 잠금 전): 전투력 순 14 → 1~5 → 6~10 → 11~13 → 15~21. 기존 배치는 다시 짬
create or replace function public.war_auto_assign() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick(); e war_entries; u record; i int := 0;
        ord int[] := array[14,1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,21];
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  select * into e from war_entries where season = s and guild_id = m.guild_id;
  if e.guild_id is null then raise exception 'not entered'; end if;
  if e.locked then raise exception 'roster locked'; end if;
  delete from war_roster where season = s and guild_id = m.guild_id;
  for u in select gm.user_id from guild_members gm where gm.guild_id = m.guild_id order by _war_power(gm.user_id) desc, gm.joined_at loop
    i := i + 1; exit when i > 21;
    insert into war_roster (season, guild_id, slot, user_id) values (s, m.guild_id, ord[i], u.user_id);
    perform _war_auto_deck(u.user_id);
  end loop;
  return war_status();
end $$;

-- 화면 보조: 조직 레벨 · 자동 참가 레벨 · 내 전쟁 덱 비었는지 (빨간 점)
create or replace function public.war_meta() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _guild_me(uid);
  return jsonb_build_object('ok', true, 'min_level', _war_min_level(),
    'guild_level', (select level from guilds where id = m.guild_id),
    'need_deck', m.user_id is not null and not exists (select 1 from war_decks d where d.user_id = uid and d.def1 is not null and d.atk1 is not null));
end $$;

revoke all on function public._war_min_level(), public._war_card_score(text, int, int), public._war_top5(uuid), public._war_power(uuid), public._war_auto_deck(uuid),
  public._war_auto_enter(date), public._war_tick(), public._war_lock(date) from public, anon, authenticated;
revoke all on function public.war_set_slot(int, uuid), public.war_auto_assign(), public.war_meta() from public, anon;
grant execute on function public.war_set_slot(int, uuid), public.war_auto_assign(), public.war_meta() to authenticated;
