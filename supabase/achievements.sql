-- =====================================================================
-- 🏆 업적 (1차) — 성장·전투·수집·스토리·소셜 + 업적 점수 마일스톤
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: daily.sql(_daily_grant · _gem_day) · phaseE_2.sql(player_state) · tower_v2.sql
--       · pvp.sql / pvp_tier.sql · gallery · story_progress · friends.sql
-- 선택(없으면 해당 업적 진행 0): camp.sql/camp2.sql · guild.sql/guild3.sql · gear_v1.sql · story_gacha_log
-- 공개 RPC: achievements_status() · achievements_claim(key) · achievements_claim_all()
-- 확인용: select public.achievements_status();
-- 진행·달성 판정은 전부 서버 (기존 테이블에서 계산, 클라이언트 값 안 믿음). 소급 O
-- =====================================================================

create table if not exists public.achievement_claims (
  user_id    uuid not null references auth.users(id) on delete cascade,
  key        text not null check (char_length(key) between 1 and 60),
  claimed_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.achievement_claims enable row level security;
revoke all on public.achievement_claims from public, anon, authenticated;

-- 업적 정의. tiers[].goal = 달성 기준 · reward = 지급 · 마지막 칸 점수 +20, 그 앞 +10
create or replace function public._ach_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"player_lv","cat":"growth","name":"모험가의 길","unit":"Lv","tiers":[
    {"goal":10,"reward":{"gold":5000,"gem":10}},
    {"goal":30,"reward":{"gold":15000,"gem":30,"tickets":1}},
    {"goal":50,"reward":{"gold":30000,"gem":50,"tickets":2}},
    {"goal":80,"reward":{"gold":50000,"gem":100,"tickets":3}}]},
  {"id":"camp_lv","cat":"growth","name":"훈련소 확장","unit":"Lv","tiers":[
    {"goal":3,"reward":{"gold":8000}},
    {"goal":5,"reward":{"gold":15000,"gem":20}},
    {"goal":8,"reward":{"gold":30000,"gem":50,"tickets":1}},
    {"goal":10,"reward":{"gold":50000,"gem":80,"tickets":2}}]},
  {"id":"camp_slots","cat":"growth","name":"훈련 슬롯","unit":"칸","tiers":[
    {"goal":3,"reward":{"gold":10000}},
    {"goal":5,"reward":{"gold":20000,"gem":30,"tickets":1}}]},
  {"id":"tower_normal","cat":"battle","name":"시련의 탑 · 일반","unit":"층","tiers":[
    {"goal":10,"reward":{"gold":5000}},
    {"goal":30,"reward":{"gold":12000,"gem":20}},
    {"goal":50,"reward":{"gold":25000,"gem":40,"tickets":1}},
    {"goal":100,"reward":{"gold":50000,"gem":80,"tickets":2}},
    {"goal":200,"reward":{"gold":80000,"gem":150,"tickets":3}}]},
  {"id":"tower_elem","cat":"battle","name":"속성 탑 입문","unit":"층","tiers":[
    {"goal":30,"reward":{"gold":20000,"gem":40,"tickets":1}}]},
  {"id":"tower_light","cat":"battle","name":"빛·어둠 정복","unit":"층","tiers":[
    {"goal":50,"reward":{"gold":40000,"gem":80,"tickets":2}}]},
  {"id":"pvp_wins","cat":"battle","name":"PvP 승장","unit":"승","tiers":[
    {"goal":10,"reward":{"gold":8000}},
    {"goal":50,"reward":{"gold":20000,"gem":30}},
    {"goal":100,"reward":{"gold":40000,"gem":60,"tickets":1}},
    {"goal":300,"reward":{"gold":70000,"gem":120,"tickets":2}}]},
  {"id":"pvp_tier","cat":"battle","name":"PvP 티어","unit":"티어","tiers":[
    {"goal":1,"reward":{"gold":10000,"gem":20}},
    {"goal":2,"reward":{"gold":20000,"gem":40,"tickets":1}},
    {"goal":3,"reward":{"gold":40000,"gem":80,"tickets":2}},
    {"goal":4,"reward":{"gold":60000,"gem":120,"tickets":3}}]},
  {"id":"gallery_n","cat":"collect","name":"인재 수집","unit":"장","tiers":[
    {"goal":30,"reward":{"gold":8000,"tickets":1}},
    {"goal":80,"reward":{"gold":20000,"gem":30,"tickets":2}},
    {"goal":150,"reward":{"gold":40000,"gem":50,"tickets":3}},
    {"goal":250,"reward":{"gold":70000,"gem":80,"tickets":5}},
    {"goal":400,"reward":{"gold":100000,"gem":150,"tickets":8}}]},
  {"id":"gacha_n","cat":"collect","name":"소환 횟수","unit":"회","tiers":[
    {"goal":20,"reward":{"gold":10000,"tickets":1}},
    {"goal":100,"reward":{"gold":30000,"gem":40,"tickets":2}},
    {"goal":300,"reward":{"gold":60000,"gem":80,"tickets":5}}]},
  {"id":"gear_p5","cat":"collect","name":"장비 +5","unit":"개","tiers":[
    {"goal":1,"reward":{"gold":15000,"gem":20}},
    {"goal":5,"reward":{"gold":30000,"gem":50,"tickets":1}},
    {"goal":15,"reward":{"gold":50000,"gem":100,"tickets":2}}]},
  {"id":"mvp_n","cat":"collect","name":"MVP","unit":"회","tiers":[
    {"goal":10,"reward":{"gold":8000}},
    {"goal":50,"reward":{"gold":20000,"gem":30}},
    {"goal":200,"reward":{"gold":40000,"gem":60,"tickets":1}}]},
  {"id":"story_ch","cat":"story","name":"챕터 클리어","unit":"챕터","tiers":[
    {"goal":1,"reward":{"gold":10000,"gem":20,"tickets":1}},
    {"goal":5,"reward":{"gold":25000,"gem":50,"tickets":2}},
    {"goal":10,"reward":{"gold":50000,"gem":100,"tickets":3}},
    {"goal":15,"reward":{"gold":80000,"gem":200,"tickets":5}}]},
  {"id":"story_stars","cat":"story","name":"별점 수집","unit":"별","tiers":[
    {"goal":30,"reward":{"gold":10000}},
    {"goal":100,"reward":{"gold":30000,"gem":40,"tickets":1}},
    {"goal":200,"reward":{"gold":50000,"gem":80,"tickets":2}}]},
  {"id":"attend_n","cat":"social","name":"출석","unit":"일","tiers":[
    {"goal":7,"reward":{"gold":5000,"tickets":1}},
    {"goal":30,"reward":{"gold":20000,"gem":40,"tickets":2}},
    {"goal":100,"reward":{"gold":50000,"gem":100,"tickets":3}}]},
  {"id":"friends_n","cat":"social","name":"친구","unit":"명","tiers":[
    {"goal":1,"reward":{"gold":3000}},
    {"goal":10,"reward":{"gold":12000,"gem":20}},
    {"goal":30,"reward":{"gold":30000,"gem":50,"tickets":1}}]},
  {"id":"guild_join","cat":"social","name":"조직 가입","unit":"","tiers":[
    {"goal":1,"reward":{"gold":10000,"gem":20}}]},
  {"id":"guild_raid","cat":"social","name":"균열 토벌","unit":"회","tiers":[
    {"goal":10,"reward":{"gold":30000,"gem":50,"tickets":1}}]}
]'::jsonb $$;

create or replace function public._ach_score_defs() returns jsonb language sql immutable as $$ select '[
  {"goal":100,"reward":{"gem":50,"tickets":2}},
  {"goal":200,"reward":{"gem":100,"tickets":3}},
  {"goal":350,"reward":{"gem":200,"tickets":5}}
]'::jsonb $$;

create or replace function public._ach_cats() returns jsonb language sql immutable as $$
  select '[{"id":"growth","name":"성장"},{"id":"battle","name":"전투"},{"id":"collect","name":"수집"},{"id":"story","name":"스토리"},{"id":"social","name":"소셜"}]'::jsonb $$;

-- 챕터별 페이즈 수 (전부 클리어해야 챕터 클리어). ch2 는 루트 하나 기준 10
create or replace function public._ach_ch_need(p_ch int) returns int language sql immutable as $$
  select case p_ch
    when 0 then 5 when 1 then 5 when 2 then 10 when 3 then 10 when 4 then 10 when 5 then 10
    when 6 then 10 when 7 then 10 when 8 then 15 when 9 then 18 when 10 then 17
    when 11 then 16 when 12 then 21 when 13 then 15 when 14 then 18 when 15 then 16
    else 0 end $$;

-- ---------- 진행도 계산 (서버) ----------
create or replace function public._ach_prog(p_uid uuid, p_id text) returns int
language plpgsql stable security definer set search_path = public as $$
declare v int := 0; d jsonb; ch text; arr jsonb; n int; mx int := 0;
begin
  if p_id = 'player_lv' then
    if to_regclass('public.player_state') is null then return 0; end if;
    select coalesce(level, 1) into v from player_state where user_id = p_uid; return coalesce(v, 1);
  elsif p_id = 'camp_lv' then
    if to_regclass('public.camp_state') is null then return 0; end if;
    select coalesce(camp_lv, 0) into v from camp_state where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'camp_slots' then
    if to_regclass('public.camp_slots') is null then return 0; end if;
    select count(*)::int into v from camp_slots where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'tower_normal' then
    if to_regclass('public.tower_progress') is null then return 0; end if;
    select coalesce(best_floor, 0) into v from tower_progress where user_id = p_uid and tower = 'normal'; return coalesce(v, 0);
  elsif p_id = 'tower_elem' then
    if to_regclass('public.tower_progress') is null then return 0; end if;
    select coalesce(max(best_floor), 0) into v from tower_progress where user_id = p_uid and tower in ('wind','ice','fire'); return coalesce(v, 0);
  elsif p_id = 'tower_light' then
    if to_regclass('public.tower_progress') is null then return 0; end if;
    select coalesce(max(best_floor), 0) into v from tower_progress where user_id = p_uid and tower in ('light','dark'); return coalesce(v, 0);
  elsif p_id = 'pvp_wins' then
    if to_regclass('public.pvp_ratings') is null then return 0; end if;
    select coalesce(sum(wins), 0)::int into v from pvp_ratings where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'pvp_tier' then
    -- 역대 최고 티어 서열: bronze0 · silver1 · gold2 · platinum3 · diamond4 · abyss5 (업적 목표는 실버1~다이아4)
    if to_regclass('public.pvp_ratings') is null or to_regclass('public.pvp_tier_table') is null then return 0; end if;
    select coalesce(max((select t.ord from pvp_tier_table t where t.min_rating <= coalesce(r.rating, 1000)
                          order by t.min_rating desc limit 1)), 0) into v
      from pvp_ratings r where r.user_id = p_uid;
    return coalesce(v, 0);
  elsif p_id = 'gallery_n' then
    if to_regclass('public.gallery') is null then return 0; end if;
    select count(*)::int into v from gallery where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'gacha_n' then
    if to_regclass('public.story_gacha_log') is null then return 0; end if;
    select count(*)::int into v from story_gacha_log where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'gear_p5' then
    if to_regclass('public.player_gear') is null then return 0; end if;
    select count(*)::int into v from player_gear where user_id = p_uid and plus >= 5; return coalesce(v, 0);
  elsif p_id = 'mvp_n' then
    if to_regclass('public.gallery') is null then return 0; end if;
    select coalesce(sum(mvp_count), 0)::int into v from gallery where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'story_ch' then
    if to_regclass('public.story_progress') is null then return 0; end if;
    select data into d from story_progress where user_id = p_uid;
    if d is null or jsonb_typeof(d->'cleared') is distinct from 'object' then return 0; end if;
    for ch, arr in select key, value from jsonb_each(d->'cleared') loop
      if ch ~ '^[0-9]+$' then
        n := case when jsonb_typeof(arr) = 'array' then jsonb_array_length(arr) else 0 end;
        if n >= _ach_ch_need(ch::int) and ch::int > mx then mx := ch::int; end if;
      end if;
    end loop;
    return mx;
  elsif p_id = 'story_stars' then
    if to_regclass('public.story_progress') is null then return 0; end if;
    select data into d from story_progress where user_id = p_uid;
    if d is null or jsonb_typeof(d->'stars') is distinct from 'object' then return 0; end if;
    select coalesce(sum((v.value)::int), 0)::int into v
      from jsonb_each(d->'stars') ch,
           jsonb_each_text(case when jsonb_typeof(ch.value) = 'object' then ch.value else '{}'::jsonb end) v
     where v.value ~ '^[0-9]+$';
    return coalesce(v, 0);
  elsif p_id = 'attend_n' then
    if to_regclass('public.daily_attend') is null then return 0; end if;
    select coalesce(total, 0) into v from daily_attend where user_id = p_uid; return coalesce(v, 0);
  elsif p_id = 'friends_n' then
    if to_regclass('public.friendships') is null then return 0; end if;
    select count(*)::int into v from friendships where user_a = p_uid or user_b = p_uid; return coalesce(v, 0);
  elsif p_id = 'guild_join' then
    if to_regclass('public.guild_members') is null then return 0; end if;
    select case when exists (select 1 from guild_members where user_id = p_uid) then 1 else 0 end into v; return v;
  elsif p_id = 'guild_raid' then
    if to_regclass('public.guild_raid_attempts') is null then return 0; end if;
    select count(*)::int into v from guild_raid_attempts
     where user_id = p_uid and finished_at is not null and coalesce(voided, false) = false and coalesce(damage, 0) > 0;
    return coalesce(v, 0);
  end if;
  return 0;
end $$;

create or replace function public._ach_key(p_id text, p_goal int) returns text language sql immutable as $$
  select p_id || ':' || p_goal::text $$;

create or replace function public._ach_score_key(p_goal int) returns text language sql immutable as $$
  select 'score:' || p_goal::text $$;

-- 업적 점수 = 받은 칸 합 (마지막 칸 +20, 그 앞 +10). score: 키는 제외
create or replace function public._ach_score(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare a jsonb; t jsonb; n int; i int; g int; s int := 0; k text;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      if exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k) then
        s := s + case when i = n - 1 then 20 else 10 end;
      end if;
    end loop;
  end loop;
  return s;
end $$;

create or replace function public._ach_json(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'::jsonb; a jsonb; t jsonb; i int; n int; prog int; g int; k text; claimed boolean; ready boolean;
  score int; sc jsonb; ready_n int := 0; cat text; cats jsonb := '[]'::jsonb; c jsonb; list jsonb;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    prog := _ach_prog(p_uid, a->>'id');
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      claimed := exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k);
      ready := (not claimed) and prog >= g;
      if ready then ready_n := ready_n + 1; end if;
      items := items || jsonb_build_array(jsonb_build_object(
        'id', a->>'id', 'cat', a->>'cat', 'name', a->>'name', 'unit', coalesce(a->>'unit',''),
        'goal', g, 'prog', least(prog, g), 'raw', prog, 'key', k,
        'reward', t->'reward', 'claimed', claimed, 'ready', ready,
        'pts', case when i = n - 1 then 20 else 10 end,
        'tier', i + 1, 'tiers', n));
    end loop;
  end loop;
  score := _ach_score(p_uid);
  for sc in select x from jsonb_array_elements(_ach_score_defs()) x loop
    g := (sc->>'goal')::int; k := _ach_score_key(g);
    claimed := exists (select 1 from achievement_claims c where c.user_id = p_uid and c.key = k);
    ready := (not claimed) and score >= g;
    if ready then ready_n := ready_n + 1; end if;
    items := items || jsonb_build_array(jsonb_build_object(
      'id', 'score', 'cat', 'score', 'name', '업적 점수', 'unit', '점',
      'goal', g, 'prog', least(score, g), 'raw', score, 'key', k,
      'reward', sc->'reward', 'claimed', claimed, 'ready', ready,
      'pts', 0, 'tier', 0, 'tiers', 0));
  end loop;
  for c in select x from jsonb_array_elements(_ach_cats()) x loop
    cat := c->>'id';
    select coalesce(jsonb_agg(x order by (x->>'id'), (x->>'goal')::int), '[]'::jsonb) into list
      from jsonb_array_elements(items) x where x->>'cat' = cat;
    cats := cats || jsonb_build_array(c || jsonb_build_object('items', list));
  end loop;
  select coalesce(jsonb_agg(x order by (x->>'goal')::int), '[]'::jsonb) into list
    from jsonb_array_elements(items) x where x->>'cat' = 'score';
  return jsonb_build_object('ok', true, 'score', score, 'ready', ready_n,
    'cats', cats, 'score_items', list);
end $$;

revoke all on function public._ach_defs(), public._ach_score_defs(), public._ach_cats(), public._ach_ch_need(int),
  public._ach_prog(uuid, text), public._ach_key(text, int), public._ach_score_key(int),
  public._ach_score(uuid), public._ach_json(uuid) from public, anon, authenticated;

create or replace function public.achievements_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _ach_json(uid);
end $$;

create or replace function public._ach_claim_one(p_uid uuid, p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb; t jsonb; i int; n int; g int; prog int; rw jsonb; ok boolean; score int; sc jsonb;
begin
  -- 점수 마일스톤
  if p_key like 'score:%' then
    g := substr(p_key, 7)::int;
    select x into sc from jsonb_array_elements(_ach_score_defs()) x where (x->>'goal')::int = g;
    if sc is null then raise exception 'invalid key'; end if;
    score := _ach_score(p_uid);
    if score < g then raise exception 'not done'; end if;
    insert into achievement_claims (user_id, key) values (p_uid, p_key) on conflict do nothing returning true into ok;
    if not coalesce(ok, false) then raise exception 'already claimed'; end if;
    return sc->'reward';
  end if;
  -- 일반 업적
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int;
      if _ach_key(a->>'id', g) = p_key then
        prog := _ach_prog(p_uid, a->>'id');
        if prog < g then raise exception 'not done'; end if;
        insert into achievement_claims (user_id, key) values (p_uid, p_key) on conflict do nothing returning true into ok;
        if not coalesce(ok, false) then raise exception 'already claimed'; end if;
        return t->'reward';
      end if;
    end loop;
  end loop;
  raise exception 'invalid key';
end $$;
revoke all on function public._ach_claim_one(uuid, text) from public, anon, authenticated;

create or replace function public.achievements_claim(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rw jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_key is null or char_length(p_key) < 3 then raise exception 'invalid key'; end if;
  perform pg_advisory_xact_lock(hashtext('ach:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  rw := _ach_claim_one(uid, p_key);
  res := _daily_grant(uid, rw, 'ach', 'ach:' || p_key);
  return _ach_json(uid) || res || jsonb_build_object('got', rw);
end $$;

create or replace function public.achievements_claim_all() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); j jsonb; it jsonb; tot jsonb := '{}'::jsonb; k text; v int; rw jsonb; res jsonb; n int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('ach:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  -- 점수 마일스톤은 업적 칸을 먼저 받은 뒤 점수가 오르므로, 업적 → 점수 순으로 두 바퀴
  for j in select 1 from generate_series(1, 2) loop
    for it in
      select x from jsonb_array_elements(_ach_json(uid)->'cats') c, jsonb_array_elements(c->'items') x where (x->>'ready')::boolean
      union all
      select x from jsonb_array_elements(_ach_json(uid)->'score_items') x where (x->>'ready')::boolean
    loop
      begin
        rw := _ach_claim_one(uid, it->>'key');
        res := _daily_grant(uid, rw, 'ach', 'ach:' || (it->>'key'));
        n := n + 1;
        if coalesce((rw->>'gold')::int, 0) > 0 then tot := tot || jsonb_build_object('gold', coalesce((tot->>'gold')::int, 0) + (rw->>'gold')::int); end if;
        if coalesce((rw->>'gem')::int, 0) > 0 then tot := tot || jsonb_build_object('gem', coalesce((tot->>'gem')::int, 0) + (rw->>'gem')::int); end if;
        if coalesce((rw->>'tickets')::int, 0) > 0 then tot := tot || jsonb_build_object('tickets', coalesce((tot->>'tickets')::int, 0) + (rw->>'tickets')::int); end if;
      exception when others then
        if SQLERRM not in ('already claimed', 'not done') then raise; end if;
      end;
    end loop;
  end loop;
  if n = 0 then raise exception 'not done'; end if;
  return _ach_json(uid) || jsonb_build_object('got', tot, 'claimed_n', n);
end $$;

revoke all on function public.achievements_status(), public.achievements_claim(text), public.achievements_claim_all() from public, anon;
grant execute on function public.achievements_status(), public.achievements_claim(text), public.achievements_claim_all() to authenticated;
