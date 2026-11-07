-- ⚠ 테스트 전용 10/10. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> 'ac67dd4f5df4920603189b3e57b25a5e13e409b830a4a45862378c594de08997' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 10) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 10 and part_hash = '62ec91dea0befbcd11ec69a76b61508845e704448311e122073fd0b573661bbc') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '10_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 10) <> 9 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (10_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- 4) 스토리 소탕 → 일일·주간 '스토리 스테이지 클리어'
-- 클라(js/story.js · js/daily.js)가 vr:daily { mode:story, n:runs, sweep:true } 로 daily_track/weekly_track 호출.
-- 서버 story_sweep 은 건드리지 않음 (중복 카운트·함수 드리프트 방지).

notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: achievements2.sql =====
-- =====================================================================
-- 🏆 업적 2차 — 아케이드 승리 · 스킬 사용 · 선물 보내기 + 칭호 보상 + 업적 점수 500
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: achievements.sql · cosmetics.sql · cosmetics2.sql · daily_social.sql(friend_gifts)
-- 새 공개 RPC: ach_track(kind, n)  — 'arcade_win' / 'skill' 누적 (서버 상한·간격 제한)
-- 선물 보내기는 friend_gifts 기록에서 계산 (소급 O). 아케이드·스킬은 이 SQL 이후부터 누적
-- 칭호: 해당 업적 마지막 칸(또는 점수 500)을 "받으면" 해금
-- =====================================================================

create table if not exists public.ach_counters (
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('arcade_wins', 'skill_uses')),
  n          bigint not null default 0,
  last_at    timestamptz not null default now(),
  primary key (user_id, kind)
);$vr_statement$;
  execute $vr_statement$alter table public.ach_counters enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.ach_counters from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.ach_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text; add int; last timestamptz; nv bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  k := case p_kind when 'arcade_win' then 'arcade_wins' when 'skill' then 'skill_uses' else null end;
  if k is null then raise exception 'invalid kind'; end if;
  -- 1회 호출 상한: 아케이드 승리 1 · 스킬 40 / 아케이드는 20초 간격
  add := greatest(0, least(coalesce(p_n, 1), case k when 'arcade_wins' then 1 else 40 end));
  if add = 0 then return jsonb_build_object('ok', true, 'kind', k); end if;
  perform pg_advisory_xact_lock(hashtext('achc:' || uid::text));
  select last_at into last from ach_counters where user_id = uid and kind = k;
  if k = 'arcade_wins' and last is not null and now() - last < interval '20 seconds' then
    return jsonb_build_object('ok', false, 'kind', k);
  end if;
  insert into ach_counters (user_id, kind, n, last_at) values (uid, k, add, now())
    on conflict (user_id, kind) do update set n = ach_counters.n + add, last_at = now()
    returning n into nv;
  return jsonb_build_object('ok', true, 'kind', k, 'n', nv);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.ach_track(text, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.ach_track(text, int) to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_title_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"recruit","name":"신입 대원","how":"기본"},
  {"id":"story_walker","name":"스토리 워커","how":"챕터 5 클리어"},
  {"id":"abyss_witness","name":"심연의 목격자","how":"챕터 15 클리어"},
  {"id":"tower_climber","name":"탑 등반가","how":"일반탑 50층"},
  {"id":"tower_conqueror","name":"탑의 정복자","how":"일반탑 100층"},
  {"id":"collector","name":"수집가","how":"도감 50%"},
  {"id":"pvp_gold","name":"골드","how":"PvP 골드 티어"},
  {"id":"pvp_platinum","name":"플래티넘","how":"PvP 플래티넘 티어"},
  {"id":"pvp_diamond","name":"다이아","how":"PvP 다이아 티어"},
  {"id":"abyss_pioneer","name":"심연 개척자","how":"업적 점수 350"},
  {"id":"abyss","name":"심연","how":"PvP 심연 시즌"},
  {"id":"gutter_king","name":"뒷골목 승부사","how":"업적 · 아케이드 300승"},
  {"id":"blood_art","name":"피로 새긴 기술","how":"업적 · 스킬 3000회"},
  {"id":"blood_brother","name":"피를 나눈 형제","how":"업적 · 선물 365회"},
  {"id":"abyss_ruler","name":"심연의 지배자","how":"업적 점수 500"}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_title_name(p_id text) returns text language sql stable set search_path = public as $$
  select case when p_id is null then null
    else (select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = p_id) end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_title_owned(p_uid uuid, p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from achievement_claims where user_id = p_uid and key = p_key) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_defs() returns jsonb language sql immutable as $$ select '[
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
    {"goal":10,"reward":{"gold":30000,"gem":50,"tickets":1}}]},
  {"id":"arcade_wins","cat":"battle","name":"아케이드 승리","unit":"승","tiers":[
    {"goal":10,"reward":{"gold":8000}},
    {"goal":50,"reward":{"gold":20000,"gem":30}},
    {"goal":150,"reward":{"gold":40000,"gem":60,"tickets":1}},
    {"goal":300,"reward":{"gold":70000,"gem":120,"tickets":2},"title":"gutter_king"}]},
  {"id":"skill_uses","cat":"battle","name":"스킬 사용","unit":"회","tiers":[
    {"goal":50,"reward":{"gold":8000}},
    {"goal":300,"reward":{"gold":20000,"gem":30}},
    {"goal":1000,"reward":{"gold":40000,"gem":60,"tickets":1}},
    {"goal":3000,"reward":{"gold":70000,"gem":120,"tickets":2},"title":"blood_art"}]},
  {"id":"gifts_sent","cat":"social","name":"선물 보내기","unit":"회","tiers":[
    {"goal":10,"reward":{"gold":5000}},
    {"goal":50,"reward":{"gold":15000,"gem":20}},
    {"goal":150,"reward":{"gold":30000,"gem":50,"tickets":1}},
    {"goal":365,"reward":{"gold":50000,"gem":100,"tickets":2},"title":"blood_brother"}]}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_score_defs() returns jsonb language sql immutable as $$ select '[
  {"goal":100,"reward":{"gem":50,"tickets":2}},
  {"goal":200,"reward":{"gem":100,"tickets":3}},
  {"goal":350,"reward":{"gem":200,"tickets":5}},
  {"goal":500,"reward":{"gem":300,"tickets":8},"title":"abyss_ruler"}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_prog(p_uid uuid, p_id text) returns int
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
  elsif p_id in ('arcade_wins', 'skill_uses') then
    select coalesce(n, 0)::int into v from ach_counters where user_id = p_uid and kind = p_id; return coalesce(v, 0);
  elsif p_id = 'gifts_sent' then
    if to_regclass('public.friend_gifts') is null then return 0; end if;
    select count(*)::int into v from friend_gifts where from_user = p_uid; return coalesce(v, 0);
  end if;
  return 0;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_json(p_uid uuid) returns jsonb
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
        'tier', i + 1, 'tiers', n, 'title', _ach_title_name(t->>'title')));
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
      'pts', 0, 'tier', 0, 'tiers', 0, 'title', _ach_title_name(sc->>'title')));
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
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_owned(p_uid uuid, p_kind text, p_id text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if p_kind = 'title' then
    if p_id = 'recruit' then return true; end if;
    if p_id = 'story_walker' then return _cosmo_story_ch(p_uid) >= 5; end if;
    if p_id = 'abyss_witness' then return _cosmo_story_ch(p_uid) >= 15; end if;
    if p_id = 'tower_climber' then return _cosmo_tower(p_uid) >= 50; end if;
    if p_id = 'tower_conqueror' then return _cosmo_tower(p_uid) >= 100; end if;
    if p_id = 'collector' then return _cosmo_gallery_pct(p_uid) >= 50; end if;
    if p_id = 'pvp_gold' then return _cosmo_pvp_ord(p_uid) >= 2; end if;
    if p_id = 'pvp_platinum' then return _cosmo_pvp_ord(p_uid) >= 3; end if;
    if p_id = 'pvp_diamond' then return _cosmo_pvp_ord(p_uid) >= 4; end if;
    if p_id = 'gutter_king' then return _ach_title_owned(p_uid, 'arcade_wins:300'); end if;
    if p_id = 'blood_art' then return _ach_title_owned(p_uid, 'skill_uses:3000'); end if;
    if p_id = 'blood_brother' then return _ach_title_owned(p_uid, 'gifts_sent:365'); end if;
    if p_id = 'abyss_ruler' then return _ach_title_owned(p_uid, 'score:500'); end if;
    if p_id = 'abyss_pioneer' then return _cosmo_ach_score(p_uid) >= 350; end if;
    if p_id = 'abyss' then
      return _cosmo_pvp_ord(p_uid) >= 5
        or (to_regclass('public.pvp_titles') is not null
            and exists (select 1 from pvp_titles where user_id = p_uid and title = 'abyss'));
    end if;
    return _cosmo_bought(p_uid, 'title', p_id);
  elsif p_kind = 'frame' then
    if p_id = 'frame_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'frame', p_id) then return true; end if;
    if p_id = 'frame_bronze' then return _cosmo_tower(p_uid) >= 30; end if;
    if p_id = 'frame_silver' then return _cosmo_gallery_pct(p_uid) >= 25; end if;
    if p_id = 'frame_gold' then return _cosmo_story_ch(p_uid) >= 10; end if;
    if p_id = 'frame_abyss' then
      return _cosmo_ach_score(p_uid) >= 200
        or _cosmo_pvp_ord(p_uid) >= 5
        or (to_regclass('public.pvp_titles') is not null
            and exists (select 1 from pvp_titles where user_id = p_uid and title = 'abyss'));
    end if;
    if p_id = 'frame_guild' then
      return to_regclass('public.guild_titles') is not null
        and exists (select 1 from guild_titles where user_id = p_uid and title = 'guild_frame');
    end if;
  elsif p_kind = 'board' then
    if p_id = 'board_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'board', p_id) then return true; end if;
    if p_id = 'board_alley' then return _cosmo_tower(p_uid) >= 20; end if;
    if p_id = 'board_antnest' then return _cosmo_story_ch(p_uid) >= 2; end if;
    if p_id = 'board_rift' then return _cosmo_ach_score(p_uid) >= 100 or _cosmo_tower(p_uid) >= 50; end if;
  elsif p_kind = 'border' then
    if p_id = 'border_basic' then return true; end if;
    if _cosmo_bought(p_uid, 'border', p_id) then return true; end if;
    if p_id = 'border_alley' then return _cosmo_tower(p_uid) >= 20; end if;
    if p_id = 'border_antnest' then return _cosmo_story_ch(p_uid) >= 2; end if;
    if p_id = 'border_rift' then return _cosmo_ach_score(p_uid) >= 100 or _cosmo_tower(p_uid) >= 50; end if;
  end if;
  return false;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._ach_defs(), public._ach_score_defs(), public._ach_prog(uuid, text), public._ach_json(uuid),
  public._ach_title_name(text), public._ach_title_owned(uuid, text), public._cosmo_owned(uuid, text, text)
  from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 공개 게임 설정만 명시적으로 조회 허용 (사용자 자료 아님).
grant select on public.story_card_pool, public.story_phase_config, public.story_premium_ur,
  public.pvp_card_meta, public.pvp_reward_table, public.pvp_tier_table, public.pvp_streak_table,
  public.dispatch_card_meta, public.dispatch_zones to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 설치 완료 (원본 SQL의 사용자 테이블은 처음부터 비어 있어야 함).
set local check_function_bodies = on;$vr_statement$;
  execute $vr_statement$do $staging_verify$
declare f record;
begin
  for f in
    select pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop execute f.ddl; end loop;
  if exists (select 1 from auth.users) then raise exception 'STOP: 설치 중 사용자 자료 발견'; end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')) then
    raise exception 'STOP: RLS 없는 테이블 발견';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and left(p.proname,1)='_'
      and pg_get_function_result(p.oid) <> 'trigger'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
    raise exception 'STOP: 외부 호출 가능한 내부 서버 함수 발견';
  end if;
end $staging_verify$;$vr_statement$;

  grant usage on schema public to public, anon, authenticated;
  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (10, 'ac67dd4f5df4920603189b3e57b25a5e13e409b830a4a45862378c594de08997', '62ec91dea0befbcd11ec69a76b61508845e704448311e122073fd0b573661bbc', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '10_install.sql: 완료 또는 이미 완료 (10/10)' as result;
