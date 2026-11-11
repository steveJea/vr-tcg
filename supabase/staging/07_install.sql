-- ⚠ 테스트 전용 7/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '33b887dc47cd39a541ec7e8b546346416cbaf9d2aa104e996a2cda9c476b2e2f' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 7) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 7 and part_hash = '768c24c4cee8a3b3eef3a22d9c2c25ce20fb8b4efd3c697620862aa1c8fc36e7') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '07_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 7) <> 6 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (07_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- ===== SOURCE: story_stars.sql =====
-- 스토리 별점(★1~3, 마나 전투) — 페이즈별 최고 별 저장. 여러 번 실행해도 안전 (함수만, 데이터 삭제 없음)
-- 저장 위치: story_progress.data.stars = { "<챕터>": { "<페이즈>": 1~3 } } · 이미 클리어한 페이즈만, 더 높을 때만 갱신
-- 별 계산은 클라이언트(보상 없음): ★1 클리어 · +★ 내 턴 10턴 이내 · +★ 남은 마나 30% 이상
create or replace function public.story_set_stars(p_chapter int, p_phase int, p_stars int) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; cur int; s int := greatest(1, least(3, coalesce(p_stars, 1)));
begin
  if me is null then raise exception 'login required'; end if;
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(me);
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  cur := coalesce((d->'stars'->(p_chapter::text)->>(p_phase::text))::int, 0);
  if s > cur then
    if jsonb_typeof(d->'stars') is distinct from 'object' then d := jsonb_set(d, '{stars}', '{}'::jsonb); end if;
    if jsonb_typeof(d->'stars'->(p_chapter::text)) is distinct from 'object' then d := jsonb_set(d, array['stars', p_chapter::text], '{}'::jsonb); end if;
    d := jsonb_set(d, array['stars', p_chapter::text, p_phase::text], to_jsonb(s));
    d := _story_save(me, d); cur := s;
  end if;
  return jsonb_build_object('ok', true, 'stars', cur, 'all', coalesce(d->'stars', '{}'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_set_stars(int, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_set_stars(int, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$select 'story_stars ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: blood_rebalance.sql =====
-- =====================================================================
-- 피 리밸런스 (1/2): 카드 레벨업 비용 50% 감소 + LEGENDARY RARE 계수 추가
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (함수 재정의만)
-- 선행: phaseE_4.sql (phaseE_3.sql / phaseE_4.sql 은 다시 돌리지 마세요 - 예전 비용으로 돌아감)
--
-- 레벨업 L → L+1:  순수한 피 = ceil(b × L × 0.5),  골드 = ceil(g × L × 10 × 0.5)   (올림이라 최소 1)
--   N b2 g1 · R b3 g1.5 · HR b5 g2 · SR b8 g3 · UR b12 g4 · MR b18 g6 · LR b27 g9 (LR 은 새로 추가, 클라와 맞춤)
--   배율은 _lv_cost_mult() 한 곳. 클라 js/story.js 의 LV_MULT 도 같이 바꿔야 해요
-- 분해 환급(쓴 피 50%)은 카드의 bloodSpent 기준이라 자동으로 새 비용 기준이 됨
-- 기존 유저 차액 환급은 blood_rebalance_refund.sql (따로, 1회)
-- 확인용: select public.card_cost_table();   → version 5, grades.SUPER RARE.lv1 = {"blood":4,"gold":15}
-- =====================================================================

create or replace function public._lv_cost_mult() returns numeric language sql immutable as $$ select 0.5::numeric $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lv_cost_b(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 2 when 'RARE' then 3 when 'HIGH RARE' then 5 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 12 when 'MYTHIC RARE' then 18 when 'LEGENDARY RARE' then 27 else 2 end::numeric $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lv_cost_g(p_grade text) returns numeric language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 1.5 when 'HIGH RARE' then 2 when 'SUPER RARE' then 3 when 'ULTRA RARE' then 4 when 'MYTHIC RARE' then 6 when 'LEGENDARY RARE' then 9 else 1 end::numeric $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lv_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'blood', greatest(1, ceil(_lv_cost_b(p_grade) * p_level * _lv_cost_mult()))::int,
    'gold',  greatest(1, ceil(_lv_cost_g(p_grade) * p_level * 10 * _lv_cost_mult()))::int) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._lv_cost_mult() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.card_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 5, 'mult', _lv_cost_mult(),
    'grades', jsonb_object_agg(g, jsonb_build_object('b', _lv_cost_b(g), 'g', _lv_cost_g(g), 'shard', _merge_shard_base(g), 'lv1', _lv_cost(g, 1))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE']) g
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public.card_cost_table() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.card_cost_table() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_level_gate.sql =====
-- 스토리 챕터 입장 레벨 제한 (계정 레벨 player_state.level) — 선행: phaseE_2.sql (+ 이후 파일들)
-- ⚠ 이 파일 실행 뒤에는 phaseE_2.sql 을 다시 돌리지 마세요 (_player_unlock_level · _player_json · story_start_phase 가 옛 버전으로 돌아가 제한이 사라짐)
-- 여러 번 실행해도 안전 (함수만, 데이터 변경 없음)
-- 설정은 _player_unlock_level('chapter_N') 한 곳. 클라이언트는 _player_json 의 unlocks.chapters 로 받음
-- 규칙: 그 챕터를 아직 한 페이즈도 클리어하지 않은 경우에만 막음 → 이미 시작한 챕터는 레벨과 상관없이 계속·다시 하기 가능
--       소탕은 클리어한 페이즈만 가능하므로 자연히 영향 없음 (변경 없음)

-- 1) 해금 레벨 (기존 키 그대로 + chapter_2 ~ chapter_11)
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24 when 'chapter_15' then 25
    else null end $$;$vr_statement$;
  execute $vr_statement$-- 2) 플레이어 정보: unlocks.chapters = { "2": 7, "3": 9, ... } 추가 (나머지는 phaseE_2 와 동일)
create or replace function public._player_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; secs int := _stamina_regen_secs(); chs jsonb;
begin
  ps := _player_sync(p_uid); mx := _stamina_max(ps.level);
  select coalesce(jsonb_object_agg(c::text, _player_unlock_level('chapter_' || c)), '{}'::jsonb) into chs
    from generate_series(0, 30) c where _player_unlock_level('chapter_' || c) is not null;
  return jsonb_build_object('ok', true, 'level', ps.level, 'max_level', _player_max_level(), 'xp', ps.xp,
    'xp_next', case when ps.level >= _player_max_level() then 0 else _player_xp_need(ps.level) end,
    'stamina', ps.stamina, 'stamina_max', mx, 'regen_secs', secs,
    'next_regen_secs', case when ps.stamina >= mx then 0 else greatest(0, secs - floor(extract(epoch from (now() - ps.stamina_at)))::int) end,
    'cost', jsonb_build_object('story', _stamina_cost(0, 0), 'quest', 0, 'arcade', 0),
    'unlocks', jsonb_build_object('sweep', _player_unlock_level('sweep'), 'skill', _player_unlock_level('skill'), 'equip', _player_unlock_level('equip'), 'equip_merge', _player_unlock_level('equip_merge'), 'chapters', chs));
end $$;$vr_statement$;
  execute $vr_statement$-- 3) 전투 시작: 레벨 제한 검사 추가 (나머지는 phaseE_2 wrapper 와 동일 — 'phaseE_2 wrapper' 표시 유지해서 phaseE_2 의 보관 로직이 원본으로 착각하지 않게)
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper (+ story_level_gate)
declare uid uuid := auth.uid(); b jsonb; d jsonb; cost int := _stamina_cost(p_chapter, p_phase); need int := _player_unlock_level('chapter_' || p_chapter); lv int; started boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _player_sync(uid);
  select data->'battle' into b from story_progress where user_id = uid for update;
  if need is not null then
    select coalesce(jsonb_array_length(data->'cleared'->(p_chapter::text)), 0) > 0 into started from story_progress where user_id = uid;
    if not coalesce(started, false) then
      select level into lv from player_state where user_id = uid;
      if coalesce(lv, 1) < need then raise exception 'level required: chapter % needs level %', p_chapter, need; end if;
    end if;
  end if;
  if b is not null and (b->>'stamina') is not null then perform _player_stamina_add(uid, (b->>'stamina')::int); end if;
  perform _player_stamina_add(uid, -cost);   -- 부족하면 'not enough stamina' (전체 롤백)
  d := _story_start_phase_e0(p_chapter, p_phase);
  d := jsonb_set(d, '{battle,stamina}', to_jsonb(cost));
  update story_progress set data = d where user_id = uid;
  return d;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._player_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_start_phase(int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_start_phase(int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: lr_grade_align.sql =====
-- =====================================================================
-- LEGENDARY RARE(LR) 서버 등급표를 클라(js/story.js)와 맞춤
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (함수 재정의만, LR 줄만 추가 / 다른 등급 숫자는 그대로)
-- 선행: story_merge.sql, story_levels.sql, phaseE_3.sql, phaseE_4.sql, phaseE_6.sql, blood_rebalance.sql
-- ⚠ 이 파일 이후 위 예전 파일들을 다시 돌리면 LR 이 빠져요 (README 표 참고)
--
--   _story_cap        최대 레벨  LR 100 (+5/EX)   ← 기존엔 else 20
--   _story_max_ex     최대 EX    LR 7
--   _story_feed_exp   먹이 EXP   LR 12000
--   _dismantle_yield  분해       LR 골드 5000 · 피 3000 · 혼 200
--   _merge_shard_base EX 조각    LR 60
--   _skill_soul_base  스킬 혼    LR 18
--   (레벨업 피·골드 LR 27·9 는 blood_rebalance.sql 에 이미 있음)
-- 확인용: select public._story_cap('LEGENDARY RARE', 0);  → 100   (SQL Editor 에서)
-- =====================================================================

create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 when 'LEGENDARY RARE' then 100 else 20 end) + 5 * greatest(0, coalesce(ex, 0))
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_max_ex(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 4 when 'ULTRA RARE' then 5 when 'MYTHIC RARE' then 6 when 'LEGENDARY RARE' then 7 else 1 end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_feed_exp(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 50 when 'RARE' then 150 when 'HIGH RARE' then 400 when 'SUPER RARE' then 1000 when 'ULTRA RARE' then 3000 when 'MYTHIC RARE' then 6000 when 'LEGENDARY RARE' then 12000 else 50 end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._dismantle_yield(p_grade text) returns jsonb language sql immutable as $$
  select case p_grade
    when 'NORMAL'         then '{"gold":20,"blood":10,"soul":0}'
    when 'RARE'           then '{"gold":50,"blood":30,"soul":1}'
    when 'HIGH RARE'      then '{"gold":120,"blood":80,"soul":3}'
    when 'SUPER RARE'     then '{"gold":300,"blood":200,"soul":10}'
    when 'ULTRA RARE'     then '{"gold":800,"blood":500,"soul":30}'
    when 'MYTHIC RARE'    then '{"gold":2000,"blood":1200,"soul":80}'
    when 'LEGENDARY RARE' then '{"gold":5000,"blood":3000,"soul":200}'
    else '{"gold":20,"blood":10,"soul":0}' end::jsonb
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._merge_shard_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 4 when 'SUPER RARE' then 8 when 'ULTRA RARE' then 15 when 'MYTHIC RARE' then 30 when 'LEGENDARY RARE' then 60 else 1 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._skill_soul_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 5 when 'ULTRA RARE' then 8 when 'MYTHIC RARE' then 12 when 'LEGENDARY RARE' then 18 else 1 end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_cap(text, int), public._story_max_ex(text), public._story_feed_exp(text), public._dismantle_yield(text),
  public._merge_shard_base(text), public._skill_soul_base(text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch0_jieun.sql =====
-- =====================================================================
-- 챕터 0 클리어 강제 10회 영입(임유리 튜토리얼)에서 하지은(10439) 확정 — 계정당 한 번
-- 조건: 10회 뽑기 · 강제 영입이 아직 안 끝남(save.ch0Pull 없음) · 확정 받은 적 없음(save.ch0Jieun 없음)
-- 10장 중 무작위 한 자리를 하지은으로, 나머지 9장은 기존과 같이 무작위. 그 외 동작은 story_gacha.sql 과 동일
-- 여러 번 실행해도 안전 (story_ticket_draw 만 교체)
-- =====================================================================
create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
  jslot int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_count = 10 and coalesce((d->>'ch0Pull')::boolean, false) = false and coalesce((d->>'ch0Jieun')::boolean, false) = false then
    jslot := 1 + floor(random() * 10)::int;   -- 강제 영입: 하지은 자리
    d := jsonb_set(d, '{ch0Jieun}', 'true'::jsonb);
  end if;
  for i in 1..p_count loop
    if i = jslot then
      cid := '10439'; g := 'SUPER RARE';
    else
      r := random();
      if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
        r := 0.80 + random() * 0.20;
      end if;
      g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
      cid := null;
      select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
      if cid is null then raise exception 'empty pool for %', g; end if;
    end if;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    e := _story_new_card(cid);
    owned := owned || jsonb_build_array(e);
    out := out || jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', g));
    insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, g, 'ticket');
  end loop;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  update story_gacha set tickets = tickets - p_count, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', out, 'tickets', t - p_count, 'added', (s->>'added')::int);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_ticket_draw(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_ticket_draw(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: pvp_boss_league.sql =====
-- =====================================================================
-- PvP 보스리그 (mode = 'boss'). pvp.sql · pvp_tier.sql · gem.sql 다음에 실행. 여러 번 실행해도 안전.
--   기존 PvP 구조 그대로 (pvp_set_deck / pvp_status / pvp_start / pvp_report / pvp_rankings / pvp_claim_reward / 티어·연승)
--   p_mode = 'boss' 로 부르면 레이팅·랭킹·하루 10회·시즌 보상이 1v1·3v3 과 따로.
--   덱 1~5장, 첫 장 = 수비대장 (HR 이하, 서버 트리거로 검사). 승패 = 상대 진영 HP 0 (클라이언트 pvp-core.js boss 모드)
--   기존 pvp 데이터(덱·레이팅·기록·보상)는 건드리지 않음. 바뀌는 것: pvp_decks 의 mode 체크 · _pvp_ok · 트리거 · 보상표 행 추가
-- =====================================================================

-- 1) pvp_decks.mode 에 'boss' 허용 (mode 체크 제약만 다시 만듦)
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.pvp_decks'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%mode%' loop
    execute format('alter table public.pvp_decks drop constraint %I', c);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$alter table public.pvp_decks add constraint pvp_decks_mode_check check (mode in ('1v1','3v3','boss'));$vr_statement$;
  execute $vr_statement$-- 2) 모드 확인: boss = 덱 1개 (1판)
create or replace function public._pvp_ok(p_league text, p_mode text) returns int language plpgsql immutable as $$
begin
  if p_league not in ('open','hr') then raise exception 'bad league'; end if;
  if p_mode = '1v1' then return 1; elsif p_mode = '3v3' then return 3; elsif p_mode = 'boss' then return 1; end if;
  raise exception 'bad mode';
end $$;$vr_statement$;
  execute $vr_statement$-- 3) 보스리그 덱: 첫 장(수비대장)은 HR 이하
create or replace function public._pvp_boss_deck_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare g text;
begin
  if new.mode <> 'boss' then return new; end if;
  select grade into g from pvp_card_meta where id = new.snap->0->>'id';
  if g is null or g not in ('NORMAL','RARE','HIGH RARE') then raise exception 'guard grade'; end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_boss_deck_chk() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists pvp_boss_deck_chk on public.pvp_decks;$vr_statement$;
  execute $vr_statement$create trigger pvp_boss_deck_chk before insert or update on public.pvp_decks for each row execute function public._pvp_boss_deck_chk();$vr_statement$;
  execute $vr_statement$-- 4) 시즌 순위 보상 (1v1 과 같은 값)
insert into public.pvp_reward_table (league, mode, rank_from, rank_to, reward)
select l, 'boss', f, t, r::jsonb from (values ('open'), ('hr')) a(l),
  (values (1, 1, '{"gold":3000,"soul":50,"tickets":50}'), (2, 3, '{"gold":2000,"soul":30,"tickets":30}'), (4, 10, '{"gold":1200,"soul":15,"tickets":20}'),
          (11, 50, '{"gold":600,"shard":20,"tickets":10}'), (51, 100, '{"gold":300,"shard":10,"tickets":10}'), (101, 1000000, '{"gold":100,"tickets":5}')) c(f, t, r)
on conflict (league, mode, rank_from) do update set rank_to = excluded.rank_to, reward = excluded.reward;$vr_statement$;
  execute $vr_statement$-- 확인: select public.pvp_rankings('open','boss');   → {"season":..., "top":[], "me":null}


-- ===== SOURCE: story_ch0_p5.sql =====
-- 챕터 0 Phase 5 (보스전 튜토리얼 「수비대장이라고?」) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (추가·갱신만, 삭제 없음)
-- 보스 안지수(10229) + 부하 4명 (주예나·동지선·남태은·류하예) · 첫 클리어 보상 주예린(10392)
-- 서버 순서 규칙(_story_start_phase_e0): P5 는 P1~P4 를 모두 깬 뒤에만 시작 가능 → P4 를 안 깬 사용자는 P4 부터
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values (0,5,'boss',3,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$update public.story_phase_config set reward_card = '10392' where chapter = 0 and phase = 5;$vr_statement$;
  execute $vr_statement$-- 확인 (5줄, 마지막 줄 = 5 | boss | 5 | 10392)
select chapter, phase, type, enemy_count, reward_card from public.story_phase_config where chapter = 0 order by phase;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch8_boss_one.sql =====
-- 챕8 P15 보스전: [염원] 안지윤 1명만 등장 → enemy_count 5 → 1 (전투 EXP 처치 수 상한). 여러 번 실행해도 안전.
update public.story_phase_config set enemy_count = 1 where chapter = 8 and phase = 15 and enemy_count is distinct from 1;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, phase, type, enemy_count from public.story_phase_config where chapter = 8 and phase = 15;  → 8 | 15 | boss | 1


-- ===== SOURCE: story_block_exp.sql =====
-- 막기 전투 EXP: 카드 EXP = (60 + 20×처치 + 10×min(막기,3)) × (보스 2), 막기 합계 상한 = enemy_count × 2
-- _story_complete_phase_e0 를 story_ch1_reward.sql 최신 버전 기준으로 다시 정의 (그 외 동작 동일). blocks 없으면 0. 여러 번 실행해도 안전.
do $$ begin
  if to_regprocedure('public._story_complete_phase_e0(int,int,jsonb)') is null then raise exception 'phaseE_2.sql 을 먼저 적용하세요'; end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_complete_phase_e0(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; ruid text; owned jsonb; ne jsonb;
        st jsonb; idx int; k int; ksum int := 0; bk int; bsum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen int[] := '{}'; key text;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  owned := _story_owned(d);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_card is not null then
      -- 페이즈 고정 보상 카드: 이미 보유해도 한 장 더 (중복 지급)
      rid := cfg.reward_card; ne := _story_new_card(rid); ruid := ne->>'uid'; owned := owned || jsonb_build_array(ne);
    elsif cfg.reward_grade is not null then
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and p.gacha and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then ne := _story_new_card(rid); ruid := ne->>'uid'; owned := owned || jsonb_build_array(ne); end if;
    end if;
  end if;
  if jsonb_typeof(p_stats) = 'array' and jsonb_array_length(p_stats) <= 30 then
    for st in select * from jsonb_array_elements(p_stats) loop
      continue when jsonb_typeof(st) <> 'object';
      key := coalesce(st->>'uid', st->>'id');
      continue when key is null or key = ruid or (key = rid and st->>'uid' is null);
      idx := _story_find(owned, key);
      continue when idx is null or idx = any(seen) or (owned->idx->>'uid') = ruid;
      seen := seen || idx;
      k := least(greatest(0, coalesce((st->>'kills')::int, 0)), greatest(0, cfg.enemy_count - ksum));
      ksum := ksum + k;
      bk := least(greatest(0, coalesce((st->>'blocks')::int, 0)), 3, greatest(0, cfg.enemy_count * 2 - bsum));   -- 막기: 카드당 3, 합계 적 수×2 (예전 클라이언트는 0)
      bsum := bsum + bk;
      gain := (60 + 20 * k + 10 * bk) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = owned->idx->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('uid', owned->idx->>'uid', 'id', owned->idx->>'id', 'kills', k, 'blocks', bk, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
  end if;
  d := jsonb_set(d, '{owned}', owned);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'reward_uid', ruid, 'exp', res);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_complete_phase_e0(int, int, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: war_auto.sql =====
-- 구역 전쟁 자동 참가·자동 배치 (2026-11-03). guild4.sql · guild4_ui.sql · war_manual.sql 뒤에 실행. 여러 번 실행해도 안전 (create or replace 만, 표·데이터 삭제 없음)
-- 1) 조직 레벨 3 이상이면 시즌마다 자동 참가 (조직 참가 버튼 없음) · 최소 인원 없음 (빈 칸은 동네 불량배 NPC, _war_build_side 그대로)
-- 2) 개인 신청 없음: 조직원 전원 자동 배치 (보스가 안 넣은 사람은 잠금 때 전투력 순으로 빈 칸)
-- 3) 아지트(14번)는 보스가 언제든 바꿀 수 있음 (시즌 중 전투 시간 09~23시 제외). 나머지 칸은 시즌 잠금(첫날 09시) 전까지
-- 4) war_auto_assign: 보스용 전투력 순 자동 배치 14 → 1~5 → 6~10 → 11~13 → 15~21
-- 5) 전쟁 덱이 없는 조직원: 전투력 상위 5장으로 자동 편성 (배치·잠금 때). war_meta.need_deck 으로 화면에 빨간 점
-- ※ 서버에는 클라이언트 '전투력' 값이 없어서 등급·레벨·한계돌파로 근사 (_war_card_score)

create or replace function public._war_min_level() returns int language sql immutable as $$ select 3 $$;$vr_statement$;
  execute $vr_statement$-- 카드 점수 (전투력 근사): 등급 가중 × 1000 + 레벨 × 20 + 한계돌파 × 50
create or replace function public._war_card_score(p_id text, p_level int, p_ex int) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select case m.grade when 'LEGENDARY RARE' then 7 when 'MYTHIC RARE' then 6 when 'ULTRA RARE' then 5 when 'SUPER RARE' then 4 when 'HIGH RARE' then 3 when 'RARE' then 2 else 1 end
                   from pvp_card_meta m where m.id = p_id), 0) * 1000 + coalesce(p_level, 1) * 20 + coalesce(p_ex, 0) * 50 $$;$vr_statement$;
  execute $vr_statement$-- 보유 카드 중 점수 상위 5장 uid (같은 인재는 1장)
create or replace function public._war_top5(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(uid order by sc desc), '[]'::jsonb) from (
    select uid, sc from (
      select x->>'uid' uid, x->>'id' id, _war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int) sc,
             row_number() over (partition by x->>'id' order by _war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int) desc) rn
      from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
      where sp.user_id = p_user and coalesce(x->>'uid', '') <> '' and x->>'uid' not like 'guest:%' and exists (select 1 from pvp_card_meta m where m.id = x->>'id')) t
    where rn = 1 order by sc desc limit 5) q $$;$vr_statement$;
  execute $vr_statement$-- 조직원 전투력 (상위 5장 합)
create or replace function public._war_power(p_user uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(_war_card_score(x->>'id', (x->>'level')::int, (x->>'ex')::int)), 0) from story_progress sp,
    jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
  where sp.user_id = p_user and x->>'uid' in (select jsonb_array_elements_text(_war_top5(p_user))) $$;$vr_statement$;
  execute $vr_statement$-- 전쟁 덱 없으면 상위 5장으로 자동 편성 (방어 1 · 공격 1 중 빈 것만). 실패해도 조용히 넘어감
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
end $$;$vr_statement$;
  execute $vr_statement$-- 자동 참가: 레벨 3 이상 조직 (잠금 전 시즌)
create or replace function public._war_auto_enter(p_season date) returns void language sql security definer set search_path = public as $$
  insert into war_entries (season, guild_id) select p_season, g.id from guilds g where g.level >= _war_min_level() on conflict do nothing $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_tick() returns date language plpgsql security definer set search_path = public as $$
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
end $$;$vr_statement$;
  execute $vr_statement$-- 시즌 잠금: 안 넣은 조직원 → 빈 칸 (전투력 순) · 덱 없으면 자동 편성 · 최소 인원 없음 (항상 'in')
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
end $$;$vr_statement$;
  execute $vr_statement$-- 배치 (보스): 잠금 전 = 모든 칸 · 잠금 뒤 = 14번(아지트)만, 시즌 중 전투 시간(live) 제외. 잠금 뒤 바꾼 아지트는 다음 날 경기부터
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
end $$;$vr_statement$;
  execute $vr_statement$-- 자동 배치 (보스, 잠금 전): 전투력 순 14 → 1~5 → 6~10 → 11~13 → 15~21. 기존 배치는 다시 짬
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
end $$;$vr_statement$;
  execute $vr_statement$-- 화면 보조: 조직 레벨 · 자동 참가 레벨 · 내 전쟁 덱 비었는지 (빨간 점)
create or replace function public.war_meta() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _guild_me(uid);
  return jsonb_build_object('ok', true, 'min_level', _war_min_level(),
    'guild_level', (select level from guilds where id = m.guild_id),
    'need_deck', m.user_id is not null and not exists (select 1 from war_decks d where d.user_id = uid and d.def1 is not null and d.atk1 is not null));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._war_min_level(), public._war_card_score(text, int, int), public._war_top5(uuid), public._war_power(uuid), public._war_auto_deck(uuid),
  public._war_auto_enter(date), public._war_tick(), public._war_lock(date) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_set_slot(int, uuid), public.war_auto_assign(), public.war_meta() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_set_slot(int, uuid), public.war_auto_assign(), public.war_meta() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_buynow_search.sql =====
-- ===== 거래소 5단계: 즉시 구매(고정가) + 서버 검색(trade_search) =====
-- 선행: trade_board.sql · trade_admin.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 함수 추가/교체만)
-- 1) 판매 글에 '즉시 구매가'(선택): 드링크 또는 골드 중 하나. 등급별 가격 범위(trade_band)·골드 규칙은 제안과 똑같이 검사
-- 2) trade_buy: 그 가격 그대로 바로 구매 → 내부적으로 '재화 제안 + 판매자 수락'을 한 번에 (수수료 10% 소각·하루 한도·같은 상대 한도·드링크 이동 한도 그대로)
--    동시 구매: 글 행을 먼저 잠그고(for update) 관련 유저를 uuid 순서로 잠금 → 먼저 온 한 명만 성공, 나머지는 '이미 끝난 글'
--    만료: 만료 시각이 지났으면 그 자리에서 만료 처리(보관물 환불) 후 실패 응답. 가격이 화면과 다르면 'price changed'
-- 3) trade_search: 게시판 전체에서 이름(인재는 화면이 이름→id 로 바꿔서 전달, 장비는 이름 일부)·종류·등급·즉시 구매만·정렬·페이지
-- 4) 시세(6단계)용: 거래 기록(trade_log)에 즉시 구매 여부(buy_now)와 시간 색인 추가. 판매가는 이미 buyer_gave(드링크·골드)에 기록됨

-- 1) 열 추가 --------------------------------------------------------------------------
alter table public.trade_listings add column if not exists buy_drinks int check (buy_drinks is null or buy_drinks > 0);$vr_statement$;
  execute $vr_statement$alter table public.trade_listings add column if not exists buy_gold bigint check (buy_gold is null or buy_gold > 0);$vr_statement$;
  execute $vr_statement$do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'trade_listings_buy_one') then
    alter table public.trade_listings add constraint trade_listings_buy_one check (buy_drinks is null or buy_gold is null);
  end if;
end $$;$vr_statement$;
  execute $vr_statement$alter table public.trade_log add column if not exists buy_now boolean not null default false;$vr_statement$;
  execute $vr_statement$create index if not exists trade_log_time on public.trade_log (created_at desc);$vr_statement$;
  execute $vr_statement$create index if not exists trade_listings_open_id on public.trade_listings (id desc) where status = 'open';$vr_statement$;
  execute $vr_statement$-- 2) 수락 본체 (판매자 지정). trade_accept 는 이걸 부르는 얇은 껍데기로 교체 (동작 같음)
create or replace function public._trade_accept_core(p_listing bigint, p_offer bigint, p_seller uuid, p_buy_now boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := p_seller; l trade_listings; o trade_offers; pct int := _trade_cfg('fee_pct'); fd int := 0; fg bigint := 0; sfee bigint := 0;
        it jsonb; m1 int; m2 int; sig jsonb := '[]'::jsonb; s jsonb; oid bigint; n int := 0; day_start timestamptz := ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul');
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.seller <> uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  if l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  select * into o from trade_offers where id = p_offer and listing_id = l.id;
  if o.id is null then raise exception 'offer not found'; end if;
  perform _trade_lock_users(array[uid] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));
  select * into o from trade_offers where id = p_offer for update;
  if o.status <> 'pending' then raise exception 'offer closed'; end if;
  -- 하루 한도 · 같은 상대 반복
  if (select count(*) from trade_log where (seller = uid or buyer = uid) and created_at >= day_start) >= _trade_cfg('daily_trades')
     or (select count(*) from trade_log where (seller = o.offerer or buyer = o.offerer) and created_at >= day_start) >= _trade_cfg('daily_trades') then raise exception 'daily trade limit'; end if;
  if (select count(*) from trade_log where ((seller = uid and buyer = o.offerer) or (seller = o.offerer and buyer = uid)) and created_at > now() - interval '7 days') >= _trade_cfg('same_partner_7d') then raise exception 'same partner limit'; end if;
  -- 물건끼리만: 판매자도 받는 물건 등급별 고정 골드
  if o.drinks = 0 and o.gold = 0 then
    select coalesce(sum(b.fix_fee), 0) into sfee from jsonb_array_elements(o.cards || o.gear) x join trade_band b on b.gkey = x->>'gkey';
    if sfee > 0 then perform _wallet_add(uid, jsonb_build_object('gold', -sfee), 'trade_fee'); end if;
  end if;
  update trade_offers set status = 'accepted', closed_at = now() where id = o.id;
  update trade_listings set status = 'done', closed_at = now(), offer_id = o.id where id = l.id;
  -- 물건 교환
  perform _trade_give_cards(o.offerer, l.cards, true);
  perform _trade_give_cards(uid, o.cards, true);
  m1 := _trade_give_gear(o.offerer, l.gear, true);
  m2 := _trade_give_gear(uid, o.gear, true);
  for it in select x from jsonb_array_elements(l.cards) x loop
    s := _trade_sigil_move(uid, o.offerer, it->'card'->>'id'); if s is not null then sig := sig || jsonb_build_array(s || jsonb_build_object('to', 'buyer')); end if;
  end loop;
  for it in select x from jsonb_array_elements(o.cards) x loop
    s := _trade_sigil_move(o.offerer, uid, it->'card'->>'id'); if s is not null then sig := sig || jsonb_build_array(s || jsonb_build_object('to', 'seller')); end if;
  end loop;
  -- 재화: 판매자에게 (10% 올림 소각)
  if o.drinks > 0 then fd := ceil(o.drinks * pct / 100.0)::int; perform _item_add(uid, 'drink', o.drinks - fd, 0, 'trade_recv', null, jsonb_build_object('offer', o.id, 'fee', fd)); end if;
  if o.gold > 0 then fg := ceil(o.gold * pct / 100.0)::bigint; perform _wallet_add(uid, jsonb_build_object('gold', o.gold - fg), 'trade_recv'); end if;
  insert into trade_log (listing_id, offer_id, seller, buyer, seller_gave, buyer_gave, fees)
  values (l.id, o.id, uid, o.offerer, jsonb_build_object('cards', l.cards, 'gear', l.gear),
          jsonb_build_object('cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold),
          jsonb_build_object('drinks', fd, 'gold', fg, 'fix_buyer', o.fee_gold, 'fix_seller', sfee, 'mailed', m1 + m2, 'sigils', sig));
  if p_buy_now then update trade_log set buy_now = true where offer_id = o.id; end if;
  -- 나머지 제안 환불
  for oid in select id from trade_offers where listing_id = l.id and status = 'pending' order by id loop
    if _trade_refund_offer(oid, 'refunded') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'buy_now', p_buy_now, 'mailed_buyer', m1, 'drinks', o.drinks - fd, 'gold', o.gold - fg, 'fee_drinks', fd, 'fee_gold', fg + sfee, 'refunded', n, 'mailed', m2, 'sigils', sig);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_accept(p_listing bigint, p_offer bigint) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _trade_accept_core(p_listing, p_offer, auth.uid(), false);
end $$;$vr_statement$;
  execute $vr_statement$-- 3) 즉시 구매가와 함께 올리기 (가격 없이 부르면 기존 trade_list 와 같음)
create or replace function public.trade_list2(p_cards text[], p_gear bigint[], p_want text default '', p_buy_drinks int default null, p_buy_gold bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; l trade_listings;
begin
  p_buy_drinks := nullif(coalesce(p_buy_drinks, 0), 0); p_buy_gold := nullif(coalesce(p_buy_gold, 0), 0);
  if p_buy_drinks < 0 or p_buy_gold < 0 then raise exception 'invalid amount'; end if;
  if p_buy_drinks is not null and p_buy_gold is not null then raise exception 'buy one currency'; end if;
  r := trade_list(p_cards, p_gear, p_want);
  if p_buy_drinks is not null or p_buy_gold is not null then
    select * into l from trade_listings where id = (r->>'listing_id')::bigint for update;
    perform _trade_check_price(l.cards || l.gear, '[]'::jsonb, coalesce(p_buy_drinks, 0), coalesce(p_buy_gold, 0));   -- 범위 밖이면 전체 취소(보관도 되돌림)
    update trade_listings set buy_drinks = p_buy_drinks, buy_gold = p_buy_gold where id = l.id;
  end if;
  return r || jsonb_build_object('buy_drinks', p_buy_drinks, 'buy_gold', p_buy_gold);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 즉시 구매
create or replace function public.trade_buy(p_listing bigint, p_drinks int default 0, p_gold bigint default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; r jsonb;
begin
  perform _trade_gate(uid);
  select * into l from trade_listings where id = p_listing for update;   -- 동시 구매·수락·내리기와 줄 세움
  if l.id is null then raise exception 'listing not found'; end if;
  if l.status = 'open' and l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  if l.seller = uid then raise exception 'own listing'; end if;
  if l.buy_drinks is null and l.buy_gold is null then raise exception 'no buy price'; end if;
  if coalesce(l.buy_drinks, 0) <> coalesce(p_drinks, 0) or coalesce(l.buy_gold, 0) <> coalesce(p_gold, 0) then raise exception 'price changed'; end if;
  if exists (select 1 from trade_offers where listing_id = l.id and offerer = uid and status = 'pending') then raise exception 'already offered'; end if;
  perform _trade_lock_users(array[uid, l.seller] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));   -- 한 번에 uuid 순서로
  r := trade_offer(l.id, '{}'::text[], '{}'::bigint[], coalesce(l.buy_drinks, 0), coalesce(l.buy_gold, 0));   -- 구매자 재화 보관 (한도·범위 검사 그대로)
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  return _trade_accept_core(l.id, (r->>'offer_id')::bigint, l.seller, true);   -- 실패하면 위 보관까지 전부 되돌아감
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 게시판·검색에 즉시 구매가 포함 (게시판 응답 모양은 그대로 + buy_drinks/buy_gold)
create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_board(p_limit int default 50, p_before bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings where status = 'open' and expires_at > now() and (p_before is null or id < p_before) order by id desc limit greatest(1, least(p_limit, 100))) l));
end $$;$vr_statement$;
  execute $vr_statement$-- p_type: all|card|gear · p_gkeys: trade_band 키(card_nr, card_hr, …, gear_low …) 중 하나라도 · p_card_ids: 이름으로 찾은 인재 id (화면이 변환)
-- p_q: 장비 이름 일부 (인재 이름은 DB 에 없어서 p_card_ids 로) · p_buy_only: 즉시 구매만 · p_sort: new|end|hot|price · p_offset 페이지
create or replace function public.trade_search(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := nullif(btrim(coalesce(p_q, '')), ''); lim int := greatest(1, least(coalesce(p_limit, 30), 50)); off int := greatest(0, least(coalesce(p_offset, 0), 2000)); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if q is not null then q := '%' || replace(replace(replace(left(q, 30), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  perform trade_expire_due(10);
  with base as (
    select l.*, (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending') as n_off,
           coalesce(l.buy_drinks::numeric, l.buy_gold::numeric / 100) as price_key   -- 골드 100 = 드링크 1 로 대충 비교 (정렬용)
      from trade_listings l
     where l.status = 'open' and l.expires_at > now()
       and (coalesce(p_type, 'all') = 'all' or (p_type = 'card' and jsonb_array_length(l.cards) > 0) or (p_type = 'gear' and jsonb_array_length(l.gear) > 0))
       and (p_gkeys is null or cardinality(p_gkeys) = 0 or exists (select 1 from jsonb_array_elements(l.cards || l.gear) x where x->>'gkey' = any(p_gkeys)))
       and (not coalesce(p_buy_only, false) or l.buy_drinks is not null or l.buy_gold is not null)
       and ((q is null and (p_card_ids is null or cardinality(p_card_ids) = 0))
            or (p_card_ids is not null and cardinality(p_card_ids) > 0 and exists (select 1 from jsonb_array_elements(l.cards) x where x->'card'->>'id' = any(p_card_ids)))
            or (q is not null and exists (select 1 from jsonb_array_elements(l.gear) x join gear_defs d on d.id = (x->'row'->>'def_id') where d.name ilike q)))
  ), page as (
    select id, row_number() over (order by
              case when p_sort = 'end' then extract(epoch from expires_at) end asc nulls last,
              case when p_sort = 'hot' then n_off end desc nulls last,
              case when p_sort = 'price' then price_key end asc nulls last,
              id desc) as ord
      from base
  )
  select jsonb_build_object('ok', true, 'offset', off,
      'more', exists (select 1 from page where ord = off + lim + 1),
      'listings', coalesce((select jsonb_agg(_trade_listing_json(t, uid) order by p.ord) from page p join trade_listings t on t.id = p.id where p.ord > off and p.ord <= off + lim), '[]'::jsonb))
    into res;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 권한 ------------------------------------------------------------------------------
revoke all on function public._trade_accept_core(bigint, bigint, uuid, boolean), public._trade_listing_json(trade_listings, uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.trade_list2(text[], bigint[], text, int, bigint), public.trade_buy(bigint, int, bigint),
  public.trade_search(text, text[], text, text[], boolean, text, int, int), public.trade_accept(bigint, bigint), public.trade_board(int, bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.trade_list2(text[], bigint[], text, int, bigint), public.trade_buy(bigint, int, bigint),
  public.trade_search(text, text[], text, text[], boolean, text, int, int), public.trade_accept(bigint, bigint), public.trade_board(int, bigint) to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_price_history.sql =====
-- ===== 거래소 6단계: 공개 시세 (읽기 전용) =====
-- 선행: trade_board.sql · trade_buynow_search.sql. 여러 번 실행해도 안전. 테이블 변경 없음 (함수만 추가)
-- 기준: 완료된 거래(trade_log) 중 '물건 1개 ↔ 재화만'인 거래만 시세로 씀 (여러 개 묶음·물건끼리 교환은 1개 가격을 알 수 없어서 제외)
--       드링크 가격과 골드 가격은 따로 계산. 즉시 구매(buy_now)와 제안 수락을 둘 다 포함하고 개수를 나눠서 보여 줌
-- 공개 범위: 로그인한 모든 플레이어. 누가 사고팔았는지(닉네임·id)는 내보내지 않음

create or replace function public._trade_sales(p_days int) returns table (kind text, item_id text, gkey text, drinks bigint, gold bigint, buy_now boolean, at timestamptz)
language sql stable security definer set search_path = public as $$
  select case when jsonb_array_length(coalesce(t.seller_gave->'cards', '[]')) = 1 then 'card' else 'gear' end,
         coalesce(t.seller_gave->'cards'->0->'card'->>'id', t.seller_gave->'gear'->0->'row'->>'def_id'),
         coalesce(t.seller_gave->'cards'->0->>'gkey', t.seller_gave->'gear'->0->>'gkey'),
         coalesce((t.buyer_gave->>'drinks')::bigint, 0), coalesce((t.buyer_gave->>'gold')::bigint, 0), t.buy_now, t.created_at
    from trade_log t
   where t.created_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 90)))
     and jsonb_array_length(coalesce(t.seller_gave->'cards', '[]')) + jsonb_array_length(coalesce(t.seller_gave->'gear', '[]')) = 1
     and jsonb_array_length(coalesce(t.buyer_gave->'cards', '[]')) + jsonb_array_length(coalesce(t.buyer_gave->'gear', '[]')) = 0
     and coalesce((t.buyer_gave->>'drinks')::bigint, 0) + coalesce((t.buyer_gave->>'gold')::bigint, 0) > 0 $$;$vr_statement$;
  execute $vr_statement$-- 묶음 통계 (드링크·골드 각각 n·중앙값·최저·최고, 즉시 구매/제안 개수)
create or replace function public._trade_stats(p_kind text, p_id text, p_days int) returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select * from _trade_sales(p_days) where kind = p_kind and item_id = p_id)
  select jsonb_build_object('n', (select count(*) from s),
    'buy_now', (select count(*) from s where buy_now), 'offer', (select count(*) from s where not buy_now),
    'drink', (select case when count(*) = 0 then null else jsonb_build_object('n', count(*), 'median', round(percentile_cont(0.5) within group (order by drinks))::bigint, 'min', min(drinks), 'max', max(drinks)) end from s where drinks > 0 and gold = 0),
    'gold', (select case when count(*) = 0 then null else jsonb_build_object('n', count(*), 'median', round(percentile_cont(0.5) within group (order by gold))::bigint, 'min', min(gold), 'max', max(gold)) end from s where gold > 0 and drinks = 0)) $$;$vr_statement$;
  execute $vr_statement$-- 한 물건의 시세: p_kind = card | gear, p_id = 인재 id 또는 장비 def_id
create or replace function public.trade_price_history(p_kind text, p_id text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_kind not in ('card', 'gear') or coalesce(p_id, '') = '' then raise exception 'invalid item'; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'id', p_id,
    'd7', _trade_stats(p_kind, p_id, 7), 'd30', _trade_stats(p_kind, p_id, 30),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'drinks', drinks, 'gold', gold, 'buy_now', buy_now) order by at desc), '[]'::jsonb)
                 from (select * from _trade_sales(30) where kind = p_kind and item_id = p_id order by at desc limit 20) r),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'n', n, 'drink', md, 'gold', mg) order by d), '[]'::jsonb)
                from (select (at at time zone 'Asia/Seoul')::date d, count(*) n,
                             round(percentile_cont(0.5) within group (order by drinks) filter (where drinks > 0 and gold = 0))::bigint md,
                             round(percentile_cont(0.5) within group (order by gold) filter (where gold > 0 and drinks = 0))::bigint mg
                        from _trade_sales(30) where kind = p_kind and item_id = p_id group by 1) x));
end $$;$vr_statement$;
  execute $vr_statement$-- 시세 목록: 최근 p_days 일 많이 거래된 물건 (p_kind = all | card | gear, p_gkey 등급 키 선택)
create or replace function public.trade_price_board(p_days int default 7, p_kind text default 'all', p_gkey text default null, p_limit int default 30) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'days', greatest(1, least(coalesce(p_days, 7), 90)),
    'total', (select count(*) from _trade_sales(p_days)),
    'items', (select coalesce(jsonb_agg(x order by (x->>'n')::int desc, x->>'last_at' desc), '[]'::jsonb) from (
      select jsonb_build_object('kind', kind, 'id', item_id, 'gkey', max(gkey), 'n', count(*), 'buy_now', count(*) filter (where buy_now),
        'drink', round(percentile_cont(0.5) within group (order by drinks) filter (where drinks > 0 and gold = 0))::bigint,
        'gold', round(percentile_cont(0.5) within group (order by gold) filter (where gold > 0 and drinks = 0))::bigint,
        'last_at', max(at),
        'last', (select jsonb_build_object('drinks', s2.drinks, 'gold', s2.gold, 'buy_now', s2.buy_now) from _trade_sales(p_days) s2 where s2.kind = s.kind and s2.item_id = s.item_id order by s2.at desc limit 1)) x
      from _trade_sales(p_days) s
      where (coalesce(p_kind, 'all') = 'all' or kind = p_kind) and (p_gkey is null or gkey = p_gkey)
      group by kind, item_id
      order by count(*) desc, max(at) desc
      limit greatest(1, least(coalesce(p_limit, 30), 100))) q));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._trade_sales(int), public._trade_stats(text, text, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.trade_price_history(text, text), public.trade_price_board(int, text, text, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.trade_price_history(text, text), public.trade_price_board(int, text, text, int) to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_wanted.sql =====
-- ===== 거래소 개편 2/4: 원하는 물건 지정 (want_ids) + '내 물건을 원하는 글' 검색 =====
-- 선행: trade_board.sql · trade_admin.sql · trade_buynow_search.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 함수 추가/교체만)
-- 1) 판매 글에 원하는 물건 목록(최대 5): [{"k":"card"|"gear","id":"..."}] — 표시·검색용 (제안을 강제하지 않음, 판매자가 고름)
-- 2) trade_list3: trade_list2 + 원하는 물건. 3) 게시판·검색 응답에 want_ids 포함 (_trade_listing_json 교체, 모양 그대로 + 필드 1개)
-- 4) trade_search2: trade_search + p_want_in (내가 가진 인재 id · 장비 def id 중 하나라도 원하는 글만)

alter table public.trade_listings add column if not exists want_ids jsonb not null default '[]'::jsonb;$vr_statement$;
  execute $vr_statement$do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'trade_listings_want_ids_arr') then
    alter table public.trade_listings add constraint trade_listings_want_ids_arr check (jsonb_typeof(want_ids) = 'array' and jsonb_array_length(want_ids) <= 5);
  end if;
end $$;$vr_statement$;
  execute $vr_statement$create index if not exists trade_listings_want_ids on public.trade_listings using gin (want_ids jsonb_path_ops) where status = 'open';$vr_statement$;
  execute $vr_statement$-- 원하는 물건 검사: 배열 · 5개 이하 · k 는 card/gear · id 는 1~40자 · 중복 제거
create or replace function public._trade_want_ids(p jsonb) returns jsonb language plpgsql immutable as $$
declare res jsonb := '[]'::jsonb; e jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' then return res; end if;
  if jsonb_array_length(p) > 5 then raise exception 'too many wants'; end if;
  for e in select x from jsonb_array_elements(p) x loop
    if jsonb_typeof(e) <> 'object' or coalesce(e->>'k', '') not in ('card', 'gear') or char_length(coalesce(e->>'id', '')) not between 1 and 40 then raise exception 'invalid want'; end if;
    if not res @> jsonb_build_array(jsonb_build_object('k', e->>'k', 'id', e->>'id')) then res := res || jsonb_build_array(jsonb_build_object('k', e->>'k', 'id', e->>'id')); end if;
  end loop;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_list3(p_cards text[], p_gear bigint[], p_want text default '', p_buy_drinks int default null, p_buy_gold bigint default null, p_want_ids jsonb default '[]'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := _trade_want_ids(p_want_ids); r jsonb;
begin
  r := trade_list2(p_cards, p_gear, p_want, p_buy_drinks, p_buy_gold);
  update trade_listings set want_ids = w where id = (r->>'listing_id')::bigint and seller = auth.uid();
  return r || jsonb_build_object('want_ids', w);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'want_ids', l.want_ids, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_search2(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0, p_want_in text[] default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := nullif(btrim(coalesce(p_q, '')), ''); lim int := greatest(1, least(coalesce(p_limit, 30), 50)); off int := greatest(0, least(coalesce(p_offset, 0), 2000)); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if q is not null then q := '%' || replace(replace(replace(left(q, 30), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  perform trade_expire_due(10);
  with base as (
    select l.*, (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending') as n_off,
           coalesce(l.buy_drinks::numeric, l.buy_gold::numeric / 100) as price_key   -- 골드 100 = 드링크 1 로 대충 비교 (정렬용)
      from trade_listings l
     where l.status = 'open' and l.expires_at > now()
       and (coalesce(p_type, 'all') = 'all' or (p_type = 'card' and jsonb_array_length(l.cards) > 0) or (p_type = 'gear' and jsonb_array_length(l.gear) > 0))
       and (p_gkeys is null or cardinality(p_gkeys) = 0 or exists (select 1 from jsonb_array_elements(l.cards || l.gear) x where x->>'gkey' = any(p_gkeys)))
       and (p_want_in is null or cardinality(p_want_in) = 0 or exists (select 1 from jsonb_array_elements(l.want_ids) w where w->>'id' = any(p_want_in)))
       and (not coalesce(p_buy_only, false) or l.buy_drinks is not null or l.buy_gold is not null)
       and ((q is null and (p_card_ids is null or cardinality(p_card_ids) = 0))
            or (p_card_ids is not null and cardinality(p_card_ids) > 0 and exists (select 1 from jsonb_array_elements(l.cards) x where x->'card'->>'id' = any(p_card_ids)))
            or (q is not null and exists (select 1 from jsonb_array_elements(l.gear) x join gear_defs d on d.id = (x->'row'->>'def_id') where d.name ilike q)))
  ), page as (
    select id, row_number() over (order by
              case when p_sort = 'end' then extract(epoch from expires_at) end asc nulls last,
              case when p_sort = 'hot' then n_off end desc nulls last,
              case when p_sort = 'price' then price_key end asc nulls last,
              id desc) as ord
      from base
  )
  select jsonb_build_object('ok', true, 'offset', off,
      'more', exists (select 1 from page where ord = off + lim + 1),
      'listings', coalesce((select jsonb_agg(_trade_listing_json(t, uid) order by p.ord) from page p join trade_listings t on t.id = p.id where p.ord > off and p.ord <= off + lim), '[]'::jsonb))
    into res;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._trade_want_ids(jsonb), public._trade_listing_json(trade_listings, uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.trade_list3(text[], bigint[], text, int, bigint, jsonb), public.trade_search2(text, text[], text, text[], boolean, text, int, int, text[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.trade_list3(text[], bigint[], text, int, bigint, jsonb), public.trade_search2(text, text[], text, text[], boolean, text, int, int, text[]) to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_direct.sql =====
-- ===== 거래소 개편 3/4: 지정 거래 (닉네임으로 상대 찾기 → 그 사람만 받을 수 있는 거래 + 우편 알림) =====
-- 선행: trade_board.sql · trade_admin.sql · trade_buynow_search.sql · trade_wanted.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 트리거 · 함수 추가/교체만)
-- 흐름: 보내는 사람 = 판매 글(물건 보관, 없어도 됨) + 드링크(물건 없으면 필수, 보관) + 원하는 물건 → 받는 사람에게 우편 → 받는 사람이 원하는 물건을 내고 '수락' 한 번에 끝
--  * 받는 사람도 같은 규칙: Lv.20 · 가입 7일 · 하루 거래 5번 · 같은 상대 7일 3번 · 하루 드링크 보내기/받기 한도 (기존 함수·트리거가 그대로 검사)
--  * 지정 글은 게시판·검색에 보내는 사람·받는 사람에게만 보임. 다른 사람은 제안 불가 (트리거)
--  * 보낸 드링크: 거래 완료 → 받는 사람에게 (10% 올림 소각, 재화 수수료와 같음) / 내림·만료·거절 → 보낸 사람에게 그대로 환불 (트리거)
--  * 거래 기록(trade_log.seller_gave)에 보낸 드링크도 남김 → 시세·관리자 화면·의심 표시 그대로

-- 0) 드링크 한도 해제 (형님 결정 2026-11-04): 하루 보내기·받기 · 보관 한도를 사실상 무제한으로 (값만 바꿈, 다시 돌려도 같음)
update public.trade_config set val = 2000000000 where key in ('daily_drink_send', 'daily_drink_recv', 'escrow_max_drinks') and val <> 2000000000;$vr_statement$;
  execute $vr_statement$alter table public.trade_listings add column if not exists target uuid references auth.users(id) on delete cascade;$vr_statement$;
  execute $vr_statement$alter table public.trade_listings add column if not exists give_drinks int not null default 0 check (give_drinks >= 0);$vr_statement$;
  execute $vr_statement$create index if not exists trade_listings_target on public.trade_listings (target, status) where target is not null;$vr_statement$;
  execute $vr_statement$-- 1) 닉네임으로 상대 찾기 (앞부분 일치, 최대 10명, 나 제외)
create or replace function public.trade_user_find(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := btrim(coalesce(p_q, ''));
begin
  if uid is null then raise exception 'login required'; end if;
  if char_length(q) < 1 then return jsonb_build_object('ok', true, 'users', '[]'::jsonb); end if;
  q := replace(replace(replace(left(q, 20), '\', '\\'), '%', '\%'), '_', '\_');
  return jsonb_build_object('ok', true, 'users', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nick', p.nickname) order by (p.nickname = btrim(p_q)) desc, p.nickname), '[]'::jsonb)
    from (select id, nickname from profiles where id <> uid and nickname ilike q || '%' order by (nickname = btrim(p_q)) desc, nickname limit 10) p));
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 지정 거래 보내기
create or replace function public.trade_direct_list(p_target uuid, p_cards text[], p_gear bigint[], p_drinks int default 0, p_want text default '', p_want_ids jsonb default '[]'::jsonb, p_msg text default '') returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d int := coalesce(p_drinks, 0); r jsonb; lid bigint; nick text; msg text := left(btrim(coalesce(p_msg, '')), 200); l trade_listings;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_target is null or p_target = uid or not exists (select 1 from profiles where id = p_target) then raise exception 'invalid target'; end if;
  if d < 0 then raise exception 'invalid amount'; end if;
  begin perform _trade_gate(p_target); exception when others then raise exception 'target cannot trade'; end;
  if (select count(*) from trade_listings where seller = uid and target = p_target and status = 'open') >= 3 then raise exception 'too many direct'; end if;
  if d > 0 and _trade_drinks_today(uid, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  if d > _trade_cfg('escrow_max_drinks') then raise exception 'escrow limit'; end if;
  if coalesce(cardinality(p_cards), 0) + coalesce(cardinality(p_gear), 0) > 0 then
    r := trade_list3(p_cards, p_gear, p_want, null, null, p_want_ids);   -- 물건 보관 · 레벨/가입일 · 열린 글 수 · 최대 5개 검사 그대로
  else
    -- 드링크만: 드링크 > 0 + 원하는 물건 1개 이상 필수 (그냥 주는 선물 거래 방지)
    if d <= 0 then raise exception 'nothing to trade'; end if;
    if jsonb_array_length(_trade_want_ids(p_want_ids)) = 0 then raise exception 'want required'; end if;
    perform _trade_gate(uid); perform _trade_lock_users(array[uid]);
    if (select count(*) from trade_listings where seller = uid and status = 'open') >= _trade_cfg('max_open_listings') then raise exception 'too many listings'; end if;
    insert into trade_listings (seller, want, cards, gear, want_ids, expires_at)
      values (uid, left(coalesce(btrim(p_want), ''), 100), '[]'::jsonb, '[]'::jsonb, _trade_want_ids(p_want_ids), now() + make_interval(hours => _trade_cfg('listing_hours'))) returning id into lid;
    r := jsonb_build_object('ok', true, 'listing_id', lid);
  end if;
  lid := (r->>'listing_id')::bigint;
  update trade_listings set target = p_target, give_drinks = d where id = lid and seller = uid returning * into l;
  if d > 0 then perform _item_add(uid, 'drink', -d, 0, 'trade_escrow', null, jsonb_build_object('listing', lid, 'direct', true)); end if;   -- 거래 가능 드링크 부족하면 전체 취소
  select nickname into nick from profiles where id = uid;
  insert into player_mail (user_id, kind, payload, reason, title, body, expires_at)
  values (p_target, 'msg', '{}'::jsonb, 'trade_direct', '🤝 ' || coalesce(nick, '플레이어') || '님의 지정 거래 제안',
          coalesce(nullif(msg, '') || E'\n\n', '') || '거래소 → 내 거래 → 받은 지정 거래에서 확인하고 수락할 수 있어요. (#' || lid || ')', l.expires_at);
  return r || jsonb_build_object('target', p_target, 'give_drinks', d);
end $$;$vr_statement$;
  execute $vr_statement$-- 3) 받은 지정 거래 목록 (받는 사람)
create or replace function public.trade_direct_inbox() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings where target = uid and status = 'open' and expires_at > now() order by id desc limit 30) l));
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 수락 (받는 사람: 원하는 물건·재화를 내고 바로 완료). 재화 범위·하루 한도·같은 상대 한도는 기존 제안/수락 그대로
create or replace function public.trade_direct_accept(p_listing bigint, p_cards text[], p_gear bigint[], p_drinks int default 0, p_gold bigint default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; r jsonb; o bigint;
begin
  perform _trade_gate(uid);
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.target is distinct from uid then raise exception 'listing not found'; end if;
  if l.status = 'open' and l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  perform _trade_lock_users(array[uid, l.seller] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));
  select id into o from trade_offers where listing_id = l.id and offerer = uid and status = 'pending';
  if o is not null then perform _trade_refund_offer(o, 'cancelled'); end if;   -- 예전에 넣어 둔 제안이 있으면 돌려주고 새로
  r := trade_offer(l.id, p_cards, p_gear, coalesce(p_drinks, 0), coalesce(p_gold, 0));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  return _trade_accept_core(l.id, (r->>'offer_id')::bigint, l.seller, false) || jsonb_build_object('got_drinks', l.give_drinks - ceil(l.give_drinks * _trade_cfg('fee_pct') / 100.0)::int);
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 거절 (받는 사람) → 보낸 사람 물건·드링크 환불 + 우편
create or replace function public.trade_direct_decline(p_listing bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; nick text;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.target is distinct from uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  perform _trade_close_listing(l.id, 'cancelled');
  select nickname into nick from profiles where id = uid;
  insert into player_mail (user_id, kind, payload, reason, title, body)
  values (l.seller, 'msg', '{}'::jsonb, 'trade_direct', '🙅 ' || coalesce(nick, '플레이어') || '님이 지정 거래를 거절했어요', '보낸 물건과 드링크는 그대로 돌려받았어요. (#' || l.id || ')');
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 트리거: 지정 글엔 받는 사람만 제안
create or replace function public._trade_direct_offer_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select target into t from trade_listings where id = new.listing_id;
  if t is not null and new.offerer <> t then raise exception 'direct only'; end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_direct_offer_guard on public.trade_offers;$vr_statement$;
  execute $vr_statement$create trigger trade_direct_offer_guard before insert on public.trade_offers for each row execute function public._trade_direct_offer_guard();$vr_statement$;
  execute $vr_statement$-- 7) 트리거: 보낸 드링크 정산 (완료 → 받는 사람 / 그 밖 종료 → 보낸 사람)
create or replace function public._trade_direct_settle() returns trigger language plpgsql security definer set search_path = public as $$
declare buyer uuid; fee int;
begin
  if new.give_drinks <= 0 or old.status <> 'open' or new.status = 'open' then return new; end if;
  if new.status = 'done' then
    select offerer into buyer from trade_offers where id = new.offer_id;
    fee := ceil(new.give_drinks * _trade_cfg('fee_pct') / 100.0)::int;
    perform _item_add(buyer, 'drink', new.give_drinks - fee, 0, 'trade_recv', null, jsonb_build_object('listing', new.id, 'fee', fee, 'direct', true));
  else
    perform _item_add(new.seller, 'drink', new.give_drinks, 0, 'trade_refund', null, jsonb_build_object('listing', new.id, 'direct', true));
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_direct_settle on public.trade_listings;$vr_statement$;
  execute $vr_statement$create trigger trade_direct_settle after update of status on public.trade_listings for each row execute function public._trade_direct_settle();$vr_statement$;
  execute $vr_statement$-- 8) 트리거: 거래 기록에 보낸 드링크 남기기 + 한도 (보낸 사람 보내기 · 받는 사람 받기)
create or replace function public._trade_direct_log() returns trigger language plpgsql security definer set search_path = public as $$
declare d int;
begin
  select give_drinks into d from trade_listings where id = new.listing_id;
  if coalesce(d, 0) > 0 then
    if _trade_drinks_today(new.seller, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
    if _trade_drinks_today(new.buyer, 'recv') + d > _trade_cfg('daily_drink_recv') then raise exception 'drink recv limit'; end if;
    new.seller_gave := new.seller_gave || jsonb_build_object('drinks', d);
    new.fees := new.fees || jsonb_build_object('direct_drinks', ceil(d * _trade_cfg('fee_pct') / 100.0)::int);
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_direct_log on public.trade_log;$vr_statement$;
  execute $vr_statement$create trigger trade_direct_log before insert on public.trade_log for each row execute function public._trade_direct_log();$vr_statement$;
  execute $vr_statement$-- 9) 게시판·검색: 지정 글은 당사자에게만 (응답 모양 그대로 + direct·give_drinks·to_me·seller_name·target_name)
create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'want_ids', l.want_ids,
    'direct', l.target is not null, 'give_drinks', l.give_drinks, 'to_me', l.target = uid,
    'seller_name', case when l.target is not null then (select nickname from profiles where id = l.seller) end,
    'target_name', case when l.target is not null and l.seller = uid then (select nickname from profiles where id = l.target) end, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_board(p_limit int default 50, p_before bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select l.* from trade_listings l where status = 'open' and expires_at > now() and (target is null or target = uid or seller = uid) and (p_before is null or id < p_before) order by id desc limit greatest(1, least(p_limit, 100))) l));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_search(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := nullif(btrim(coalesce(p_q, '')), ''); lim int := greatest(1, least(coalesce(p_limit, 30), 50)); off int := greatest(0, least(coalesce(p_offset, 0), 2000)); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if q is not null then q := '%' || replace(replace(replace(left(q, 30), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  perform trade_expire_due(10);
  with base as (
    select l.*, (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending') as n_off,
           coalesce(l.buy_drinks::numeric, l.buy_gold::numeric / 100) as price_key   -- 골드 100 = 드링크 1 로 대충 비교 (정렬용)
      from trade_listings l
     where l.status = 'open' and l.expires_at > now()
       and (l.target is null or l.target = uid or l.seller = uid)
       and (coalesce(p_type, 'all') = 'all' or (p_type = 'card' and jsonb_array_length(l.cards) > 0) or (p_type = 'gear' and jsonb_array_length(l.gear) > 0))
       and (p_gkeys is null or cardinality(p_gkeys) = 0 or exists (select 1 from jsonb_array_elements(l.cards || l.gear) x where x->>'gkey' = any(p_gkeys)))
       and (not coalesce(p_buy_only, false) or l.buy_drinks is not null or l.buy_gold is not null)
       and ((q is null and (p_card_ids is null or cardinality(p_card_ids) = 0))
            or (p_card_ids is not null and cardinality(p_card_ids) > 0 and exists (select 1 from jsonb_array_elements(l.cards) x where x->'card'->>'id' = any(p_card_ids)))
            or (q is not null and exists (select 1 from jsonb_array_elements(l.gear) x join gear_defs d on d.id = (x->'row'->>'def_id') where d.name ilike q)))
  ), page as (
    select id, row_number() over (order by
              case when p_sort = 'end' then extract(epoch from expires_at) end asc nulls last,
              case when p_sort = 'hot' then n_off end desc nulls last,
              case when p_sort = 'price' then price_key end asc nulls last,
              id desc) as ord
      from base
  )
  select jsonb_build_object('ok', true, 'offset', off,
      'more', exists (select 1 from page where ord = off + lim + 1),
      'listings', coalesce((select jsonb_agg(_trade_listing_json(t, uid) order by p.ord) from page p join trade_listings t on t.id = p.id where p.ord > off and p.ord <= off + lim), '[]'::jsonb))
    into res;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.trade_search2(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0, p_want_in text[] default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := nullif(btrim(coalesce(p_q, '')), ''); lim int := greatest(1, least(coalesce(p_limit, 30), 50)); off int := greatest(0, least(coalesce(p_offset, 0), 2000)); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if q is not null then q := '%' || replace(replace(replace(left(q, 30), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  perform trade_expire_due(10);
  with base as (
    select l.*, (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending') as n_off,
           coalesce(l.buy_drinks::numeric, l.buy_gold::numeric / 100) as price_key   -- 골드 100 = 드링크 1 로 대충 비교 (정렬용)
      from trade_listings l
     where l.status = 'open' and l.expires_at > now()
       and (l.target is null or l.target = uid or l.seller = uid)
       and (coalesce(p_type, 'all') = 'all' or (p_type = 'card' and jsonb_array_length(l.cards) > 0) or (p_type = 'gear' and jsonb_array_length(l.gear) > 0))
       and (p_gkeys is null or cardinality(p_gkeys) = 0 or exists (select 1 from jsonb_array_elements(l.cards || l.gear) x where x->>'gkey' = any(p_gkeys)))
       and (p_want_in is null or cardinality(p_want_in) = 0 or exists (select 1 from jsonb_array_elements(l.want_ids) w where w->>'id' = any(p_want_in)))
       and (not coalesce(p_buy_only, false) or l.buy_drinks is not null or l.buy_gold is not null)
       and ((q is null and (p_card_ids is null or cardinality(p_card_ids) = 0))
            or (p_card_ids is not null and cardinality(p_card_ids) > 0 and exists (select 1 from jsonb_array_elements(l.cards) x where x->'card'->>'id' = any(p_card_ids)))
            or (q is not null and exists (select 1 from jsonb_array_elements(l.gear) x join gear_defs d on d.id = (x->'row'->>'def_id') where d.name ilike q)))
  ), page as (
    select id, row_number() over (order by
              case when p_sort = 'end' then extract(epoch from expires_at) end asc nulls last,
              case when p_sort = 'hot' then n_off end desc nulls last,
              case when p_sort = 'price' then price_key end asc nulls last,
              id desc) as ord
      from base
  )
  select jsonb_build_object('ok', true, 'offset', off,
      'more', exists (select 1 from page where ord = off + lim + 1),
      'listings', coalesce((select jsonb_agg(_trade_listing_json(t, uid) order by p.ord) from page p join trade_listings t on t.id = p.id where p.ord > off and p.ord <= off + lim), '[]'::jsonb))
    into res;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._trade_listing_json(trade_listings, uuid), public._trade_direct_offer_guard(), public._trade_direct_settle(), public._trade_direct_log() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.trade_user_find(text), public.trade_direct_list(uuid, text[], bigint[], int, text, jsonb, text), public.trade_direct_inbox(),
  public.trade_direct_accept(bigint, text[], bigint[], int, bigint), public.trade_direct_decline(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.trade_user_find(text), public.trade_direct_list(uuid, text[], bigint[], int, text, jsonb, text), public.trade_direct_inbox(),
  public.trade_direct_accept(bigint, text[], bigint[], int, bigint), public.trade_direct_decline(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: global_notice.sql =====
-- ===== 거래소 개편 4/4: 전체 알림 (UR·MR·LR 획득) + 소식 기록 =====
-- 선행: gacha.sql (story_gacha_log) · schema.sql (profiles). 여러 번 실행해도 안전. 지우는 것 없음 (표·트리거·함수 추가만)
-- 1) 어떤 뽑기든(일일·티켓·합성·이벤트 등) story_gacha_log 에 UR 이상이 들어오면 global_notices 에 한 줄 (트리거 → 뽑기 함수는 그대로)
-- 2) 화면은 global_notice_list 로 30초마다 새 알림만 받아 토스트 + 📢 소식 창. 이름 누르면 지정 거래 (이름 숨기기 없음)
-- 3) 3일 지난 알림은 목록에서 안 보임 (표는 남음, 정리는 원하면 따로)

create table if not exists public.global_notices (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  nick       text not null default '플레이어',
  card_id    text not null,
  grade      text not null,
  src        text not null default 'daily',
  created_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists global_notices_time on public.global_notices (created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.global_notices enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.global_notices from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._global_notice_gacha() returns trigger language plpgsql security definer set search_path = public as $$
declare g text := upper(coalesce(new.grade, ''));
begin
  if g in ('ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE', 'UR', 'MR', 'LR') then
    insert into global_notices (user_id, nick, card_id, grade, src)
    values (new.user_id, coalesce((select nickname from profiles where id = new.user_id), '플레이어'), new.card_id,
            case g when 'ULTRA RARE' then 'UR' when 'MYTHIC RARE' then 'MR' when 'LEGENDARY RARE' then 'LR' else g end,
            coalesce(to_jsonb(new)->>'kind', 'daily'));
  end if;
  return new;
exception when others then return new;   -- 알림 실패로 뽑기가 깨지면 안 됨
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists global_notice_gacha on public.story_gacha_log;$vr_statement$;
  execute $vr_statement$create trigger global_notice_gacha after insert on public.story_gacha_log for each row execute function public._global_notice_gacha();$vr_statement$;
  execute $vr_statement$-- 목록: p_after 보다 새 것 (없으면 최근), 최대 50, 3일 이내. me = 내 알림 (이름 링크 끄기용)
create or replace function public.global_notice_list(p_after bigint default null, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'notices', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'uid', n.user_id, 'nick', n.nick, 'card_id', n.card_id, 'grade', n.grade, 'src', n.src,
      'created_at', n.created_at, 'me', n.user_id = uid) order by n.id desc), '[]'::jsonb)
    from (select * from global_notices where created_at > now() - interval '3 days' and (p_after is null or id > p_after)
          order by id desc limit greatest(1, least(coalesce(p_limit, 50), 100))) n));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._global_notice_gacha() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.global_notice_list(bigint, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.global_notice_list(bigint, int) to authenticated;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_lv10.sql =====
-- ===== 거래 계정 레벨 하한 20 → 10 (형님 결정 2026-11-04) =====
-- 일반 거래·즉시 구매·지정 거래(보내는 사람·받는 사람) 모두 _trade_gate 가 trade_config.min_level 을 읽으므로 값만 바꾸면 전부 적용
-- 여러 번 실행해도 안전 (값만 바꿈, 지우는 것 없음)
insert into public.trade_config (key, val, note) values ('min_level', 10, '계정 레벨 하한')
on conflict (key) do update set val = 10 where public.trade_config.val <> 10;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: nickname.sql =====
-- 닉네임: 직접 정하기 · 2~12자 · 중복 금지(대소문자 무시). 여러 번 실행해도 안전.
-- 화면(랭킹·PvP·친구·조직 등)은 원래 profiles.nickname 을 쓰므로 이름 표시는 그대로 이 값을 따라감.
-- nick_set = 본인이 직접 정했는지. false 면 로그인 때 닉네임 짓기 창이 뜸 (기존 구글 이름은 그때까지 임시 표시).

alter table public.profiles add column if not exists nick_set boolean not null default false;$vr_statement$;
  execute $vr_statement$-- 직접 정한 닉네임끼리 중복 금지 (대소문자·앞뒤 공백 무시). 구글 이름(임시)은 기존 중복이 있어서 제외
create unique index if not exists profiles_nick_unique on public.profiles (lower(btrim(nickname))) where nick_set;$vr_statement$;
  execute $vr_statement$-- 클라이언트는 아바타만 직접 고칠 수 있음. 닉네임은 set_nickname() 으로만
revoke update on public.profiles from authenticated, anon;$vr_statement$;
  execute $vr_statement$grant update (avatar_url, updated_at) on public.profiles to authenticated;$vr_statement$;
  execute $vr_statement$revoke insert on public.profiles from authenticated, anon;$vr_statement$;
  execute $vr_statement$grant insert (id, nickname, avatar_url) on public.profiles to authenticated;$vr_statement$;
  execute $vr_statement$-- set_nickname 밖에서 닉네임이 바뀌면(관리자 초기화 등) '직접 정함' 표시를 풀어서 다시 짓게 함
create or replace function public._profiles_nick_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.nick_rpc', true), '') <> '1' then
    if tg_op = 'INSERT' then new.nick_set := false;
    elsif new.nickname is distinct from old.nickname or new.nick_set is distinct from old.nick_set then new.nick_set := false; end if;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists profiles_nick_guard on public.profiles;$vr_statement$;
  execute $vr_statement$create trigger profiles_nick_guard before insert or update on public.profiles for each row execute function public._profiles_nick_guard();$vr_statement$;
  execute $vr_statement$-- 검사 (쓸 수 있는지만): ok / short / long / bad / taken
create or replace function public._nick_check(p text, uid uuid) returns text language sql stable security definer set search_path = public as $$
  select case
    when p is null or char_length(btrim(p)) < 2 then 'short'
    when char_length(btrim(p)) > 12 then 'long'
    when btrim(p) !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ _.\-]+$' or btrim(p) ~ '\s\s' then 'bad'
    when exists (select 1 from profiles x where lower(btrim(x.nickname)) = lower(btrim(p)) and x.id <> coalesce(uid, '00000000-0000-0000-0000-000000000000'::uuid)) then 'taken'
    else 'ok' end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public.nickname_check(p_nick text) returns text
language sql stable security definer set search_path = public as $$ select public._nick_check(p_nick, auth.uid()) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.set_nickname(p_nick text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text := btrim(p_nick); r text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('nick:' || lower(n)));
  r := _nick_check(n, uid);
  if r <> 'ok' then raise exception 'nick %', r; end if;
  perform set_config('app.nick_rpc', '1', true);
  insert into profiles (id, nickname, nick_set) values (uid, n, true)
    on conflict (id) do update set nickname = n, nick_set = true, updated_at = now();
  perform set_config('app.nick_rpc', '', true);
  return jsonb_build_object('ok', true, 'nickname', n);
exception when unique_violation then raise exception 'nick taken';
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._nick_check(text, uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.nickname_check(text), public.set_nickname(text) from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.nickname_check(text) to authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.set_nickname(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: nickname_v2.sql =====
-- 닉네임 v2: 금지어 · 두 번째 변경부터 심연석 200개. nickname.sql · gem.sql 다음에 실행. 여러 번 실행해도 안전.

-- 1) 금지어 (공백·기호 빼고 소문자로 비교, 단어가 포함되면 막음). 형님이 표에 줄을 더하거나 지워서 관리 가능
create table if not exists public.nick_banned (word text primary key check (word = lower(word) and char_length(word) between 1 and 20));$vr_statement$;
  execute $vr_statement$alter table public.nick_banned enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.nick_banned from anon, authenticated;$vr_statement$;
  execute $vr_statement$insert into public.nick_banned (word) values
  ('시발'),('씨발'),('씨바'),('씨팔'),('시팔'),('쓰발'),('ㅅㅂ'),('ㅆㅂ'),('ㅅㅍ'),('병신'),('븅신'),('빙신'),('ㅂㅅ'),('좆'),('존나'),('졸라'),('ㅈㄴ'),
  ('개새'),('새끼'),('색기'),('ㅅㄲ'),('지랄'),('ㅈㄹ'),('미친놈'),('미친년'),('미친새'),('엠창'),('느금'),('니미'),('니애미'),('애미'),('애비'),('에미'),
  ('섹스'),('보지'),('자지'),('창녀'),('걸레'),('꼴린'),('따먹'),('강간'),('한남'),('김치녀'),('틀딱'),('운영자'),('관리자'),('운영진'),
  ('fuck'),('fuk'),('shit'),('bitch'),('asshole'),('dick'),('pussy'),('cunt'),('nigger'),('nigga'),('faggot'),('slut'),('whore'),
  ('porn'),('rape'),('admin'),('operator'),('gamemaster')
on conflict do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._nick_norm(p text) returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p, '')), '[\s_.\-0-9]', '', 'g') $$;$vr_statement$;
  execute $vr_statement$-- 2) 검사: ok / short / long / bad / banned / taken
create or replace function public._nick_check(p text, uid uuid) returns text language sql stable security definer set search_path = public as $$
  select case
    when p is null or char_length(btrim(p)) < 2 then 'short'
    when char_length(btrim(p)) > 12 then 'long'
    when btrim(p) !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ _.\-]+$' or btrim(p) ~ '\s\s' then 'bad'
    when exists (select 1 from nick_banned b where position(b.word in _nick_norm(p)) > 0) then 'banned'
    when exists (select 1 from profiles x where lower(btrim(x.nickname)) = lower(btrim(p)) and x.id <> coalesce(uid, '00000000-0000-0000-0000-000000000000'::uuid)) then 'taken'
    else 'ok' end
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._nick_check(text, uuid), public._nick_norm(text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 변경: 처음(아직 직접 안 정함)은 무료, 이미 정한 뒤 바꾸면 심연석 200 (무료분 먼저, 같은 트랜잭션에서 차감)
create or replace function public._nick_price() returns int language sql immutable as $$ select 200 $$;$vr_statement$;
  execute $vr_statement$create or replace function public.set_nickname(p_nick text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text := btrim(p_nick); r text; was boolean; old text; cost int := 0; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('nick:' || lower(n)));
  select nick_set, nickname into was, old from profiles where id = uid for update;
  if coalesce(was, false) and old = n then raise exception 'nick same'; end if;
  r := _nick_check(n, uid);
  if r <> 'ok' then raise exception 'nick %', r; end if;
  if coalesce(was, false) then
    cost := _nick_price();
    begin g := _gem_spend(uid, cost, 'nickname', jsonb_build_object('from', old, 'to', n));
    exception when others then if sqlerrm ~ 'not enough' then raise exception 'nick gem'; else raise; end if; end;
  end if;
  perform set_config('app.nick_rpc', '1', true);
  insert into profiles (id, nickname, nick_set) values (uid, n, true)
    on conflict (id) do update set nickname = n, nick_set = true, updated_at = now();
  perform set_config('app.nick_rpc', '', true);
  return jsonb_build_object('ok', true, 'nickname', n, 'cost', cost);
exception when unique_violation then raise exception 'nick taken';
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.set_nickname(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.set_nickname(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 로그인 안 한 사람(anon)은 닉네임 함수 못 씀 (Supabase 기본 권한이 anon 에게도 줘서 명시적으로 회수)
revoke execute on function public.nickname_check(text), public.set_nickname(text) from anon;$vr_statement$;
  execute $vr_statement$revoke execute on function public._nick_check(text, uuid), public._nick_norm(text), public._nick_price() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.nickname_check(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: rankings_v2.sql =====
-- 랭킹 v2: 시련의 탑 · 스토리 랭킹 (읽기 전용 함수 2개). 여러 번 실행해도 안전.
-- 닉네임·기록만 돌려주고 user_id 는 내보내지 않아요. 아케이드(rankings_weekly/all), PvP(pvp_rankings)는 기존 그대로 사용.

-- 1) 탑 랭킹: 탑별 최고 층 (같으면 먼저 도달한 사람이 위)
create or replace function public.tower_rankings(p_tower text default 'normal') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  if p_tower not in ('normal', 'wind', 'ice', 'fire', 'light', 'dark') then raise exception 'bad tower'; end if;
  with t as (select g.user_id, g.best_floor, g.clears, rank() over (order by g.best_floor desc) rk, row_number() over (order by g.best_floor desc, g.updated_at) rn
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'floor', best_floor, 'me', t.user_id = uid) order by rn), '[]'::jsonb)
    into top from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id;
  with t as (select g.user_id, g.best_floor, rank() over (order by g.best_floor desc) rk
             from tower_progress g where g.tower = p_tower and g.best_floor > 0)
  select jsonb_build_object('rank', rk, 'floor', best_floor) into mine from t where t.user_id = uid;
  return jsonb_build_object('top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 스토리 랭킹: 깬 페이즈 중 가장 먼 곳 (챕터 → 페이즈 순). 화면엔 '9-15' 처럼 표시
create or replace function public.story_rankings() returns jsonb
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
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid) order by rn)
                     from (select * from t order by rn limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.tower_rankings(text) from public;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_rankings() from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.tower_rankings(text) to anon, authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_rankings() to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: rankings_v2_story_tie.sql =====
-- 스토리 랭킹 동점 처리 보강 (rankings_v2.sql 다음에 실행). 여러 번 실행해도 안전.
-- 순위: 가장 먼 챕터-페이즈 → 깬 페이즈 수 → 그 기록에 먼저 도달한 사람.
-- story_progress 에는 '언제 깼는지'가 없어서, 기록(챕터·페이즈·깬 수)이 올라간 시각을 따로 적어 둡니다.

create table if not exists public.story_rank_reach (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  ch int not null, ph int not null, total int not null,
  reached_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$alter table public.story_rank_reach enable row level security;$vr_statement$;
  execute $vr_statement$-- 정책 없음 = 직접 조회 불가 (아래 함수로만)
revoke all on public.story_rank_reach from anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._story_best(d jsonb, out ch int, out ph int, out total int)
language sql immutable set search_path = public as $$
  with c as (select (k.key)::int ch, max((v.value)::int) ph, count(*)::int n
               from jsonb_each(case when jsonb_typeof(d->'cleared') = 'object' then d->'cleared' else '{}'::jsonb end) k,
                    jsonb_array_elements_text(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) v
              where k.key ~ '^[0-9]{1,3}$' and v.value ~ '^[0-9]{1,3}$' group by k.key)
  select (select c.ch from c order by c.ch desc limit 1), (select c.ph from c order by c.ch desc limit 1), (select coalesce(sum(n), 0)::int from c)
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_reach_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare b record;
begin
  select * into b from _story_best(new.data);
  if b.ch is null then return new; end if;
  insert into story_rank_reach (user_id, ch, ph, total, reached_at) values (new.user_id, b.ch, b.ph, b.total, now())
  on conflict (user_id) do update set ch = excluded.ch, ph = excluded.ph, total = excluded.total, reached_at = now()
    where (story_rank_reach.ch, story_rank_reach.ph, story_rank_reach.total) is distinct from (excluded.ch, excluded.ph, excluded.total);
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists story_reach on public.story_progress;$vr_statement$;
  execute $vr_statement$create trigger story_reach after insert or update of data on public.story_progress for each row execute function public._story_reach_trg();$vr_statement$;
  execute $vr_statement$-- 기존 기록 채우기: 정확한 시각을 모르니 마지막 저장 시각으로 (이미 있으면 그대로)
insert into public.story_rank_reach (user_id, ch, ph, total, reached_at)
select s.user_id, b.ch, b.ph, b.total, s.updated_at from public.story_progress s, lateral public._story_best(s.data) b where b.ch is not null
on conflict (user_id) do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public.story_rankings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  with t as (select r.*, rank() over (order by ch desc, ph desc, total desc, reached_at) rk from story_rank_reach r)
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid) order by rk)
                     from (select * from t order by rk limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_rankings() from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_rankings() to anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_best(jsonb), public._story_reach_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: friends.sql =====
-- =====================================================================
-- 👥 친구 (1단계: 검색·신청·수락·거절·취소·삭제·목록·접속 상태) — 여러 번 실행해도 안전, 삭제 없음
-- 선행: schema.sql(profiles) · phaseE_2.sql(player_state, 레벨 표시용)
-- 친구 코드 = user id 앞 8자리 (대문자). 닉네임 부분 검색 또는 코드로 검색
-- 이후 친구 대전/리플레이 공유는 friendships(정렬된 쌍 a<b) 를 기준으로 붙이면 됨
-- 공개 RPC: friends_ping() · friends_list() · friends_search(q) · friend_request(user) · friend_respond(req_id, accept)
--           friend_cancel(req_id) · friend_remove(user) · friends_pending_count()
-- =====================================================================

create table if not exists public.friend_requests (
  id         bigint generated always as identity primary key,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  unique (from_user, to_user)
);$vr_statement$;
  execute $vr_statement$create index if not exists friend_requests_to_idx on public.friend_requests (to_user);$vr_statement$;
  execute $vr_statement$alter table public.friend_requests enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.friend_requests from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 친구 관계: 한 쌍당 한 줄 (user_a < user_b). 친구 대전·리플레이 공유 시 참조
create table if not exists public.friendships (
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);$vr_statement$;
  execute $vr_statement$create index if not exists friendships_b_idx on public.friendships (user_b);$vr_statement$;
  execute $vr_statement$alter table public.friendships enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.friendships from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 접속 기록 (클라이언트가 몇 분마다 friends_ping)
create table if not exists public.player_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$alter table public.player_presence enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.player_presence from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_cap() returns int language sql immutable as $$ select 50 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_code(p uuid) returns text language sql immutable as $$ select upper(left(replace(p::text, '-', ''), 8)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._is_friend(p1 uuid, p2 uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where user_a = least(p1, p2) and user_b = greatest(p1, p2)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_count(p uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from friendships where user_a = p or user_b = p $$;$vr_statement$;
  execute $vr_statement$create or replace function public._friend_card(p uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('user_id', p, 'code', _friend_code(p),
    'name', coalesce((select nickname from profiles where id = p), '플레이어'),
    'avatar', (select avatar_url from profiles where id = p),
    'level', coalesce((select level from player_state where user_id = p), 1),
    'seen_at', (select seen_at from player_presence where user_id = p),
    'online', coalesce((select seen_at > now() - interval '5 minutes' from player_presence where user_id = p), false)) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._is_friend(uuid, uuid), public._friend_count(uuid), public._friend_card(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.friends_ping() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true, 'pending', (select count(*) from friend_requests where to_user = uid));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friends_pending_count() returns int language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return (select count(*)::int from friend_requests where to_user = uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friends_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  insert into player_presence (user_id, seen_at) values (uid, now()) on conflict (user_id) do update set seen_at = now();
  return jsonb_build_object('ok', true, 'me', _friend_card(uid), 'cap', _friend_cap(),
    'friends', (select coalesce(jsonb_agg(_friend_card(o) || jsonb_build_object('since', f.created_at)
                 order by (select seen_at from player_presence where user_id = o) desc nulls last), '[]'::jsonb)
               from (select case when user_a = uid then user_b else user_a end o, created_at from friendships where user_a = uid or user_b = uid) f),
    'incoming', (select coalesce(jsonb_agg(_friend_card(r.from_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.to_user = uid),
    'outgoing', (select coalesce(jsonb_agg(_friend_card(r.to_user) || jsonb_build_object('req_id', r.id, 'at', r.created_at) order by r.id desc), '[]'::jsonb)
               from friend_requests r where r.from_user = uid));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friends_search(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := btrim(coalesce(p_q, ''));
begin
  if uid is null then raise exception 'login required'; end if;
  if char_length(q) < 2 then raise exception 'query too short'; end if;
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  return (select coalesce(jsonb_agg(_friend_card(x.id) || jsonb_build_object(
      'state', case when _is_friend(uid, x.id) then 'friend'
                    when exists (select 1 from friend_requests where from_user = uid and to_user = x.id) then 'sent'
                    when exists (select 1 from friend_requests where from_user = x.id and to_user = uid) then 'received'
                    else 'none' end)), '[]'::jsonb)
    from (select p.id from profiles p
          where p.id <> uid and (p.nickname ilike '%' || q || '%' or (char_length(q) = 8 and _friend_code(p.id) = upper(q)))
          order by (_friend_code(p.id) = upper(q)) desc, (p.nickname = btrim(p_q)) desc, char_length(p.nickname) limit 20) x);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_request(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not exists (select 1 from profiles where id = p_user) then raise exception 'invalid user'; end if;
  perform pg_advisory_xact_lock(hashtext('friend:' || least(uid, p_user)::text || greatest(uid, p_user)::text));
  if _is_friend(uid, p_user) then raise exception 'already friends'; end if;
  -- 상대가 이미 나에게 신청했다면 바로 수락
  select id into rid from friend_requests where from_user = p_user and to_user = uid;
  if rid is not null then return friend_respond(rid, true); end if;
  if _friend_count(uid) >= _friend_cap() then raise exception 'friend cap'; end if;
  if (select count(*) from friend_requests where from_user = uid) >= 50 then raise exception 'too many requests'; end if;
  insert into friend_requests (from_user, to_user) values (uid, p_user) on conflict do nothing;
  return jsonb_build_object('ok', true, 'state', 'sent');
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_respond(p_req bigint, p_accept boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r friend_requests;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from friend_requests where id = p_req and to_user = uid;
  if r.id is null then raise exception 'request not found'; end if;
  perform pg_advisory_xact_lock(hashtext('friend:' || least(r.from_user, uid)::text || greatest(r.from_user, uid)::text));
  delete from friend_requests where id = r.id;
  if not coalesce(p_accept, false) then return jsonb_build_object('ok', true, 'state', 'declined'); end if;
  if _friend_count(uid) >= _friend_cap() then raise exception 'friend cap'; end if;
  if _friend_count(r.from_user) >= _friend_cap() then raise exception 'their friend cap'; end if;
  insert into friendships (user_a, user_b) values (least(uid, r.from_user), greatest(uid, r.from_user)) on conflict do nothing;
  delete from friend_requests where from_user = uid and to_user = r.from_user;
  return jsonb_build_object('ok', true, 'state', 'friend');
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_cancel(p_req bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from friend_requests where id = p_req and from_user = uid;
  if not found then raise exception 'request not found'; end if;
  return jsonb_build_object('ok', true, 'state', 'none');
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_remove(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from friendships where user_a = least(uid, p_user) and user_b = greatest(uid, p_user);
  if not found then raise exception 'not friends'; end if;
  return jsonb_build_object('ok', true, 'state', 'none');
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.friends_ping(), public.friends_pending_count(), public.friends_list(), public.friends_search(text),
  public.friend_request(uuid), public.friend_respond(bigint, boolean), public.friend_cancel(bigint), public.friend_remove(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.friends_ping(), public.friends_pending_count(), public.friends_list(), public.friends_search(text),
  public.friend_request(uuid), public.friend_respond(bigint, boolean), public.friend_cancel(bigint), public.friend_remove(uuid) to authenticated;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (7, '33b887dc47cd39a541ec7e8b546346416cbaf9d2aa104e996a2cda9c476b2e2f', '768c24c4cee8a3b3eef3a22d9c2c25ce20fb8b4efd3c697620862aa1c8fc36e7', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '07_install.sql: 완료 또는 이미 완료 (7/14)' as result;
