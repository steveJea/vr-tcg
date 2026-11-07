-- ⚠ 테스트 전용 10/13. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> 'cc55a18ffb6e7f31c29402be300a5e256b333fd450277ae07e425819f76899c9' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 10) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 10 and part_hash = '06ed9a63be6b194a3da066e8cb9b234a77ce595a1b463052e049287d57159144') then
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
  execute $vr_statement$-- ===== SOURCE: security_phase1_rewards.sql =====
-- 보안 1단계: 보상 근거 분리 / 임의 카운터 차단 (2026-11-07 KST)
-- 먼저 docs/SECURITY_PHASE1.md와 security_phase1_preflight.sql 확인.
-- 기존 DB에는 이 파일만 실행. staging/설치본이나 옛 SQL을 재실행하지 마세요.
-- 소유자가 테스트 DB에 먼저 적용/확인, 운영은 별도 승인 후 같은 파일 적용.
-- 기존 잔액/도감/수령/진행 행 삭제·초기화·자동 보상 회수 없음.
-- 중요: 전투 검증기 없는 보상은 정상 플레이에서도 지급 보류됩니다.
-- 설치본의 단일 트랜잭션에 포함
select pg_advisory_xact_lock(20261107, 501);$vr_statement$;
  execute $vr_statement$do $preconditions$
declare obj text;
begin
  foreach obj in array array['gallery','gallery_claims','daily_progress','weekly_progress',
    'daily_attend','achievement_claims','ach_counters','story_progress','story_gacha',
    'story_gacha_log','story_card_pool','card_id_alias','player_wallet','gem_ledger',
    'arcade_tut_claims','pvp_reward_claims','pvp_tier_claims','guild_claims'] loop
    if to_regclass('public.' || obj) is null then raise exception 'STOP: missing table %; inspect preflight', obj; end if;
  end loop;
  foreach obj in array array['_daily_defs()','_weekly_defs()','_ach_defs()',
    '_daily_grant(uuid,jsonb,text,text)','_gem_add(uuid,integer,integer,text,text,jsonb)',
    '_gem_sync(uuid)','_story_ticket_sync(uuid)','_gallery_sync_owned(uuid,jsonb)',
    'gallery_register(text[],text)','daily_track(text,integer)','weekly_track(text,integer)',
    'ach_track(text,integer)','tower_complete(text,integer,jsonb)',
    'tower_sweep_complete(text,integer,jsonb)','pvp_report(bigint,integer,integer)'] loop
    if to_regprocedure('public.' || obj) is null then raise exception 'STOP: missing function %; inspect preflight', obj; end if;
  end loop;
end $preconditions$;$vr_statement$;
  execute $vr_statement$-- No client-writable flags or generic "verify this result" RPC. Later phases must
-- supply a verifier, not flip an unverified client result into a trusted event.
create table if not exists public.reward_security_policy (
  key text primary key, enabled boolean not null default false,
  installed_at timestamptz not null default now(),
  check (key in ('battle_rewards_v1')), check (not enabled)
);$vr_statement$;
  execute $vr_statement$insert into public.reward_security_policy(key) values ('battle_rewards_v1') on conflict do nothing;$vr_statement$;
  execute $vr_statement$alter table public.reward_security_policy enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.reward_security_policy from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create table if not exists public.verified_game_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_kind text not null check (source_kind = 'gacha'),
  source_id text not null,
  event_kind text not null check (event_kind = 'card_acquired'),
  card_id text not null references public.story_card_pool(id),
  rule_version integer not null default 1 check (rule_version = 1),
  occurred_at timestamptz not null default now(),
  unique(user_id, source_kind, source_id, event_kind)
);$vr_statement$;
  execute $vr_statement$create index if not exists verified_game_events_user_card on public.verified_game_events(user_id, card_id);$vr_statement$;
  execute $vr_statement$alter table public.verified_game_events enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.verified_game_events from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create table if not exists public.reward_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_kind text not null,
  source_or_period text not null,
  reward jsonb not null check (jsonb_typeof(reward) = 'object'),
  result jsonb not null default '{}'::jsonb,
  rule_version integer not null default 1,
  claimed_at timestamptz not null default now(),
  primary key(user_id, reward_kind, source_or_period)
);$vr_statement$;
  execute $vr_statement$alter table public.reward_claims enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.reward_claims from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- Release catalog from data/cards.csv. Hidden pool entries cannot inflate collection %.
create table if not exists public.reward_card_catalog (
  card_id text primary key references public.story_card_pool(id)
);$vr_statement$;
  execute $vr_statement$alter table public.reward_card_catalog enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.reward_card_catalog from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$insert into public.reward_card_catalog(card_id) values
  ('10118'),
  ('10019'),
  ('10018'),
  ('10299'),
  ('10074'),
  ('10080'),
  ('10445'),
  ('10375'),
  ('10051'),
  ('10404'),
  ('10049'),
  ('10048'),
  ('10189'),
  ('10060'),
  ('10071'),
  ('10086'),
  ('10169'),
  ('10137'),
  ('10138'),
  ('10020'),
  ('10463'),
  ('10228'),
  ('10453'),
  ('10293'),
  ('10010'),
  ('10380'),
  ('10114'),
  ('10401'),
  ('10315'),
  ('10026'),
  ('10191'),
  ('10469'),
  ('10001'),
  ('10183'),
  ('10064'),
  ('10444'),
  ('10279'),
  ('10225'),
  ('10431'),
  ('10332'),
  ('10201'),
  ('10346'),
  ('10275'),
  ('10124'),
  ('10134'),
  ('10037'),
  ('10031'),
  ('10180'),
  ('10390'),
  ('10027'),
  ('10033'),
  ('10353'),
  ('10244'),
  ('10245'),
  ('10292'),
  ('10076'),
  ('10045'),
  ('10409'),
  ('10407'),
  ('10036'),
  ('10075'),
  ('10173'),
  ('10406'),
  ('10328'),
  ('10329'),
  ('10098'),
  ('10187'),
  ('10319'),
  ('10081'),
  ('10252'),
  ('10298'),
  ('10125'),
  ('10025'),
  ('10035'),
  ('10112'),
  ('10270'),
  ('10069'),
  ('10088'),
  ('10004'),
  ('10420'),
  ('10408'),
  ('10205'),
  ('10139'),
  ('10347'),
  ('10023'),
  ('10448'),
  ('10067'),
  ('10005'),
  ('10276'),
  ('10259'),
  ('10386'),
  ('10105'),
  ('10077'),
  ('10212'),
  ('10065'),
  ('10008'),
  ('10425'),
  ('10107'),
  ('10032'),
  ('10142'),
  ('10089'),
  ('10094'),
  ('10350'),
  ('10366'),
  ('10016'),
  ('10385'),
  ('10474'),
  ('10287'),
  ('10182'),
  ('10136'),
  ('10209'),
  ('10170'),
  ('10128'),
  ('10433'),
  ('10374'),
  ('10218'),
  ('10441'),
  ('10349'),
  ('10314'),
  ('10337'),
  ('10038'),
  ('10365'),
  ('10278'),
  ('10251'),
  ('10109'),
  ('10017'),
  ('10015'),
  ('10028'),
  ('10181'),
  ('10333'),
  ('10054'),
  ('10046'),
  ('10066'),
  ('10195'),
  ('10283'),
  ('10284'),
  ('10321'),
  ('10320'),
  ('10371'),
  ('10345'),
  ('10021'),
  ('10424'),
  ('10398'),
  ('10318'),
  ('10458'),
  ('10464'),
  ('10233'),
  ('10034'),
  ('10171'),
  ('10119'),
  ('10226'),
  ('10307'),
  ('10402'),
  ('10009'),
  ('10055'),
  ('10013'),
  ('10313'),
  ('10106'),
  ('10316'),
  ('10416'),
  ('10057'),
  ('10220'),
  ('10340'),
  ('10309'),
  ('10070'),
  ('10113'),
  ('10364'),
  ('10410'),
  ('10419'),
  ('10053'),
  ('10176'),
  ('10200'),
  ('10234'),
  ('10123'),
  ('10304'),
  ('10434'),
  ('10430'),
  ('10379'),
  ('10325'),
  ('10260'),
  ('10300'),
  ('10462'),
  ('10072'),
  ('10256'),
  ('10115'),
  ('10348'),
  ('10339'),
  ('10394'),
  ('10047'),
  ('10188'),
  ('10132'),
  ('10087'),
  ('10202'),
  ('10184'),
  ('10103'),
  ('10265'),
  ('10266'),
  ('10465'),
  ('10466'),
  ('10002'),
  ('10289'),
  ('10083'),
  ('10079'),
  ('10338'),
  ('10336'),
  ('10418'),
  ('10323'),
  ('10403'),
  ('10185'),
  ('10308'),
  ('10413'),
  ('10415'),
  ('10414'),
  ('10186'),
  ('10295'),
  ('10297'),
  ('10317'),
  ('10108'),
  ('10417'),
  ('10172'),
  ('10262'),
  ('10261'),
  ('10290'),
  ('10384'),
  ('10383'),
  ('10110'),
  ('10442'),
  ('10129'),
  ('10014'),
  ('10235'),
  ('10111'),
  ('10357'),
  ('10360'),
  ('10306'),
  ('10285'),
  ('10343'),
  ('10271'),
  ('10003'),
  ('10095'),
  ('10096'),
  ('10342'),
  ('10327'),
  ('10286'),
  ('10273'),
  ('10253'),
  ('10061'),
  ('10460'),
  ('10459'),
  ('10461'),
  ('10296'),
  ('10246'),
  ('10204'),
  ('10447'),
  ('10429'),
  ('10211'),
  ('10193'),
  ('10120'),
  ('10101'),
  ('10099'),
  ('10241'),
  ('10044'),
  ('10043'),
  ('10376'),
  ('10377'),
  ('10322'),
  ('10239'),
  ('10039'),
  ('10310'),
  ('10247'),
  ('10248'),
  ('10221'),
  ('10011'),
  ('10140'),
  ('10388'),
  ('10121'),
  ('10236'),
  ('10102'),
  ('10092'),
  ('10194'),
  ('10361'),
  ('10354'),
  ('10254'),
  ('10222'),
  ('10470'),
  ('10059'),
  ('10428'),
  ('10471'),
  ('10450'),
  ('10432'),
  ('10359'),
  ('10362'),
  ('10454'),
  ('10363'),
  ('10436'),
  ('10412'),
  ('10040'),
  ('10042'),
  ('10237'),
  ('10207'),
  ('10208'),
  ('10303'),
  ('10468'),
  ('10467'),
  ('10294'),
  ('10258'),
  ('10056'),
  ('10041'),
  ('10255'),
  ('10141'),
  ('10133'),
  ('10091'),
  ('10090'),
  ('10344'),
  ('10330'),
  ('10263'),
  ('10249'),
  ('10063'),
  ('10052'),
  ('10190'),
  ('10174'),
  ('10122'),
  ('10029'),
  ('10232'),
  ('10104'),
  ('10378'),
  ('10126'),
  ('10062'),
  ('10203'),
  ('10097'),
  ('10280'),
  ('10352'),
  ('10277'),
  ('10100'),
  ('10451'),
  ('10389'),
  ('10264'),
  ('10438'),
  ('10177'),
  ('10178'),
  ('10372'),
  ('10373'),
  ('10130'),
  ('10131'),
  ('10341'),
  ('10272'),
  ('10117'),
  ('10078'),
  ('10084'),
  ('10085'),
  ('10217'),
  ('10216'),
  ('10324'),
  ('10006'),
  ('10068'),
  ('10400'),
  ('10331'),
  ('10250'),
  ('10022'),
  ('10437'),
  ('10426'),
  ('10381'),
  ('10179'),
  ('10215'),
  ('10214'),
  ('10223'),
  ('10269'),
  ('10268'),
  ('10473'),
  ('10135'),
  ('10206'),
  ('10240'),
  ('10238'),
  ('10230'),
  ('10227'),
  ('10387'),
  ('10281'),
  ('10472'),
  ('10455'),
  ('10423'),
  ('10456'),
  ('10457'),
  ('10224'),
  ('10382'),
  ('10393'),
  ('10030'),
  ('10391'),
  ('10392'),
  ('10311'),
  ('10397'),
  ('10242'),
  ('10356'),
  ('10274'),
  ('10192'),
  ('10093'),
  ('10312'),
  ('10243'),
  ('10231'),
  ('10399'),
  ('10050'),
  ('10073'),
  ('10229'),
  ('10012'),
  ('10219'),
  ('10305'),
  ('10443'),
  ('10024'),
  ('10446'),
  ('10427'),
  ('10411'),
  ('10058'),
  ('10395'),
  ('10213'),
  ('10175'),
  ('10007'),
  ('10257'),
  ('10291'),
  ('10326'),
  ('10288'),
  ('10282'),
  ('10405'),
  ('10452'),
  ('10370'),
  ('10368'),
  ('10369'),
  ('10358'),
  ('10351'),
  ('10449'),
  ('10422'),
  ('10421'),
  ('10396'),
  ('10435'),
  ('10127'),
  ('10439'),
  ('10355'),
  ('10367'),
  ('10440'),
  ('10267'),
  ('10509')
on conflict do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_total() returns int
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select count(*)::int from public.reward_card_catalog
$$;$vr_statement$;
  execute $vr_statement$-- Actual INSERT into the server-only draw log is the evidence, NOT owned JSON,
-- gallery, matches, a browser event, or an old counter. No legacy backfill.
create or replace function public._reward_gacha_event() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare cid text; eid bigint;
begin
  select p.id into cid from public.story_card_pool p
  where p.id = coalesce((select a.new_id from public.card_id_alias a where a.old_id = new.card_id), new.card_id);
  if cid is null then raise exception 'invalid acquired card'; end if;
  insert into public.verified_game_events(user_id, source_kind, source_id, event_kind, card_id)
  values (new.user_id, 'gacha', new.id::text, 'card_acquired', cid)
  on conflict do nothing returning id into eid;
  if eid is not null then
    insert into public.gallery(user_id, card_id, count, mvp_count, first_at, last_at)
    values (new.user_id, cid, 0, 0, now(), now() - interval '1 minute')
    on conflict (user_id, card_id) do nothing;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._reward_gacha_event() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists reward_gacha_event on public.story_gacha_log;$vr_statement$;
  execute $vr_statement$create trigger reward_gacha_event after insert on public.story_gacha_log
for each row execute function public._reward_gacha_event();$vr_statement$;
  execute $vr_statement$-- The old JSON trigger is intentionally removed. Do not certify existing owned
-- cards or gallery rows as acquisitions (including a sold/forged legacy card).
drop trigger if exists story_progress_gallery on public.story_progress;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_sync_owned(p_uid uuid, p_data jsonb)
returns int language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select 0 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_have(p_uid uuid) returns int
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select count(distinct e.card_id)::int from public.verified_game_events e
  join public.reward_card_catalog c on c.card_id=e.card_id
  where user_id = p_uid and event_kind = 'card_acquired'
$$;$vr_statement$;
  execute $vr_statement$-- All currencies in a daily/gallery/achievement grant share one receipt. The
-- caller already validates its server catalog and eligibility; this is private.
-- Row/period locks in public claim RPCs precede the gem lock, then wallet/tickets.
create or replace function public._daily_grant(p_uid uuid, p_rw jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare res jsonb := '{}'::jsonb; prior public.reward_claims; t int; inserted boolean; k text; v jsonb;
begin
  if p_uid is null or p_ref is null or length(p_ref) not between 1 and 200
    or p_reason is null or p_reason not in ('attend','daily','weekly','gallery','ach')
    or jsonb_typeof(p_rw) is distinct from 'object' then raise exception 'invalid reward'; end if;
  for k, v in select * from jsonb_each(p_rw) loop
    if k not in ('gold','gem','tickets') or jsonb_typeof(v) <> 'number'
      or v::text !~ '^[0-9]+$' or v::numeric > 2147483647 then raise exception 'invalid reward'; end if;
  end loop;
  perform pg_advisory_xact_lock(hashtext('gem:' || p_uid::text));
  select * into prior from public.reward_claims where user_id=p_uid and reward_kind=p_reason and source_or_period=p_ref;
  if found then
    if prior.reward <> p_rw then raise exception 'reward conflict'; end if;
    return prior.result;
  end if;
  -- Old gem receipts are NOT permission to replay ticket/gold parts of a grant.
  if exists (select 1 from public.gem_ledger where user_id=p_uid and ref=p_ref) then raise exception 'already claimed'; end if;
  insert into public.reward_claims(user_id, reward_kind, source_or_period, reward)
  values (p_uid,p_reason,p_ref,p_rw) on conflict do nothing returning true into inserted;
  if not coalesce(inserted,false) then raise exception 'already claimed'; end if;
  if coalesce((p_rw->>'gold')::int,0)>0 then
    res := res || jsonb_build_object('wallet',public._wallet_add(p_uid,jsonb_build_object('gold',(p_rw->>'gold')::int),p_reason));
  end if;
  if coalesce((p_rw->>'gem')::int,0)>0 then
    perform public._gem_add(p_uid,(p_rw->>'gem')::int,0,p_reason,p_ref,jsonb_build_object('rule_version',1));
  end if;
  if coalesce((p_rw->>'tickets')::int,0)>0 then
    insert into public.story_gacha(user_id,last_draw) values (p_uid,public._gem_day()-1) on conflict do nothing;
    update public.story_gacha set tickets=tickets+(p_rw->>'tickets')::int, updated_at=now() where user_id=p_uid returning tickets into t;
    res := res || jsonb_build_object('tickets',t);
  end if;
  update public.reward_claims set result=res where user_id=p_uid and reward_kind=p_reason and source_or_period=p_ref;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$-- Legacy mission and battle counters are retained but never used as evidence.
-- No battle event supplier exists in phase 1, so all daily/weekly combat claims
-- are held. Attendance is still server date + auth + account/day lock.
create or replace function public._reward_battle_enabled() returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce((select enabled from public.reward_security_policy where key='battle_rewards_v1'),false)
$$;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.ach_track(p_kind text, p_n int default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_claim(p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_claim(p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.story_star_claim(p_chapter int, p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_claim_tier(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_claim_reward(p_league text, p_mode text, p_season date) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.raid_claim() returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.war_claim() returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.gallery_register(p_cards text[], p_mvp text default null)
returns table(card_id text, count int, mvp_count int, is_new boolean)
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  raise exception 'reward verification pending' using errcode='P0001';
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._daily_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare dp daily_progress; a daily_attend; today date := _gem_day(); done int;
begin
  select * into dp from daily_progress where user_id = p_uid and day = today;
  select * into a from daily_attend where user_id = p_uid;
  select count(*) into done from jsonb_array_elements(_daily_defs()) m where 0 >= (m->>'goal')::int;
  return jsonb_build_object('ok', true, 'reward_held', true, 'day', today,
    'next_reset', ((today + 1)::timestamp at time zone 'Asia/Seoul'),
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, 0),
                   'claimed', coalesce(dp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_daily_defs()) m),
    'all', jsonb_build_object('reward', _daily_all_reward(), 'done', done, 'goal', jsonb_array_length(_daily_defs()), 'claimed', coalesce(dp.claimed, '[]'::jsonb) ? 'all'),
    'attend', jsonb_build_object('rewards', _attend_defs(), 'step', case when coalesce(a.step, 0) >= 7 and a.last_day < today then 0 else coalesce(a.step, 0) end,
                   'today', a.last_day = today, 'total', coalesce(a.total, 0)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._weekly_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare wp weekly_progress; v_week date := _weekly_week(); done int; next_reset timestamptz;
begin
  select * into wp from weekly_progress where user_id = p_uid and week = v_week;
  select count(*) into done from jsonb_array_elements(_weekly_defs()) m where 0 >= (m->>'goal')::int;
  next_reset := ((v_week + 7)::timestamp at time zone 'Asia/Seoul');
  return jsonb_build_object('ok', true, 'reward_held', true, 'week', v_week, 'next_reset', next_reset,
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, 0),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_weekly_defs()) m),
    'all', jsonb_build_object('reward', _weekly_all_reward(), 'done', done, 'goal', jsonb_array_length(_weekly_defs()),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? 'all'));
end $$;$vr_statement$;
  execute $vr_statement$-- Only independently server-observed actions can unlock an achievement today.
create or replace function public._ach_prog(p_uid uuid,p_id text) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v int := 0;
begin
  case p_id
  when 'camp_lv' then select camp_lv into v from public.camp_state where user_id=p_uid;
  when 'camp_slots' then select count(*)::int into v from public.camp_slots where user_id=p_uid;
  when 'gallery_n' then return public._gallery_have(p_uid);
  when 'gacha_n' then select count(*)::int into v from public.verified_game_events where user_id=p_uid and event_kind='card_acquired';
  when 'gear_p5' then select count(*)::int into v from public.player_gear where user_id=p_uid and plus>=5;
  when 'attend_n' then select total into v from public.daily_attend where user_id=p_uid;
  when 'friends_n' then select count(*)::int into v from public.friendships where user_a=p_uid or user_b=p_uid;
  when 'guild_join' then select exists(select 1 from public.guild_members where user_id=p_uid)::int into v;
  when 'gifts_sent' then select count(*)::int into v from public.friend_gifts where from_user=p_uid;
  else return 0; -- battle/level/star/MVP counters need phase 2-5 verifiers
  end case;
  return coalesce(v,0);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_score(p_uid uuid) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare a jsonb; t jsonb; n int; i int; g int; s int := 0; k text;
begin
  for a in select x from jsonb_array_elements(_ach_defs()) x loop
    n := jsonb_array_length(a->'tiers');
    for i in 0 .. n - 1 loop
      t := a->'tiers'->i; g := (t->>'goal')::int; k := _ach_key(a->>'id', g);
      if exists (select 1 from public.reward_claims c where c.user_id=p_uid and c.reward_kind='ach' and c.source_or_period='ach:' || k) then
        s := s + case when i = n - 1 then 20 else 10 end;
      end if;
    end loop;
  end loop;
  return s;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_json(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
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
        'tier', i + 1, 'tiers', n, 'held', a->>'id' not in ('camp_lv','camp_slots','gallery_n','gacha_n','gear_p5','attend_n','friends_n','guild_join','gifts_sent'), 'title', _ach_title_name(t->>'title')));
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
  execute $vr_statement$create or replace function public.attend_claim() returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); today date := _gem_day(); a daily_attend; st int; rw jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_attend (user_id) values (uid) on conflict do nothing;
  select * into a from daily_attend where user_id = uid for update;
  if a.last_day = today then raise exception 'already claimed'; end if;
  st := case when a.step >= 7 then 1 else a.step + 1 end;
  rw := _attend_defs()->(st - 1);
  update daily_attend set last_day = today, step = st, total = total + 1 where user_id = uid;
  res := _daily_grant(uid, rw, 'attend', 'attend:' || today);
  return _daily_json(uid) || res || jsonb_build_object('got', rw, 'got_day', st);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'reward_held', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_rw(1), '2', _arcade_tut_rw(2), '3', _arcade_tut_rw(3)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_ticket_sync(uid uuid) returns jsonb
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
declare t int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into public.story_gacha(user_id,last_draw) values (uid,public._gem_day()-1) on conflict do nothing;
  select tickets into t from public.story_gacha where user_id=uid for update;
  return jsonb_build_object('tickets',t,'added',0,'chapters','[]'::jsonb,'reward_held',true);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gem_sync(p_uid uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d jsonb; ch int; r jsonb; out jsonb := '[]'::jsonb; lg gem_login; today date := _gem_day();
begin
  -- Chapter gems are held until phase 2; daily login remains server dated.
  insert into gem_login (user_id, last_day, streak) values (p_uid, today - 1, 0) on conflict (user_id) do nothing;
  select * into lg from gem_login where user_id = p_uid for update;
  if lg.last_day < today then
    lg.streak := case when lg.last_day = today - 1 then lg.streak + 1 else 1 end;
    update gem_login set last_day = today, streak = lg.streak where user_id = p_uid;
    if lg.streak % 7 = 0 then
      r := _gem_add(p_uid, _gem_login_reward(), 0, 'login_7', 'login:' || today, jsonb_build_object('streak', lg.streak));
      if r is not null then out := out || jsonb_build_array(jsonb_build_object('reason', 'login_7', 'streak', lg.streak, 'gem', _gem_login_reward())); end if;
    end if;
  end if;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin raise exception 'reward verification pending'; end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_pay(uid uuid, p text, f int) returns jsonb
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin raise exception 'reward verification pending'; end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_feed(p_uid uuid, p_src text, p_n int) returns int
language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select 0 $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); a pvp_attempts; n int; need int; v_win boolean; r int; sk int := 0; srw jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  n := _pvp_ok(a.league, a.mode); need := case when n = 3 then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  v_win := p_wins = need;
  update pvp_attempts set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win where id = p_id;
  if v_win then
    update pvp_ratings set rating = rating + a.dl + a.dw, wins = wins + 1, losses = losses - 1, updated_at = now()
      where user_id = uid and league = a.league and mode = a.mode and season = a.season;
    if a.opp_user is not null then
      update pvp_ratings set rating = rating - a.dl / 2 - a.dw / 2, def_wins = def_wins - 1, def_losses = def_losses + 1, updated_at = now()
        where user_id = a.opp_user and league = a.league and mode = a.mode and season = a.season;
    end if;
    sk := _pvp_streak(uid, a.league, a.mode, a.season, p_id);
    select reward into srw from pvp_streak_table where pvp_streak_table.n = sk;
    -- No verified battle supplier yet. Do not consume a reward or claim it was paid.
    srw := null;
    update pvp_attempts set streak = sk, streak_reward = srw where id = p_id;
    -- 조직 세력 (guild.sql): 승리당 +10 (하루 상한은 _guild_feed 가 처리)
    if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform _guild_feed(uid, 'pvp', 10); end if;
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end,
    'tier', _pvp_tier(r), 'streak', sk, 'streak_reward', srw, 'reward_held', true);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_complete(p_tower text, p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; first boolean; paid boolean := false; pay jsonb := '{}'::jsonb; turns int; k text;
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or b ? 'sweep' or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  if r.day_floors >= _tower_daily(p_tower) then raise exception 'daily limit'; end if;   -- 자정을 넘긴 전투도 새 날 카운트로
  first := p_floor = r.best_floor + 1;
  if public._reward_battle_enabled() and first and p_floor > r.paid_floor then pay := _tower_pay(uid, p_tower, p_floor); paid := true; end if;
  update tower_progress set battle = null, clears = clears + 1, day_floors = day_floors + 1,
    best_floor = case when first then p_floor else best_floor end,
    paid_floor = case when paid then p_floor else paid_floor end,
    rewards = case when paid then (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((pay->'reward'->>x.k)::int, 0) + coalesce((pay->'currency'->>x.k)::int, 0))
                                   from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)) else rewards end,
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'reward_held', true, 'tower', p_tower, 'first', first, 'paid', paid, 'floor', p_floor, 'best_floor', case when first then p_floor else r.best_floor end,
    'reward', case when paid then pay->'reward' else '{}'::jsonb end, 'currency', pay->'currency', 'tickets', pay->'tickets',
    'today', r.day_floors + 1, 'daily', _tower_daily(p_tower));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.tower_sweep_complete(p_tower text, p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare uid uuid := auth.uid(); r tower_progress; b jsonb; f int; n int; fl int; pay jsonb; tk int := null; paidTo int;
  tot jsonb := '{}'::jsonb; floors jsonb := '[]'::jsonb; k text; turns jsonb := coalesce(p_stats->'turns', '[]'::jsonb);
begin
  r := _tower_row(uid, p_tower);
  b := r.battle;
  if b is null or not coalesce((b->>'sweep')::boolean, false) then raise exception 'sweep not started'; end if;
  f := (b->>'from')::int;
  if f <> r.best_floor + 1 then raise exception 'sweep stale'; end if;
  if p_to is null or p_to < f - 1 or p_to > (b->>'last')::int then raise exception 'invalid range'; end if;
  n := p_to - f + 1;
  if r.day_floors + n > _tower_daily(p_tower) then raise exception 'daily limit'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::numeric < n * _quest_sweep_secs() then raise exception 'too fast'; end if;
  if jsonb_typeof(turns) <> 'array' or jsonb_array_length(turns) < n
     or exists (select 1 from jsonb_array_elements(turns) x(v) where jsonb_typeof(x.v) <> 'number' or (x.v)::int < 1 or (x.v)::int > 40) then raise exception 'invalid stats'; end if;
  paidTo := r.paid_floor;
  for fl in f .. p_to loop
    if public._reward_battle_enabled() and fl > paidTo then
      pay := _tower_pay(uid, p_tower, fl); paidTo := fl; tk := coalesce((pay->>'tickets')::int, tk);
      floors := floors || jsonb_build_object('floor', fl, 'reward', pay->'reward', 'currency', pay->'currency');
      for k in select jsonb_object_keys((pay->'reward') || (pay->'currency')) loop
        tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int, 0) + coalesce((pay->'reward'->>k)::int, 0) + coalesce((pay->'currency'->>k)::int, 0));
      end loop;
    else floors := floors || jsonb_build_object('floor', fl, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb, 'paid_before', true);
    end if;
  end loop;
  update tower_progress set battle = null, clears = clears + n, day_floors = day_floors + n, best_floor = greatest(best_floor, p_to), paid_floor = paidTo,
    rewards = (select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((tot->>x.k)::int, 0)) from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)),
    updated_at = now()
  where user_id = uid and tower = p_tower;
  return jsonb_build_object('ok', true, 'reward_held', true, 'tower', p_tower, 'from', f, 'to', p_to, 'cleared', n, 'boss', (b->>'boss')::int, 'best_floor', greatest(r.best_floor, p_to),
    'total', tot, 'floors', floors, 'tickets', tk, 'today', r.day_floors + n, 'daily', _tower_daily(p_tower));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select tower_complete('normal', p_floor, p_stats) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.quest_sweep_complete(p_to int, p_stats jsonb default '{}'::jsonb) returns jsonb language sql security definer set search_path = pg_catalog, public, pg_temp as $$ select tower_sweep_complete('normal', p_to, p_stats) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_claim_one(p_uid uuid, p_key text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare a jsonb; t jsonb; i int; n int; g int; prog int; rw jsonb; ok boolean; score int; sc jsonb;
begin
  -- 점수 마일스톤
  if p_key like 'score:%' then
    g := substr(p_key, 7)::int;
    if p_key <> public._ach_score_key(g) then raise exception 'invalid key'; end if;
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
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_reward(p_uid uuid, p_gid bigint, p_rw jsonb, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare ok boolean; w jsonb;
begin
  if p_reason in ('raid_attempt','raid_last_hit') then
    return jsonb_build_object('reward','{}'::jsonb,'reward_held',true);
  end if;
  if p_reason not in ('guild_checkin','guild_rally_week','guild_rally_bonus') or p_reason is null then
    raise exception 'reward verification pending';
  end if;
  insert into guild_claims (user_id, ref, guild_id, reward) values (p_uid, p_ref, p_gid, p_rw) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  if coalesce((p_rw->>'loyalty')::int, 0) > 0 then perform _loyalty_add(p_uid, (p_rw->>'loyalty')::int, p_reason, null, jsonb_build_object('ref', p_ref)); end if;
  if coalesce((p_rw->>'gold')::int, 0) > 0 then w := _wallet_add(p_uid, jsonb_build_object('gold', (p_rw->>'gold')::int), p_reason); end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 then perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, 'guild:' || p_ref, jsonb_build_object('guild', p_gid)); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _guild_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'exp')::int, 0) > 0 and p_gid is not null then perform _guild_exp(p_gid, p_uid, (p_rw->>'exp')::int, p_reason, 'u:' || p_uid || ':' || p_ref); end if;
  return jsonb_build_object('reward', p_rw, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_close(a guild_raid_attempts, p_dmg bigint) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare N jsonb := _raid_numbers(); k int; rw jsonb;
begin
  update guild_raid_attempts set damage = p_dmg, finished_at = now() where id = a.id;
  insert into guild_raid_damage (guild_id, week, user_id, damage, attempts) values (a.guild_id, a.week, a.user_id, p_dmg, 1)
    on conflict (guild_id, week, user_id) do update set damage = guild_raid_damage.damage + p_dmg, attempts = guild_raid_damage.attempts + 1, updated_at = now();
  k := _raid_hit(a.guild_id, a.week, a.user_id, p_dmg);
  rw := jsonb_build_object('loyalty', (N->'attempt'->>'loyalty')::int,
    'gold', least((N->'attempt'->>'gold_max')::int, (N->'attempt'->>'gold_base')::int + (p_dmg / (N->'attempt'->>'gold_per_damage')::int)::int), 'exp', (N->'attempt'->>'exp')::int);
  perform _guild_reward(a.user_id, a.guild_id, rw, 'raid_attempt', 'raida:' || a.id);
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then perform _guild_event(a.user_id, 'raid', 1); end if;
  return jsonb_build_object('damage', p_dmg, 'cleared', k, 'got', '{}'::jsonb, 'reward_held', true);
end $$;$vr_statement$;
  execute $vr_statement$-- Cosmetic-only legacy score: already earned cosmetics are not confiscated.
create or replace function public._cosmo_ach_score(p_uid uuid) returns int
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
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
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._star_chapter(d jsonb, p_chapter int) returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare mx int; tot int; cl jsonb := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb); got jsonb := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb); ms jsonb := '[]'::jsonb; m jsonb; need int;
begin
  select 3 * count(*) into mx from story_phase_config where chapter = p_chapter and (p_chapter >= 1 or phase = 4);
  select coalesce(sum(least(3, greatest(0, (s.value)::int))), 0) into tot
    from jsonb_each_text(case when jsonb_typeof(d->'stars'->(p_chapter::text)) = 'object' then d->'stars'->(p_chapter::text) else '{}'::jsonb end) s
    where s.key ~ '^\d+$' and cl @> to_jsonb(s.key::int)
      and exists (select 1 from story_phase_config c where c.chapter = p_chapter and c.phase = s.key::int and (p_chapter >= 1 or c.phase = 4));
  tot := least(tot, mx);
  for m in select * from jsonb_array_elements(_star_milestones()) loop
    need := coalesce((m->>'need')::int, mx);
    if mx = 0 or need > mx or (m->>'key' <> 'all' and need >= mx) then continue; end if;   -- 최대보다 크거나 '전부'와 같으면 생략
    ms := ms || (m || jsonb_build_object('need', need, 'claimed', got @> to_jsonb(m->>'key'), 'ready', false, 'held', true));
  end loop;
  return jsonb_build_object('chapter', p_chapter, 'total', tot, 'max', mx, 'milestones', ms);
end $$;$vr_statement$;
  execute $vr_statement$-- Explicit API allowlist for affected names: revoke EVERY overload, then grant
-- only the reviewed signatures (including default parameters on those signatures).
do $acl$
declare f record; obj text; col record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and
      (left(p.proname,1)='_' or p.proname = any(array[
        'gallery_register','daily_track','weekly_track','ach_track','daily_claim','weekly_claim',
        'daily_status','weekly_status','attend_claim','gallery_rewards','gallery_reward_claim',
        'achievements_status','achievements_claim','achievements_claim_all','arcade_tut_status',
        'arcade_tut_claim','story_star_claim','story_tickets','pvp_claim_tier','pvp_claim_reward',
        'pvp_report','raid_claim','war_claim','tower_complete','tower_sweep_complete',
        'quest_complete','quest_sweep_complete'])) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  foreach obj in array array[
    'gallery_register(text[],text)','daily_track(text,integer)','weekly_track(text,integer)','ach_track(text,integer)',
    'daily_claim(text)','weekly_claim(text)','daily_status()','weekly_status()','attend_claim()',
    'gallery_rewards()','gallery_reward_claim(integer)','achievements_status()','achievements_claim(text)',
    'achievements_claim_all()','arcade_tut_status()','arcade_tut_claim(integer)','story_star_claim(integer,text)',
    'story_tickets()','pvp_claim_tier(text,text)','pvp_claim_reward(text,text,date)',
    'pvp_report(bigint,integer,integer)','raid_claim()','war_claim()',
    'tower_complete(text,integer,jsonb)','tower_sweep_complete(text,integer,jsonb)',
    'quest_complete(integer,jsonb)','quest_sweep_complete(integer,jsonb)'] loop
    execute format('grant execute on function public.%s to authenticated',obj);
  end loop;
  -- Strip raw and column-level writes too; retain existing SELECT/RLS contracts.
  foreach obj in array array['gallery','gallery_claims','daily_progress','weekly_progress','daily_attend',
    'achievement_claims','ach_counters','story_progress','story_gacha','story_gacha_log',
    'player_wallet','player_state','player_items','gem_ledger','gem_login','arcade_tut_claims',
    'pvp_reward_claims','pvp_tier_claims','guild_claims','verified_game_events','reward_claims','reward_security_policy',
    'reward_card_catalog','story_card_pool','card_id_alias','gem_shop','pvp_streak_table','pvp_reward_table','pvp_tier_table'] loop
    execute format('alter table public.%I enable row level security',obj);
    execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from public,anon,authenticated',obj);
    for col in select attname from pg_attribute where attrelid=to_regclass('public.'||obj) and attnum>0 and not attisdropped loop
      execute format('revoke insert (%I),update (%I),references (%I) on public.%I from public,anon,authenticated',col.attname,col.attname,col.attname,obj);
    end loop;
  end loop;
end $acl$;$vr_statement$;
  execute $vr_statement$revoke all on sequence public.verified_game_events_id_seq from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$-- Sequence mutation must not let an API role forge a future source/ledger identity.
do $sequences$
declare obj text; seq text;
begin
  foreach obj in array array['story_gacha_log','gem_ledger'] loop
    seq := pg_get_serial_sequence('public.'||obj,'id');
    if seq is not null then execute format('revoke all on sequence %s from public,anon,authenticated',seq); end if;
  end loop;
end $sequences$;$vr_statement$;
  execute $vr_statement$do $verify_phase1$
begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and left(p.proname,1)='_' and p.prokind='f'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute')))
    then raise exception 'STOP: private reward helper exposed'; end if;
  if has_table_privilege('authenticated','public.verified_game_events','INSERT')
    or has_table_privilege('authenticated','public.reward_claims','INSERT')
    or has_any_column_privilege('authenticated','public.story_gacha','UPDATE')
    or has_any_column_privilege('authenticated','public.daily_progress','INSERT')
    then raise exception 'STOP: raw reward writes exposed'; end if;
end $verify_phase1$;$vr_statement$;
  execute $vr_statement$-- Force PostgREST to see changed overload ACLs; never requires a service key.
notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함


-- ===== SOURCE: security_phase2_clears.sql =====
-- 보안 2단계: 서버 세션 + 순서/시간/입장/통계 범위 + 원자적 정산.
-- IMPORTANT: plausibility-v3 is NOT deterministic replay. A patient client can
-- fabricate a plausible win. Read docs/SECURITY_PHASE2.md before staging approval.
-- Existing DB: phase1 preflight -> phase1 rewards -> THIS file. No wildcard SQL.
-- 설치본의 단일 트랜잭션에 포함
select pg_advisory_xact_lock(20261107,502);$vr_statement$;
  execute $vr_statement$do $$ begin
  if to_regclass('public.reward_claims') is null or to_regprocedure('public._reward_battle_enabled()') is null then
    raise exception 'STOP: phase 1 required'; end if;
  if to_regclass('public.battle_sessions_v2') is not null and not exists(
    select 1 from pg_attribute where attrelid=to_regclass('public.battle_sessions_v2') and attname='settlement') then
    raise exception 'STOP: offline shadow prototype present; inspect before upgrade'; end if;
end $$;$vr_statement$;
  execute $vr_statement$-- Preserve reviewed economic implementations privately, once, before closing APIs.
do $preserve$
declare n text; sig text; src text; dest text;
begin
  foreach n in array array['story_start_phase','story_complete_phase','story_abort_phase','story_sweep','_ach_prog'] loop
    sig := case n when 'story_start_phase' then '(integer,integer)' when 'story_complete_phase' then '(integer,integer,jsonb)'
      when 'story_abort_phase' then '()' when 'story_sweep' then '(integer,integer,integer)' else '(uuid,text)' end;
    dest := '_phase2_old_' || ltrim(n,'_');
    if to_regprocedure('public.' || dest || sig) is null then
      src := pg_get_functiondef(to_regprocedure('public.' || n || sig));
      if src is null then raise exception 'STOP: missing %',n; end if;
      execute replace(src,'FUNCTION public.' || n || '(', 'FUNCTION public.' || dest || '(');
    end if;
  end loop;
end $preserve$;$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_policy_v2(mode text primary key check(mode in ('tutorial','story','tower')), enabled boolean not null default true);$vr_statement$;
  execute $vr_statement$insert into public.battle_policy_v2(mode) values ('tutorial'),('story'),('tower') on conflict do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_legacy_access_v2(
  user_id uuid primary key references auth.users(id) on delete cascade,
  cleared jsonb not null default '{}', tower_best jsonb not null default '{}', tower_paid jsonb not null default '{}');$vr_statement$;
  execute $vr_statement$-- Frozen access-only baseline; never grants stars/rewards/missions for old JSON.
insert into public.battle_legacy_access_v2(user_id,cleared,tower_best,tower_paid)
select u.id,coalesce(s.data->'cleared','{}'),
  coalesce((select jsonb_object_agg(tower,best_floor) from public.tower_progress t where t.user_id=u.id),'{}'),
  coalesce((select jsonb_object_agg(tower,paid_floor) from public.tower_progress t where t.user_id=u.id),'{}')
from auth.users u left join public.story_progress s on s.user_id=u.id on conflict do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_session_seeds_v2(
  user_id uuid not null references auth.users(id) on delete cascade, mode text not null, target text not null,
  seed integer not null check(seed between 1 and 2147483646), rule_version integer not null default 3 check(rule_version=3),
  primary key(user_id,mode,target,rule_version));$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_sessions_v2(
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null, mode text not null check(mode in ('tutorial','story','tower','tower_sweep')),
  target text not null, party jsonb not null, seed integer not null, rule_version integer not null default 3 check(rule_version=3),
  snapshot jsonb not null, issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp()+interval '2 hours',
  status text not null default 'issued' check(status in ('issued','settled','expired','aborted')),
  submission jsonb, settlement jsonb, finished_at timestamptz,
  unique(user_id,request_id), check(expires_at>issued_at));$vr_statement$;
  execute $vr_statement$create unique index if not exists battle_sessions_v2_one_active on public.battle_sessions_v2(user_id) where status='issued';$vr_statement$;
  execute $vr_statement$create index if not exists battle_sessions_v2_daily on public.battle_sessions_v2(user_id,issued_at);$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_clear_receipts_v2(
  user_id uuid not null references auth.users(id) on delete cascade, mode text not null, target text not null,
  session_id uuid not null references public.battle_sessions_v2(id), stars integer not null default 0 check(stars between 0 and 3),
  settled_at timestamptz not null default clock_timestamp(), primary key(user_id,mode,target));$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_events_v2(
  session_id uuid primary key references public.battle_sessions_v2(id), user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null, win boolean not null, skills integer not null, day date not null, week date not null);$vr_statement$;
  execute $vr_statement$create index if not exists battle_events_v2_period on public.battle_events_v2(user_id,day,week);$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_acquisitions_v2(
  session_id uuid primary key references public.battle_sessions_v2(id), user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null references public.story_card_pool(id));$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_card_meta_v2(id text primary key,definition jsonb not null);$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_story_defs_v2(chapter integer not null,phase integer not null,variant text not null,
  definition jsonb not null, primary key(chapter,phase,variant));$vr_statement$;
  execute $vr_statement$create table if not exists public.battle_tutorial_defs_v2(stage integer primary key check(stage between 1 and 3),definition jsonb not null);$vr_statement$;
  execute $vr_statement$insert into public.battle_tutorial_defs_v2(stage,definition) values
  (1, '{"first":"me","me":["10019","10018","10299","10445","10404","10375","10325","10080","10074","10049"],"aiField":["10348","10339","10184"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10325":7},"fullMp":["10019","10325"],"haste":["10325"],"bonus":{"3":30}}'::jsonb),
  (2, '{"first":"me","me":["10299","10137","10183","10045","10445","10404","10375","10060","10080","10074","10049"],"aiField":["10270","10462","10132","10202"],"aiDeck":[],"aiHp":3000,"meHpNow":2500,"wipe":true,"levels":{"10060":2},"fullMp":["10060"],"haste":["10060"],"bonus":{"1":30,"2":30,"3":10,"4":70}}'::jsonb),
  (3, '{"first":"me","me":["10036","10049","10118","10445","10404","10375","10080","10074","10311","10083"],"aiField":["10115","10103","10462","10256"],"aiDeck":[],"aiHp":3000,"wipe":true,"levels":{"10311":2},"fullMp":["10311"],"haste":["10311"],"mercs":["10292","10183","10325"],"bonus":{"1":0,"2":20,"3":80,"4":10,"5":50}}'::jsonb)
on conflict (stage) do nothing;$vr_statement$;
  execute $vr_statement$-- BEGIN GENERATED PHASE2 STORY
insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(0,1,'','{"no":1,"type":"normal","enemies":{"ids":["10256"],"boost":{"10256":{"HP":700}}},"party":{"forced":["10325"],"mustLive":["10325"],"noExtra":true,"auto":true,"battleLevels":{"10325":2}},"fullMp":true,"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,2,'','{"no":2,"type":"normal","enemies":{"ids":["10154","10153","10153","10153","10153"]},"party":{"forced":["10325"],"mustLive":["10325"],"noExtra":true,"auto":true},"reserve":["10256"],"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,3,'','{"no":3,"type":"normal","enemies":{"ids":["10323","10168","10168","10168","10168"],"storyLevels":{"10168":30,"10323":30},"levels":{"10168":3,"10323":5}},"party":{"forced":["10325"],"mustLive":[],"fixedLevel":{"10325":1},"only":["10256","10462"],"guests":["10256","10462"]},"awaken":{"pauseOnEntrance":true,"on":"10325","id":"10326","storyLevel":100,"battleLevel":10,"line":"....약해...","image":"img/story/ch0-05.webp"},"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,4,'','{"no":4,"type":"normal","enemies":{"ids":["10111","10224","10265"],"levels":{"10111":2,"10224":2,"10265":2}},"party":{"forced":["10325","10256","10207","10462"],"mustLive":["10325"],"noExtra":true,"auto":true},"pool":true,"mana":200,"mustSummon":["10207"],"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(0,5,'','{"no":5,"type":"boss","enemies":{"ids":["10229","10391","10097","10093","10103"],"levels":{"10093":2,"10097":2,"10103":2,"10229":3,"10391":2}},"party":{"forced":["10325","10256","10207","10462","10208"],"mustLive":["10325"],"noExtra":true,"auto":true},"baseHp":300,"bossId":"10229","pool":true,"mana":200,"hero":"10325","tutorial":true,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(1,1,'','{"no":1,"type":"normal","enemies":{"count":1,"rank":[0,30]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,2,'','{"no":2,"type":"normal","enemies":{"count":2,"rank":[0,50]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,3,'','{"no":3,"type":"normal","enemies":{"count":2,"rank":[30,90]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,4,'','{"no":4,"type":"normal","enemies":{"count":3,"rank":[50,120]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,5,'','{"no":5,"type":"boss","enemies":{"count":4,"rank":[120,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter","party":{}}'::jsonb),
(1,1,'10111','{"no":1,"type":"normal","enemies":{"ids":["10210"]},"party":{"forced":["10111","10112"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10111','{"no":2,"type":"normal","enemies":{"ids":["10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10111','{"no":3,"type":"normal","enemies":{"ids":["10153","10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10111','{"no":4,"type":"normal","enemies":{"ids":["10154","10153","10143","10144"]},"party":{"forced":["10111"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10111','{"no":5,"type":"boss","enemies":{"ids":["10146","10153","10143","10144","10145"]},"party":{"forced":["10111"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,1,'10224','{"no":1,"type":"normal","enemies":{"ids":["10143"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10224','{"no":2,"type":"normal","enemies":{"ids":["10153","10143"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10224','{"no":3,"type":"normal","enemies":{"ids":["10145","10144"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10224','{"no":4,"type":"normal","enemies":{"ids":["10145","10154","10153"]},"party":{"forced":["10224"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10224','{"no":5,"type":"boss","enemies":{"ids":["10146","10153","10154","10145"]},"party":{"forced":["10224"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,1,'10265','{"no":1,"type":"normal","enemies":{"ids":["10143"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,2,'10265','{"no":2,"type":"normal","enemies":{"ids":["10153","10154"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,3,'10265','{"no":3,"type":"normal","enemies":{"ids":["10143","10144"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,4,'10265','{"no":4,"type":"normal","enemies":{"ids":["10145","10144","10153"]},"party":{"forced":["10265"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(1,5,'10265','{"no":5,"type":"boss","enemies":{"ids":["10146","10144","10145","10153","10154"]},"party":{"forced":["10265"]},"bossId":"10146","hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"starter"}'::jsonb),
(2,1,'','{"no":1,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,2,'','{"no":2,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,3,'','{"no":3,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,4,'','{"no":4,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,5,'','{"no":5,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(2,6,'','{"no":6,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,7,'','{"no":7,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,8,'','{"no":8,"type":"normal","enemies":{"count":5,"rank":[60,203]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route","party":{}}'::jsonb),
(2,9,'','{"no":9,"type":"normal","enemies":{"ids":["10368","10370","10149","10154","10153"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"rules":{"mustLive":["10298"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10146"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"bossId":"10369","rules":{"mustLive":["10298"]},"hero":null,"tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,1,'10081','{"no":1,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,2,'10081','{"no":2,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,3,'10081','{"no":3,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,4,'10081','{"no":4,"type":"normal","enemies":{"ids":["10148","10147","10146","10145","10144"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,5,'10081','{"no":5,"type":"normal","enemies":{"ids":["10149","10148","10147","10146","10145"]},"party":{"forced":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,6,'10081','{"no":6,"type":"normal","enemies":{"ids":["10149","10148","10147","10146","10145"]},"party":{"forced":["10081"],"exclude":["10306"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,7,'10081','{"no":7,"type":"normal","enemies":{"ids":["10082","10082","10082"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,8,'10081','{"no":8,"type":"normal","enemies":{"ids":["10082","10082","10082","10082","10082"]},"party":{"forced":["10081","10062"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,9,'10081','{"no":9,"type":"normal","enemies":{"ids":["10147","10146","10144","10145","10143"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'10081','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10148"]},"party":{"forced":["10081"],"exclude":["10252","10306"]},"bossId":"10369","rules":{"mustLive":["10081"]},"hero":"10081","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,1,'10298','{"no":1,"type":"normal","enemies":{"ids":["10146","10143","10144","10145"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,2,'10298','{"no":2,"type":"normal","enemies":{"ids":["10146","10147","10145","10144","10143"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,3,'10298','{"no":3,"type":"normal","enemies":{"ids":["10148","10146","10145","10144","10143"]},"party":{"forced":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,4,'10298','{"no":4,"type":"normal","enemies":{"ids":["10149","10146","10145","10144","10143"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,5,'10298','{"no":5,"type":"normal","enemies":{"ids":["10149","10153","10146","10144","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,6,'10298','{"no":6,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,7,'10298','{"no":7,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10306","10125"],"exclude":["10298"]},"rules":{"mustLive":["10306"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,8,'10298','{"no":8,"type":"normal","enemies":{"ids":["10149","10154","10153","10146","10145"]},"party":{"forced":["10298"],"exclude":["10125"]},"rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,9,'10298','{"no":9,"type":"normal","enemies":{"ids":["10368","10370","10149","10154","10153"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(2,10,'10298','{"no":10,"type":"boss","enemies":{"ids":["10369","10368","10370","10149","10146"]},"party":{"forced":["10298"],"exclude":["10125","10306"]},"bossId":"10369","rules":{"mustLive":["10298"]},"hero":"10298","tutorial":false,"single":false,"loan":[],"loanLevel":{},"variantKind":"route"}'::jsonb),
(3,1,'','{"no":1,"type":"normal","enemies":{"ids":["10157","10156","10155","10154","10153"]},"party":{"forced":["10384"],"noMale":true},"bossId":"10157","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,2,'','{"no":2,"type":"normal","enemies":{"ids":["10097","10297","10290","10103","10432"]},"party":{"forced":["10384"],"maxMor":49},"bossId":"10097","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,3,'','{"no":3,"type":"normal","enemies":{"ids":["10280","10160","10159","10158","10157"]},"party":{"forced":["10383"]},"bossId":"10280","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,4,'','{"no":4,"type":"normal","enemies":{"ids":["10393","10290","10097","10306","10041"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10393","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,5,'','{"no":5,"type":"normal","enemies":{"ids":["10290","10306","10097","10405","10227"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10290","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(3,6,'','{"no":6,"type":"normal","enemies":{"ids":["10290","10306","10097","10405","10229"]},"party":{"forced":["10384"],"exclude":["10383"],"maxGrade":"HIGH RARE"},"bossId":"10290","spare":{"10229":["10384"]},"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,7,'','{"no":7,"type":"normal","enemies":{"ids":["10229","10040","10097","10466","10290"]},"party":{"forced":["10384","10383"]},"bossId":"10229","enemyFirst":true,"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,8,'','{"no":8,"type":"normal","enemies":{"ids":["10123","10161","10160","10159","10158"]},"party":{"forced":["10384"]},"bossId":"10123","enemyFirst":true,"hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,9,'','{"no":9,"type":"normal","enemies":{"ids":["10123","10183","10161","10160","10159"]},"party":{"forced":["10383"],"maxGrade":"SUPER RARE"},"bossId":"10123","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(3,10,'','{"no":10,"type":"boss","enemies":{"ids":["10200","10161","10160","10123","10025"]},"party":{"forced":["10384"],"exclude":["10383"]},"bossId":"10200","hero":"10384","tutorial":false,"single":true,"loan":["10384","10383"],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,1,'','{"no":1,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10157"]},"party":{"forced":["10300"]},"bossId":"10157","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,2,'','{"no":2,"type":"normal","enemies":{"ids":["10153","10154","10156","10157","10158"]},"party":{"forced":["10300"]},"bossId":"10158","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,3,'','{"no":3,"type":"normal","enemies":{"ids":["10160","10161","10162","10163","10159"]},"party":{"forced":["10300"]},"bossId":"10159","hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,4,'','{"no":4,"type":"normal","enemies":{"ids":["10156","10165","10166","10159","10164"]},"party":{"forced":["10300","10325"]},"bossId":"10164","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,5,'','{"no":5,"type":"normal","enemies":{"ids":["10156","10164","10165","10166","10167"]},"party":{"forced":["10300","10325"]},"bossId":"10167","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,6,'','{"no":6,"type":"normal","enemies":{"ids":["10168","10156","10154","10153","10159"]},"party":{"forced":["10300"]},"bossId":"10159","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,7,'','{"no":7,"type":"normal","enemies":{"ids":["10156","10154","10153","10159","10072"]},"party":{"forced":["10300"]},"bossId":"10072","rules":{"mustLive":["10300"]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,8,'','{"no":8,"type":"normal","enemies":{"ids":["10160","10161","10162","10168","10072"]},"party":{"forced":["10300"]},"bossId":"10072","rules":{"revive":[{"id":"10072","level":1,"delay":2}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,9,'','{"no":9,"type":"normal","enemies":{"ids":["10161","10162","10072","10168","10325"]},"party":{"forced":["10300"]},"bossId":"10325","rules":{"revive":[{"id":"10072","level":"keep","delay":2},{"id":"10256","level":"keep","delay":2}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(4,10,'','{"no":10,"type":"normal","enemies":{"ids":["10301","10302","10302","10302","10302"],"levels":{"10301":5},"boost":{"10302":{"HP":317,"ATK":62,"DEF":62,"power":13277}}},"party":{"forced":["10325"]},"bossId":"10301","rules":{"invuln":"10301","expire":10,"revive":[{"id":"10302","level":1,"delay":1}]},"hero":"10300","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,1,'','{"no":1,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10157"],"storyLevels":{"10153":25,"10154":25,"10155":25,"10156":25,"10157":30}},"party":{"forced":["10442"]},"bossId":"10157","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,2,'','{"no":2,"type":"normal","enemies":{"ids":["10143","10158","10155","10156","10159"],"storyLevels":{"10143":25,"10155":25,"10156":25,"10158":25,"10159":30}},"party":{"forced":["10442"]},"bossId":"10159","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,3,'','{"no":3,"type":"normal","enemies":{"ids":["10159","10153","10154","10357","10360"],"boost":{"10360":{"HP":150,"ATK":30,"DEF":26,"power":2241}},"storyLevels":{"10153":25,"10154":25,"10159":25,"10357":25}},"party":{"forced":["10442"]},"bossId":"10360","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10160","10161","10162","10163"],"storyLevels":{"10158":25,"10160":25,"10161":25,"10162":25,"10163":30}},"party":{"forced":["10442"]},"bossId":"10163","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,5,'','{"no":5,"type":"normal","enemies":{"ids":["10153","10154","10156","10164","10165"],"storyLevels":{"10153":25,"10154":25,"10156":25,"10164":25,"10165":30}},"party":{"forced":["10442"]},"bossId":"10165","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,6,'','{"no":6,"type":"normal","enemies":{"ids":["10166","10167","10144","10145","10146"],"storyLevels":{"10144":25,"10145":25,"10146":30,"10166":25,"10167":25}},"party":{"forced":["10442"]},"bossId":"10146","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,7,'','{"no":7,"type":"normal","enemies":{"ids":["10152","10147","10148","10149","10150"],"storyLevels":{"10147":25,"10148":25,"10149":25,"10150":30,"10152":25}},"party":{"forced":["10442"],"banClass":["DARK"]},"bossId":"10150","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,8,'','{"no":8,"type":"normal","enemies":{"ids":["10152","10147","10148","10143","10150"],"storyLevels":{"10143":25,"10147":25,"10148":25,"10150":30,"10152":25}},"party":{"forced":["10442"],"banClass":["LIGHT"]},"bossId":"10150","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,9,'','{"no":9,"type":"normal","enemies":{"ids":["10150","10152","10144","10145","10146"],"storyLevels":{"10144":25,"10145":25,"10146":30,"10150":25,"10152":25}},"party":{"forced":["10442"],"maxGrade":"SUPER RARE"},"bossId":"10146","hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(5,10,'','{"no":10,"type":"boss","enemies":{"ids":["10357","10168","10143","10147","10360"],"boost":{"10357":{"HP":240,"ATK":40,"DEF":30,"power":7800},"10360":{"HP":360,"ATK":62,"DEF":44,"power":4883}},"storyLevels":{"10143":25,"10147":25,"10168":25}},"party":{"forced":["10399"],"maxGrade":"SUPER RARE","exclude":["10442"]},"bossId":"10360","rules":{"undying":["10357"]},"hero":"10442","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,1,'','{"no":1,"type":"normal","enemies":{"ids":["10210","10151","10151"]},"party":{"forced":["10112","10111"]},"bossId":"10210","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,2,'','{"no":2,"type":"normal","enemies":{"ids":["10146","10153","10143","10144","10145"]},"party":{"forced":["10111"]},"bossId":"10146","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,3,'','{"no":3,"type":"normal","enemies":{"ids":["10152","10152","10152","10152","10152"]},"party":{"forced":["10111"]},"bossId":"10152","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,4,'','{"no":4,"type":"normal","enemies":{"ids":["10163","10163","10163","10163","10163"]},"party":{"forced":["10111"],"exclude":["10325"]},"bossId":"10163","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,5,'','{"no":5,"type":"normal","enemies":{"ids":["10166","10163","10163","10163","10163"]},"party":{"forced":["10110"],"exclude":["10111"]},"bossId":"10166","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$vr_statement$;
  execute $vr_statement$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(6,6,'','{"no":6,"type":"normal","enemies":{"ids":["10166","10166","10166","10166","10166"]},"party":{"forced":["10110"],"exclude":["10325","10111"]},"bossId":"10166","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,7,'','{"no":7,"type":"normal","enemies":{"ids":["10419","10166","10166","10163","10163"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10419","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,8,'','{"no":8,"type":"normal","enemies":{"ids":["10035","10167","10167","10166","10166"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10035","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,9,'','{"no":9,"type":"normal","enemies":{"ids":["10321","10168","10168","10167","10167"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10321","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(6,10,'','{"no":10,"type":"boss","enemies":{"ids":["10325","10168","10168","10168","10168"]},"party":{"forced":["10110"],"exclude":["10325","10111","10112"]},"bossId":"10325","hero":"10110","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,1,'','{"no":1,"type":"normal","enemies":{"ids":["10162","10161","10161","10161","10161"],"boost":{"10161":{"HP":231,"ATK":48,"DEF":41,"storyLv":40,"power":8753},"10162":{"HP":267,"ATK":53,"DEF":46,"storyLv":40,"power":9939}}},"party":{"forced":["10115","10267"],"noMale":true,"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10162","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,2,'','{"no":2,"type":"normal","enemies":{"ids":["10163","10149","10148","10146","10146"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10163":{"HP":391,"ATK":65,"DEF":56,"storyLv":40,"power":21555}}},"party":{"forced":["10115","10267"],"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10163","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,3,'','{"no":3,"type":"normal","enemies":{"ids":["10151","10148","10148","10148","10148"],"boost":{"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808}}},"party":{"forced":["10115","10267"],"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10151","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,4,'','{"no":4,"type":"normal","enemies":{"ids":["10165","10164","10164","10164","10164"],"boost":{"10164":{"HP":469,"ATK":74,"DEF":64,"storyLv":50,"power":25336},"10165":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808}}},"party":{"forced":["10115","10267"],"noMale":true,"mustLive":["10115"],"levels":{"10115":40,"10267":40}},"bossId":"10165","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,5,'','{"no":5,"type":"normal","enemies":{"ids":["10164","10163","10163","10163","10163"],"boost":{"10163":{"HP":445,"ATK":74,"DEF":64,"storyLv":50,"power":24551},"10164":{"HP":526,"ATK":83,"DEF":72,"storyLv":60,"power":28430}}},"party":{"forced":["10267"],"noMale":true,"exclude":["10115"],"mustLive":["10267"]},"bossId":"10164","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,6,'','{"no":6,"type":"normal","enemies":{"ids":["10267"],"boost":{"10267":{"HP":430,"ATK":65,"DEF":140,"storyLv":30,"power":41589}}},"party":{"forced":["10115"],"exclude":["10267"],"max":3,"maxGrade":"SUPER RARE","mustLive":[]},"bossId":"10267","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,7,'','{"no":7,"type":"normal","enemies":{"ids":["10198","10196","10197","10199"],"boost":{"10196":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10197":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10198":{"HP":127,"ATK":16,"DEF":16,"storyLv":60,"power":1709},"10199":{"HP":240,"ATK":33,"DEF":33,"storyLv":60,"power":8337}}},"party":{"forced":["10018","10019","10299","10074"],"max":5,"noFemale":true,"maxMor":39,"mustLive":[]},"bossId":"10198","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,8,'','{"no":8,"type":"normal","enemies":{"ids":["10144","10143","10143","10143","10143"],"boost":{"10143":{"HP":80,"ATK":17,"DEF":13,"storyLv":60,"power":1076},"10144":{"HP":80,"ATK":19,"DEF":14,"storyLv":60,"power":1126}}},"party":{"forced":["10115","10018"],"noFemale":true,"exclude":["10118"],"mustLive":["10115"]},"bossId":"10144","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,9,'','{"no":9,"type":"normal","enemies":{"ids":["10299","10019","10018","10074"],"boost":{"10018":{"HP":251,"ATK":46,"DEF":31,"storyLv":60,"power":9153},"10019":{"HP":240,"ATK":44,"DEF":33,"storyLv":60,"power":9100},"10074":{"HP":48,"ATK":8,"DEF":10,"storyLv":60,"power":523},"10299":{"HP":554,"ATK":97,"DEF":69,"storyLv":60,"power":28335}}},"party":{"forced":["10115"],"exclude":["10267","10118"],"mustLive":["10115"]},"bossId":"10299","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(7,10,'','{"no":10,"type":"boss","enemies":{"ids":["10116","10116","10116","10116","10116"],"boost":{"10116":{"HP":1008,"ATK":50,"DEF":151,"storyLv":60,"power":80121}}},"party":{"forced":["10115"],"exclude":["10118"],"mustLive":["10115"]},"bossId":"10116","hero":"10115","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,1,'','{"no":1,"type":"normal","enemies":{"ids":["10494","10495","10495","10495","10495"],"boost":{"10494":{"HP":111,"ATK":17,"DEF":14,"storyLv":40,"power":1433},"10495":{"HP":214,"ATK":27,"DEF":18,"storyLv":40,"power":6130}}},"party":{"forced":["10493"],"mustLive":["10493"],"levels":{"10493":80}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,2,'','{"no":2,"type":"normal","enemies":{"ids":["10496","10497","10497","10497","10497"],"boost":{"10496":{"HP":386,"ATK":54,"DEF":54,"storyLv":40,"power":19302},"10497":{"HP":97,"ATK":14,"DEF":14,"storyLv":40,"power":1337}}},"party":{"forced":["10493"],"mustLive":["10493"],"levels":{"10493":80}},"bossId":"10496","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,3,'','{"no":3,"type":"normal","enemies":{"ids":["10144","10145","10145","10145","10145"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":40,"power":1003},"10145":{"HP":83,"ATK":18,"DEF":14,"storyLv":40,"power":1131}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10144","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,4,'','{"no":4,"type":"normal","enemies":{"ids":["10501","10500","10500","10500","10500"],"boost":{"10500":{"HP":217,"ATK":48,"DEF":48,"storyLv":40,"power":9293},"10501":{"HP":458,"ATK":82,"DEF":82,"storyLv":40,"power":28432}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10501","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,5,'','{"no":5,"type":"normal","enemies":{"ids":["10154","10144","10145","10153","10155"],"boost":{"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":42,"power":1003},"10145":{"HP":85,"ATK":18,"DEF":14,"storyLv":42,"power":1145},"10153":{"HP":85,"ATK":14,"DEF":10,"storyLv":42,"power":1066},"10154":{"HP":99,"ATK":16,"DEF":11,"storyLv":42,"power":1226},"10155":{"HP":113,"ATK":17,"DEF":13,"storyLv":42,"power":1383}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":42}},"bossId":"10154","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,6,'','{"no":6,"type":"normal","enemies":{"ids":["10153","10154","10155","10156","10156"],"boost":{"10153":{"HP":87,"ATK":14,"DEF":10,"storyLv":46,"power":1082},"10154":{"HP":102,"ATK":16,"DEF":12,"storyLv":46,"power":1265},"10155":{"HP":116,"ATK":17,"DEF":13,"storyLv":46,"power":1406},"10156":{"HP":130,"ATK":19,"DEF":14,"storyLv":46,"power":1664}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":46}},"bossId":"10153","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,7,'','{"no":7,"type":"normal","enemies":{"ids":["10157","10144","10145","10155","10156"],"boost":{"10144":{"HP":74,"ATK":18,"DEF":13,"storyLv":50,"power":1050},"10145":{"HP":89,"ATK":19,"DEF":15,"storyLv":50,"power":1207},"10155":{"HP":119,"ATK":18,"DEF":13,"storyLv":50,"power":1448},"10156":{"HP":134,"ATK":19,"DEF":15,"storyLv":50,"power":1713},"10157":{"HP":149,"ATK":21,"DEF":16,"storyLv":50,"power":1892}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":50}},"bossId":"10157","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,8,'','{"no":8,"type":"normal","enemies":{"ids":["10500","10501","10501","10501","10501"],"boost":{"10500":{"HP":246,"ATK":55,"DEF":55,"storyLv":52,"power":10591},"10501":{"HP":534,"ATK":96,"DEF":96,"storyLv":52,"power":33210}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":52}},"bossId":"10500","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,9,'','{"no":9,"type":"normal","enemies":{"ids":["10494","10495","10496","10144","10145"],"boost":{"10144":{"HP":76,"ATK":18,"DEF":14,"storyLv":54,"power":1079},"10145":{"HP":92,"ATK":20,"DEF":15,"storyLv":54,"power":1247},"10494":{"HP":122,"ATK":18,"DEF":15,"storyLv":54,"power":1556},"10495":{"HP":247,"ATK":31,"DEF":21,"storyLv":54,"power":7076},"10496":{"HP":461,"ATK":65,"DEF":65,"storyLv":54,"power":23122}}},"party":{"forced":["10493"],"exclude":["10231"],"mustLive":["10493"],"levels":{"10493":54}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,10,'','{"no":10,"type":"normal","enemies":{"ids":["10156","10153","10154","10157","10157"],"boost":{"10153":{"HP":93,"ATK":16,"DEF":11,"storyLv":56,"power":1180},"10154":{"HP":108,"ATK":17,"DEF":12,"storyLv":56,"power":1329},"10156":{"HP":140,"ATK":20,"DEF":16,"storyLv":56,"power":1798},"10157":{"HP":155,"ATK":22,"DEF":17,"storyLv":56,"power":1977}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":56}},"bossId":"10156","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,11,'','{"no":11,"type":"normal","enemies":{"ids":["10494","10495","10496","10497","10498"],"boost":{"10494":{"HP":126,"ATK":19,"DEF":16,"storyLv":58,"power":1623},"10495":{"HP":257,"ATK":32,"DEF":21,"storyLv":58,"power":7318},"10496":{"HP":482,"ATK":68,"DEF":68,"storyLv":58,"power":24180},"10497":{"HP":110,"ATK":16,"DEF":16,"storyLv":58,"power":1521},"10498":{"HP":259,"ATK":39,"DEF":64,"storyLv":58,"power":9524}}},"party":{"forced":["10493"],"exclude":["10231"],"mustLive":["10493"],"levels":{"10493":58}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,12,'','{"no":12,"type":"normal","enemies":{"ids":["10155","10144","10145","10154","10157"],"boost":{"10144":{"HP":79,"ATK":19,"DEF":14,"storyLv":59,"power":1119},"10145":{"HP":95,"ATK":21,"DEF":16,"storyLv":59,"power":1301},"10154":{"HP":111,"ATK":17,"DEF":13,"storyLv":59,"power":1368},"10155":{"HP":126,"ATK":19,"DEF":14,"storyLv":59,"power":1536},"10157":{"HP":158,"ATK":22,"DEF":17,"storyLv":59,"power":2001}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":59}},"bossId":"10155","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,13,'','{"no":13,"type":"normal","enemies":{"ids":["10493","10493","10493","10493","10493"],"boost":{"10493":{"HP":554,"ATK":83,"DEF":83,"storyLv":60,"power":41039}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10493","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,14,'','{"no":14,"type":"normal","enemies":{"ids":["10494","10495","10496","10153","10156"],"boost":{"10153":{"HP":95,"ATK":16,"DEF":11,"storyLv":60,"power":1195},"10156":{"HP":143,"ATK":21,"DEF":16,"storyLv":60,"power":1843},"10494":{"HP":127,"ATK":19,"DEF":16,"storyLv":60,"power":1631},"10495":{"HP":262,"ATK":33,"DEF":22,"storyLv":60,"power":7501},"10496":{"HP":493,"ATK":69,"DEF":69,"storyLv":60,"power":24657}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10494","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(8,15,'','{"no":15,"type":"boss","enemies":{"ids":["10502"],"boost":{"10502":{"HP":1344,"ATK":151,"DEF":151,"storyLv":60,"power":146456}}},"party":{"forced":["10231"],"noMale":true,"mustLive":["10231"],"levels":{"10231":60}},"bossId":"10502","hero":"10231","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (10, 'cc55a18ffb6e7f31c29402be300a5e256b333fd450277ae07e425819f76899c9', '06ed9a63be6b194a3da066e8cb9b234a77ce595a1b463052e049287d57159144', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '10_install.sql: 완료 또는 이미 완료 (10/13)' as result;
