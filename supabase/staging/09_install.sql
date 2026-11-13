-- ⚠ 테스트 전용 9/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '2e51781f300b93c84298e678ab1ea699a95d4d5bc29d23bc3cc785cdcfebdd30' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 9) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 9 and part_hash = '8f1352ee2993a2d373c74b4677c6d99b3f6ffa5e7004f3c228ea3502230c96b9') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '09_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 9) <> 8 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (09_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- 받기: 서버가 별을 다시 합산 · 한 번만
create or replace function public.story_star_claim(p_chapter int, p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; st jsonb; m jsonb; got jsonb; t int; w jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  d := _story_lock(me);
  st := _star_chapter(d, p_chapter);
  select x into m from jsonb_array_elements(st->'milestones') x where x->>'key' = p_key;
  if m is null then raise exception 'invalid milestone'; end if;
  if (m->>'claimed')::boolean then raise exception 'already claimed'; end if;
  if not (m->>'ready')::boolean then raise exception 'not enough stars'; end if;
  got := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb) || to_jsonb(p_key);
  if jsonb_typeof(d->'starClaims') is distinct from 'object' then d := jsonb_set(d, '{starClaims}', '{}'::jsonb); end if;
  d := _story_save(me, jsonb_set(d, array['starClaims', p_chapter::text], got));
  insert into story_gacha (user_id, last_draw) values (me, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + (m->>'tickets')::int, updated_at = now() where user_id = me returning tickets into t;
  w := _wallet_add(me, jsonb_build_object('gold', (m->>'gold')::int), 'star_reward');
  return jsonb_build_object('ok', true, 'tickets', t, 'wallet', w, 'gave', jsonb_build_object('tickets', (m->>'tickets')::int, 'gold', (m->>'gold')::int), 'status', _star_chapter(d, p_chapter));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._star_milestones(), public._star_chapter(jsonb, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_star_status(), public.story_star_claim(int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_star_status(), public.story_star_claim(int, text) to authenticated;$vr_statement$;
  execute $vr_statement$select 'story_star_rewards ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: camp.sql =====
-- ===== 훈련소 1단계 (인재를 넣어 두면 시간이 지나며 EXP 가 쌓임) =====
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: phaseE_1.sql(_wallet_add) · phaseE_2.sql(_player_sync) · gem.sql(_gem_spend) · story_levels.sql / story_merge.sql(_story_gain · _story_cap · 인재 uid)
-- 규칙
--  * 칸 5개: 1칸 플레이어 Lv10 무료 · 2칸 Lv20 골드 2만 · 3칸 Lv35 골드 5만 · 4칸 Lv50 심연석 300 · 5칸 Lv70 심연석 800
--  * EXP: 칸 하나에 시간당 20 + 플레이어 레벨 × 1.5 (받을 때 레벨 기준). 마지막으로 받은 뒤 최대 24시간까지만 쌓임
--  * 레벨 상한: min(등급 최대 레벨(EX 포함), 플레이어 레벨 − 5). 상한에 닿으면 더 안 쌓임
--  * 시간은 서버 now() 만 사용. 훈련 중인 인재도 덱·스토리·PvP 사용 가능
--  * 훈련 중인 인재는 거래 등록·분해·합성 재료로 못 씀 (story_progress 에서 빠지려 하면 거부하는 트리거)

-- 1) 테이블 (행이 있으면 그 칸은 열린 것)
create table if not exists public.camp_slots (
  user_id  uuid not null references auth.users(id) on delete cascade,
  slot     int  not null check (slot between 1 and 5),
  card_uid text,
  last_at  timestamptz,
  opened_at timestamptz not null default now(),
  primary key (user_id, slot));$vr_statement$;
  execute $vr_statement$create unique index if not exists camp_slots_card on public.camp_slots (user_id, card_uid) where card_uid is not null;$vr_statement$;
  execute $vr_statement$alter table public.camp_slots enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.camp_slots from anon, authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists camp_slots_own on public.camp_slots;$vr_statement$;
  execute $vr_statement$create policy camp_slots_own on public.camp_slots for select using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$grant select on public.camp_slots to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 수치
create or replace function public._camp_need_level(s int) returns int language sql immutable as $$ select case s when 1 then 10 when 2 then 20 when 3 then 35 when 4 then 50 when 5 then 70 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_cost(s int) returns jsonb language sql immutable as $$
  select case s when 1 then '{}'::jsonb when 2 then '{"gold":20000}'::jsonb when 3 then '{"gold":50000}'::jsonb when 4 then '{"gem":300}'::jsonb when 5 then '{"gem":800}'::jsonb end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_rate(plv int) returns numeric language sql immutable as $$ select 20 + 1.5 * greatest(plv, 1) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_max_hours() returns int language sql immutable as $$ select 24 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_cap(g text, ex int, plv int) returns int language sql immutable as $$ select least(_story_cap(g, ex), plv - 5) $$;$vr_statement$;
  execute $vr_statement$-- 3) 도우미
create or replace function public._camp_plv(p_uid uuid) returns int language plpgsql security definer set search_path = public as $$
declare lv int; begin select (_player_sync(p_uid)).level into lv; return coalesce(lv, 1); end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_owned(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' end from story_progress where user_id = p_uid), '[]'::jsonb) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_grade(p_id text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select grade from story_card_pool where id = p_id), 'NORMAL') $$;$vr_statement$;
  execute $vr_statement$-- 지금 받으면 들어올 EXP (상한 반영)
create or replace function public._camp_pending(e jsonb, p_last timestamptz, plv int) returns int language plpgsql stable security definer set search_path = public as $$
declare hrs numeric; amt int; lv int; ex int; cap int; need int := 0; l int;
begin
  if e is null or p_last is null then return 0; end if;
  hrs := least(_camp_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0));
  amt := floor(_camp_rate(plv) * hrs)::int;
  lv := greatest(1, coalesce((e->>'level')::int, 1)); ex := greatest(0, coalesce((e->>'exp')::int, 0));
  cap := _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv);
  if lv >= cap then return 0; end if;
  for l in lv..cap - 1 loop need := need + l * 100; end loop;
  return greatest(0, least(amt, need - ex));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare plv int := _camp_plv(p_uid); owned jsonb := _camp_owned(p_uid);
begin
  -- 1칸은 Lv10 되면 자동으로 열림
  if plv >= _camp_need_level(1) then insert into camp_slots (user_id, slot) values (p_uid, 1) on conflict do nothing; end if;
  return jsonb_build_object('ok', true, 'now', now(), 'level', plv, 'rate', _camp_rate(plv), 'max_hours', _camp_max_hours(), 'cap_minus', 5,
    'slots', (select jsonb_agg(jsonb_build_object('slot', s, 'need_level', _camp_need_level(s), 'cost', _camp_cost(s), 'open', c.slot is not null,
                'uid', c.card_uid, 'last_at', c.last_at,
                'card', (select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1),
                'pending', coalesce(_camp_pending((select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1), c.last_at, plv), 0)) order by s)
              from generate_series(1, 5) s left join camp_slots c on c.user_id = p_uid and c.slot = s));
end $$;$vr_statement$;
  execute $vr_statement$-- 한 칸 정산 (story_progress 를 이미 잠근 상태에서 호출). 반환 { uid, exp, from, level }
create or replace function public._camp_settle(p_uid uuid, p_slot int, plv int) returns jsonb language plpgsql security definer set search_path = public as $$
declare c camp_slots; d jsonb; owned jsonb; idx int; e jsonb; amt int; before int;
begin
  select * into c from camp_slots where user_id = p_uid and slot = p_slot for update;
  if c.card_uid is null then return null; end if;
  select data into d from story_progress where user_id = p_uid;
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1, t.e into idx, e from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'uid' = c.card_uid limit 1;
  if idx is null then update camp_slots set card_uid = null, last_at = null where user_id = p_uid and slot = p_slot; return null; end if;
  amt := _camp_pending(e, c.last_at, plv);
  update camp_slots set last_at = now() where user_id = p_uid and slot = p_slot;
  if amt <= 0 then return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', 0, 'from', coalesce((e->>'level')::int, 1), 'level', coalesce((e->>'level')::int, 1)); end if;
  before := coalesce((e->>'level')::int, 1);
  e := _story_gain(e, amt, _camp_grade(e->>'id'));
  update story_progress set data = jsonb_set(d, array['owned', idx::text], e), updated_at = now() where user_id = p_uid;
  return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', amt, 'from', before, 'level', (e->>'level')::int);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 공개 함수
create or replace function public.camp_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  return _camp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.camp_unlock(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); plv int; cost jsonb; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot is null or p_slot not between 1 and 5 then raise exception 'bad slot'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  if exists (select 1 from camp_slots where user_id = uid and slot = p_slot) then raise exception 'already open'; end if;
  if p_slot > 1 and not exists (select 1 from camp_slots where user_id = uid and slot = p_slot - 1) then raise exception 'open previous'; end if;
  plv := _camp_plv(uid);
  if plv < _camp_need_level(p_slot) then raise exception 'need level %', _camp_need_level(p_slot); end if;
  cost := _camp_cost(p_slot);
  if (cost->>'gold') is not null then w := _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_unlock'); end if;   -- 부족하면 'not enough gold'
  if (cost->>'gem') is not null then perform _gem_spend(uid, (cost->>'gem')::int, 'camp_unlock', jsonb_build_object('slot', p_slot)); end if;
  insert into camp_slots (user_id, slot) values (uid, p_slot);
  return _camp_json(uid) || jsonb_build_object('spent', cost, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.camp_put(p_slot int, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c camp_slots; e jsonb; plv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  select * into c from camp_slots where user_id = uid and slot = p_slot for update;
  if c.user_id is null then raise exception 'slot locked'; end if;
  if c.card_uid is not null then raise exception 'slot busy'; end if;
  if exists (select 1 from camp_slots where user_id = uid and card_uid = p_uid) then raise exception 'already training'; end if;
  select o into e from jsonb_array_elements(_camp_owned(uid)) o where o->>'uid' = p_uid limit 1;
  if e is null then raise exception 'not owned'; end if;
  plv := _camp_plv(uid);
  if coalesce((e->>'level')::int, 1) >= _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv) then raise exception 'at cap'; end if;
  update camp_slots set card_uid = p_uid, last_at = now() where user_id = uid and slot = p_slot;
  return _camp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$-- 빼기: 쌓인 EXP 는 먼저 정산하고 뺌
create or replace function public.camp_remove(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform 1 from story_progress where user_id = uid for update;
  r := _camp_settle(uid, p_slot, _camp_plv(uid));
  update camp_slots set card_uid = null, last_at = null where user_id = uid and slot = p_slot;
  return _camp_json(uid) || jsonb_build_object('got', case when r is null then '[]'::jsonb else jsonb_build_array(r) end);
end $$;$vr_statement$;
  execute $vr_statement$-- 모두 받기
create or replace function public.camp_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); plv int; s int; r jsonb; got jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform 1 from story_progress where user_id = uid for update;
  plv := _camp_plv(uid);
  for s in select slot from camp_slots where user_id = uid and card_uid is not null order by slot loop
    r := _camp_settle(uid, s, plv);
    if r is not null and (r->>'exp')::int > 0 then got := got || jsonb_build_array(r); end if;
  end loop;
  return _camp_json(uid) || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 보호: 훈련 중인 인재가 보유 목록에서 빠지는 변경(거래 등록·분해·합성 재료 등)은 거부
create or replace function public._camp_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from camp_slots c where c.user_id = new.user_id and c.card_uid is not null
             and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(new.data->'owned') = 'array' then new.data->'owned' else '[]'::jsonb end) o where o->>'uid' = c.card_uid)
             and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(old.data->'owned') = 'array' then old.data->'owned' else '[]'::jsonb end) o where o->>'uid' = c.card_uid)) then
    raise exception '훈련소에 있는 인재는 거래·분해·합성 재료로 쓸 수 없어요. 먼저 훈련소에서 빼 주세요 (card in camp)';
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists camp_guard on public.story_progress;$vr_statement$;
  execute $vr_statement$create trigger camp_guard before update of data on public.story_progress for each row execute function public._camp_guard();$vr_statement$;
  execute $vr_statement$revoke all on function public._camp_need_level(int), public._camp_cost(int), public._camp_rate(int), public._camp_max_hours(), public._camp_cap(text, int, int),
  public._camp_plv(uuid), public._camp_owned(uuid), public._camp_grade(text), public._camp_pending(jsonb, timestamptz, int), public._camp_json(uuid),
  public._camp_settle(uuid, int, int), public._camp_guard() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.camp_status(), public.camp_unlock(int), public.camp_put(int, text), public.camp_remove(int), public.camp_claim() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.camp_status(), public.camp_unlock(int), public.camp_put(int, text), public.camp_remove(int), public.camp_claim() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: camp2.sql =====
-- ===== 훈련소 2·3단계: 훈련소 레벨업 + 연마소(장비) + 도장(스킬) =====
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: camp.sql · gear_v1.sql · gear_craft.sql(gear_enhance_cost · _gear_mine · _gear_dust_add) · phaseE_6.sql(_skill_cost · story_skill_meta) · gem.sql(_gem_spend)
-- ※ camp.sql 을 다시 실행했다면 이 파일도 다시 실행 (_camp_json · _camp_settle · _camp_guard 를 여기서 덮어씀)
-- 규칙
--  * 훈련소 Lv1~10. 다음 레벨 비용: Lv2 골드 1만 · Lv3 2만 · Lv4 4만 · Lv5 8만 · Lv6 심연석 200 · Lv7 300 · Lv8 500 · Lv9 700 · Lv10 1000 (무료 심연석부터 사용)
--    필요 플레이어 레벨 = 5 × 목표 레벨 + 10 (Lv5 → 35, Lv8 → 50, Lv10 → 60). 레벨마다 훈련 EXP +5% (Lv10 = +45%)
--  * 연마소 (훈련소 Lv5): 장비 1개. 다음 강화 비용(골드·가루)의 50% 를 먼저 내고, +1 2시간 · +2 4시간 · +3 8시간 · +4 12시간 · +5 24시간 뒤 받으면 +1
--    연마 중인 장비는 강화·재설정·분해·매각·거래 불가 (장착·해제·잠금은 가능). 바로 강화(gear_enhance)는 그대로
--  * 도장 (훈련소 Lv8 + 심연석 1500): 스킬 하나. 다음 스킬 레벨 비용(혼·골드)의 50% 를 먼저 내고, 지금 스킬 레벨 × 4시간 뒤 받으면 +1. 도장으로는 Lv7 까지
--    2번째 칸 심연석 1000. 도장 중인 스킬은 바로 레벨업 불가, 그 인재는 거래·분해·합성 재료 불가
--  * 재화가 모자라면 시작 안 함 ('not enough ...'). 시간은 서버 now() 만. 시작 후 취소 없음

-- 1) 테이블
create table if not exists public.camp_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  camp_lv int not null default 1 check (camp_lv between 1 and 10),
  dojo_slots int not null default 0 check (dojo_slots between 0 and 2),
  updated_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$create table if not exists public.camp_jobs (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('forge', 'dojo')),
  slot int not null default 1,
  gear_id bigint, card_uid text, skill int,
  from_lv int not null, cost jsonb not null,
  started_at timestamptz not null default now(), ends_at timestamptz not null, claimed_at timestamptz);$vr_statement$;
  execute $vr_statement$create unique index if not exists camp_jobs_open_slot on public.camp_jobs (user_id, kind, slot) where claimed_at is null;$vr_statement$;
  execute $vr_statement$create unique index if not exists camp_jobs_open_gear on public.camp_jobs (gear_id) where claimed_at is null and gear_id is not null;$vr_statement$;
  execute $vr_statement$create unique index if not exists camp_jobs_open_skill on public.camp_jobs (user_id, card_uid, skill) where claimed_at is null and card_uid is not null;$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['camp_state', 'camp_jobs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', t || '_own', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop; end $$;$vr_statement$;
  execute $vr_statement$-- 2) 수치
create or replace function public._camp_lv_cost(p_to int) returns jsonb language sql immutable as $$
  select case p_to when 2 then '{"gold":10000}' when 3 then '{"gold":20000}' when 4 then '{"gold":40000}' when 5 then '{"gold":80000}'
    when 6 then '{"gem":200}' when 7 then '{"gem":300}' when 8 then '{"gem":500}' when 9 then '{"gem":700}' when 10 then '{"gem":1000}' end::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_lv_need(p_to int) returns int language sql immutable as $$ select 5 * p_to + 10 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_lv_mult(p_lv int) returns numeric language sql immutable as $$ select 1 + 0.05 * (greatest(p_lv, 1) - 1) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_forge_lv() returns int language sql immutable as $$ select 5 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_dojo_lv() returns int language sql immutable as $$ select 8 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_dojo_cost(p_slot int) returns int language sql immutable as $$ select case p_slot when 1 then 1500 when 2 then 1000 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_dojo_max() returns int language sql immutable as $$ select 7 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_forge_hours(p_to int) returns int language sql immutable as $$ select case p_to when 1 then 2 when 2 then 4 when 3 then 8 when 4 then 12 when 5 then 24 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_half(n numeric) returns int language sql immutable as $$ select ceil(coalesce(n, 0) * 0.5)::int $$;$vr_statement$;
  execute $vr_statement$-- 3) 도우미
create or replace function public._camp_st(p_uid uuid) returns camp_state language plpgsql security definer set search_path = public as $$
declare s camp_state; begin
  insert into camp_state (user_id) values (p_uid) on conflict do nothing;
  select * into s from camp_state where user_id = p_uid; return s; end $$;$vr_statement$;
  execute $vr_statement$-- 지금 받으면 들어올 EXP (상한 반영, 훈련소 레벨 배율 포함)
create or replace function public._camp_pending2(e jsonb, p_last timestamptz, plv int, mult numeric) returns int language plpgsql stable security definer set search_path = public as $$
declare hrs numeric; amt int; lv int; ex int; cap int; need int := 0; l int;
begin
  if e is null or p_last is null then return 0; end if;
  hrs := least(_camp_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0));
  amt := floor(_camp_rate(plv) * mult * hrs)::int;
  lv := greatest(1, coalesce((e->>'level')::int, 1)); ex := greatest(0, coalesce((e->>'exp')::int, 0));
  cap := _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv);
  if lv >= cap then return 0; end if;
  for l in lv..cap - 1 loop need := need + l * 100; end loop;
  return greatest(0, least(amt, need - ex));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare plv int := _camp_plv(p_uid); owned jsonb := _camp_owned(p_uid); cs camp_state := _camp_st(p_uid); m numeric := _camp_lv_mult(cs.camp_lv);
begin
  if plv >= _camp_need_level(1) then insert into camp_slots (user_id, slot) values (p_uid, 1) on conflict do nothing; end if;
  return jsonb_build_object('ok', true, 'now', now(), 'level', plv, 'rate', round(_camp_rate(plv) * m, 1), 'max_hours', _camp_max_hours(), 'cap_minus', 5,
    'camp_lv', cs.camp_lv, 'camp_max', 10, 'mult', m,
    'next', case when cs.camp_lv < 10 then jsonb_build_object('lv', cs.camp_lv + 1, 'cost', _camp_lv_cost(cs.camp_lv + 1), 'need_level', _camp_lv_need(cs.camp_lv + 1)) end,
    'forge_lv', _camp_forge_lv(), 'dojo_lv', _camp_dojo_lv(), 'dojo_slots', cs.dojo_slots, 'dojo_max', _camp_dojo_max(),
    'dojo_next_cost', case when cs.dojo_slots < 2 then _camp_dojo_cost(cs.dojo_slots + 1) end,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'slot', j.slot, 'gear_id', j.gear_id, 'card_uid', j.card_uid, 'skill', j.skill,
              'from', j.from_lv, 'cost', j.cost, 'started_at', j.started_at, 'ends_at', j.ends_at, 'done', j.ends_at <= now(),
              'card', case when j.card_uid is not null then (select o->>'id' from jsonb_array_elements(owned) o where o->>'uid' = j.card_uid limit 1) end,
              'gear_def', case when j.gear_id is not null then (select g.def_id from player_gear g where g.id = j.gear_id) end) order by j.kind, j.slot)
              from camp_jobs j where j.user_id = p_uid and j.claimed_at is null), '[]'::jsonb),
    'slots', (select jsonb_agg(jsonb_build_object('slot', s, 'need_level', _camp_need_level(s), 'cost', _camp_cost(s), 'open', c.slot is not null,
                'uid', c.card_uid, 'last_at', c.last_at,
                'card', (select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1),
                'pending', coalesce(_camp_pending2((select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1), c.last_at, plv, m), 0)) order by s)
              from generate_series(1, 5) s left join camp_slots c on c.user_id = p_uid and c.slot = s));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_settle(p_uid uuid, p_slot int, plv int) returns jsonb language plpgsql security definer set search_path = public as $$
declare c camp_slots; d jsonb; owned jsonb; idx int; e jsonb; amt int; before int; m numeric := _camp_lv_mult((_camp_st(p_uid)).camp_lv);
begin
  select * into c from camp_slots where user_id = p_uid and slot = p_slot for update;
  if c.card_uid is null then return null; end if;
  select data into d from story_progress where user_id = p_uid;
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1, t.e into idx, e from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'uid' = c.card_uid limit 1;
  if idx is null then update camp_slots set card_uid = null, last_at = null where user_id = p_uid and slot = p_slot; return null; end if;
  amt := _camp_pending2(e, c.last_at, plv, m);
  update camp_slots set last_at = now() where user_id = p_uid and slot = p_slot;
  if amt <= 0 then return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', 0, 'from', coalesce((e->>'level')::int, 1), 'level', coalesce((e->>'level')::int, 1)); end if;
  before := coalesce((e->>'level')::int, 1);
  e := _story_gain(e, amt, _camp_grade(e->>'id'));
  update story_progress set data = jsonb_set(d, array['owned', idx::text], e), updated_at = now() where user_id = p_uid;
  return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', amt, 'from', before, 'level', (e->>'level')::int);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 훈련소 레벨업
create or replace function public.camp_levelup() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; nx int; cost jsonb; plv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  select * into cs from camp_state where user_id = uid for update;
  if cs.camp_lv >= 10 then raise exception 'max camp level'; end if;
  nx := cs.camp_lv + 1; plv := _camp_plv(uid);
  if plv < _camp_lv_need(nx) then raise exception 'need level %', _camp_lv_need(nx); end if;
  -- 레벨이 바뀌기 전 배율로 지금까지 쌓인 EXP 정산 (배율 소급 방지)
  perform 1 from story_progress where user_id = uid for update;
  perform _camp_settle(uid, s.slot, plv) from camp_slots s where s.user_id = uid and s.card_uid is not null;
  cost := _camp_lv_cost(nx);
  if (cost->>'gold') is not null then perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_levelup'); end if;
  if (cost->>'gem') is not null then perform _gem_spend(uid, (cost->>'gem')::int, 'camp_levelup', jsonb_build_object('lv', nx)); end if;
  update camp_state set camp_lv = nx, updated_at = now() where user_id = uid;
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 연마소
create or replace function public.camp_forge_start(p_gear bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; c gear_enhance_cost; cost jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  if (_camp_st(uid)).camp_lv < _camp_forge_lv() then raise exception 'forge locked'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'forge' and claimed_at is null) then raise exception 'forge busy'; end if;
  g := _gear_mine(uid, p_gear);
  if g.plus >= 5 then raise exception 'max plus'; end if;
  select * into c from gear_enhance_cost where plus = g.plus + 1;
  if c.plus is null then raise exception 'no cost'; end if;
  cost := jsonb_build_object('gold', _camp_half(c.gold), 'dust', _camp_half(c.dust));
  perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_forge');   -- 'not enough gold'
  perform _gear_dust_add(uid, -(cost->>'dust')::int);                                           -- 'not enough dust'
  insert into camp_jobs (user_id, kind, slot, gear_id, from_lv, cost, ends_at)
    values (uid, 'forge', 1, g.id, g.plus, cost, now() + make_interval(hours => _camp_forge_hours(g.plus + 1)));
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 도장
create or replace function public.camp_dojo_unlock() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  if cs.camp_lv < _camp_dojo_lv() then raise exception 'dojo locked'; end if;
  if cs.dojo_slots >= 2 then raise exception 'already open'; end if;
  n := cs.dojo_slots + 1;
  perform _gem_spend(uid, _camp_dojo_cost(n), 'camp_dojo', jsonb_build_object('slot', n));   -- 'not enough gem'
  update camp_state set dojo_slots = n, updated_at = now() where user_id = uid;
  return _camp_json(uid) || jsonb_build_object('spent', jsonb_build_object('gem', _camp_dojo_cost(n)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.camp_dojo_start(p_slot int, p_uid text, p_skill int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; e jsonb; g text; ul int; lv int; c jsonb; cost jsonb; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  if p_slot is null or p_slot < 1 or p_slot > cs.dojo_slots then raise exception 'dojo locked'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'dojo' and slot = p_slot and claimed_at is null) then raise exception 'slot busy'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'dojo' and card_uid = p_uid and skill = p_skill and claimed_at is null) then raise exception 'already training'; end if;
  select o into e from jsonb_array_elements(_camp_owned(uid)) o where o->>'uid' = p_uid limit 1;
  if e is null then raise exception 'not owned'; end if;
  select m.unlock into ul from story_skill_meta m where m.card_id = e->>'id' and m.idx = p_skill;
  if ul is null then raise exception 'invalid skill'; end if;
  if coalesce((e->>'level')::int, 1) < ul then raise exception 'skill locked'; end if;
  sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
  lv := greatest(1, coalesce((sl->>p_skill::text)::int, 1));
  if lv >= _camp_dojo_max() then raise exception 'dojo max'; end if;
  g := _camp_grade(e->>'id');
  c := _skill_cost(g, lv);
  cost := jsonb_build_object('gold', _camp_half((c->>'gold')::int), 'soul', _camp_half((c->>'soul')::int));
  perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int, 'soul', -(cost->>'soul')::int), 'camp_dojo');   -- 'not enough gold/soul'
  insert into camp_jobs (user_id, kind, slot, card_uid, skill, from_lv, cost, ends_at)
    values (uid, 'dojo', p_slot, p_uid, p_skill, lv, cost, now() + make_interval(hours => 4 * lv));
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;$vr_statement$;
  execute $vr_statement$-- 7) 받기 (연마·도장 중 끝난 것 모두, p_job 주면 그것만)
create or replace function public.camp_job_claim(p_job bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); j camp_jobs; got jsonb := '[]'::jsonb; d jsonb; owned jsonb; i int; e jsonb; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform set_config('camp.ok', '1', true);
  for j in select * from camp_jobs where user_id = uid and claimed_at is null and ends_at <= now() and (p_job is null or id = p_job) order by id for update loop
    if j.kind = 'forge' then
      update player_gear set plus = least(5, plus + 1) where id = j.gear_id and user_id = uid and plus = j.from_lv;
      got := got || jsonb_build_array(jsonb_build_object('kind', 'forge', 'gear_id', j.gear_id, 'ok', found, 'level', j.from_lv + 1));
    else
      d := _story_lock(uid); owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = j.card_uid;
      if i is not null then
        e := owned->i; sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
        e := e || jsonb_build_object('skillLv', sl || jsonb_build_object(j.skill::text, greatest(coalesce((sl->>j.skill::text)::int, 1), j.from_lv + 1)),
                                     'soulSpent', coalesce((e->>'soulSpent')::int, 0) + coalesce((j.cost->>'soul')::int, 0));
        perform _story_save(uid, jsonb_set(d, array['owned', i::text], e));
      end if;
      got := got || jsonb_build_array(jsonb_build_object('kind', 'dojo', 'card_uid', j.card_uid, 'skill', j.skill, 'ok', i is not null, 'level', j.from_lv + 1));
    end if;
    update camp_jobs set claimed_at = now() where id = j.id;
  end loop;
  perform set_config('camp.ok', '', true);
  if p_job is not null and jsonb_array_length(got) = 0 then raise exception 'not done'; end if;
  return _camp_json(uid) || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$-- 8) 보호
-- 연마 중 장비: 강화 단계·부옵션 변경·삭제(분해·매각·거래) 거부. 장착·해제·잠금은 허용
create or replace function public._camp_gear_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('camp.ok', true), '') = '1' then return coalesce(new, old); end if;
  if exists (select 1 from camp_jobs j where j.gear_id = old.id and j.claimed_at is null) then
    if tg_op = 'DELETE' or new.plus is distinct from old.plus or new.opts is distinct from old.opts or new.user_id is distinct from old.user_id then
      raise exception '연마소에 있는 장비는 강화·재설정·분해·매각·거래할 수 없어요 (gear in forge)';
    end if;
  end if;
  return coalesce(new, old);
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists camp_gear_guard on public.player_gear;$vr_statement$;
  execute $vr_statement$create trigger camp_gear_guard before update or delete on public.player_gear for each row execute function public._camp_gear_guard();$vr_statement$;
  execute $vr_statement$-- 훈련·도장 중 인재: 보유 목록에서 빠지면 거부. 도장 중인 스킬 레벨이 바뀌면 거부 (도장 받기 제외)
create or replace function public._camp_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare nw jsonb := case when jsonb_typeof(new.data->'owned') = 'array' then new.data->'owned' else '[]'::jsonb end;
        od jsonb := case when jsonb_typeof(old.data->'owned') = 'array' then old.data->'owned' else '[]'::jsonb end;
begin
  if exists (select 1 from (select card_uid from camp_slots where user_id = new.user_id and card_uid is not null
                            union select card_uid from camp_jobs where user_id = new.user_id and kind = 'dojo' and claimed_at is null) c
             where not exists (select 1 from jsonb_array_elements(nw) o where o->>'uid' = c.card_uid)
               and exists (select 1 from jsonb_array_elements(od) o where o->>'uid' = c.card_uid)) then
    raise exception '훈련소·도장에 있는 인재는 거래·분해·합성 재료로 쓸 수 없어요. 먼저 훈련소에서 빼 주세요 (card in camp)';
  end if;
  if coalesce(current_setting('camp.ok', true), '') <> '1' and exists (select 1 from camp_jobs j where j.user_id = new.user_id and j.kind = 'dojo' and j.claimed_at is null
       and (select o->'skillLv'->>j.skill::text from jsonb_array_elements(nw) o where o->>'uid' = j.card_uid limit 1)
           is distinct from (select o->'skillLv'->>j.skill::text from jsonb_array_elements(od) o where o->>'uid' = j.card_uid limit 1)) then
    raise exception '도장에서 수련 중인 스킬은 지금 올릴 수 없어요 (skill in dojo)';
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._camp_lv_cost(int), public._camp_lv_need(int), public._camp_lv_mult(int), public._camp_forge_lv(), public._camp_dojo_lv(), public._camp_dojo_cost(int),
  public._camp_dojo_max(), public._camp_forge_hours(int), public._camp_half(numeric), public._camp_st(uuid), public._camp_pending2(jsonb, timestamptz, int, numeric),
  public._camp_json(uuid), public._camp_settle(uuid, int, int), public._camp_gear_guard(), public._camp_guard() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.camp_levelup(), public.camp_forge_start(bigint), public.camp_dojo_unlock(), public.camp_dojo_start(int, text, int), public.camp_job_claim(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.camp_levelup(), public.camp_forge_start(bigint), public.camp_dojo_unlock(), public.camp_dojo_start(int, text, int), public.camp_job_claim(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: daily_social.sql =====
-- =====================================================================
-- 🎁 도감 수집률 보상 + 👥 친구 일일 선물 + 📋 개인 주간 미션
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: daily.sql(_daily_grant · _gem_day) · friends.sql · gallery(schema) · phaseE_2(_player_stamina_add)
-- 시간: 전부 서버 now() / _gem_day() (한국 시간). 주간 = 월요일 00:00 KST 시작
-- 공개 RPC
--   gallery_rewards() · gallery_reward_claim(pct)
--   friend_gift_send(user) · friend_gift_claim(id) · friend_gift_claim_all()
--   friends_list() · friends_ping()  — 선물 정보 포함으로 교체
--   weekly_status() · weekly_track(kind, n) · weekly_claim(key)
-- 확인용: select public.gallery_rewards(); select public.weekly_status();
-- =====================================================================

-- =====================================================================
-- 1) 도감 수집률 구간 보상 (25 · 50 · 75 · 100%)
-- =====================================================================
create table if not exists public.gallery_claims (
  user_id   uuid not null references auth.users(id) on delete cascade,
  pct       int  not null check (pct in (25, 50, 75, 100)),
  claimed_at timestamptz not null default now(),
  primary key (user_id, pct)
);$vr_statement$;
  execute $vr_statement$alter table public.gallery_claims enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gallery_claims from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- data/cards.csv 장수(헤더 제외)와 맞출 것. 새 카드 넣으면 여기도 올리기
create or replace function public._gallery_total() returns int language sql immutable as $$ select 438 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_reward_defs() returns jsonb language sql immutable as $$ select '[
  {"pct":25,"reward":{"gold":15000,"tickets":10}},
  {"pct":50,"reward":{"gold":45000,"gem":50,"tickets":20}},
  {"pct":75,"reward":{"gold":90000,"gem":100,"tickets":30}},
  {"pct":100,"reward":{"gold":150000,"gem":300,"tickets":50}}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_have(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from gallery where user_id = p_uid $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gallery_have(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._gallery_rewards_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare have int := _gallery_have(p_uid); tot int := _gallery_total(); pct int;
begin
  pct := case when tot <= 0 then 0 else least(100, (have * 100) / tot) end;
  return jsonb_build_object('ok', true, 'have', have, 'total', tot, 'pct', pct,
    'milestones', (select jsonb_agg(m || jsonb_build_object(
        'ready', pct >= (m->>'pct')::int,
        'claimed', exists (select 1 from gallery_claims c where c.user_id = p_uid and c.pct = (m->>'pct')::int))
      order by (m->>'pct')::int)
      from jsonb_array_elements(_gallery_reward_defs()) m));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gallery_rewards_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.gallery_rewards() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _gallery_rewards_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.gallery_reward_claim(p_pct int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; have int; tot int; pct int; res jsonb; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_gallery_reward_defs()) x where (x->>'pct')::int = p_pct;
  if m is null then raise exception 'invalid pct'; end if;
  perform pg_advisory_xact_lock(hashtext('galrw:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  have := _gallery_have(uid); tot := _gallery_total();
  pct := case when tot <= 0 then 0 else least(100, (have * 100) / tot) end;
  if pct < p_pct then raise exception 'not done'; end if;
  insert into gallery_claims (user_id, pct) values (uid, p_pct) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  res := _daily_grant(uid, m->'reward', 'gallery', 'gallery:' || p_pct);
  return _gallery_rewards_json(uid) || res || jsonb_build_object('got', m->'reward');
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gallery_rewards(), public.gallery_reward_claim(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gallery_rewards(), public.gallery_reward_claim(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- =====================================================================
-- 2) 친구 일일 선물 (친구 1명당 하루 1회 보내기 · 하루 최대 20개 받기)
-- =====================================================================
create table if not exists public.friend_gifts (
  id         bigint generated always as identity primary key,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  unique (from_user, to_user, day)
);$vr_statement$;
  execute $vr_statement$create index if not exists friend_gifts_to_day_idx on public.friend_gifts (to_user, day) where claimed_at is null;$vr_statement$;
  execute $vr_statement$create index if not exists friend_gifts_to_claimed_idx on public.friend_gifts (to_user, day) where claimed_at is not null;$vr_statement$;
  execute $vr_statement$alter table public.friend_gifts enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.friend_gifts from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_gift_reward() returns jsonb language sql immutable as $$ select '{"stamina":5}'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_gift_claim_cap() returns int language sql immutable as $$ select 20 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_gift_grant(p_uid uuid, p_rw jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; st int;
begin
  if coalesce((p_rw->>'stamina')::int, 0) > 0 then
    st := _player_stamina_add(p_uid, (p_rw->>'stamina')::int);
    res := res || jsonb_build_object('stamina', st);
  end if;
  if coalesce((p_rw->>'gold')::int, 0) > 0 or coalesce((p_rw->>'gem')::int, 0) > 0 or coalesce((p_rw->>'tickets')::int, 0) > 0 then
    res := res || _daily_grant(p_uid, p_rw - 'stamina', 'friend_gift', 'friend_gift');
  end if;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._friend_gift_grant(uuid, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_gift_send(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not _is_friend(uid, p_user) then raise exception 'not friends'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  insert into friend_gifts (from_user, to_user, day) values (uid, p_user, today)
    on conflict (from_user, to_user, day) do nothing returning id into gid;
  if gid is null then raise exception 'already sent'; end if;
  return jsonb_build_object('ok', true, 'id', gid, 'day', today);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_gift_claim(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); g friend_gifts; n int; rw jsonb := _friend_gift_reward(); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  select * into g from friend_gifts where id = p_id and to_user = uid for update;
  if g.id is null then raise exception 'gift not found'; end if;
  if g.claimed_at is not null then raise exception 'already claimed'; end if;
  select count(*) into n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  if n >= _friend_gift_claim_cap() then raise exception 'claim cap'; end if;
  update friend_gifts set claimed_at = now() where id = g.id;
  res := _friend_gift_grant(uid, rw);
  return jsonb_build_object('ok', true, 'got', rw, 'claimed_today', n + 1, 'cap', _friend_gift_claim_cap()) || res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_gift_claim_all() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); g friend_gifts; n int; left_n int; tot int := 0; rw jsonb := _friend_gift_reward(); st int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('fgift:' || uid::text));
  select count(*) into n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  left_n := greatest(0, _friend_gift_claim_cap() - n);
  if left_n <= 0 then raise exception 'claim cap'; end if;
  for g in select * from friend_gifts where to_user = uid and claimed_at is null order by id limit left_n for update loop
    update friend_gifts set claimed_at = now() where id = g.id;
    tot := tot + 1;
  end loop;
  if tot <= 0 then raise exception 'nothing to claim'; end if;
  if coalesce((rw->>'stamina')::int, 0) > 0 then st := _player_stamina_add(uid, (rw->>'stamina')::int * tot); end if;
  return jsonb_build_object('ok', true, 'n', tot, 'got', jsonb_build_object('stamina', coalesce((rw->>'stamina')::int, 0) * tot),
    'stamina', st, 'claimed_today', n + tot, 'cap', _friend_gift_claim_cap());
end $$;$vr_statement$;
  execute $vr_statement$-- friends_list / friends_ping 에 선물 상태 추가 (기존 필드 유지)
create or replace function public.friends_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); claimed_n int; inbox jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  select count(*) into claimed_n from friend_gifts where to_user = uid and day = today and claimed_at is not null;
  select coalesce(jsonb_agg(_friend_card(g.from_user) || jsonb_build_object('gift_id', g.id, 'at', g.created_at) order by g.id), '[]'::jsonb)
    into inbox from friend_gifts g where g.to_user = uid and g.claimed_at is null;
  return jsonb_build_object('ok', true, 'me', _friend_card(uid), 'cap', _friend_cap(),
    'friends', (select coalesce(jsonb_agg(_friend_card(o) || jsonb_build_object('since', f.created_at,
                   'gift_sent', exists (select 1 from friend_gifts g where g.from_user = uid and g.to_user = o and g.day = today))
                 order by (select seen_at from player_presence where user_id = o) desc nulls last), '[]'::jsonb)
               from (select case when user_a = uid then user_b else user_a end o, created_at from friendships where user_a = uid or user_b = uid) f),
    'incoming', (select coalesce(jsonb_agg(_friend_card(r.from_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.to_user = uid),
    'outgoing', (select coalesce(jsonb_agg(_friend_card(r.to_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.from_user = uid),
    'gifts', jsonb_build_object('inbox', inbox, 'reward', _friend_gift_reward(), 'claimed_today', claimed_n, 'cap', _friend_gift_claim_cap(),
               'left', greatest(0, _friend_gift_claim_cap() - claimed_n)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friends_ping() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true,
    'pending', (select count(*) from friend_requests where to_user = uid),
    'gifts', (select count(*) from friend_gifts where to_user = uid and claimed_at is null));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.friend_gift_send(uuid), public.friend_gift_claim(bigint), public.friend_gift_claim_all(),
  public.friends_list(), public.friends_ping() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.friend_gift_send(uuid), public.friend_gift_claim(bigint), public.friend_gift_claim_all(),
  public.friends_list(), public.friends_ping() to authenticated;$vr_statement$;
  execute $vr_statement$-- =====================================================================
-- 3) 개인 주간 미션 (월요일 00:00 KST 초기화)
-- =====================================================================
create table if not exists public.weekly_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  week    date not null,
  prog    jsonb not null default '{}'::jsonb,
  claimed jsonb not null default '[]'::jsonb,
  primary key (user_id, week)
);$vr_statement$;
  execute $vr_statement$alter table public.weekly_progress enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.weekly_progress from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 주 시작일 = 그 주의 월요일 (KST 날짜 기준). PG date_trunc('week') 는 월요일 시작
create or replace function public._weekly_week() returns date language sql stable as $$
  select date_trunc('week', _gem_day()::timestamp)::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._weekly_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 7","goal":7,"per":2,"reward":{"gold":8000,"tickets":1}},
  {"key":"win","name":"전투 승리 x 15","goal":15,"per":3,"reward":{"gold":10000,"gem":30}},
  {"key":"story","name":"스토리 스테이지 클리어 x 10","goal":10,"per":2,"reward":{"gold":10000,"gem":30}},
  {"key":"tower","name":"시련의 탑 도전 x 5","goal":5,"per":1,"reward":{"gold":8000,"gem":20}},
  {"key":"skill","name":"고유기술 사용 x 50","goal":50,"per":40,"reward":{"gold":8000,"gem":20}}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._weekly_all_reward() returns jsonb language sql immutable as $$ select '{"gem":100,"tickets":2}'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._weekly_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare wp weekly_progress; week date := _weekly_week(); done int; next_reset timestamptz;
begin
  select * into wp from weekly_progress where user_id = p_uid and week = week;
  select count(*) into done from jsonb_array_elements(_weekly_defs()) m where coalesce((wp.prog->>(m->>'key'))::int, 0) >= (m->>'goal')::int;
  next_reset := ((week + 7)::timestamp at time zone 'Asia/Seoul');
  return jsonb_build_object('ok', true, 'week', week, 'next_reset', next_reset,
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, coalesce((wp.prog->>(m->>'key'))::int, 0)),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_weekly_defs()) m),
    'all', jsonb_build_object('reward', _weekly_all_reward(), 'done', done, 'goal', jsonb_array_length(_weekly_defs()),
                   'claimed', coalesce(wp.claimed, '[]'::jsonb) ? 'all'));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._weekly_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _weekly_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_track(p_kind text, p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; week date := _weekly_week(); cur int; nv int;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_weekly_defs()) x where x->>'key' = p_kind;
  if m is null then raise exception 'invalid kind'; end if;
  perform pg_advisory_xact_lock(hashtext('weekly:' || uid::text));
  insert into weekly_progress (user_id, week) values (uid, week) on conflict do nothing;
  select coalesce((prog->>p_kind)::int, 0) into cur from weekly_progress where user_id = uid and week = week;
  nv := least((m->>'goal')::int, cur + greatest(0, least(coalesce(p_n, 1), (m->>'per')::int)));
  if nv <> cur then update weekly_progress set prog = prog || jsonb_build_object(p_kind, nv) where user_id = uid and week = week; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'prog', nv, 'goal', (m->>'goal')::int);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_claim(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; week date := _weekly_week(); wp weekly_progress; rw jsonb; res jsonb; done int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('weekly:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into weekly_progress (user_id, week) values (uid, week) on conflict do nothing;
  select * into wp from weekly_progress where user_id = uid and week = week for update;
  if wp.claimed ? p_key then raise exception 'already claimed'; end if;
  if p_key = 'all' then
    select count(*) into done from jsonb_array_elements(_weekly_defs()) x where coalesce((wp.prog->>(x->>'key'))::int, 0) >= (x->>'goal')::int;
    if done < jsonb_array_length(_weekly_defs()) then raise exception 'not done'; end if;
    rw := _weekly_all_reward();
  else
    select x into m from jsonb_array_elements(_weekly_defs()) x where x->>'key' = p_key;
    if m is null then raise exception 'invalid key'; end if;
    if coalesce((wp.prog->>p_key)::int, 0) < (m->>'goal')::int then raise exception 'not done'; end if;
    rw := m->'reward';
  end if;
  update weekly_progress set claimed = claimed || to_jsonb(p_key) where user_id = uid and week = week;
  res := _daily_grant(uid, rw, 'weekly', 'weekly:' || week || ':' || p_key);
  return _weekly_json(uid) || res || jsonb_build_object('got', rw);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.weekly_status(), public.weekly_track(text, int), public.weekly_claim(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.weekly_status(), public.weekly_track(text, int), public.weekly_claim(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: achievements.sql =====
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
);$vr_statement$;
  execute $vr_statement$alter table public.achievement_claims enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.achievement_claims from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 업적 정의. tiers[].goal = 달성 기준 · reward = 지급 · 마지막 칸 점수 +20, 그 앞 +10
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
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_score_defs() returns jsonb language sql immutable as $$ select '[
  {"goal":100,"reward":{"gem":50,"tickets":2}},
  {"goal":200,"reward":{"gem":100,"tickets":3}},
  {"goal":350,"reward":{"gem":200,"tickets":5}}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_cats() returns jsonb language sql immutable as $$
  select '[{"id":"growth","name":"성장"},{"id":"battle","name":"전투"},{"id":"collect","name":"수집"},{"id":"story","name":"스토리"},{"id":"social","name":"소셜"}]'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 챕터별 페이즈 수 (전부 클리어해야 챕터 클리어). ch2 는 루트 하나 기준 10
create or replace function public._ach_ch_need(p_ch int) returns int language sql immutable as $$
  select case p_ch
    when 0 then 5 when 1 then 5 when 2 then 10 when 3 then 10 when 4 then 10 when 5 then 10
    when 6 then 10 when 7 then 10 when 8 then 15 when 9 then 18 when 10 then 17
    when 11 then 16 when 12 then 21 when 13 then 15 when 14 then 18 when 15 then 16
    else 0 end $$;$vr_statement$;
  execute $vr_statement$-- ---------- 진행도 계산 (서버) ----------
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
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_key(p_id text, p_goal int) returns text language sql immutable as $$
  select p_id || ':' || p_goal::text $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_score_key(p_goal int) returns text language sql immutable as $$
  select 'score:' || p_goal::text $$;$vr_statement$;
  execute $vr_statement$-- 업적 점수 = 받은 칸 합 (마지막 칸 +20, 그 앞 +10). score: 키는 제외
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._ach_defs(), public._ach_score_defs(), public._ach_cats(), public._ach_ch_need(int),
  public._ach_prog(uuid, text), public._ach_key(text, int), public._ach_score_key(int),
  public._ach_score(uuid), public._ach_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.achievements_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _ach_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_claim_one(p_uid uuid, p_key text) returns jsonb
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._ach_claim_one(uuid, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.achievements_claim(p_key text) returns jsonb
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
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.achievements_claim_all() returns jsonb
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.achievements_status(), public.achievements_claim(text), public.achievements_claim_all() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.achievements_status(), public.achievements_claim(text), public.achievements_claim_all() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: idle_box.sql =====
-- =====================================================================
-- 🎁 방치 보상 상자 — 꺼둔 동안 골드·이상한 조각·순수한 피·장비 가루 누적
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: phaseE_1.sql(_wallet_add) · phaseE_2.sql(player_state) · gem.sql(_gem_spend · _gem_day)
--       · gear_craft.sql(_gear_dust_add) · gear_v1.sql(_gear_meta)
-- 시간: 서버 now(). 첫 생성 시 last_claim = now() (소급 없음). 상한 8시간
-- 시간당(플레이어 Lv): 골드 400+Lv×20 · 조각 1+floor(Lv/10) · 피 1+floor(Lv/20) · 가루 1+floor(Lv/25)
-- 빠른 보상: 심연석 30 → 4시간분 즉시 · 하루 2회(KST _gem_day)
-- 공개 RPC: idle_box_status() · idle_box_claim() · idle_box_boost()
-- 확인용: select public.idle_box_status();
-- =====================================================================

create table if not exists public.idle_box (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  last_claim timestamptz not null default now(),
  boost_day  date,
  boost_n    int not null default 0 check (boost_n >= 0),
  updated_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$alter table public.idle_box enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.idle_box from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_max_hours() returns numeric language sql immutable as $$ select 8 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_boost_hours() returns numeric language sql immutable as $$ select 4 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_boost_cost() returns int language sql immutable as $$ select 30 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_boost_max() returns int language sql immutable as $$ select 2 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_rate(p_lv int) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'gold',  400 + 20 * greatest(p_lv, 1),
    'shard', 1 + (greatest(p_lv, 1) / 10),
    'blood', 1 + (greatest(p_lv, 1) / 20),
    'dust',  1 + (greatest(p_lv, 1) / 25)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_amt(p_rate jsonb, p_hrs numeric) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'gold',  floor((p_rate->>'gold')::numeric  * p_hrs)::int,
    'shard', floor((p_rate->>'shard')::numeric * p_hrs)::int,
    'blood', floor((p_rate->>'blood')::numeric * p_hrs)::int,
    'dust',  floor((p_rate->>'dust')::numeric  * p_hrs)::int) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_plv(p_uid uuid) returns int language plpgsql stable security definer set search_path = public as $$
declare lv int := 1;
begin
  if to_regclass('public.player_state') is not null then
    select coalesce(level, 1) into lv from player_state where user_id = p_uid;
  end if;
  return greatest(coalesce(lv, 1), 1);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_row(p_uid uuid) returns public.idle_box
language plpgsql security definer set search_path = public as $$
declare r idle_box;
begin
  insert into idle_box (user_id, last_claim) values (p_uid, now()) on conflict do nothing;
  select * into r from idle_box where user_id = p_uid for update;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_hours(p_last timestamptz) returns numeric language sql stable as $$
  select least(_idle_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_grant(p_uid uuid, p_got jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w jsonb := null; d bigint := null; cur jsonb := '{}'::jsonb;
begin
  if coalesce((p_got->>'gold')::int, 0) > 0 then cur := cur || jsonb_build_object('gold', (p_got->>'gold')::int); end if;
  if coalesce((p_got->>'shard')::int, 0) > 0 then cur := cur || jsonb_build_object('shard', (p_got->>'shard')::int); end if;
  if coalesce((p_got->>'blood')::int, 0) > 0 then cur := cur || jsonb_build_object('blood', (p_got->>'blood')::int); end if;
  if cur <> '{}'::jsonb then w := _wallet_add(p_uid, cur, p_reason); end if;
  if coalesce((p_got->>'dust')::int, 0) > 0 then
    if to_regprocedure('public._gear_dust_add(uuid,bigint)') is null then raise exception 'dust unavailable'; end if;
    d := _gear_dust_add(p_uid, (p_got->>'dust')::bigint);
  end if;
  return jsonb_build_object('wallet', w, 'dust', d);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._idle_json(p_uid uuid, p_r idle_box) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv int := _idle_plv(p_uid); rate jsonb := _idle_rate(lv); hrs numeric; got jsonb;
  today date := _gem_day(); boost_left int; boost_n int;
begin
  hrs := _idle_hours(p_r.last_claim);
  got := _idle_amt(rate, hrs);
  boost_n := case when p_r.boost_day = today then p_r.boost_n else 0 end;
  boost_left := greatest(0, _idle_boost_max() - boost_n);
  return jsonb_build_object('ok', true, 'now', now(), 'level', lv, 'rate', rate, 'hours', round(hrs::numeric, 3),
    'max_hours', _idle_max_hours(), 'full', hrs >= _idle_max_hours(),
    'pending', got, 'ready', (got->>'gold')::int > 0 or (got->>'shard')::int > 0 or (got->>'blood')::int > 0 or (got->>'dust')::int > 0,
    'last_claim', p_r.last_claim,
    'boost', jsonb_build_object('cost', _idle_boost_cost(), 'hours', _idle_boost_hours(), 'left', boost_left, 'max', _idle_boost_max(),
      'reward', _idle_amt(rate, _idle_boost_hours())));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._idle_max_hours(), public._idle_boost_hours(), public._idle_boost_cost(), public._idle_boost_max(),
  public._idle_rate(int), public._idle_amt(jsonb, numeric), public._idle_plv(uuid), public._idle_row(uuid),
  public._idle_hours(timestamptz), public._idle_grant(uuid, jsonb, text), public._idle_json(uuid, idle_box)
  from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.idle_box_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  r := _idle_row(uid);
  return _idle_json(uid, r);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.idle_box_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box; j jsonb; got jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  r := _idle_row(uid);
  j := _idle_json(uid, r);
  if not coalesce((j->>'ready')::boolean, false) then raise exception 'not done'; end if;
  got := j->'pending';
  res := _idle_grant(uid, got, 'idle_box');
  update idle_box set last_claim = now(), updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.idle_box_boost() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r idle_box; today date := _gem_day(); boost_n int; got jsonb; res jsonb; gem jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('idle:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  r := _idle_row(uid);
  boost_n := case when r.boost_day = today then r.boost_n else 0 end;
  if boost_n >= _idle_boost_max() then raise exception 'daily limit'; end if;
  got := _idle_amt(_idle_rate(_idle_plv(uid)), _idle_boost_hours());
  gem := _gem_spend(uid, _idle_boost_cost(), 'idle_boost', jsonb_build_object('hours', _idle_boost_hours()));
  res := _idle_grant(uid, got, 'idle_boost');
  update idle_box set boost_day = today, boost_n = boost_n + 1, updated_at = now() where user_id = uid;
  select * into r from idle_box where user_id = uid;
  return _idle_json(uid, r) || res || jsonb_build_object('got', got, 'gem', gem);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.idle_box_status(), public.idle_box_claim(), public.idle_box_boost() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.idle_box_status(), public.idle_box_claim(), public.idle_box_boost() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: cosmetics.sql =====
-- =====================================================================
-- 🎨 꾸미기 1차 — 칭호 + 프로필 프레임 (전투 보드·카드 테두리는 이후)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: profiles · phaseE_2(player_state) · tower_v2 · gallery · story_progress
--       · pvp_tier(pvp_titles · pvp_ratings) · guild(guild_titles) · gem.sql(_gem_spend)
--       · achievements.sql(_ach_score) 선택 · daily_social(_gallery_have · _gallery_total) 선택
-- 공개 RPC: cosmetics_status() · cosmetics_equip(title, frame) · cosmetics_buy(kind, id)
--           · cosmetics_lookup(ids)
-- 확인용: select public.cosmetics_status();
-- 소유 = 조건 달성(소급) 또는 심연석 구매. 장착은 보유만. profiles.cosmo_* 에 저장 → 남에게 표시
-- =====================================================================

alter table public.profiles add column if not exists cosmo_title text;$vr_statement$;
  execute $vr_statement$alter table public.profiles add column if not exists cosmo_frame text;$vr_statement$;
  execute $vr_statement$create table if not exists public.cosmetic_purchases (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind    text not null check (kind in ('title', 'frame')),
  id      text not null check (char_length(id) between 1 and 40),
  bought_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);$vr_statement$;
  execute $vr_statement$alter table public.cosmetic_purchases enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.cosmetic_purchases from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 칭호 정의
create or replace function public._cosmo_title_defs() returns jsonb language sql immutable as $$ select '[
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
  {"id":"abyss","name":"심연","how":"PvP 심연 시즌"}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 프레임 정의. shop=심연석 가격(없으면 구매 불가)
create or replace function public._cosmo_frame_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"frame_basic","name":"기본","how":"기본","shop":null},
  {"id":"frame_bronze","name":"청동","how":"일반탑 30층","shop":300},
  {"id":"frame_silver","name":"은","how":"도감 25%","shop":300},
  {"id":"frame_gold","name":"금","how":"챕터 10 클리어","shop":300},
  {"id":"frame_abyss","name":"심연","how":"업적 200점 또는 PvP 심연","shop":null},
  {"id":"frame_guild","name":"조직","how":"조직 상점","shop":null}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_ch_need(p_ch int) returns int language sql immutable as $$
  select case p_ch
    when 0 then 5 when 1 then 5 when 2 then 10 when 3 then 10 when 4 then 10 when 5 then 10
    when 6 then 10 when 7 then 10 when 8 then 15 when 9 then 18 when 10 then 17
    when 11 then 16 when 12 then 21 when 13 then 15 when 14 then 18 when 15 then 16
    else 0 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_story_ch(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; ch text; arr jsonb; n int; mx int := 0;
begin
  if to_regclass('public.story_progress') is null then return 0; end if;
  select data into d from story_progress where user_id = p_uid;
  if d is null or jsonb_typeof(d->'cleared') is distinct from 'object' then return 0; end if;
  for ch, arr in select key, value from jsonb_each(d->'cleared') loop
    if ch ~ '^[0-9]+$' then
      n := case when jsonb_typeof(arr) = 'array' then jsonb_array_length(arr) else 0 end;
      if n >= _cosmo_ch_need(ch::int) and ch::int > mx then mx := ch::int; end if;
    end if;
  end loop;
  return mx;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_tower(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select best_floor from tower_progress where user_id = p_uid and tower = 'normal'), 0) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_gallery_pct(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare have int := 0; tot int := 438;
begin
  if to_regclass('public.gallery') is null then return 0; end if;
  if to_regprocedure('public._gallery_have(uuid)') is not null then have := _gallery_have(p_uid);
  else select count(*)::int into have from gallery where user_id = p_uid; end if;
  if to_regprocedure('public._gallery_total()') is not null then tot := _gallery_total(); end if;
  if tot <= 0 then return 0; end if;
  return least(100, (have * 100) / tot);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_pvp_ord(p_uid uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare v int := 0;
begin
  if to_regclass('public.pvp_ratings') is null or to_regclass('public.pvp_tier_table') is null then return 0; end if;
  select coalesce(max((select t.ord from pvp_tier_table t where t.min_rating <= coalesce(r.rating, 1000)
                        order by t.min_rating desc limit 1)), 0) into v
    from pvp_ratings r where r.user_id = p_uid;
  return coalesce(v, 0);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_ach_score(p_uid uuid) returns int language sql stable security definer set search_path = public as $$
  select case when to_regprocedure('public._ach_score(uuid)') is not null then _ach_score(p_uid) else 0 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_bought(p_uid uuid, p_kind text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from cosmetic_purchases where user_id = p_uid and kind = p_kind and id = p_id) $$;$vr_statement$;
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
  end if;
  return false;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_equip_get(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; f text;
begin
  select cosmo_title, cosmo_frame into t, f from profiles where id = p_uid;
  if t is null or not _cosmo_owned(p_uid, 'title', t) then t := 'recruit'; end if;
  if f is null or not _cosmo_owned(p_uid, 'frame', f) then f := 'frame_basic'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, updated_at = now() where id = p_uid
    and (cosmo_title is distinct from t or cosmo_frame is distinct from f);
  return jsonb_build_object('title', t, 'frame', f);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_json(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare eq jsonb; titles jsonb; frames jsonb;
begin
  eq := _cosmo_equip_get(p_uid);
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, 'title', d->>'id'),
      'equipped', (eq->>'title') = (d->>'id')) order by ord), '[]'::jsonb)
    into titles from jsonb_array_elements(_cosmo_title_defs()) with ordinality t(d, ord);
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, 'frame', d->>'id'),
      'equipped', (eq->>'frame') = (d->>'id'),
      'price', d->'shop') order by ord), '[]'::jsonb)
    into frames from jsonb_array_elements(_cosmo_frame_defs()) with ordinality t(d, ord);
  return jsonb_build_object('ok', true, 'equipped', eq, 'titles', titles, 'frames', frames);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._cosmo_title_defs(), public._cosmo_frame_defs(), public._cosmo_ch_need(int),
  public._cosmo_story_ch(uuid), public._cosmo_tower(uuid), public._cosmo_gallery_pct(uuid),
  public._cosmo_pvp_ord(uuid), public._cosmo_ach_score(uuid), public._cosmo_bought(uuid, text, text),
  public._cosmo_owned(uuid, text, text), public._cosmo_equip_get(uuid), public._cosmo_json(uuid)
  from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  insert into profiles (id) values (uid) on conflict do nothing;
  return _cosmo_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_equip(p_title text, p_frame text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  if p_title is null or p_frame is null then raise exception 'invalid'; end if;
  if not _cosmo_owned(uid, 'title', p_title) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'frame', p_frame) then raise exception 'not owned'; end if;
  update profiles set cosmo_title = p_title, cosmo_frame = p_frame, updated_at = now() where id = uid;
  return _cosmo_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_buy(p_kind text, p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; price int; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind is distinct from 'frame' then raise exception 'invalid'; end if;
  select x into d from jsonb_array_elements(_cosmo_frame_defs()) x where x->>'id' = p_id;
  if d is null then raise exception 'invalid'; end if;
  if d->'shop' is null or jsonb_typeof(d->'shop') = 'null' then raise exception 'not for sale'; end if;
  price := (d->>'shop')::int;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  if _cosmo_owned(uid, 'frame', p_id) then raise exception 'already owned'; end if;
  perform _gem_spend(uid, price, 'cosmo_buy', jsonb_build_object('id', p_id));
  insert into cosmetic_purchases (user_id, kind, id) values (uid, 'frame', p_id) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already owned'; end if;
  return _cosmo_json(uid) || jsonb_build_object('bought', p_id, 'price', price);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_lookup(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_object_agg(id::text, jsonb_build_object(
      'title', coalesce(cosmo_title, 'recruit'),
      'frame', coalesce(cosmo_frame, 'frame_basic'),
      'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), ''),
      'frame_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_frame_defs()) d where d->>'id' = coalesce(p.cosmo_frame, 'frame_basic')), '')))
    from profiles p where p.id = any(coalesce(p_ids, '{}'::uuid[]))), '{}'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.cosmetics_status(), public.cosmetics_equip(text, text), public.cosmetics_buy(text, text), public.cosmetics_lookup(uuid[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.cosmetics_status(), public.cosmetics_equip(text, text), public.cosmetics_buy(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.cosmetics_lookup(uuid[]) to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 친구 카드에 칭호·프레임
create or replace function public._friend_card(p uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('user_id', p, 'code', _friend_code(p),
    'name', coalesce((select nickname from profiles where id = p), '플레이어'),
    'avatar', (select avatar_url from profiles where id = p),
    'level', coalesce((select level from player_state where user_id = p), 1),
    'seen_at', (select seen_at from player_presence where user_id = p),
    'online', coalesce((select seen_at > now() - interval '5 minutes' from player_presence where user_id = p), false),
    'title', coalesce((select cosmo_title from profiles where id = p), 'recruit'),
    'frame', coalesce((select cosmo_frame from profiles where id = p), 'frame_basic'),
    'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d
      where d->>'id' = coalesce((select cosmo_title from profiles where id = p), 'recruit')), '신입 대원')) $$;$vr_statement$;
  execute $vr_statement$-- 랭킹에 칭호·프레임
create or replace function public.tower_rankings(p_tower text default 'normal') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  if p_tower not in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') then raise exception 'bad tower'; end if;
  with t as (select g.user_id, g.best_floor, g.clears, rank() over (order by g.best_floor desc) rk, row_number() over (order by g.best_floor desc, g.updated_at) rn
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'floor', best_floor, 'me', t.user_id = uid,
           'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
           'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rn), '[]'::jsonb)
    into top from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id;
  with t as (select g.user_id, g.best_floor, rank() over (order by g.best_floor desc) rk
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select jsonb_build_object('rank', rk, 'floor', best_floor) into mine from t where t.user_id = uid;
  return jsonb_build_object('top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.story_rankings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  with c as (
    select s.user_id, s.updated_at, (k.key)::int ch, max((v.value)::int) ph, count(*) n
      from story_progress s, jsonb_each(case when jsonb_typeof(s.data->'cleared') = 'object' then s.data->'cleared' else '{}'::jsonb end) k,
           jsonb_array_elements_text(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) v
     where k.key ~ '^[0-9]{1,3}$' and v.value ~ '^[0-9]{1,3}$'
     group by s.user_id, s.updated_at, k.key),
  b as (select distinct on (user_id) user_id, updated_at, ch, ph from c order by user_id, ch desc),
  tot as (select user_id, sum(n)::int total from c group by user_id),
  t as (select b.*, tot.total, rank() over (order by ch desc, ph desc) rk, row_number() over (order by ch desc, ph desc, tot.total desc, b.updated_at) rn
          from b join tot using (user_id))
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid,
                     'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
                     'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rn)
                     from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := p_season; top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with latest as (
    select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
      from pvp_ratings r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.wins + r.losses > 0
     order by r.user_id, r.season desc),
  t as (select user_id, rating, wins, losses, rank() over (order by rating desc, wins desc) rk from latest)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses,
           'me', t.user_id = uid, 'tier', _pvp_tier(rating),
           'abyss', exists (select 1 from pvp_titles x where x.user_id = t.user_id and x.title = 'abyss'),
           'title', coalesce(p.cosmo_title, 'recruit'), 'frame', coalesce(p.cosmo_frame, 'frame_basic'),
           'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), '')) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with latest as (
    select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
      from pvp_ratings r
     where r.league = p_league and r.mode = p_mode and (s is null or r.season = s) and r.wins + r.losses > 0
     order by r.user_id, r.season desc),
  t as (select user_id, rating, wins, losses, rank() over (order by rating desc, wins desc) rk from latest)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses, 'tier', _pvp_tier(rating)) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', coalesce(s, _pvp_season()), 'top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.tower_rankings(text), public.story_rankings(), public.pvp_rankings(text, text, date) from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.tower_rankings(text), public.story_rankings(), public.pvp_rankings(text, text, date) to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: cosmetics2.sql =====
-- =====================================================================
-- 🎨 꾸미기 2차 — 전투 보드 · 카드 테두리 (1차 cosmetics.sql 이후)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: cosmetics.sql · gem.sql(_gem_spend) · story/tower/achievements 선택
-- 공개 RPC (교체): cosmetics_status · cosmetics_equip(title,frame,board,border)
--                  · cosmetics_buy(kind,id) · cosmetics_lookup
-- 확인용: select public.cosmetics_status();
-- =====================================================================

alter table public.profiles add column if not exists cosmo_board text;$vr_statement$;
  execute $vr_statement$alter table public.profiles add column if not exists cosmo_border text;$vr_statement$;
  execute $vr_statement$-- kind 확장: title · frame · board · border
alter table public.cosmetic_purchases drop constraint if exists cosmetic_purchases_kind_check;$vr_statement$;
  execute $vr_statement$alter table public.cosmetic_purchases add constraint cosmetic_purchases_kind_check
  check (kind in ('title', 'frame', 'board', 'border'));$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_board_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"board_basic","name":"기본","how":"기본","shop":null},
  {"id":"board_alley","name":"밤의 골목","how":"일반탑 20층 또는 상점","shop":500},
  {"id":"board_antnest","name":"개미굴","how":"챕터 2 클리어 또는 상점","shop":500},
  {"id":"board_rift","name":"심연 균열","how":"업적 100점·탑 50층 또는 상점","shop":500}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_border_defs() returns jsonb language sql immutable as $$ select '[
  {"id":"border_basic","name":"기본","how":"기본","shop":null},
  {"id":"border_alley","name":"밤의 골목","how":"일반탑 20층 또는 상점","shop":500},
  {"id":"border_antnest","name":"개미굴","how":"챕터 2 클리어 또는 상점","shop":500},
  {"id":"border_rift","name":"심연 균열","how":"업적 100점·탑 50층 또는 상점","shop":500}
]'::jsonb $$;$vr_statement$;
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
  execute $vr_statement$create or replace function public._cosmo_equip_get(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; f text; b text; d text;
begin
  select cosmo_title, cosmo_frame, cosmo_board, cosmo_border into t, f, b, d from profiles where id = p_uid;
  if t is null or not _cosmo_owned(p_uid, 'title', t) then t := 'recruit'; end if;
  if f is null or not _cosmo_owned(p_uid, 'frame', f) then f := 'frame_basic'; end if;
  if b is null or not _cosmo_owned(p_uid, 'board', b) then b := 'board_basic'; end if;
  if d is null or not _cosmo_owned(p_uid, 'border', d) then d := 'border_basic'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, cosmo_board = b, cosmo_border = d, updated_at = now()
   where id = p_uid and (cosmo_title is distinct from t or cosmo_frame is distinct from f
      or cosmo_board is distinct from b or cosmo_border is distinct from d);
  return jsonb_build_object('title', t, 'frame', f, 'board', b, 'border', d);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_list(p_uid uuid, p_kind text, p_eq text, p_defs jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(d || jsonb_build_object(
      'owned', _cosmo_owned(p_uid, p_kind, d->>'id'),
      'equipped', p_eq = (d->>'id'),
      'price', d->'shop') order by ord), '[]'::jsonb)
    from jsonb_array_elements(p_defs) with ordinality t(d, ord) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._cosmo_json(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare eq jsonb;
begin
  eq := _cosmo_equip_get(p_uid);
  return jsonb_build_object('ok', true, 'equipped', eq,
    'titles', _cosmo_list(p_uid, 'title', eq->>'title', _cosmo_title_defs()),
    'frames', _cosmo_list(p_uid, 'frame', eq->>'frame', _cosmo_frame_defs()),
    'boards', _cosmo_list(p_uid, 'board', eq->>'board', _cosmo_board_defs()),
    'borders', _cosmo_list(p_uid, 'border', eq->>'border', _cosmo_border_defs()));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._cosmo_board_defs(), public._cosmo_border_defs(), public._cosmo_list(uuid, text, text, jsonb)
  from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- drop old 2-arg equip so 4-arg replaces cleanly for PostgREST
drop function if exists public.cosmetics_equip(text, text);$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_equip(p_title text, p_frame text, p_board text default null, p_border text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cur jsonb; t text; f text; b text; d text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  cur := _cosmo_equip_get(uid);
  t := coalesce(p_title, cur->>'title'); f := coalesce(p_frame, cur->>'frame');
  b := coalesce(nullif(p_board, ''), cur->>'board'); d := coalesce(nullif(p_border, ''), cur->>'border');
  if not _cosmo_owned(uid, 'title', t) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'frame', f) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'board', b) then raise exception 'not owned'; end if;
  if not _cosmo_owned(uid, 'border', d) then raise exception 'not owned'; end if;
  update profiles set cosmo_title = t, cosmo_frame = f, cosmo_board = b, cosmo_border = d, updated_at = now() where id = uid;
  return _cosmo_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_buy(p_kind text, p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; price int; ok boolean; defs jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind = 'frame' then defs := _cosmo_frame_defs();
  elsif p_kind = 'board' then defs := _cosmo_board_defs();
  elsif p_kind = 'border' then defs := _cosmo_border_defs();
  else raise exception 'invalid'; end if;
  select x into d from jsonb_array_elements(defs) x where x->>'id' = p_id;
  if d is null then raise exception 'invalid'; end if;
  if d->'shop' is null or jsonb_typeof(d->'shop') = 'null' then raise exception 'not for sale'; end if;
  price := (d->>'shop')::int;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  if _cosmo_owned(uid, p_kind, p_id) then raise exception 'already owned'; end if;
  perform _gem_spend(uid, price, 'cosmo_buy', jsonb_build_object('kind', p_kind, 'id', p_id));
  insert into cosmetic_purchases (user_id, kind, id) values (uid, p_kind, p_id) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already owned'; end if;
  return _cosmo_json(uid) || jsonb_build_object('bought', p_id, 'kind', p_kind, 'price', price);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('cosmo:' || uid::text));
  insert into profiles (id) values (uid) on conflict do nothing;
  return _cosmo_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.cosmetics_lookup(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_object_agg(id::text, jsonb_build_object(
      'title', coalesce(cosmo_title, 'recruit'),
      'frame', coalesce(cosmo_frame, 'frame_basic'),
      'board', coalesce(cosmo_board, 'board_basic'),
      'border', coalesce(cosmo_border, 'border_basic'),
      'title_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_title_defs()) d where d->>'id' = coalesce(p.cosmo_title, 'recruit')), ''),
      'frame_name', coalesce((select d->>'name' from jsonb_array_elements(_cosmo_frame_defs()) d where d->>'id' = coalesce(p.cosmo_frame, 'frame_basic')), '')))
    from profiles p where p.id = any(coalesce(p_ids, '{}'::uuid[]))), '{}'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.cosmetics_status(), public.cosmetics_equip(text, text, text, text), public.cosmetics_buy(text, text), public.cosmetics_lookup(uuid[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.cosmetics_status(), public.cosmetics_equip(text, text, text, text), public.cosmetics_buy(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.cosmetics_lookup(uuid[]) to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: batch_ui_bugs.sql =====
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.idle_box_boost() from public, anon;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (9, '2e51781f300b93c84298e678ab1ea699a95d4d5bc29d23bc3cc785cdcfebdd30', '8f1352ee2993a2d373c74b4677c6d99b3f6ffa5e7004f3c228ea3502230c96b9', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '09_install.sql: 완료 또는 이미 완료 (9/14)' as result;
