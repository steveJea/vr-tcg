-- ⚠ 테스트 전용 3/10. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where part_no = 3) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 3 and part_hash = 'd8c563ec9bf73dd9b2118c16108122afca21efac2566cc64c5d21c98b423b8f7') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '03_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 3) <> 2 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (03_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$revoke all on function public.admin_user_quest(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_user_quest(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- 확인: select tower, count(*), max(paid_floor) from public.tower_progress group by tower;


-- ===== SOURCE: story_ch1_reward.sql =====
-- =====================================================================
-- 챕터 1 페이즈별 고정 보상 카드 (모든 루트 동일). 여러 번 실행해도 안전 (idempotent)
-- 1-1 예유진 · 1-2 남태은 · 1-3 선나영 · 1-4 반지아 · 1-5 이윤이
-- 첫 클리어 때만 지급, 이미 보유한 카드면 한 장 더(중복). 소급 지급 없음.
-- 전제: phaseE_2.sql 적용됨 (원래 완료 함수가 _story_complete_phase_e0 로 보관된 상태)
-- 변경: _story_complete_phase_e0 = story_merge.sql 버전 + reward_card 우선 (그 외 동작 동일)
-- =====================================================================
alter table public.story_phase_config add column if not exists reward_card text;$vr_statement$;
  execute $vr_statement$-- (보상 카드 5장 모두 story_card_pool 에 이미 있음: 2026-10-25 확인)
update public.story_phase_config set reward_card = case phase
  when 1 then '10248' when 2 then '10093' when 3 then '10185' when 4 then '10130' when 5 then '10308' end
where chapter = 1 and phase between 1 and 5;$vr_statement$;
  execute $vr_statement$do $$ begin
  if to_regprocedure('public._story_complete_phase_e0(int,int,jsonb)') is null then
    raise exception 'phaseE_2.sql 을 먼저 적용하세요 (_story_complete_phase_e0 없음)';
  end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_complete_phase_e0(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; ruid text; owned jsonb; ne jsonb;
        st jsonb; idx int; k int; ksum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen int[] := '{}'; key text;
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
      gain := (60 + 20 * k) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = owned->idx->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('uid', owned->idx->>'uid', 'id', owned->idx->>'id', 'kills', k, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
  end if;
  d := jsonb_set(d, '{owned}', owned);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'reward_uid', ruid, 'exp', res);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_complete_phase_e0(int, int, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 확인용
select chapter, phase, reward_grade, reward_card, (select name from public.story_card_pool p where p.id = c.reward_card) as card_name
from public.story_phase_config c where chapter = 1 order by phase;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: cards_1025.sql =====
-- =====================================================================
-- VR: Abyss Gate - 신규 카드 반영 (2026-10-25)
-- 유가을(10267, HIGH RARE) 뽑기 풀 추가 · 민홍기(10118) 2번 스킬 「용서는 없다」 액티브 전환 → 스킬 레벨 메타(해금 Lv5)
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10267','HIGH RARE','유가을',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;$vr_statement$;
  execute $vr_statement$insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10118',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$-- 확인용: 2행
select 'pool' k, id, grade, name, gacha::text from public.story_card_pool where id = '10267'
union all
select 'skill', card_id, idx::text, unlock::text, null from public.story_skill_meta where card_id = '10118' and idx = 2;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_decks.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 story_set_decks 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- 마이 덱(최대 10개) · 덱 카드 자동 잠금 · 카드 즐겨찾기
-- 저장 위치: story_progress.data.decks = [{name, uids[]}], owned[i].fav, owned[i].locked(+dlk: 덱 자동 잠금 표시)
-- 모두 SECURITY DEFINER + auth.uid() 본인 행만. 여러 번 실행해도 안전(idempotent).

-- 1) 마이 덱 저장: 최대 10개, 덱당 최대 10장 (story_decks10.sql), 내가 가진 카드만. 덱에 든 카드는 locked+dlk, 빠지면 dlk 잠금만 해제(수동 잠금 유지)
create or replace function public.story_set_decks(p_decks jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; clean jsonb := '[]'::jsonb; x jsonb; ids jsonb; u text; nm text;
        alluids text[] := '{}'; mine text[]; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_decks is null or jsonb_typeof(p_decks) <> 'array' then raise exception 'bad decks'; end if;
  if jsonb_array_length(p_decks) > 10 then raise exception 'too many decks'; end if;
  select coalesce(array_agg(o->>'uid'), '{}') into mine from jsonb_array_elements(owned) o where coalesce(o->>'uid', '') <> '' and o->>'uid' not like 'guest:%';
  for x in select * from jsonb_array_elements(p_decks) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'bad deck'; end if;
    nm := left(btrim(coalesce(x->>'name', '')), 16);
    ids := '[]'::jsonb;
    if jsonb_typeof(x->'uids') = 'array' then
      if jsonb_array_length(x->'uids') > 5 then raise exception 'deck too large'; end if;
      for u in select jsonb_array_elements_text(x->'uids') loop
        if not (u = any(mine)) then raise exception 'card not owned'; end if;
        if not (ids @> to_jsonb(u)) then ids := ids || to_jsonb(u); alluids := alluids || u; end if;
      end loop;
    end if;
    clean := clean || jsonb_build_object('name', nm, 'uids', ids);
  end loop;
  for i in 0 .. coalesce(jsonb_array_length(owned), 0) - 1 loop
    e := owned->i;
    if (e->>'uid') = any(alluids) then
      if not coalesce((e->>'locked')::boolean, false) then e := e || jsonb_build_object('locked', true, 'dlk', true); end if;
    elsif coalesce((e->>'dlk')::boolean, false) then
      e := e - 'locked' - 'dlk';
    end if;
    owned := jsonb_set(owned, array[i::text], e);
  end loop;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{decks}', clean);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'decks', clean);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_set_decks(jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_set_decks(jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 즐겨찾기
create or replace function public.story_set_fav(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then e || jsonb_build_object('fav', true) else e - 'fav' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'fav', coalesce(p_on, false));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_set_fav(text, boolean) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_set_fav(text, boolean) to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 잠금: 덱에 든 카드는 해제 불가. 수동 잠금 시 dlk 제거(덱에서 빠져도 잠금 유지)
create or replace function public.story_set_lock(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  if not coalesce(p_on, false) and exists (
    select 1 from jsonb_array_elements(case when jsonb_typeof(d->'decks') = 'array' then d->'decks' else '[]'::jsonb end) k
    where jsonb_typeof(k->'uids') = 'array' and k->'uids' @> to_jsonb(p_uid)) then raise exception 'card in deck'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then (e - 'dlk') || jsonb_build_object('locked', true) else e - 'locked' - 'dlk' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'locked', coalesce(p_on, false));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_set_lock(text, boolean) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_set_lock(text, boolean) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: pvp.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _pvp_extra, _pvp_snap, pvp_rankings, pvp_report, pvp_start, pvp_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 비동기 PvP (리그: 무제한 open / HR급 이하 hr · 모드: 1v1 / 3v3 · 주간 시즌 · 하루 10회) =====
-- 실행: Supabase SQL Editor 에서 전체 실행. 여러 번 실행해도 안전(idempotent).
-- 서버 권한: 덱 소유·등급·코스트 검사, 상대 선택, seed 발급, 하루 횟수, 레이팅 계산은 모두 SECURITY DEFINER RPC 에서.
-- 남는 신뢰 구멍: 전투 계산은 브라우저(js/pvp-core.js)에서 하고 결과(승패)를 보고함 → 서버가 seed·양쪽 스냅샷을 저장하므로
--   tools/pvp_verify.mjs 로 나중에 다시 돌려 조작을 찾을 수 있음(verified 컬럼). 실시간 차단은 아님.

-- 0) 카드 메타 (등급·코스트) — data/cards.csv 에서 생성. 카드 추가 시 이 블록만 다시 생성해 실행
create table if not exists public.pvp_card_meta (id text primary key, grade text not null, cost int not null default 0);$vr_statement$;
  execute $vr_statement$alter table public.pvp_card_meta enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_card_meta_read on public.pvp_card_meta;$vr_statement$;
  execute $vr_statement$create policy pvp_card_meta_read on public.pvp_card_meta for select using (true);$vr_statement$;
  execute $vr_statement$insert into public.pvp_card_meta (id, grade, cost) values
('10118','SUPER RARE',43),
('10019','RARE',17),
('10018','RARE',17),
('10299','HIGH RARE',26),
('10074','NORMAL',5),
('10080','NORMAL',5),
('10445','NORMAL',7),
('10375','NORMAL',6),
('10051','ULTRA RARE',48),
('10404','NORMAL',8),
('10049','NORMAL',14),
('10048','NORMAL',14),
('10189','SUPER RARE',45),
('10060','MYTHIC RARE',62),
('10071','NORMAL',10),
('10086','NORMAL',8),
('10169','NORMAL',14),
('10137','HIGH RARE',30),
('10138','HIGH RARE',26),
('10020','RARE',23),
('10463','HIGH RARE',30),
('10228','RARE',24),
('10453','NORMAL',6),
('10293','RARE',25),
('10010','NORMAL',13),
('10380','RARE',24),
('10114','NORMAL',7),
('10401','NORMAL',12),
('10315','NORMAL',10),
('10026','NORMAL',11),
('10191','NORMAL',10),
('10469','NORMAL',12),
('10001','NORMAL',10),
('10183','SUPER RARE',37),
('10064','NORMAL',7),
('10444','NORMAL',5),
('10279','NORMAL',5),
('10225','RARE',23),
('10431','NORMAL',8),
('10332','NORMAL',13),
('10201','NORMAL',6),
('10346','NORMAL',11),
('10275','NORMAL',11),
('10124','RARE',21),
('10134','RARE',20),
('10037','NORMAL',12),
('10031','NORMAL',6),
('10180','RARE',17),
('10390','NORMAL',12),
('10027','NORMAL',6),
('10033','NORMAL',11),
('10353','NORMAL',10),
('10244','NORMAL',12),
('10245','NORMAL',11),
('10292','HIGH RARE',28),
('10076','NORMAL',7),
('10045','SUPER RARE',45),
('10409','NORMAL',7),
('10407','RARE',23),
('10036','HIGH RARE',29),
('10075','NORMAL',9),
('10173','NORMAL',11),
('10406','HIGH RARE',27),
('10328','NORMAL',15),
('10329','SUPER RARE',37),
('10098','RARE',18),
('10187','RARE',17),
('10319','RARE',16),
('10081','HIGH RARE',32),
('10252','NORMAL',11),
('10298','HIGH RARE',29),
('10125','NORMAL',15),
('10025','SUPER RARE',37),
('10035','HIGH RARE',28),
('10112','SUPER RARE',36),
('10270','RARE',16),
('10069','NORMAL',13),
('10088','NORMAL',11),
('10004','NORMAL',9),
('10420','RARE',18),
('10408','RARE',19),
('10205','HIGH RARE',33),
('10139','NORMAL',6),
('10347','RARE',22),
('10023','NORMAL',6),
('10448','NORMAL',11),
('10067','SUPER RARE',38),
('10005','NORMAL',8),
('10276','RARE',20),
('10259','RARE',21),
('10386','RARE',24),
('10105','RARE',22),
('10077','HIGH RARE',32),
('10212','NORMAL',5),
('10065','HIGH RARE',25),
('10008','NORMAL',11),
('10425','HIGH RARE',29),
('10107','NORMAL',10),
('10032','NORMAL',8),
('10142','NORMAL',5),
('10089','RARE',22),
('10094','NORMAL',7),
('10350','HIGH RARE',35),
('10366','NORMAL',13),
('10016','RARE',18),
('10385','RARE',16),
('10474','NORMAL',13),
('10287','RARE',18),
('10182','RARE',16),
('10136','HIGH RARE',27),
('10209','NORMAL',7),
('10170','NORMAL',10),
('10128','NORMAL',6),
('10433','HIGH RARE',26),
('10374','HIGH RARE',32),
('10218','NORMAL',14),
('10441','NORMAL',6),
('10349','RARE',16),
('10314','NORMAL',6),
('10337','NORMAL',6),
('10038','NORMAL',7),
('10365','NORMAL',12),
('10278','RARE',23),
('10251','NORMAL',14),
('10109','SUPER RARE',42),
('10017','HIGH RARE',30),
('10015','HIGH RARE',32),
('10028','NORMAL',7),
('10181','SUPER RARE',35),
('10333','SUPER RARE',43),
('10054','ULTRA RARE',46),
('10046','RARE',22),
('10066','NORMAL',12),
('10195','RARE',15),
('10283','NORMAL',14),
('10284','RARE',20),
('10321','SUPER RARE',38),
('10320','NORMAL',5),
('10371','HIGH RARE',28),
('10345','RARE',19),
('10021','RARE',20),
('10424','RARE',21),
('10398','RARE',16),
('10318','NORMAL',13),
('10458','RARE',18),
('10464','RARE',19),
('10233','NORMAL',9),
('10034','NORMAL',14),
('10171','NORMAL',13),
('10119','NORMAL',9),
('10226','RARE',16),
('10307','RARE',16),
('10402','NORMAL',7),
('10009','NORMAL',14),
('10055','NORMAL',7),
('10013','SUPER RARE',39),
('10313','NORMAL',15),
('10106','NORMAL',6),
('10316','NORMAL',12),
('10416','NORMAL',11),
('10057','NORMAL',5),
('10220','NORMAL',13),
('10340','NORMAL',11),
('10309','HIGH RARE',25),
('10070','SUPER RARE',39),
('10113','NORMAL',7),
('10364','NORMAL',10),
('10410','NORMAL',9),
('10419','HIGH RARE',25),
('10053','ULTRA RARE',45),
('10176','ULTRA RARE',49),
('10200','SUPER RARE',38),
('10234','RARE',16),
('10123','HIGH RARE',29),
('10304','ULTRA RARE',51),
('10435','ULTRA RARE',50),
('10434','NORMAL',9),
('10430','NORMAL',9),
('10379','NORMAL',14),
('10325','ULTRA RARE',46),
('10260','NORMAL',13),
('10300','RARE',20),
('10462','RARE',15),
('10072','HIGH RARE',26),
('10256','RARE',21),
('10115','RARE',19),
('10348','NORMAL',8),
('10339','NORMAL',8),
('10394','HIGH RARE',25),
('10047','HIGH RARE',27),
('10188','HIGH RARE',34),
('10132','RARE',21),
('10087','HIGH RARE',29),
('10202','RARE',19),
('10184','NORMAL',8),
('10103','RARE',19),
('10265','RARE',25),
('10266','RARE',18),
('10465','SUPER RARE',43),
('10466','RARE',22),
('10002','NORMAL',9),
('10289','NORMAL',9),
('10083','NORMAL',5),
('10079','NORMAL',11),
('10338','HIGH RARE',34),
('10336','HIGH RARE',34),
('10418','SUPER RARE',40),
('10323','ULTRA RARE',49),
('10403','NORMAL',14),
('10185','NORMAL',9),
('10308','HIGH RARE',28),
('10413','HIGH RARE',35),
('10415','SUPER RARE',43),
('10414','HIGH RARE',35),
('10186','SUPER RARE',37),
('10295','NORMAL',12),
('10297','RARE',23),
('10317','SUPER RARE',40),
('10108','SUPER RARE',41),
('10417','RARE',17),
('10172','NORMAL',6),
('10262','NORMAL',8),
('10261','RARE',20),
('10290','RARE',17),
('10384','RARE',15),
('10383','SUPER RARE',42),
('10110','HIGH RARE',34),
('10442','HIGH RARE',30),
('10129','RARE',15),
('10014','NORMAL',7),
('10235','NORMAL',6),
('10111','RARE',25),
('10357','RARE',15),
('10360','NORMAL',13),
('10306','RARE',17),
('10285','RARE',19),
('10343','HIGH RARE',27),
('10271','NORMAL',12),
('10003','NORMAL',9),
('10095','RARE',22),
('10096','HIGH RARE',28),
('10342','NORMAL',12),
('10327','NORMAL',14),
('10286','NORMAL',10),
('10273','NORMAL',10),
('10253','NORMAL',15),
('10061','SUPER RARE',36),
('10460','NORMAL',10),
('10459','NORMAL',13),
('10461','RARE',23),
('10296','RARE',21),
('10246','RARE',20),
('10204','RARE',24),
('10447','RARE',21),
('10429','RARE',23),
('10211','NORMAL',15),
('10193','NORMAL',9),
('10120','NORMAL',13),
('10101','NORMAL',14),
('10099','NORMAL',10),
('10241','RARE',20),
('10044','RARE',21),
('10043','HIGH RARE',30),
('10376','NORMAL',10),
('10377','NORMAL',8),
('10322','ULTRA RARE',50),
('10239','HIGH RARE',31),
('10039','NORMAL',8),
('10310','NORMAL',8),
('10247','NORMAL',14),
('10248','NORMAL',6),
('10221','NORMAL',9),
('10011','NORMAL',7),
('10140','NORMAL',11),
('10388','NORMAL',7),
('10121','RARE',16),
('10236','SUPER RARE',42),
('10102','HIGH RARE',26),
('10092','RARE',17),
('10194','RARE',17),
('10361','HIGH RARE',27),
('10354','SUPER RARE',36),
('10254','RARE',18),
('10222','RARE',17),
('10470','RARE',23),
('10059','RARE',17),
('10428','NORMAL',5),
('10471','NORMAL',14),
('10450','NORMAL',10),
('10432','RARE',22),
('10359','ULTRA RARE',51),
('10362','HIGH RARE',33),
('10454','RARE',21),
('10363','NORMAL',9),
('10436','NORMAL',12),
('10412','NORMAL',12),
('10040','NORMAL',15),
('10042','RARE',24),
('10237','RARE',25),
('10207','HIGH RARE',27),
('10208','HIGH RARE',31),
('10303','NORMAL',9),
('10468','NORMAL',13),
('10467','NORMAL',15),
('10294','NORMAL',15),
('10258','RARE',25),
('10056','NORMAL',14),
('10041','HIGH RARE',32),
('10255','SUPER RARE',44),
('10141','RARE',22),
('10133','RARE',23),
('10091','RARE',21),
('10090','RARE',20),
('10344','NORMAL',7),
('10330','NORMAL',11),
('10263','NORMAL',6),
('10249','NORMAL',13),
('10063','NORMAL',14),
('10052','SUPER RARE',39),
('10190','NORMAL',13),
('10174','NORMAL',12),
('10122','NORMAL',14),
('10029','RARE',23),
('10232','NORMAL',12),
('10104','RARE',24),
('10378','RARE',23),
('10126','HIGH RARE',31),
('10062','MYTHIC RARE',58),
('10203','HIGH RARE',33),
('10097','RARE',22),
('10280','NORMAL',10),
('10352','NORMAL',10),
('10277','NORMAL',7),
('10100','NORMAL',9),
('10451','NORMAL',12),
('10389','NORMAL',11),
('10264','NORMAL',11),
('10438','NORMAL',13),
('10177','NORMAL',13),
('10178','NORMAL',12),
('10372','RARE',24),
('10373','SUPER RARE',35),
('10130','NORMAL',7),
('10131','HIGH RARE',31),
('10341','SUPER RARE',44),
('10272','NORMAL',6),
('10117','SUPER RARE',44),
('10078','HIGH RARE',30),
('10084','NORMAL',10),
('10085','NORMAL',11),
('10217','SUPER RARE',40),
('10216','SUPER RARE',39),
('10324','ULTRA RARE',53),
('10006','NORMAL',14),
('10068','SUPER RARE',41),
('10400','HIGH RARE',26),
('10331','ULTRA RARE',52),
('10250','NORMAL',7),
('10022','NORMAL',8),
('10437','RARE',18),
('10426','RARE',18),
('10381','NORMAL',5),
('10179','NORMAL',8),
('10215','NORMAL',13),
('10214','HIGH RARE',31),
('10223','NORMAL',12),
('10269','SUPER RARE',38),
('10268','HIGH RARE',29),
('10473','HIGH RARE',28),
('10135','RARE',25),
('10206','NORMAL',11),
('10240','HIGH RARE',32),
('10238','NORMAL',12),
('10230','RARE',22),
('10227','RARE',24),
('10387','NORMAL',10),
('10281','SUPER RARE',41),
('10472','NORMAL',8),
('10455','RARE',24),
('10423','NORMAL',10),
('10456','NORMAL',7),
('10457','HIGH RARE',33),
('10224','RARE',24),
('10382','NORMAL',6),
('10393','HIGH RARE',33),
('10030','NORMAL',9),
('10391','RARE',19),
('10392','SUPER RARE',42),
('10311','MYTHIC RARE',65),
('10397','RARE',21),
('10242','RARE',15),
('10356','NORMAL',10),
('10274','NORMAL',6),
('10192','NORMAL',15),
('10093','NORMAL',8),
('10312','ULTRA RARE',47),
('10243','NORMAL',14),
('10231','HIGH RARE',35),
('10399','SUPER RARE',43),
('10050','NORMAL',9),
('10073','HIGH RARE',33),
('10229','HIGH RARE',34),
('10012','NORMAL',12),
('10219','NORMAL',8),
('10305','NORMAL',9),
('10443','NORMAL',8),
('10024','SUPER RARE',41),
('10446','NORMAL',13),
('10427','NORMAL',14),
('10411','NORMAL',9),
('10058','ULTRA RARE',54),
('10395','NORMAL',15),
('10213','SUPER RARE',44),
('10175','RARE',19),
('10007','RARE',20),
('10257','HIGH RARE',31),
('10291','ULTRA RARE',54),
('10326','MYTHIC RARE',55),
('10288','HIGH RARE',30),
('10282','NORMAL',11),
('10405','RARE',18),
('10452','HIGH RARE',34),
('10370','RARE',19),
('10368','RARE',19),
('10369','SUPER RARE',36),
('10358','ULTRA RARE',55),
('10351','NORMAL',10),
('10449','NORMAL',6),
('10422','NORMAL',8),
('10421','NORMAL',13),
('10396','NORMAL',15),
('10127','SUPER RARE',44),
('10439','SUPER RARE',45),
('10355','NORMAL',14),
('10367','RARE',25),
('10440','ULTRA RARE',53),
('10267','HIGH RARE',35)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;$vr_statement$;
  execute $vr_statement$-- 1) 테이블 (모두 본인 행만 읽기 · 쓰기는 RPC 만)
create table if not exists public.pvp_decks (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null check (league in ('open','hr')),
  mode text not null check (mode in ('1v1','3v3')),
  slot smallint not null check (slot between 0 and 2),
  uids jsonb not null default '[]'::jsonb,
  snap jsonb not null default '[]'::jsonb,      -- 등록 시점 방어 덱 스냅샷 (서버가 story_progress 에서 복사)
  cost int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, league, mode, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_ratings (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null,
  rating int not null default 1000, wins int not null default 0, losses int not null default 0,
  def_wins int not null default 0, def_losses int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, league, mode, season));$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, day date not null,
  opp_user uuid, opp_name text, seed bigint not null,
  my_snap jsonb not null, opp_snap jsonb not null,
  my_rating int not null, opp_rating int not null, dw int not null, dl int not null,
  created_at timestamptz not null default now(),
  reported_at timestamptz, wins smallint, losses smallint, win boolean not null default false,
  verified boolean);$vr_statement$;
  execute $vr_statement$-- tools/pvp_verify.mjs 재검증 결과
create index if not exists pvp_attempts_user_day on public.pvp_attempts (user_id, day);$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_reward_table (
  league text not null, mode text not null, rank_from int not null, rank_to int not null, reward jsonb not null,
  primary key (league, mode, rank_from));$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_reward_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, rank int not null, reward jsonb not null,
  claimed_at timestamptz not null default now(), primary key (user_id, league, mode, season));$vr_statement$;
  execute $vr_statement$alter table public.pvp_decks enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_ratings enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_attempts enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_reward_table enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_reward_claims enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_decks_own on public.pvp_decks;$vr_statement$;
  execute $vr_statement$create policy pvp_decks_own on public.pvp_decks for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_ratings_own on public.pvp_ratings;$vr_statement$;
  execute $vr_statement$create policy pvp_ratings_own on public.pvp_ratings for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_attempts_own on public.pvp_attempts;$vr_statement$;
  execute $vr_statement$create policy pvp_attempts_own on public.pvp_attempts for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_reward_read on public.pvp_reward_table;$vr_statement$;
  execute $vr_statement$create policy pvp_reward_read on public.pvp_reward_table for select using (true);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_claims_own on public.pvp_reward_claims;$vr_statement$;
  execute $vr_statement$create policy pvp_claims_own on public.pvp_reward_claims for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$revoke insert, update, delete on public.pvp_decks, public.pvp_ratings, public.pvp_attempts, public.pvp_reward_table, public.pvp_reward_claims, public.pvp_card_meta from anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 시즌 보상표 (양 리그·모드 동일): gold / blood / shard(이상한 조각) / soul = player_wallet, tickets = 소환권(story_gacha.tickets)
insert into public.pvp_reward_table (league, mode, rank_from, rank_to, reward)
select l, m, f, t, r::jsonb from (values ('open'), ('hr')) a(l), (values ('1v1'), ('3v3')) b(m),
  (values (1, 1, '{"gold":3000,"soul":50,"tickets":50}'), (2, 3, '{"gold":2000,"soul":30,"tickets":30}'), (4, 10, '{"gold":1200,"soul":15,"tickets":20}'),
          (11, 50, '{"gold":600,"shard":20,"tickets":10}'), (51, 100, '{"gold":300,"shard":10,"tickets":10}'), (101, 1000000, '{"gold":100,"tickets":5}')) c(f, t, r)
on conflict (league, mode, rank_from) do update set rank_to = excluded.rank_to, reward = excluded.reward;$vr_statement$;
  execute $vr_statement$-- 2) 공통
create or replace function public._pvp_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$-- 주간 시즌 = 한국 시간 월요일 00:00 시작 (ISO 주)
create or replace function public._pvp_season() returns date language sql stable as $$ select date_trunc('week', now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_ok(p_league text, p_mode text) returns int language plpgsql immutable as $$
begin
  if p_league not in ('open','hr') then raise exception 'bad league'; end if;
  if p_mode = '1v1' then return 1; elsif p_mode = '3v3' then return 3; end if;
  raise exception 'bad mode';
end $$;$vr_statement$;
  execute $vr_statement$-- 덱 스냅샷: 내가 가진 카드(uid)만, 1~5장, 같은 카드 id 중복 불가, HR 리그는 HR 이하 + 코스트 합 150 이하
create or replace function public._pvp_snap(p_user uuid, p_uids jsonb, p_league text) returns jsonb language plpgsql stable set search_path = public as $$
declare owned jsonb; out jsonb := '[]'::jsonb; u text; o jsonb; m pvp_card_meta; cost int := 0; ids text[] := '{}';
begin
  if jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) not between 1 and 5 then raise exception 'deck size'; end if;
  select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' else '[]'::jsonb end into owned from story_progress where user_id = p_user;
  for u in select jsonb_array_elements_text(p_uids) loop
    if u like 'guest:%' then raise exception 'card not owned'; end if;
    select x into o from jsonb_array_elements(coalesce(owned, '[]'::jsonb)) x where x->>'uid' = u limit 1;
    if o is null then raise exception 'card not owned'; end if;
    select * into m from pvp_card_meta where id = o->>'id';
    if m.id is null then raise exception 'unknown card'; end if;
    if m.id = any(ids) then raise exception 'duplicate card'; end if;
    if p_league = 'hr' and m.grade not in ('NORMAL','RARE','HIGH RARE') then raise exception 'grade not allowed'; end if;
    ids := ids || m.id; cost := cost + m.cost;
    out := out || jsonb_build_object('uid', u, 'id', o->>'id', 'level', coalesce((o->>'level')::int, 1), 'ex', coalesce((o->>'ex')::int, 0),
      'exb', coalesce((o->>'exb')::numeric, 0), 'boost', coalesce(o->'boost', '{}'::jsonb), 'skillLv', coalesce(o->'skillLv', '{}'::jsonb));
  end loop;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', out, 'cost', cost);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_rating(p_user uuid, p_league text, p_mode text) returns pvp_ratings language plpgsql set search_path = public as $$
declare r pvp_ratings;
begin
  insert into pvp_ratings (user_id, league, mode, season) values (p_user, p_league, p_mode, _pvp_season()) on conflict do nothing;
  select * into r from pvp_ratings where user_id = p_user and league = p_league and mode = p_mode and season = _pvp_season() for update;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_snap(uuid, jsonb, text), public._pvp_rating(uuid, text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 덱 등록 (PvP 전용 · 마이 덱과 별개). p_uids = [] 이면 그 슬롯 삭제
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
  s := _pvp_snap(uid, p_uids, p_league);
  -- 3v3: 같은 카드는 세 덱 중 한 곳에만
  select coalesce(array_agg(x->>'id'), '{}') into other from pvp_decks d, jsonb_array_elements(d.snap) x
    where d.user_id = uid and d.league = p_league and d.mode = p_mode and d.slot <> p_slot;
  if exists (select 1 from jsonb_array_elements(s->'cards') x where x->>'id' = any(other)) then raise exception 'card used in another deck'; end if;
  insert into pvp_decks (user_id, league, mode, slot, uids, snap, cost, updated_at)
  values (uid, p_league, p_mode, p_slot, p_uids, s->'cards', (s->>'cost')::int, now())
  on conflict (user_id, league, mode, slot) do update set uids = excluded.uids, snap = excluded.snap, cost = excluded.cost, updated_at = now();
  return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', s->'cards', 'cost', (s->>'cost')::int);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 상태: 오늘 남은 횟수(리그·모드별 10회) · 내 레이팅 · 내 덱 · 시즌
create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  return jsonb_build_object('left', greatest(0, 10 - used), 'max', 10, 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'));
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 매칭 시작: 횟수 차감 · 내 덱 재검사(지금 가진 카드로) · 비슷한 레이팅 상대(방어 덱 스냅샷) · seed 발급
--    패배 처리를 먼저 반영(미보고 = 패배). 승리 보고 시 되돌리고 승리 반영
-- 추가 도전권 (gem.sql 의 심연석 구매로 늘어남). 오늘(KST) 리그·모드별 추가 횟수
create table if not exists public.pvp_bonus_tries (
  user_id uuid not null references auth.users(id) on delete cascade, league text not null, mode text not null, day date not null,
  n int not null default 0 check (n >= 0), primary key (user_id, league, mode, day));$vr_statement$;
  execute $vr_statement$alter table public.pvp_bonus_tries enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.pvp_bonus_tries from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_extra(p_uid uuid, p_league text, p_mode text) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select n from pvp_bonus_tries where user_id = p_uid and league = p_league and mode = p_mode and day = (now() at time zone 'Asia/Seoul')::date), 0) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_extra(uuid, text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_start(p_league text, p_mode text) returns jsonb
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
    mine := mine || jsonb_build_array(_pvp_snap(uid, d.uids, p_league)->'cards');
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
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 결과 보고: 시작 후 1시간 안, 한 번만. 승리면 선반영한 패배를 되돌리고 승리 반영
create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a pvp_attempts; n int; need int; v_win boolean; r int;
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
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end);
end $$;$vr_statement$;
  execute $vr_statement$-- 7) 랭킹 (리그·모드·시즌별 상위 100 + 내 순위). 1판 이상 한 유저만
create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := coalesce(p_season, _pvp_season()); top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses, 'me', t.user_id = uid) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', s, 'top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$-- 8) 지난 시즌 보상 받기 (시즌 끝난 뒤 1회). 보상표 = pvp_reward_table (임시안)
create or replace function public.pvp_claim_reward(p_league text, p_mode text, p_season date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rk int; rw jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _pvp_ok(p_league, p_mode);
  if p_season is null or p_season >= _pvp_season() then raise exception 'season not ended'; end if;
  if exists (select 1 from pvp_reward_claims where user_id = uid and league = p_league and mode = p_mode and season = p_season) then raise exception 'already claimed'; end if;
  select t.rk into rk from (select user_id, rank() over (order by rating desc, wins desc) rk from pvp_ratings
    where league = p_league and mode = p_mode and season = p_season and wins + losses > 0) t where t.user_id = uid;
  if rk is null then raise exception 'not ranked'; end if;
  select reward into rw from pvp_reward_table where league = p_league and mode = p_mode and rk between rank_from and rank_to order by rank_from limit 1;
  if rw is null then raise exception 'no reward'; end if;
  insert into pvp_reward_claims (user_id, league, mode, season, rank, reward) values (uid, p_league, p_mode, p_season, rk, rw);
  if rw - 'tickets' <> '{}'::jsonb then perform _wallet_add(uid, rw - 'tickets', 'pvp_season'); end if;
  if coalesce((rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (rw->>'tickets')::int, updated_at = now() where user_id = uid;
  end if;
  return jsonb_build_object('ok', true, 'rank', rk, 'reward', rw);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_status(text, text), public.pvp_start(text, text),
  public.pvp_report(bigint, int, int), public.pvp_claim_reward(text, text, date) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_status(text, text), public.pvp_start(text, text),
  public.pvp_report(bigint, int, int), public.pvp_claim_reward(text, text, date) to authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_rankings(text, text, date) from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_rankings(text, text, date) to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch7.sql =====
-- =====================================================================
-- 스토리 챕터 7 「THE BELL JAR」 (단일 루트: 민유연 · 5페이즈 유가을 단독 · 7페이즈 강태안/강태준/이민수/김철민, 페이즈 10개)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch6.sql 까지 적용된 상태
-- 챕터 2~6과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 재화 드롭·소탕·소환권·행동력은 기존 함수가 챕터 번호로 처리
-- 페이즈 열림: 챕터 6 전체 클리어 후 (story_start_phase 의 기존 조건)
-- 적 수: 6페이즈 1명(유가을), 7·9페이즈 4명, 나머지 5명
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (7,1,'normal',3,null,5), (7,2,'normal',3,null,5), (7,3,'normal',3,null,5), (7,4,'normal',3,null,5), (7,5,'normal',3,null,5),
  (7,6,'normal',3,null,1), (7,7,'normal',3,null,4), (7,8,'normal',3,null,5), (7,9,'normal',3,null,4), (7,10,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 7 | 10
-- 출전 조건(남성/여성 금지·최대 장수·추가 편성 금지)·필수 카드 레벨·적 스토리 레벨·NPC 카드는 클라이언트 데이터(js/story-data-ch7.js, data/npc_cards.csv)에만 있음


-- ===== SOURCE: cards_1026.sql =====
-- =====================================================================
-- VR: Abyss Gate - CH7 빌런 스킬 (2026-10-26)
-- 강태준(10019) 「에이스의 힘이다」 · 강태안(10018) 「너한테만 통하는 기술이야」 · 이민수(10299) 「나? 폭격기야~」 · 김철민(10074) 「약해보이냐? 진짜?」
-- 액티브 1번 스킬 해금 Lv1 → 스킬 레벨업(story_skill_levelup) 메타. 스탯·뽑기 풀 변경 없음
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10019',1,1), ('10018',1,1), ('10299',1,1), ('10074',1,1)
on conflict (card_id, idx) do update set unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$-- 확인용: 4행
select card_id, idx, unlock from public.story_skill_meta where card_id in ('10019','10018','10299','10074') order by card_id;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: grade_lr.sql =====
-- =====================================================================
-- 2026-10-27 LEGENDARY RARE(LR) 등급 추가: 등급 check 제약에 LR 허용. 여러 번 실행해도 안전.
--   LR 카드(장서아 10334)는 NPC 전용이라 카드 풀·뽑기·PVP 메타에는 넣지 않음 (제약만 열어 둠).
--   보상 등급(reward_grade)·아케이드 갤러리(card_pool) 제약은 그대로 (LR 보상·뽑기 없음).
-- =====================================================================
alter table public.story_card_pool drop constraint if exists story_card_pool_grade_check;$vr_statement$;
  execute $vr_statement$alter table public.story_card_pool add constraint story_card_pool_grade_check
  check (grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'));$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: pvp_tier.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _pvp_grant, pvp_report, pvp_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- PvP 티어 · 시즌 티어 보상 · 연승 보너스 (pvp.sql 다음에 실행). 여러 번 실행해도 안전.
--   티어(시즌 레이팅): 브론즈 <950 · 실버 950 · 골드 1050 · 플래티넘 1150 · 다이아 1250 · 심연 1400
--   시즌 티어 보상: 지난 시즌 3판 이상 → pvp_claim_tier 로 1회 (리그·모드·시즌별). 심연 = 한정 칭호·프레임(pvp_titles)
--   연승: 이번 시즌 연속 승리 3·5·10 달성 판의 결과 보고 때 서버가 바로 지급 (보고는 판당 1번 → 중복 없음)
--   연승 계산: 같은 리그·모드·시즌 기록에서 가장 최근 패배(미보고 판 = 패배) 이후 승리 수. 진행 중(1시간 안 미보고) 판은 제외
-- =====================================================================

-- 1) 표
create table if not exists public.pvp_tier_table (
  tier text primary key, ord int not null, min_rating int not null, reward jsonb not null);$vr_statement$;
  execute $vr_statement$insert into public.pvp_tier_table (tier, ord, min_rating, reward) values
  ('bronze',   0,    0, '{"gold":200}'),
  ('silver',   1,  950, '{"gold":400,"shard":5,"gem":50}'),
  ('gold',     2, 1050, '{"gold":800,"soul":5,"tickets":3,"gem":100}'),
  ('platinum', 3, 1150, '{"gold":1500,"soul":10,"tickets":5,"gem":200}'),
  ('diamond',  4, 1250, '{"gold":2500,"soul":20,"tickets":10,"gem":400}'),
  ('abyss',    5, 1400, '{"gold":4000,"soul":35,"tickets":20,"gem":1000,"title":"abyss"}')
on conflict (tier) do update set ord = excluded.ord, min_rating = excluded.min_rating, reward = excluded.reward;$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_streak_table (n int primary key, reward jsonb not null);$vr_statement$;
  execute $vr_statement$insert into public.pvp_streak_table (n, reward) values
  (3, '{"gold":300}'), (5, '{"gold":600,"soul":5}'), (10, '{"gold":1500,"soul":15,"tickets":3,"gem":30}')
on conflict (n) do update set reward = excluded.reward;$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_tier_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, tier text not null, rating int not null, reward jsonb not null,
  claimed_at timestamptz not null default now(), primary key (user_id, league, mode, season));$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_titles (
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, league text not null, mode text not null, season date not null,
  granted_at timestamptz not null default now(), primary key (user_id, title, league, mode, season));$vr_statement$;
  execute $vr_statement$alter table public.pvp_attempts add column if not exists streak int;$vr_statement$;
  execute $vr_statement$-- 보고 시점 연승 (승리 판만)
alter table public.pvp_attempts add column if not exists streak_reward jsonb;$vr_statement$;
  execute $vr_statement$-- 연승 보너스 지급 내역

alter table public.pvp_tier_table enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_streak_table enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_tier_claims enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.pvp_titles enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_tier_read on public.pvp_tier_table;$vr_statement$;
  execute $vr_statement$create policy pvp_tier_read on public.pvp_tier_table for select using (true);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_streak_read on public.pvp_streak_table;$vr_statement$;
  execute $vr_statement$create policy pvp_streak_read on public.pvp_streak_table for select using (true);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_tier_claims_own on public.pvp_tier_claims;$vr_statement$;
  execute $vr_statement$create policy pvp_tier_claims_own on public.pvp_tier_claims for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_titles_own on public.pvp_titles;$vr_statement$;
  execute $vr_statement$create policy pvp_titles_own on public.pvp_titles for select using (auth.uid() = user_id);$vr_statement$;
  execute $vr_statement$revoke insert, update, delete on public.pvp_tier_table, public.pvp_streak_table, public.pvp_tier_claims, public.pvp_titles from anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 내부 함수
create or replace function public._pvp_tier(p_rating int) returns text language sql stable set search_path = public as $$
  select tier from pvp_tier_table where min_rating <= coalesce(p_rating, 1000) order by min_rating desc limit 1 $$;$vr_statement$;
  execute $vr_statement$-- 보상 지급: gold/blood/shard/soul → 지갑, tickets → 소환권, title → pvp_titles
create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = public as $$
declare w jsonb := p_rw - 'tickets' - 'title' - 'gem';
begin
  if w <> '{}'::jsonb then perform _wallet_add(p_uid, w, p_reason); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 and to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is not null then   -- 심연석 (gem.sql)
    perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, case when p_reason = 'pvp_tier' then 'pvp_tier:' || p_league || ':' || p_mode || ':' || p_season end, jsonb_build_object('league', p_league, 'mode', p_mode, 'season', p_season));
  end if;
  if p_rw ? 'title' then
    insert into pvp_titles (user_id, title, league, mode, season) values (p_uid, p_rw->>'title', p_league, p_mode, p_season) on conflict do nothing;
  end if;
end $$;$vr_statement$;
  execute $vr_statement$-- 연승 (p_upto: 이 판 id 까지. null = 전부, 진행 중 판 제외)
create or replace function public._pvp_streak(p_uid uuid, p_league text, p_mode text, p_season date, p_upto bigint default null) returns int
language sql stable set search_path = public as $$
  select count(*)::int from pvp_attempts a
  where a.user_id = p_uid and a.league = p_league and a.mode = p_mode and a.season = p_season and a.win
    and (p_upto is null or a.id <= p_upto)
    and a.id > coalesce((select max(b.id) from pvp_attempts b where b.user_id = p_uid and b.league = p_league and b.mode = p_mode and b.season = p_season
                          and not b.win and (p_upto is null or b.id <= p_upto)
                          and (b.reported_at is not null or now() - b.created_at > interval '1 hour')), 0) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_tier(int), public._pvp_grant(uuid, jsonb, text, text, text, date), public._pvp_streak(uuid, text, text, date, bigint) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 상태: 기존 + 연승 · 심연 칭호 · 티어표 · 연승표 · 지난 시즌 미수령 티어 보상
create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb; prev pvp_ratings; pend jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  select * into prev from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season() - 7;
  if prev.user_id is not null and prev.wins + prev.losses >= 3
     and not exists (select 1 from pvp_tier_claims where user_id = uid and league = p_league and mode = p_mode and season = prev.season) then
    pend := jsonb_build_object('season', prev.season, 'rating', prev.rating, 'tier', _pvp_tier(prev.rating));
  end if;
  return jsonb_build_object('left', greatest(0, 10 + _pvp_extra(uid, p_league, p_mode) - used), 'max', 10 + _pvp_extra(uid, p_league, p_mode), 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'),
    'tier', _pvp_tier(r.rating), 'streak', _pvp_streak(uid, p_league, p_mode, _pvp_season()),
    'abyss', exists (select 1 from pvp_titles where user_id = uid and title = 'abyss'),
    'tiers', (select jsonb_agg(jsonb_build_object('tier', tier, 'min', min_rating, 'reward', reward) order by ord) from pvp_tier_table),
    'streaks', (select jsonb_agg(jsonb_build_object('n', s.n, 'reward', s.reward) order by s.n) from pvp_streak_table s),
    'pending', pend);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 결과 보고: 기존 + 연승 계산·보너스 지급
create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    if srw is not null then perform _pvp_grant(uid, srw, 'pvp_streak', a.league, a.mode, a.season); end if;
    update pvp_attempts set streak = sk, streak_reward = srw where id = p_id;
    -- 조직 세력 (guild.sql): 승리당 +10 (하루 상한은 _guild_feed 가 처리)
    if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform _guild_feed(uid, 'pvp', 10); end if;
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end,
    'tier', _pvp_tier(r), 'streak', sk, 'streak_reward', srw);
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 랭킹: 기존 + 티어 · 심연 칭호
create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := coalesce(p_season, _pvp_season()); top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses,
           'me', t.user_id = uid, 'tier', _pvp_tier(rating), 'abyss', exists (select 1 from pvp_titles x where x.user_id = t.user_id and x.title = 'abyss')) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses, 'tier', _pvp_tier(rating)) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', s, 'top', top, 'me', mine);
end $$;$vr_statement$;
  execute $vr_statement$-- 6) 지난 시즌 티어 보상 받기 (리그·모드·시즌별 1회, 3판 이상)
create or replace function public.pvp_claim_tier(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := _pvp_season() - 7; r pvp_ratings; t text; rw jsonb; ok boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _pvp_ok(p_league, p_mode);
  perform pg_advisory_xact_lock(hashtext('pvptier:' || uid::text));
  select * into r from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = s;
  if r.user_id is null or r.wins + r.losses < 3 then raise exception 'not eligible'; end if;
  t := _pvp_tier(r.rating);
  select reward into rw from pvp_tier_table where tier = t;
  insert into pvp_tier_claims (user_id, league, mode, season, tier, rating, reward) values (uid, p_league, p_mode, s, t, r.rating, rw)
    on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already claimed'; end if;
  perform _pvp_grant(uid, rw, 'pvp_tier', p_league, p_mode, s);
  return jsonb_build_object('ok', true, 'season', s, 'tier', t, 'rating', r.rating, 'reward', rw);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_status(text, text), public.pvp_report(bigint, int, int), public.pvp_claim_tier(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_status(text, text), public.pvp_report(bigint, int, int), public.pvp_claim_tier(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_rankings(text, text, date) from public;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_rankings(text, text, date) to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gem.sql =====
-- =====================================================================
-- 심연석 🔮 (유료 재화) 1단계 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(지갑) · phaseE_2.sql(행동력) · story_gacha.sql(소환권) · admin.sql · pvp.sql · pvp_tier.sql
-- 잔액: player_wallet.gem_paid(결제) + gem_free(무료). 화면에는 합계 하나. 사용은 무료 → 유료 순서
-- 쓰기는 전부 서버 함수로만: _gem_add / _gem_spend (클라이언트 호출 불가), 모든 변동은 gem_ledger 에 기록
--   gem_ledger.ref 는 유저별 고유 → 같은 보상(챕터·로그인·시즌 티어)·나중의 결제 주문이 두 번 들어가지 않음
-- 공개 RPC: gem_status() (챕터 첫 클리어·7일 연속 접속 보상 지급 포함) · gem_buy(item[, league, mode])
-- 관리자: admin_grant_gem(user, amount, reason) · admin_gem_ledger(user, limit)
-- 나중 결제: 결제 확인(Edge Function, service role)이 _gem_add(uid, 0, paid, 'iap', 'iap:<주문번호>', ...) 호출 → 환불은 같은 주문의 paid 만 회수
-- 확인용: select public.gem_status();
-- =====================================================================

-- 1) 잔액 (지갑에 열 추가)
alter table public.player_wallet add column if not exists gem_paid bigint not null default 0;$vr_statement$;
  execute $vr_statement$alter table public.player_wallet add column if not exists gem_free bigint not null default 0;$vr_statement$;
  execute $vr_statement$do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'player_wallet_gem_chk') then
    alter table public.player_wallet add constraint player_wallet_gem_chk check (gem_paid >= 0 and gem_free >= 0);
  end if;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 원장 (클라이언트 접근 불가 — 본인 기록은 gem_status 로만)
create table if not exists public.gem_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  d_free     int not null default 0,
  d_paid     int not null default 0,
  free_after bigint not null,
  paid_after bigint not null,
  reason     text not null check (char_length(reason) <= 40),   -- chapter_clear · login_7 · pvp_tier · pvp_streak · buy:<item> · admin · iap · refund
  ref        text not null default gen_random_uuid()::text,       -- 고유 참조 (chapter:3 · login:2026-10-27 · pvp_tier:open:1v1:2026-10-19 · iap:<주문>)
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, ref)
);$vr_statement$;
  execute $vr_statement$create index if not exists gem_ledger_user_idx on public.gem_ledger (user_id, created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.gem_ledger enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gem_ledger from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 상점 가격표 (한 곳에서 조정). step = 오늘 n번째 구매마다 가격 +step, daily_max = 하루 최대 (null = 무제한)
create table if not exists public.gem_shop (
  item      text primary key,
  ord       int not null default 0,
  price     int not null check (price > 0),
  step      int not null default 0 check (step >= 0),
  daily_max int,
  gives     jsonb not null,
  active    boolean not null default true
);$vr_statement$;
  execute $vr_statement$insert into public.gem_shop (item, ord, price, step, daily_max, gives) values
  ('ticket',   1,  150,  0, null, '{"tickets":1}'),
  ('pull10',   2, 1500,  0, null, '{"tickets":10}'),
  ('stamina',  3,  100, 50,    5, '{"stamina":"full"}'),
  ('pvp_try',  4,   50,  0,    3, '{"pvp_try":1}'),
  ('gold10k',  5,  100,  0, null, '{"gold":10000}')
on conflict (item) do update set ord = excluded.ord, price = excluded.price, step = excluded.step, daily_max = excluded.daily_max, gives = excluded.gives;$vr_statement$;
  execute $vr_statement$alter table public.gem_shop enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gem_shop from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 연속 접속 (7일마다 +30)
create table if not exists public.gem_login (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  last_day date not null,
  streak   int not null default 1
);$vr_statement$;
  execute $vr_statement$alter table public.gem_login enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gem_login from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 내부 도우미
create or replace function public._gem_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gem_chapter_reward() returns int language sql immutable as $$ select 50 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gem_login_reward() returns int language sql immutable as $$ select 30 $$;$vr_statement$;
  execute $vr_statement$-- 증감 (양수 = 지급). p_ref 가 이미 있으면 아무것도 안 하고 null (중복 방지). 잔액 부족이면 'not enough gem' 예외 → 전체 롤백
create or replace function public._gem_add(p_uid uuid, p_free int, p_paid int, p_reason text, p_ref text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w player_wallet; f bigint; p bigint;
begin
  if p_uid is null then raise exception 'login required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if coalesce(p_free, 0) = 0 and coalesce(p_paid, 0) = 0 then return null; end if;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  if p_ref is not null and exists (select 1 from gem_ledger where user_id = p_uid and ref = p_ref) then return null; end if;
  f := w.gem_free + coalesce(p_free, 0); p := w.gem_paid + coalesce(p_paid, 0);
  if f < 0 or p < 0 then raise exception 'not enough gem'; end if;
  update player_wallet set gem_free = f, gem_paid = p, updated_at = now() where user_id = p_uid;
  insert into gem_ledger (user_id, d_free, d_paid, free_after, paid_after, reason, ref, meta)
  values (p_uid, coalesce(p_free, 0), coalesce(p_paid, 0), f, p, left(btrim(p_reason), 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  return jsonb_build_object('gem', f + p, 'free', f, 'paid', p, 'd_free', coalesce(p_free, 0), 'd_paid', coalesce(p_paid, 0));
end $$;$vr_statement$;
  execute $vr_statement$-- 사용: 무료 먼저, 모자라면 유료
create or replace function public._gem_spend(p_uid uuid, p_amount int, p_reason text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w player_wallet; fp int;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'invalid amount'; end if;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  if w.gem_free + w.gem_paid < p_amount then raise exception 'not enough gem'; end if;
  fp := least(w.gem_free, p_amount)::int;
  return _gem_add(p_uid, -fp, -(p_amount - fp), p_reason, null, p_meta);
end $$;$vr_statement$;
  execute $vr_statement$-- 오늘(KST) 이 상품을 몇 번 샀는지
create or replace function public._gem_bought(p_uid uuid, p_item text) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from gem_ledger where user_id = p_uid and reason = 'buy:' || p_item and created_at >= (_gem_day()::timestamp at time zone 'Asia/Seoul') $$;$vr_statement$;
  execute $vr_statement$-- 화면용 상태: 잔액 · 상점(오늘 가격·남은 횟수) · 최근 20건
create or replace function public._gem_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w player_wallet;
begin
  select * into w from player_wallet where user_id = p_uid;
  return jsonb_build_object('ok', true, 'gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'free', coalesce(w.gem_free, 0), 'paid', coalesce(w.gem_paid, 0),
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price + s.step * least(b.n, coalesce(s.daily_max, b.n)), 'gives', s.gives,
                     'left', case when s.daily_max is null then null else greatest(0, s.daily_max - b.n) end) order by s.ord), '[]'::jsonb)
             from gem_shop s cross join lateral (select _gem_bought(p_uid, s.item) n) b where s.active),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('d', x.d_free + x.d_paid, 'after', x.free_after + x.paid_after, 'reason', x.reason, 'at', x.created_at) order by x.id desc), '[]'::jsonb)
            from (select * from gem_ledger where user_id = p_uid order by id desc limit 20) x),
    'login_streak', coalesce((select streak from gem_login where user_id = p_uid and last_day >= _gem_day() - 1), 0));
end $$;$vr_statement$;
  execute $vr_statement$-- 무료 획득 동기화: 챕터 첫 클리어(+50, 소급 포함) · 7일 연속 접속(+30). 반환 새로 받은 목록
create or replace function public._gem_sync(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; ch int; r jsonb; out jsonb := '[]'::jsonb; lg gem_login; today date := _gem_day();
begin
  select data into d from story_progress where user_id = p_uid;
  if d is not null then
    for ch in
      select c.chapter from story_phase_config c group by c.chapter
      having bool_and(case when jsonb_typeof(d->'cleared'->(c.chapter::text)) = 'array'
                           then (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase) or (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase::text) else false end)
      order by c.chapter
    loop
      r := _gem_add(p_uid, _gem_chapter_reward(), 0, 'chapter_clear', 'chapter:' || ch, jsonb_build_object('chapter', ch));
      if r is not null then out := out || jsonb_build_array(jsonb_build_object('reason', 'chapter_clear', 'chapter', ch, 'gem', _gem_chapter_reward())); end if;
    end loop;
  end if;
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
  execute $vr_statement$revoke all on function public._gem_add(uuid, int, int, text, text, jsonb), public._gem_spend(uuid, int, text, jsonb), public._gem_bought(uuid, text),
  public._gem_json(uuid), public._gem_sync(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 공개 RPC
-- 내 심연석 (+ 무료 획득 지급). 반환 { ok, gem, free, paid, shop, log, login_streak, granted:[...] }
create or replace function public.gem_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  g := _gem_sync(uid);
  return _gem_json(uid) || jsonb_build_object('granted', g);
end $$;$vr_statement$;
  execute $vr_statement$-- 구매. 가격·지급량은 서버 표(gem_shop)가 기준 (클라이언트는 상품 키만 보냄). pvp_try 는 리그·모드 필요
-- 오류: invalid item · daily limit · not enough gem · stamina full · (pvp) invalid league/mode
create or replace function public.gem_buy(p_item text, p_league text default null, p_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s gem_shop; n int; price int; res jsonb := '{}'::jsonb; ps player_state; mx int; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into s from gem_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  n := _gem_bought(uid, s.item);
  if s.daily_max is not null and n >= s.daily_max then raise exception 'daily limit'; end if;
  price := s.price + s.step * n;
  -- 지급 조건 먼저 확인 (실패하면 심연석도 안 빠짐)
  if s.item = 'stamina' then
    ps := _player_sync(uid); mx := _stamina_max(ps.level);
    if ps.stamina >= mx then raise exception 'stamina full'; end if;
  elsif s.item = 'pvp_try' then
    perform _pvp_ok(p_league, p_mode);
  end if;
  perform _gem_spend(uid, price, 'buy:' || s.item, jsonb_build_object('price', price, 'gives', s.gives) || case when s.item = 'pvp_try' then jsonb_build_object('league', p_league, 'mode', p_mode) else '{}'::jsonb end);
  if s.gives ? 'tickets' then
    insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (s.gives->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  if s.gives ? 'gold' then res := res || jsonb_build_object('wallet', _wallet_add(uid, jsonb_build_object('gold', (s.gives->>'gold')::int), 'gem_buy')); end if;
  if s.gives ? 'stamina' then res := res || jsonb_build_object('stamina', _player_stamina_add(uid, mx)); end if;
  if s.gives ? 'pvp_try' then
    insert into pvp_bonus_tries (user_id, league, mode, day, n) values (uid, p_league, p_mode, _pvp_day(), 1)
      on conflict (user_id, league, mode, day) do update set n = pvp_bonus_tries.n + 1;
    res := res || jsonb_build_object('pvp_extra', _pvp_extra(uid, p_league, p_mode));
  end if;
  return _gem_json(uid) || res || jsonb_build_object('item', s.item, 'price', price);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gem_status(), public.gem_buy(text, text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gem_status(), public.gem_buy(text, text, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 7) 지갑 상태에 심연석 추가 (합계 gem + 내역 분리)
create or replace function public.wallet_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); w player_wallet;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into w from player_wallet where user_id = uid;
  return jsonb_build_object('ok', true, 'gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0),
    'gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'gem_free', coalesce(w.gem_free, 0), 'gem_paid', coalesce(w.gem_paid, 0));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.wallet_status() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.wallet_status() to authenticated;$vr_statement$;
  execute $vr_statement$-- 8) 관리자: 무료 심연석 지급(+)/회수(−) · 원장 보기
create or replace function public.admin_grant_gem(p_user uuid, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare bef bigint; res jsonb;
begin
  perform public._admin_guard();
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'amount must be ±1..1000000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  select coalesce(gem_free, 0) + coalesce(gem_paid, 0) into bef from player_wallet where user_id = p_user;
  bef := coalesce(bef, 0);
  res := public._gem_add(p_user, p_amount, 0, 'admin', null, jsonb_build_object('by', auth.jwt()->>'email', 'memo', left(btrim(p_reason), 200)));
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_gem', p_user, p_amount, left(btrim(p_reason), 200), least(bef, 2147483647)::int, least((res->>'gem')::bigint, 2147483647)::int);
  return jsonb_build_object('ok', true, 'before', bef, 'after', (res->>'gem')::bigint, 'free', (res->>'free')::bigint, 'paid', (res->>'paid')::bigint);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_gem_ledger(p_user uuid, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare w player_wallet;
begin
  perform public._admin_guard();
  select * into w from player_wallet where user_id = p_user;
  return jsonb_build_object('gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'free', coalesce(w.gem_free, 0), 'paid', coalesce(w.gem_paid, 0),
    'log', coalesce((select jsonb_agg(jsonb_build_object('d_free', x.d_free, 'd_paid', x.d_paid, 'free_after', x.free_after, 'paid_after', x.paid_after, 'reason', x.reason, 'ref', x.ref, 'meta', x.meta, 'at', x.created_at) order by x.id desc)
                     from (select * from gem_ledger where user_id = p_user order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) x), '[]'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_grant_gem(uuid, int, text), public.admin_gem_ledger(uuid, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_grant_gem(uuid, int, text), public.admin_gem_ledger(uuid, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 9) PvP 연동 (pvp.sql / pvp_tier.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_gem_sql.mjs 가 일치 확인)
--    추가 도전권(pvp_bonus_tries) · 시즌 티어/10연승 보상에 심연석
-- 추가 도전권 (gem.sql 의 심연석 구매로 늘어남). 오늘(KST) 리그·모드별 추가 횟수
create table if not exists public.pvp_bonus_tries (
  user_id uuid not null references auth.users(id) on delete cascade, league text not null, mode text not null, day date not null,
  n int not null default 0 check (n >= 0), primary key (user_id, league, mode, day));$vr_statement$;
  execute $vr_statement$alter table public.pvp_bonus_tries enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.pvp_bonus_tries from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_extra(p_uid uuid, p_league text, p_mode text) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select n from pvp_bonus_tries where user_id = p_uid and league = p_league and mode = p_mode and day = (now() at time zone 'Asia/Seoul')::date), 0) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_extra(uuid, text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_start(p_league text, p_mode text) returns jsonb
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
    mine := mine || jsonb_build_array(_pvp_snap(uid, d.uids, p_league)->'cards');
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_start(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_start(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = public as $$
declare w jsonb := p_rw - 'tickets' - 'title' - 'gem';
begin
  if w <> '{}'::jsonb then perform _wallet_add(p_uid, w, p_reason); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 and to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is not null then   -- 심연석 (gem.sql)
    perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, case when p_reason = 'pvp_tier' then 'pvp_tier:' || p_league || ':' || p_mode || ':' || p_season end, jsonb_build_object('league', p_league, 'mode', p_mode, 'season', p_season));
  end if;
  if p_rw ? 'title' then
    insert into pvp_titles (user_id, title, league, mode, season) values (p_uid, p_rw->>'title', p_league, p_mode, p_season) on conflict do nothing;
  end if;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_grant(uuid, jsonb, text, text, text, date) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb; prev pvp_ratings; pend jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  select * into prev from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season() - 7;
  if prev.user_id is not null and prev.wins + prev.losses >= 3
     and not exists (select 1 from pvp_tier_claims where user_id = uid and league = p_league and mode = p_mode and season = prev.season) then
    pend := jsonb_build_object('season', prev.season, 'rating', prev.rating, 'tier', _pvp_tier(prev.rating));
  end if;
  return jsonb_build_object('left', greatest(0, 10 + _pvp_extra(uid, p_league, p_mode) - used), 'max', 10 + _pvp_extra(uid, p_league, p_mode), 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'),
    'tier', _pvp_tier(r.rating), 'streak', _pvp_streak(uid, p_league, p_mode, _pvp_season()),
    'abyss', exists (select 1 from pvp_titles where user_id = uid and title = 'abyss'),
    'tiers', (select jsonb_agg(jsonb_build_object('tier', tier, 'min', min_rating, 'reward', reward) order by ord) from pvp_tier_table),
    'streaks', (select jsonb_agg(jsonb_build_object('n', s.n, 'reward', s.reward) order by s.n) from pvp_streak_table s),
    'pending', pend);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_status(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_status(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$insert into public.pvp_tier_table (tier, ord, min_rating, reward) values
  ('bronze',   0,    0, '{"gold":200}'),
  ('silver',   1,  950, '{"gold":400,"shard":5,"gem":50}'),
  ('gold',     2, 1050, '{"gold":800,"soul":5,"tickets":3,"gem":100}'),
  ('platinum', 3, 1150, '{"gold":1500,"soul":10,"tickets":5,"gem":200}'),
  ('diamond',  4, 1250, '{"gold":2500,"soul":20,"tickets":10,"gem":400}'),
  ('abyss',    5, 1400, '{"gold":4000,"soul":35,"tickets":20,"gem":1000,"title":"abyss"}')
on conflict (tier) do update set ord = excluded.ord, min_rating = excluded.min_rating, reward = excluded.reward;$vr_statement$;
  execute $vr_statement$insert into public.pvp_streak_table (n, reward) values
  (3, '{"gold":300}'), (5, '{"gold":600,"soul":5}'), (10, '{"gold":1500,"soul":15,"tickets":3,"gem":30}')
on conflict (n) do update set reward = excluded.reward;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _guild_feed, guild_shop_buy 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- [조직] 1단계 (길드 코어) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(지갑) · phaseE_2.sql(레벨·행동력) · gem.sql(심연석) · admin.sql · pvp.sql · pvp_tier.sql
-- 역할: 보스(boss) · 간부(officer) · 조직원(member). 개인 재화: 충성 (loyalty_wallet + loyalty_ledger)
-- 창설: 계정 Lv.15+ · 골드 50,000 또는 심연석 300 (기존 _wallet_add / _gem_spend 로 차감)
-- 세력(조직 EXP): 스토리(행동력 6 = 1, 하루 100) · PvP 승리 +10 (하루 100). 기여한 만큼 본인 충성 +
-- 탈퇴 후 24시간 가입 불가 · 추방된 조직은 72시간 재가입 불가 · 추방 하루 5명
-- 쓰기는 전부 서버 함수로만. 테이블은 클라이언트 접근 불가 (RLS + revoke)
-- 나중 단계: 집결(출석) · 의뢰(퀘스트) · 토벌(레이드) · 전쟁 → _guild_exp / _loyalty_add 를 호출해 연결
-- 확인용: select public.guild_status();
-- =====================================================================

-- 1) 테이블
create table if not exists public.guild_level_table (
  level int primary key, exp_total bigint not null, max_members int not null, officers int not null, unlock text);$vr_statement$;
  execute $vr_statement$insert into public.guild_level_table (level, exp_total, max_members, officers, unlock) values
  (1, 0, 15, 1, '기본 상점'), (2, 1000, 18, 2, null), (3, 3000, 21, 2, '상점 확장'), (4, 7000, 24, 3, '토벌 (준비 중)'), (5, 15000, 27, 3, '엠블럼 프레임'),
  (6, 30000, 30, 4, '전쟁 (준비 중)'), (7, 60000, 33, 4, null), (8, 120000, 36, 5, null), (9, 240000, 38, 5, null), (10, 480000, 40, 5, null)
on conflict (level) do update set exp_total = excluded.exp_total, max_members = excluded.max_members, officers = excluded.officers, unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$create table if not exists public.guilds (
  id          bigint generated always as identity primary key,
  name        text not null,
  name_key    text not null unique,                 -- lower(name) — 대소문자 무시 중복 금지
  emblem      int not null default 1 check (emblem between 1 and 12),
  intro       text not null default '' check (char_length(intro) <= 60),
  notice      text not null default '' check (char_length(notice) <= 100),
  join_mode   text not null default 'open' check (join_mode in ('open', 'approval', 'closed')),
  level       int not null default 1,
  exp         bigint not null default 0 check (exp >= 0),
  boss        uuid not null references auth.users(id),
  renamed_at  timestamptz,
  created_at  timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_members (
  user_id       uuid primary key references auth.users(id) on delete cascade,   -- 한 사람 한 조직
  guild_id      bigint not null references public.guilds(id) on delete cascade,
  role          text not null default 'member' check (role in ('boss', 'officer', 'member')),
  joined_at     timestamptz not null default now(),
  loyalty_total bigint not null default 0,           -- 이 조직에서 쌓은 충성 (누적, 순위용)
  seen_at       timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists guild_members_gid on public.guild_members (guild_id);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_requests (
  id         bigint generated always as identity primary key,
  guild_id   bigint not null references public.guilds(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('apply', 'invite')),
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  by_user    uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '3 days'
);$vr_statement$;
  execute $vr_statement$create unique index if not exists guild_requests_pending on public.guild_requests (guild_id, user_id, kind) where status = 'pending';$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_cooldowns (
  user_id  uuid not null references auth.users(id) on delete cascade,
  guild_id bigint not null default 0,                -- 0 = 모든 조직 (탈퇴), 그 외 = 그 조직만 (추방)
  until    timestamptz not null,
  primary key (user_id, guild_id)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_log (
  id bigint generated always as identity primary key, guild_id bigint, actor uuid, action text not null, target uuid, meta jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$create index if not exists guild_log_gid on public.guild_log (guild_id, created_at desc);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_exp_log (
  id bigint generated always as identity primary key, guild_id bigint not null, user_id uuid, amount int not null, src text not null,
  day date not null, ref text not null default gen_random_uuid()::text, created_at timestamptz not null default now(), unique (guild_id, ref));$vr_statement$;
  execute $vr_statement$create index if not exists guild_exp_log_day on public.guild_exp_log (user_id, day, src);$vr_statement$;
  execute $vr_statement$create table if not exists public.loyalty_wallet (
  user_id uuid primary key references auth.users(id) on delete cascade, balance bigint not null default 0 check (balance >= 0), updated_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$create table if not exists public.loyalty_ledger (
  id bigint generated always as identity primary key, user_id uuid not null references auth.users(id) on delete cascade, delta int not null, after bigint not null,
  reason text not null check (char_length(reason) <= 40), ref text not null default gen_random_uuid()::text, meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), unique (user_id, ref));$vr_statement$;
  execute $vr_statement$create index if not exists loyalty_ledger_user on public.loyalty_ledger (user_id, created_at desc);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_shop (
  item text primary key, ord int not null default 0, price int not null check (price > 0), gives jsonb not null,
  limit_kind text check (limit_kind in ('day', 'week', 'once')), limit_n int, min_level int not null default 1, active boolean not null default true);$vr_statement$;
  execute $vr_statement$insert into public.guild_shop (item, ord, price, gives, limit_kind, limit_n, min_level) values
  ('ticket',    1,  300, '{"tickets":1}',          'week', 2,    1),
  ('stamina30', 2,  100, '{"stamina":30}',         'day',  1,    1),
  ('gold5k',    3,   80, '{"gold":5000}',          null,   null, 1),
  ('shard5',    4,  150, '{"shard":5}',            null,   null, 3),
  ('soul3',     5,  150, '{"soul":3}',             null,   null, 3),
  ('frame',     6, 2000, '{"title":"guild_frame"}', 'once', 1,   5)
on conflict (item) do update set ord = excluded.ord, price = excluded.price, gives = excluded.gives, limit_kind = excluded.limit_kind, limit_n = excluded.limit_n, min_level = excluded.min_level;$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_titles (user_id uuid not null references auth.users(id) on delete cascade, title text not null, created_at timestamptz not null default now(), primary key (user_id, title));$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['guild_level_table', 'guilds', 'guild_members', 'guild_requests', 'guild_cooldowns', 'guild_log', 'guild_exp_log', 'loyalty_wallet', 'loyalty_ledger', 'guild_shop', 'guild_titles'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 수치
create or replace function public._guild_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_min_level() returns int language sql immutable as $$ select 15 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_cost_gold() returns int language sql immutable as $$ select 50000 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_cost_gem() returns int language sql immutable as $$ select 300 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_rename_gem() returns int language sql immutable as $$ select 500 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_feed_cap(p_src text) returns int language sql immutable as $$ select case p_src when 'story' then 100 when 'pvp' then 100 else 1000 end $$;$vr_statement$;
  execute $vr_statement$-- 3) 내부 도우미
create or replace function public._guild_lock(p_gid bigint) returns void language sql as $$ select pg_advisory_xact_lock(hashtext('guild:' || p_gid)) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_me(p_uid uuid) returns guild_members language sql stable security definer set search_path = public as $$
  select * from guild_members where user_id = p_uid $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_name_ok(p_name text) returns text language plpgsql immutable as $$
declare n text := btrim(coalesce(p_name, '')); w text;
begin
  if n !~ '^[가-힣A-Za-z0-9]{2,8}$' then raise exception 'bad name'; end if;
  foreach w in array array['운영', '관리자', 'admin', 'gm', '시발', '씨발', '병신', '좆', '섹스', '느금', '애미', '애비', '지랄', '꺼져', 'fuck', 'shit', 'sex'] loop
    if position(w in lower(n)) > 0 then raise exception 'bad name'; end if;
  end loop;
  return n;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_text_ok(p_text text, p_max int) returns text language plpgsql immutable as $$
declare t text := btrim(coalesce(p_text, '')); w text;
begin
  if char_length(t) > p_max then raise exception 'too long'; end if;
  foreach w in array array['시발', '씨발', '병신', '좆', '섹스', '느금', '애미'] loop
    if position(w in t) > 0 then raise exception 'bad word'; end if;
  end loop;
  return t;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_log(p_gid bigint, p_actor uuid, p_action text, p_target uuid, p_meta jsonb) returns void language sql security definer set search_path = public as $$
  insert into guild_log (guild_id, actor, action, target, meta) values (p_gid, p_actor, p_action, p_target, coalesce(p_meta, '{}'::jsonb)) $$;$vr_statement$;
  execute $vr_statement$-- 쿨타임 확인: 탈퇴(전체) 또는 이 조직에서 추방
create or replace function public._guild_cd_check(p_uid uuid, p_gid bigint) returns void language plpgsql stable security definer set search_path = public as $$
declare u timestamptz;
begin
  select max(until) into u from guild_cooldowns where user_id = p_uid and guild_id in (0, coalesce(p_gid, 0)) and until > now();
  if u is not null then raise exception 'cooldown until %', to_char(u at time zone 'Asia/Seoul', 'MM-DD HH24:MI'); end if;
end $$;$vr_statement$;
  execute $vr_statement$-- 멤버 추가 (조직 잠금 상태에서 호출). 인원·중복·쿨타임 확인, 이 사람의 다른 대기 신청은 취소
create or replace function public._guild_add_member(p_gid bigint, p_uid uuid, p_by uuid) returns void language plpgsql security definer set search_path = public as $$
declare g guilds; cnt int; mx int;
begin
  select * into g from guilds where id = p_gid;
  if g.id is null then raise exception 'no such guild'; end if;
  if exists (select 1 from guild_members where user_id = p_uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(p_uid, p_gid);
  select count(*) into cnt from guild_members where guild_id = p_gid;
  select max_members into mx from guild_level_table where level = g.level;
  if cnt >= coalesce(mx, 15) then raise exception 'guild full'; end if;
  insert into guild_members (user_id, guild_id, role) values (p_uid, p_gid, 'member');
  update guild_requests set status = 'cancelled' where user_id = p_uid and status = 'pending';
  perform _guild_log(p_gid, coalesce(p_by, p_uid), 'join', p_uid, '{}');
end $$;$vr_statement$;
  execute $vr_statement$-- 충성 증감 (+ 획득, − 사용). p_ref 중복이면 null. 부족하면 'not enough loyalty'
create or replace function public._loyalty_add(p_uid uuid, p_delta int, p_reason text, p_ref text, p_meta jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare b bigint;
begin
  if coalesce(p_delta, 0) = 0 then return null; end if;
  insert into loyalty_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select balance into b from loyalty_wallet where user_id = p_uid for update;
  if p_ref is not null and exists (select 1 from loyalty_ledger where user_id = p_uid and ref = p_ref) then return null; end if;
  b := b + p_delta;
  if b < 0 then raise exception 'not enough loyalty'; end if;
  update loyalty_wallet set balance = b, updated_at = now() where user_id = p_uid;
  insert into loyalty_ledger (user_id, delta, after, reason, ref, meta) values (p_uid, p_delta, b, left(p_reason, 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  if p_delta > 0 then update guild_members set loyalty_total = loyalty_total + p_delta where user_id = p_uid; end if;
  return b;
end $$;$vr_statement$;
  execute $vr_statement$-- 세력(조직 EXP) 추가 + 레벨업. p_ref 중복이면 0. 반환 실제 추가량
create or replace function public._guild_exp(p_gid bigint, p_uid uuid, p_n int, p_src text, p_ref text) returns int language plpgsql security definer set search_path = public as $$
declare g guilds; lv int;
begin
  if coalesce(p_n, 0) <= 0 then return 0; end if;
  select * into g from guilds where id = p_gid for update;
  if g.id is null then return 0; end if;
  if p_ref is not null and exists (select 1 from guild_exp_log where guild_id = p_gid and ref = p_ref) then return 0; end if;
  insert into guild_exp_log (guild_id, user_id, amount, src, day, ref) values (p_gid, p_uid, p_n, p_src, _guild_day(), coalesce(p_ref, gen_random_uuid()::text));
  select max(level) into lv from guild_level_table where exp_total <= g.exp + p_n;
  update guilds set exp = exp + p_n, level = greatest(level, coalesce(lv, 1)) where id = p_gid;
  if coalesce(lv, 1) > g.level then perform _guild_log(p_gid, null, 'level_up', null, jsonb_build_object('level', lv)); end if;
  return p_n;
end $$;$vr_statement$;
  execute $vr_statement$-- 활동 → 세력 + 본인 충성 (하루 상한). 조직이 없으면 아무것도 안 함. 스토리/PvP 함수에서 호출
create or replace function public._guild_feed(p_uid uuid, p_src text, p_n int) returns int language plpgsql security definer set search_path = public as $$
declare m guild_members; used int; n int;
begin
  select * into m from guild_members where user_id = p_uid;
  if m.user_id is null or coalesce(p_n, 0) <= 0 then return 0; end if;
  if p_src = 'pvp' and to_regprocedure('public._guild_event(uuid,text,integer)') is not null then perform _guild_event(p_uid, 'pvp_win', 1); end if;   -- 조직 의뢰 (guild2.sql)
  select coalesce(sum(amount), 0) into used from guild_exp_log where user_id = p_uid and day = _guild_day() and src = p_src;
  n := least(p_n, _guild_feed_cap(p_src) - used);
  if n <= 0 then return 0; end if;
  perform _guild_exp(m.guild_id, p_uid, n, p_src, null);
  perform _loyalty_add(p_uid, n, 'feed:' || p_src, null, jsonb_build_object('guild', m.guild_id));
  return n;
end $$;$vr_statement$;
  execute $vr_statement$-- 조직 요약 / 상세 JSON
create or replace function public._guild_card(p_gid bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', g.id, 'name', g.name, 'emblem', g.emblem, 'intro', g.intro, 'join_mode', g.join_mode, 'level', g.level,
    'members', (select count(*) from guild_members where guild_id = g.id), 'max_members', (select max_members from guild_level_table where level = g.level),
    'boss_name', (select coalesce(nickname, '보스') from profiles where id = g.boss))
  from guilds g where g.id = p_gid $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_shop_left(p_uid uuid, s guild_shop) returns int language sql stable security definer set search_path = public as $$
  select case when s.limit_kind is null then null else greatest(0, s.limit_n - (select count(*)::int from loyalty_ledger l where l.user_id = p_uid and l.reason = 'shop:' || s.item
    and l.created_at >= case s.limit_kind when 'day' then (_guild_day()::timestamp at time zone 'Asia/Seoul')
                                          when 'week' then (date_trunc('week', _guild_day()::timestamp) at time zone 'Asia/Seoul') else '-infinity'::timestamptz end)) end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._guild_lock(bigint), public._guild_me(uuid), public._guild_log(bigint, uuid, text, uuid, jsonb), public._guild_cd_check(uuid, bigint),
  public._guild_add_member(bigint, uuid, uuid), public._loyalty_add(uuid, int, text, text, jsonb), public._guild_exp(bigint, uuid, int, text, text),
  public._guild_feed(uuid, text, int), public._guild_card(bigint), public._guild_shop_left(uuid, guild_shop) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 공개 RPC
-- 내 조직 상태. 조직 없음: { ok, guild:null, list, invites, applies, cooldown, can_create, cost } / 있음: { ok, guild, me, members, requests, shop, levels, log, loyalty }
create or replace function public.guild_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; lv int; cd timestamptz; res jsonb; lt guild_level_table; nx guild_level_table;
begin
  if uid is null then raise exception 'login required'; end if;
  update guild_requests set status = 'cancelled' where status = 'pending' and expires_at < now() and (user_id = uid or guild_id = (select guild_id from guild_members where user_id = uid));
  select coalesce((select level from player_state where user_id = uid), 1) into lv;
  res := jsonb_build_object('ok', true, 'loyalty', coalesce((select balance from loyalty_wallet where user_id = uid), 0), 'my_level', lv);
  m := _guild_me(uid);
  if m.user_id is null then
    select max(until) into cd from guild_cooldowns where user_id = uid and guild_id = 0 and until > now();
    return res || jsonb_build_object('guild', null, 'cooldown', cd, 'min_level', _guild_min_level(), 'cost', jsonb_build_object('gold', _guild_cost_gold(), 'gem', _guild_cost_gem()),
      'list', (select coalesce(jsonb_agg(_guild_card(x.id) order by x.lv desc, x.n desc), '[]'::jsonb) from (
                 select g2.id, g2.level lv, (select count(*) from guild_members where guild_id = g2.id) n from guilds g2 where g2.join_mode <> 'closed' order by g2.level desc, g2.exp desc limit 20) x),
      'invites', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'guild', _guild_card(r.guild_id)) order by r.id desc), '[]'::jsonb) from guild_requests r where r.user_id = uid and r.kind = 'invite' and r.status = 'pending'),
      'applies', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'guild', _guild_card(r.guild_id)) order by r.id desc), '[]'::jsonb) from guild_requests r where r.user_id = uid and r.kind = 'apply' and r.status = 'pending'));
  end if;
  update guild_members set seen_at = now() where user_id = uid;
  select * into g from guilds where id = m.guild_id;
  select * into lt from guild_level_table where level = g.level;
  select * into nx from guild_level_table where level = g.level + 1;
  return res || jsonb_build_object(
    'guild', _guild_card(g.id) || jsonb_build_object('notice', g.notice, 'exp', g.exp, 'exp_cur', lt.exp_total, 'exp_next', nx.exp_total, 'officers_max', lt.officers, 'boss', g.boss),
    'me', jsonb_build_object('role', m.role, 'joined_at', m.joined_at, 'loyalty_total', m.loyalty_total,
      'today', (select coalesce(jsonb_object_agg(src, s), '{}'::jsonb) from (select src, sum(amount) s from guild_exp_log where user_id = uid and day = _guild_day() group by src) t),
      'can_claim', m.role <> 'boss' and exists (select 1 from guild_members b where b.guild_id = g.id and b.role = 'boss' and b.seen_at < now() - interval '14 days')),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', gm.user_id, 'name', coalesce(p.nickname, '조직원'), 'role', gm.role, 'loyalty_total', gm.loyalty_total,
                  'joined_at', gm.joined_at, 'seen_at', gm.seen_at,
                  'card', (select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = gm.user_id and o->>'uid' = sp.data->>'leader' limit 1))
                order by case gm.role when 'boss' then 0 when 'officer' then 1 else 2 end, gm.loyalty_total desc), '[]'::jsonb)
                from guild_members gm left join profiles p on p.id = gm.user_id where gm.guild_id = g.id),
    'requests', case when m.role in ('boss', 'officer') then (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'user_id', r.user_id, 'name', coalesce(p.nickname, '플레이어'),
                  'level', coalesce((select level from player_state where user_id = r.user_id), 1)) order by r.id), '[]'::jsonb)
                from guild_requests r left join profiles p on p.id = r.user_id where r.guild_id = g.id and r.kind = 'apply' and r.status = 'pending') else '[]'::jsonb end,
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price, 'gives', s.gives, 'min_level', s.min_level, 'left', _guild_shop_left(uid, s),
                'owned', s.limit_kind = 'once' and exists (select 1 from guild_titles t where t.user_id = uid and t.title = s.gives->>'title')) order by s.ord), '[]'::jsonb) from guild_shop s where s.active),
    'levels', (select jsonb_agg(jsonb_build_object('level', level, 'exp', exp_total, 'members', max_members, 'officers', officers, 'unlock', unlock) order by level) from guild_level_table),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('action', l.action, 'actor', (select nickname from profiles where id = l.actor), 'target', (select nickname from profiles where id = l.target), 'meta', l.meta, 'at', l.created_at) order by l.id desc), '[]'::jsonb)
            from (select * from guild_log where guild_id = g.id order by id desc limit 20) l));
end $$;$vr_statement$;
  execute $vr_statement$-- 조직 찾기 (이름 검색, 비공개 제외)
create or replace function public.guild_search(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return (select coalesce(jsonb_agg(_guild_card(g.id) order by g.level desc, g.exp desc), '[]'::jsonb) from (
    select * from guilds where name_key like '%' || lower(replace(replace(btrim(coalesce(p_q, '')), '%', ''), '_', '')) || '%' order by level desc, exp desc limit 20) g);
end $$;$vr_statement$;
  execute $vr_statement$-- 창설: p_pay = 'gold' | 'gem'
create or replace function public.guild_create(p_name text, p_emblem int, p_intro text, p_join text, p_pay text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text; gid bigint; lv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  select coalesce((select level from player_state where user_id = uid), 1) into lv;
  if lv < _guild_min_level() then raise exception 'level required %', _guild_min_level(); end if;
  if exists (select 1 from guild_members where user_id = uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(uid, 0);
  n := _guild_name_ok(p_name);
  if p_emblem is null or p_emblem not between 1 and 12 then raise exception 'bad emblem'; end if;
  if coalesce(p_join, 'open') not in ('open', 'approval', 'closed') then raise exception 'bad join mode'; end if;
  perform pg_advisory_xact_lock(hashtext('guildname:' || lower(n)));
  if exists (select 1 from guilds where name_key = lower(n)) then raise exception 'name taken'; end if;
  if p_pay = 'gold' then perform _wallet_add(uid, jsonb_build_object('gold', -_guild_cost_gold()), 'guild_create');
  elsif p_pay = 'gem' then perform _gem_spend(uid, _guild_cost_gem(), 'guild_create', jsonb_build_object('name', n));
  else raise exception 'bad pay'; end if;
  insert into guilds (name, name_key, emblem, intro, join_mode, boss) values (n, lower(n), p_emblem, _guild_text_ok(p_intro, 60), coalesce(p_join, 'open'), uid) returning id into gid;
  insert into guild_members (user_id, guild_id, role) values (uid, gid, 'boss');
  update guild_requests set status = 'cancelled' where user_id = uid and status = 'pending';
  perform _guild_log(gid, uid, 'create', null, jsonb_build_object('pay', p_pay));
  return jsonb_build_object('ok', true, 'id', gid);
end $$;$vr_statement$;
  execute $vr_statement$-- 설정 변경: p_patch { intro, emblem, join_mode (보스) · notice (보스·간부) · name (보스, 심연석 500, 30일 1회) }
create or replace function public.guild_update(p_patch jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; n text;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_lock(m.guild_id);
  select * into g from guilds where id = m.guild_id;
  if p_patch ? 'notice' then
    if m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
    update guilds set notice = _guild_text_ok(p_patch->>'notice', 100) where id = g.id;
  end if;
  if p_patch ?| array['intro', 'emblem', 'join_mode', 'name'] and m.role <> 'boss' then raise exception 'no permission'; end if;
  if p_patch ? 'intro' then update guilds set intro = _guild_text_ok(p_patch->>'intro', 60) where id = g.id; end if;
  if p_patch ? 'emblem' then
    if (p_patch->>'emblem')::int not between 1 and 12 then raise exception 'bad emblem'; end if;
    update guilds set emblem = (p_patch->>'emblem')::int where id = g.id;
  end if;
  if p_patch ? 'join_mode' then
    if p_patch->>'join_mode' not in ('open', 'approval', 'closed') then raise exception 'bad join mode'; end if;
    update guilds set join_mode = p_patch->>'join_mode' where id = g.id;
  end if;
  if p_patch ? 'name' then
    n := _guild_name_ok(p_patch->>'name');
    if g.renamed_at is not null and g.renamed_at > now() - interval '30 days' then raise exception 'rename cooldown'; end if;
    perform pg_advisory_xact_lock(hashtext('guildname:' || lower(n)));
    if exists (select 1 from guilds where name_key = lower(n) and id <> g.id) then raise exception 'name taken'; end if;
    perform _gem_spend(uid, _guild_rename_gem(), 'guild_rename', jsonb_build_object('guild', g.id, 'name', n));
    update guilds set name = n, name_key = lower(n), renamed_at = now() where id = g.id;
  end if;
  perform _guild_log(g.id, uid, 'update', null, p_patch - 'notice' - 'intro' || case when p_patch ? 'notice' then '{"notice":true}'::jsonb else '{}'::jsonb end);
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 가입 신청: 공개 = 바로 가입 · 승인제 = 신청 (대기 최대 3개) · 비공개 = 불가
create or replace function public.guild_apply(p_gid bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g guilds;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  perform _guild_lock(p_gid);
  select * into g from guilds where id = p_gid;
  if g.id is null then raise exception 'no such guild'; end if;
  if exists (select 1 from guild_members where user_id = uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(uid, p_gid);
  if g.join_mode = 'closed' then raise exception 'closed'; end if;
  if g.join_mode = 'open' then perform _guild_add_member(p_gid, uid, null); return jsonb_build_object('ok', true, 'joined', true); end if;
  if (select count(*) from guild_requests where user_id = uid and kind = 'apply' and status = 'pending' and expires_at > now()) >= 3 then raise exception 'too many requests'; end if;
  insert into guild_requests (guild_id, user_id, kind, by_user) values (p_gid, uid, 'apply', uid) on conflict do nothing;
  return jsonb_build_object('ok', true, 'joined', false, 'pending', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 초대 (보스·간부, 닉네임으로)
create or replace function public.guild_invite(p_nick text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; t uuid;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
  select id into t from profiles where nickname = btrim(p_nick) limit 1;
  if t is null then raise exception 'no such player'; end if;
  if exists (select 1 from guild_members where user_id = t) then raise exception 'already in guild'; end if;
  if (select count(*) from guild_requests where guild_id = m.guild_id and kind = 'invite' and created_at > now() - interval '1 day') >= 20 then raise exception 'too many invites'; end if;
  insert into guild_requests (guild_id, user_id, kind, by_user) values (m.guild_id, t, 'invite', uid) on conflict do nothing;
  perform _guild_log(m.guild_id, uid, 'invite', t, '{}');
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (3, 'ac67dd4f5df4920603189b3e57b25a5e13e409b830a4a45862378c594de08997', 'd8c563ec9bf73dd9b2118c16108122afca21efac2566cc64c5d21c98b423b8f7', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '03_install.sql: 완료 또는 이미 완료 (3/10)' as result;
