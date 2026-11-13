-- ⚠ 테스트 전용 5/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where part_no = 5) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 5 and part_hash = 'a76fd1f8e73c144cb17b7ab191f735e7a2a7e9e101d52f5719ba02c5097b4036') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '05_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 5) <> 4 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (05_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- 7) 관리자: 시즌 현황 · 의심 기록 · 공격 무효(정산 전만: 그 공격 전 상태로 되돌리고 점수 회수)
create or replace function public.admin_war(p_season date) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('entries', (select coalesce(jsonb_agg(to_jsonb(e) order by e.points desc), '[]'::jsonb) from war_entries e where season = coalesce(p_season, _war_season())),
    'matches', (select coalesce(jsonb_agg(to_jsonb(m) order by m.day, m.id), '[]'::jsonb) from war_matches m where season = coalesce(p_season, _war_season())),
    'flagged', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'match_id', a.match_id, 'user_id', a.user_id, 'target', a.target_slot, 'win', a.win, 'points', a.points, 'at', a.finished_at) order by a.id desc), '[]'::jsonb)
                from war_attacks a join war_matches m on m.id = a.match_id where m.season = coalesce(p_season, _war_season()) and a.flagged and not a.voided));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_war_void(p_id bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare a war_attacks; mt war_matches;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  select * into a from war_attacks where id = p_id for update;
  if a.id is null or a.voided or a.finished_at is null then raise exception 'no attack'; end if;
  select * into mt from war_matches where id = a.match_id for update;
  if mt.settled then raise exception 'match settled'; end if;
  update war_attacks set voided = true where id = p_id;
  update war_ajits set state = a.before->'def_state', deck = (a.before->>'def_deck')::int, destroyed_at = null, destroyed_by = null where match_id = a.match_id and side = 1 - a.side and slot = a.target_slot;
  update war_atk_state set state = a.before->'atk_state' where match_id = a.match_id and user_id = a.user_id and deck = a.atk_deck;
  if a.points > 0 then
    update war_matches set score_a = score_a - case a.side when 0 then a.points else 0 end, score_b = score_b - case a.side when 1 then a.points else 0 end where id = a.match_id;
  end if;
  if mt.boss_kill and exists (select 1 from war_ajits where match_id = a.match_id and side = 1 - a.side and slot = a.target_slot and role = 'boss') then update war_matches set boss_kill = false, winner = null, ended_at = null where id = a.match_id; end if;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason) values (auth.uid(), auth.jwt()->>'email', 'war_void', a.user_id, a.points, left(btrim(p_reason), 200));
  return jsonb_build_object('ok', true, 'voided', p_id);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_war(date), public.admin_war_void(bigint, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_war(date), public.admin_war_void(bigint, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: manual_battle.sql =====
-- 수동 전투 (균열 토벌 · PvP): 내 행동 기록 저장 → tools/raid_verify.mjs · tools/pvp_verify.mjs 가 같은 seed 로 다시 돌려 검증
-- guild3.sql · guild.sql(pvp_report) 뒤에 실행. 여러 번 실행해도 안전
alter table public.guild_raid_attempts add column if not exists actions jsonb;$vr_statement$;
  execute $vr_statement$-- null = 자동 전투
alter table public.pvp_attempts add column if not exists actions jsonb;$vr_statement$;
  execute $vr_statement$-- null = 자동 · 판마다 배열 [[..],[..]]

-- 수동은 시간이 더 걸려서 토벌 제한 시간 10분 → 20분 (나머지 숫자는 guild3.sql 그대로)
create or replace function public._raid_numbers() returns jsonb language sql immutable as $$ select '{
  "attempts_per_day": 3, "sweep_pct": 90, "min_secs": 3, "open_minutes": 20,
  "hp_per_member": {"normal": 500000, "hard": 1250000, "abyss": 3000000}, "hp_min_members": 5, "hp_growth": 1.35,
  "diff_level": {"normal": 1, "hard": 3, "abyss": 5}, "diff_mult": {"normal": 1, "hard": 1.6, "abyss": 2.5},
  "hit_cap": 6000, "hit_cap_growth": 1.1, "attempt_hits": 200,
  "attempt": {"loyalty": 5, "gold_base": 200, "gold_per_damage": 200, "gold_max": 2000, "exp": 5},
  "stage": {"loyalty": 20, "gold": 2000, "gem": 30, "gem_every3": 150, "tickets_every5": 1, "exp_per_stage": 30},
  "last_hit": {"loyalty": 10},
  "rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 100}}, {"from": 2, "to": 3, "reward": {"gem": 500, "loyalty": 70}}, {"from": 4, "to": 10, "reward": {"gem": 200, "loyalty": 40}}],
  "member": {"gem": 100, "loyalty": 20},
  "join_hours": 24
}'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 행동 기록 검사: 배열 · 크기 제한 (한 판 최대 행동 수 = 턴 × 5장 + 턴 종료)
create or replace function public._battle_acts_ok(p jsonb, p_max int) returns boolean language sql immutable as $$
  select p is not null and jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= p_max and octet_length(p::text) <= 65536 $$;$vr_statement$;
  execute $vr_statement$-- 토벌: raid_finish 전에 호출 (끝나기 전 · 본인 판만 · 한 번만)
create or replace function public.raid_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a guild_raid_attempts;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from guild_raid_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.kind <> 'fight' or a.finished_at is not null then raise exception 'already finished'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if not _battle_acts_ok(p_actions, 15 * 6 + 5) then raise exception 'bad actions'; end if;
  update guild_raid_attempts set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- PvP: pvp_report 전에 호출 (보고 전 · 본인 판만 · 한 번만). 판마다 배열
create or replace function public.pvp_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a pvp_attempts; x jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if p_actions is null or jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) > 3 or octet_length(p_actions::text) > 131072 then raise exception 'bad actions'; end if;
  for x in select value from jsonb_array_elements(p_actions) loop
    if not _battle_acts_ok(x, 20 * 6 + 5) then raise exception 'bad actions'; end if;
  end loop;
  update pvp_attempts set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._battle_acts_ok(jsonb, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.raid_log(bigint, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.raid_log(bigint, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_log(bigint, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_log(bigint, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: war_manual.sql =====
-- 구역 전쟁 수동 전투: 내 행동 기록 저장 → tools/war_verify.mjs 가 같은 seed 로 다시 돌려 검증
-- guild4.sql · manual_battle.sql 뒤에 실행. 여러 번 실행해도 안전
alter table public.war_attacks add column if not exists actions jsonb;$vr_statement$;
  execute $vr_statement$-- null = 자동 전투

-- 수동은 시간이 더 걸려서 공격 제한 시간 10분 → 20분 (나머지 숫자는 guild4.sql 그대로)
create or replace function public._war_numbers() returns jsonb language sql immutable as $$ select '{
  "min_members": 10, "attacks_per_day": 5, "open_hour": 9, "close_hour": 23, "min_secs": 3, "open_minutes": 20, "lock_minutes": 3, "hp_cap": 60000,
  "layout": {"def": [1,2,3,4,5], "atk": [6,7,8,9,10], "mid": [11,12,13], "boss": [14], "etc": [15,16,17,18,19,20,21]},
  "roles": {"def": {"atk": 1, "def": 1.2}, "atk": {"atk": 1.2, "def": 1}, "mid": {"atk": 1.15, "def": 1.15}, "boss": {"atk": 1.25, "def": 1.25}, "etc": {"atk": 1, "def": 1}},
  "points": {"def": 200, "atk": 150, "etc": 150, "mid": 250, "boss": 400},
  "standings": {"win": 3, "draw": 2, "loss": 0, "boss_bonus": 1},
  "npc_level": 10, "npc_scale": 1, "signup_days_before": 3,
  "match_win": {"loyalty": 60, "gold": 5000}, "match_boss_kill": {"loyalty": 20, "gold": 2000}, "match_draw": {"loyalty": 20, "gold": 1500}, "match_loss": {"loyalty": 10}, "match_exp_win": 300,
  "season_rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 300}}, {"from": 2, "to": 2, "reward": {"gem": 700, "loyalty": 200}}, {"from": 3, "to": 3, "reward": {"gem": 500, "loyalty": 150}},
                  {"from": 4, "to": 10, "reward": {"gem": 300, "loyalty": 100}}, {"from": 11, "to": 30, "reward": {"gem": 150, "loyalty": 50}}],
  "season_member": {"gem": 100, "loyalty": 30}
}'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- war_finish 전에 호출 (끝나기 전 · 본인 공격만 · 한 번만). 40턴 → 내 턴 20 × (5장 + 턴 종료)
create or replace function public.war_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a war_attacks;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from war_attacks where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.finished_at is not null then raise exception 'already finished'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if not _battle_acts_ok(p_actions, 20 * 6 + 5) then raise exception 'bad actions'; end if;
  update war_attacks set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_log(bigint, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_log(bigint, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild4_ui.sql =====
-- 조직 4단계 보완: 구역 전쟁 「참가 신청(개인)」 · 아지트 칸에 리더 얼굴. 여러 번 실행해도 안전.
-- 선행: guild4.sql
-- · 조직원은 신청 기간(셋째 주 일~화)에 개인 참가 신청 (war_signup). 보스는 신청 안 한 조직원도 배치 가능 (war_set_slot 그대로)
-- · 시즌 잠금 때 빈 칸 자동 배치는 신청한 사람부터 (그다음 나머지 조직원)
-- · war_ui(): 내 조직 신청자 목록 + 내 조직·오늘 상대의 리더 인재 id (화면 표시용)

create table if not exists public.war_signups (
  season date not null, user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null,
  created_at timestamptz not null default now(), primary key (season, user_id));$vr_statement$;
  execute $vr_statement$create index if not exists war_signups_g on public.war_signups (season, guild_id);$vr_statement$;
  execute $vr_statement$alter table public.war_signups enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.war_signups from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 리더 인재 id (스토리 저장에서)
create or replace function public._war_leader_card(p_uid uuid) returns text language sql stable security definer set search_path = public as $$
  select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = p_uid and o->>'uid' = sp.data->>'leader' limit 1 $$;$vr_statement$;
  execute $vr_statement$-- 개인 참가 신청 / 취소
create or replace function public.war_signup(p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick();
begin
  if uid is null then raise exception 'login required'; end if;
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if _war_phase(s) <> 'signup' then raise exception 'signup closed'; end if;
  if p_on then insert into war_signups (season, user_id, guild_id) values (s, uid, m.guild_id) on conflict (season, user_id) do update set guild_id = excluded.guild_id;
  else delete from war_signups where season = s and user_id = uid; end if;
  return war_ui();
end $$;$vr_statement$;
  execute $vr_statement$-- 화면 보조: 신청자 · 리더 얼굴
create or replace function public.war_ui() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date; d int; mid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_season(); d := _war_day(s); m := _guild_me(uid);
  if m.user_id is null then return jsonb_build_object('ok', true, 'signed', '[]'::jsonb, 'me_signed', false, 'cards', '{}'::jsonb); end if;
  select id into mid from war_matches where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id);
  return jsonb_build_object('ok', true,
    'signed', (select coalesce(jsonb_agg(user_id), '[]'::jsonb) from war_signups where season = s and guild_id = m.guild_id),
    'me_signed', exists (select 1 from war_signups where season = s and user_id = uid),
    'cards', (select coalesce(jsonb_object_agg(u, _war_leader_card(u)) filter (where _war_leader_card(u) is not null), '{}'::jsonb) from (
       select gm.user_id u from guild_members gm where gm.guild_id = m.guild_id
       union select a.user_id from war_ajits a where a.match_id = mid and a.user_id is not null) x));
end $$;$vr_statement$;
  execute $vr_statement$-- 시즌 잠금: 빈 칸 자동 배치는 신청자 먼저
create or replace function public._war_lock(p_season date) returns void language plpgsql security definer set search_path = public as $$
declare e record; u record; s int; n int; sc numeric;
begin
  for e in select * from war_entries where season = p_season and not locked loop
    -- 배치 안 된 조직원 → 빈 칸
    for u in select gm.user_id from guild_members gm where gm.guild_id = e.guild_id
               and not exists (select 1 from war_roster r where r.season = p_season and r.user_id = gm.user_id) order by (exists (select 1 from war_signups ws where ws.season = p_season and ws.user_id = gm.user_id)) desc, gm.joined_at loop
      select min(x) into s from generate_series(1, 21) x where not exists (select 1 from war_roster r where r.season = p_season and r.guild_id = e.guild_id and r.slot = x and r.user_id is not null);
      exit when s is null;
      insert into war_roster (season, guild_id, slot, user_id) values (p_season, e.guild_id, s, u.user_id) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
    end loop;
    -- 떠난 사람 정리 · 방어 덱 잠금
    update war_roster r set user_id = null where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null
      and not exists (select 1 from guild_members gm where gm.user_id = r.user_id and gm.guild_id = e.guild_id);
    update war_roster r set def_snap = (select case when d.def1 is null then null else jsonb_build_array(d.def1, coalesce(d.def2, '[]'::jsonb)) end from war_decks d where d.user_id = r.user_id)
      where r.season = p_season and r.guild_id = e.guild_id and r.user_id is not null;
    select count(*) into n from war_roster where season = p_season and guild_id = e.guild_id and user_id is not null;
    sc := _war_scale(p_season, e.guild_id);
    update war_entries set locked = true, scale = sc, status = case when n >= (_war_numbers()->>'min_members')::int then 'in' else 'out' end where season = p_season and guild_id = e.guild_id;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._war_leader_card(uuid), public._war_lock(date) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_signup(boolean), public.war_ui() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_signup(boolean), public.war_ui() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: pvp_info_notices.sql =====
-- PR 3/3: PvP 랭커 정보 팝업 + 공지 게시판. 여러 번 실행해도 안전. RLS 켬.
-- 필요: pvp.sql, phaseE_2.sql(player_state), guild.sql, admin.sql(_admin_guard)

-- 1) PvP 랭커 정보 — 로그인 유저만. 순위로 조회(유저 id 노출 없음). 공개 필드만 반환:
--    닉네임 · 계정 레벨 · 리더 카드 id · 해당 리그/모드 PvP 덱(카드 id·레벨) · 소속 조직(이름·엠블럼)
create or replace function public.pvp_user_info(p_league text, p_mode text, p_rank int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); t uuid; g record; deck jsonb; lead text;
begin
  if uid is null then raise exception 'login required' using errcode = '42501'; end if;
  perform _pvp_ok(p_league, p_mode);
  if p_rank is null or p_rank < 1 or p_rank > 100 then raise exception 'bad rank'; end if;
  select x.user_id into t from (
    select user_id, row_number() over (order by rating desc, wins desc, user_id) rn from (
      select distinct on (r.user_id) r.user_id, r.rating, r.wins, r.losses
        from pvp_ratings r
       where r.league = p_league and r.mode = p_mode and r.wins + r.losses > 0
       order by r.user_id, r.season desc) z) x where x.rn = p_rank;
  if t is null then raise exception 'not found'; end if;
  select o->>'id' into lead from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
    where sp.user_id = t and o->>'uid' = sp.data->>'leader' limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('slot', d.slot, 'cards',
      (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', coalesce((c->>'level')::int, 1))), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(d.snap->'cards') = 'array' then d.snap->'cards' when jsonb_typeof(d.snap) = 'array' then d.snap else '[]'::jsonb end) c)) order by d.slot), '[]'::jsonb)
    into deck from pvp_decks d where d.user_id = t and d.league = p_league and d.mode = p_mode;
  select gg.name, gg.emblem into g from guild_members m join guilds gg on gg.id = m.guild_id where m.user_id = t;
  return jsonb_build_object('ok', true, 'rank', p_rank, 'me', t = uid,
    'name', coalesce((select nickname from profiles where id = t), '플레이어'),
    'level', coalesce((select level from player_state where user_id = t), 1),
    'leader', lead, 'decks', deck,
    'guild', case when g.name is null then null else jsonb_build_object('name', g.name, 'emblem', g.emblem) end);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_user_info(text, text, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_user_info(text, text, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 공지 게시판 — 누구나 읽기, 쓰기·수정·삭제는 관리자 RPC 만
create table if not exists public.notices (
  id         bigint generated always as identity primary key,
  body       text not null check (char_length(body) between 1 and 200),
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists notices_order_idx on public.notices (pinned desc, created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.notices enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.notices from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.notices to anon, authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists "notices_read_all" on public.notices;$vr_statement$;
  execute $vr_statement$create policy "notices_read_all" on public.notices for select to anon, authenticated using (true);$vr_statement$;
  execute $vr_statement$-- 저장: p_id null = 새 글, 아니면 수정
create or replace function public.admin_notice_save(p_id bigint, p_body text, p_pinned boolean) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare r notices; b text := btrim(coalesce(p_body, ''));
begin
  perform public._admin_guard();
  if char_length(b) not between 1 and 200 then raise exception 'body 1~200'; end if;
  if p_id is null then
    insert into notices (body, pinned) values (b, coalesce(p_pinned, false)) returning * into r;
  else
    update notices set body = b, pinned = coalesce(p_pinned, pinned), updated_at = now() where id = p_id returning * into r;
    if r.id is null then raise exception 'not found'; end if;
  end if;
  return to_jsonb(r);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_notice_delete(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  delete from notices where id = p_id;
  return jsonb_build_object('ok', found);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_notice_save(bigint, text, boolean), public.admin_notice_delete(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_notice_save(bigint, text, boolean), public.admin_notice_delete(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch0.sql =====
-- =====================================================================
-- 챕터 0 (튜토리얼 · 공허한 여신) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql, phaseE_2.sql, story_ch1_reward.sql (reward_card 열 · 고정 보상 지급)
--   페이즈 1~3, 첫 클리어 보상: 1 오유나 · 2 황보예 · 3 송지아 (이미 있으면 한 장 더)
--   새 사용자: 캐릭터(스타터)를 고르기 전에도 챕터 0 을 할 수 있음
--   기존 사용자: 진행 그대로. 챕터 0 은 다른 챕터의 열림 조건에 들어가지 않음 (챕터 1 은 챕터 0 클리어 없이 열림)
--   행동력: 다른 페이즈와 같이 6 (0 이면 소탕으로 공짜 반복 가능) · 챕터 0 전체 클리어 시 소환권 +10 (기존 규칙)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (0,1,'normal',3,null,1), (0,2,'normal',3,null,5), (0,3,'normal',3,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$update public.story_phase_config set reward_card = case phase when 1 then '10256' when 2 then '10462' when 3 then '10207' end where chapter = 0;$vr_statement$;
  execute $vr_statement$-- 원래 전투 시작(_e0, phaseE_2 가 감쌈)을 다시 정의: 챕터 0 은 스타터 불필요 · 챕터 0 은 다른 챕터 선행 조건에서 제외
create or replace function public._story_start_phase_e0(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  if p_chapter <> 0 and coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  -- 열림 조건: 같은 챕터의 이전 페이즈 모두 클리어 + 이전 챕터 전체 클리어 (챕터 0 은 다른 챕터 조건에서 빠짐)
  if exists (
    select 1 from story_phase_config c
    where (c.chapter < p_chapter or (c.chapter = p_chapter and c.phase < p_phase))
      and (c.chapter <> 0 or p_chapter = 0)
      and not (coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase))
  ) then raise exception 'phase locked'; end if;
  d := jsonb_set(d, '{battle}', jsonb_build_object('chapter', p_chapter, 'phase', p_phase, 'at', (extract(epoch from clock_timestamp()))::bigint));
  return _story_save(uid, d);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_start_phase_e0(int, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$select chapter, phase, type, reward_card from public.story_phase_config where chapter = 0 order by phase;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch0_pull.sql =====
-- =====================================================================
-- 챕터 0 클리어 후 강제 10회 프리미엄 영입 — 끝 표시(ch0Pull)를 서버 진행에 저장. 여러 번 실행해도 안전
-- 소환권 10장은 기존 규칙(챕터 전체 첫 클리어마다 +10, _story_ticket_sync · 계정당 한 번)이 그대로 지급 → 추가 지급 없음
-- story_mark_seen 허용 키에 'ch0Pull' 추가 (그 외 동작 동일)
-- =====================================================================
create or replace function public.story_mark_seen(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if p_key not in ('openingSeen', 'startSeen', 'ch0Pull') then raise exception 'invalid key'; end if;
  d := _story_lock(uid);
  return _story_save(uid, jsonb_set(d, array[p_key], 'true'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_mark_seen(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_mark_seen(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_v1.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _gear_grant, mail_claim 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 장비 시스템 v1 (PR1: DB 기반만, UI 없음) =====
-- 설계: 장비 시스템 초안 v4 Page. 여러 번 실행해도 안전 (if not exists / on conflict / create or replace)
-- 의존: phaseE_1.sql (player_wallet, wallet_log), gem.sql (_gem_spend), story_progress (owned[].id)
-- 등급 tier: 1 낡은 · 2 일반 · 3 고급 · 4 희귀 · 5 영웅 · 6 전설 · 7 심연 (6·7 = 이벤트 전용, event_only)
-- 쓰기는 전부 security definer RPC. 테이블은 정의=모두 읽기, 보유=본인만 읽기, 직접 쓰기 불가

-- 1) 정의 테이블 -------------------------------------------------------------
create table if not exists public.gear_defs (
  id         text primary key,                       -- 예: weapon_4_2
  slot       text not null check (slot in ('weapon','armor','acc')),
  tier       int  not null check (tier between 1 and 7),
  name       text not null,
  icon       text not null,                          -- img/gear/{slot}_{tier}_{n}.webp
  main_stat  text not null check (main_stat in ('atk','hp','def','crit','evade','mp')),
  main_pct   numeric not null check (main_pct > 0),  -- 무기 ATK +2%..+14% 등
  opt_count  int  not null default 0 check (opt_count between 0 and 3),
  event_only boolean not null default false,
  raid_only  boolean not null default false
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_opt_pool (       -- 랜덤 부옵션 범위 (slot별)
  slot text not null, opt text not null, min_v numeric not null, max_v numeric not null, min_tier int not null default 3,
  primary key (slot, opt)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_tier_gate (      -- 챕터·탑 대역 → 드롭 등급
  band       int primary key,                           -- 1..6
  ch_from    int not null, ch_to int not null, floor_from int not null, floor_to int not null,
  main_tier  int not null check (main_tier between 1 and 5),
  bonus_tier int not null check (bonus_tier between 1 and 5),
  bonus_pct  numeric not null check (bonus_pct between 0 and 100)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_drop_mode (      -- 난이도 모드 배율
  mode text primary key check (mode in ('normal','hard','hell','abyss')),
  bonus_mult numeric not null, up_pct numeric not null, sigil_frag_pct numeric not null
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_mode_config (    -- 모드별 장비 효과 (사용자 조절값)
  mode text primary key check (mode in ('story','tower','raid','pvp','war','arcade')),
  gear_pct numeric not null check (gear_pct between 0 and 100),
  sigil_max_plus int not null check (sigil_max_plus between 0 and 5)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_slot_price (     -- 가방 확장 (10칸 단위, 보석)
  slots_from int primary key, slots_to int not null, gem int not null check (gem > 0)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_raid_rewards (   -- 토벌 보상표 (PR5에서 사용)
  id serial primary key, kind text not null check (kind in ('drop','clear_box','rank_box')),
  stage_from int not null default 0, stage_to int not null default 0, rank_from int not null default 0, rank_to int not null default 0,
  tier int not null check (tier between 1 and 5), up_tier int check (up_tier between 1 and 5), up_pct numeric not null default 0,
  qty int not null default 1, sigil_frags int not null default 0,
  unique (kind, stage_from, rank_from)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_event_grants (   -- 전설·심연은 여기 적힌 것만 지급 (PR7, 지금은 비어 있음)
  id serial primary key, event_key text not null, def_id text not null references public.gear_defs(id),
  starts_at timestamptz not null, ends_at timestamptz not null, note text,
  unique (event_key, def_id)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.sigil_defs (
  card_id   text primary key,                          -- data/cards.csv id
  name      text not null,
  effects   int  not null check (effects in (1,2)),   -- SR 1, UR 이상 2
  steps     jsonb not null,                            -- [{plus:0, mods:{...}}, ... +5]
  icon      text not null
);$vr_statement$;
  execute $vr_statement$create table if not exists public.sigil_sources (       -- 인재별 조각 획득처 (최소 2곳)
  card_id text not null references public.sigil_defs(card_id), source text not null
    check (source in ('story_boss','raid_select','guild_shop','pvp_shop','event','exchange')),
  ref text, primary key (card_id, source)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.sigil_cost (          -- 단계별 필요 조각: 제작 50, +1 30, +2 50, +3 80, +4 120, +5 200 = 530
  plus int primary key check (plus between 0 and 5), frags int not null check (frags > 0)
);$vr_statement$;
  execute $vr_statement$-- 2) 보유 테이블 -------------------------------------------------------------
create table if not exists public.player_gear (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  def_id      text not null references public.gear_defs(id),
  plus        int  not null default 0 check (plus between 0 and 5),
  opts        jsonb not null default '[]'::jsonb,
  locked      boolean not null default false,
  equipped_card text,                                  -- story_progress owned[].id
  source      text not null,
  created_at  timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists player_gear_user on public.player_gear (user_id);$vr_statement$;
  execute $vr_statement$create unique index if not exists player_gear_one_slot on public.player_gear (user_id, equipped_card, (split_part(def_id, '_', 1))) where equipped_card is not null;$vr_statement$;
  execute $vr_statement$create table if not exists public.player_gear_meta (
  user_id uuid primary key references auth.users(id) on delete cascade,
  slots   int not null default 100 check (slots between 100 and 200),
  dust    bigint not null default 0 check (dust >= 0),   -- 장비 가루 (분해 재료)
  updated_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create table if not exists public.player_sigils (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null references public.sigil_defs(card_id),
  plus    int check (plus between 0 and 5),              -- null = 아직 제작 전 (조각만 있음)
  frags   int not null default 0 check (frags >= 0),
  primary key (user_id, card_id)
);$vr_statement$;
  execute $vr_statement$create table if not exists public.player_mail (          -- 우편함 (기존 우편함 없음 → 신설). 7일 보관
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('gear','sigil_frag','gold','gem')),
  payload jsonb not null, reason text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  claimed_at timestamptz
);$vr_statement$;
  execute $vr_statement$create index if not exists player_mail_user on public.player_mail (user_id) where claimed_at is null;$vr_statement$;
  execute $vr_statement$-- 3) RLS ---------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['gear_defs','gear_opt_pool','gear_tier_gate','gear_drop_mode','gear_mode_config','gear_slot_price','gear_raid_rewards','sigil_defs','sigil_sources','sigil_cost'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
  foreach t in array array['player_gear','player_gear_meta','player_sigils','player_mail'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())', t || '_own', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$alter table public.gear_event_grants enable row level security;$vr_statement$;
  execute $vr_statement$-- 이벤트 표는 클라이언트 비공개
revoke all on public.gear_event_grants from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 내부 함수 ---------------------------------------------------------------
create or replace function public._gear_meta(p_uid uuid) returns public.player_gear_meta
language plpgsql security definer set search_path = public as $$
declare m player_gear_meta;
begin
  insert into player_gear_meta (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into m from player_gear_meta where user_id = p_uid for update;
  return m;
end $$;$vr_statement$;
  execute $vr_statement$-- 랜덤 부옵션
create or replace function public._gear_roll_opts(p_def text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare d gear_defs; r jsonb := '[]'::jsonb; o record;
begin
  select * into d from gear_defs where id = p_def;
  for o in select * from gear_opt_pool where slot = d.slot and min_tier <= d.tier order by random() limit d.opt_count loop
    r := r || jsonb_build_array(jsonb_build_object('opt', o.opt, 'v', round((o.min_v + random() * (o.max_v - o.min_v))::numeric, 1)));
  end loop;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$-- 장비 지급 (유일한 생성 경로). 영웅(5) 초과는 이벤트 지급표에 있을 때만
-- p_to_mail=true 면 가방이 꽉 차도 우편함으로. false 면 꽉 찼을 때 'bag full' 예외 (소탕·탑은 시작 전에 막음)
create or replace function public._gear_grant(p_uid uuid, p_def text, p_source text, p_to_mail boolean default false, p_event text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d gear_defs; m player_gear_meta; n int; gid bigint;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into d from gear_defs where id = p_def;
  if not found then raise exception 'unknown gear'; end if;
  if d.tier > 5 or d.event_only then
    if p_source <> 'event' or p_event is null or not exists (
      select 1 from gear_event_grants e where e.event_key = p_event and e.def_id = p_def and now() between e.starts_at and e.ends_at)
    then raise exception 'tier above hero is event only'; end if;
  end if;
  m := _gear_meta(p_uid);
  select count(*) into n from player_gear where user_id = p_uid;
  if n >= m.slots then
    if not p_to_mail then raise exception 'bag full'; end if;
    insert into player_mail (user_id, kind, payload, reason) values (p_uid, 'gear', jsonb_build_object('def_id', p_def, 'source', p_source, 'event', p_event), p_source);
    return jsonb_build_object('ok', true, 'mail', true);
  end if;
  insert into player_gear (user_id, def_id, opts, source, locked)
    values (p_uid, p_def, _gear_roll_opts(p_def), p_source, d.tier >= 6) returning id into gid;
  return jsonb_build_object('ok', true, 'gear_id', gid);
end $$;$vr_statement$;
  execute $vr_statement$-- 드롭 등급 결정 (소탕·탑). 결과는 항상 1..5. 모드 보너스도 영웅에서 멈춤
create or replace function public._gear_roll_tier(p_chapter int, p_floor int, p_mode text default 'normal') returns int
language plpgsql volatile security definer set search_path = public as $$
declare g gear_tier_gate; dm gear_drop_mode; t int;
begin
  select * into g from gear_tier_gate
    where (p_chapter is not null and p_chapter between ch_from and ch_to) or (p_floor is not null and p_floor between floor_from and floor_to)
    order by band desc limit 1;
  if not found then select * into g from gear_tier_gate order by band limit 1; end if;
  select * into dm from gear_drop_mode where mode = coalesce(p_mode, 'normal');
  if not found then select * into dm from gear_drop_mode where mode = 'normal'; end if;
  t := g.main_tier;
  if random() * 100 < g.bonus_pct * dm.bonus_mult then t := g.bonus_tier; end if;
  if random() * 100 < dm.up_pct then t := t + 1; end if;
  return least(t, 5);
end $$;$vr_statement$;
  execute $vr_statement$-- 장비 1개 드롭 (슬롯 랜덤). 영웅 초과는 _gear_grant 에서도 다시 거부
create or replace function public._gear_drop(p_uid uuid, p_chapter int, p_floor int, p_mode text, p_source text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t int; did text;
begin
  t := _gear_roll_tier(p_chapter, p_floor, p_mode);
  select id into did from gear_defs where tier = t and not event_only and not raid_only order by random() limit 1;
  return _gear_grant(p_uid, did, p_source, false, null);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_meta(uuid), public._gear_roll_opts(text), public._gear_grant(uuid, text, text, boolean, text),
  public._gear_roll_tier(int, int, text), public._gear_drop(uuid, int, int, text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 공개 RPC (authenticated) ------------------------------------------------
-- 내 장비·증표·가방·우편 요약
create or replace function public.gear_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m player_gear_meta; nx gear_slot_price;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _gear_meta(uid);
  select * into nx from gear_slot_price where slots_from = m.slots + 1;
  return jsonb_build_object(
    'slots', m.slots, 'dust', m.dust,
    'count', (select count(*) from player_gear where user_id = uid),
    'next_expand', case when nx.slots_from is null then null else jsonb_build_object('to', nx.slots_to, 'gem', nx.gem) end,
    'gear', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'def', g.def_id, 'plus', g.plus, 'opts', g.opts, 'locked', g.locked, 'card', g.equipped_card) order by g.id)
                      from player_gear g where g.user_id = uid), '[]'::jsonb),
    'sigils', coalesce((select jsonb_agg(jsonb_build_object('card', s.card_id, 'plus', s.plus, 'frags', s.frags)) from player_sigils s where s.user_id = uid), '[]'::jsonb),
    'mail', (select count(*) from player_mail where user_id = uid and claimed_at is null and expires_at > now()));
end $$;$vr_statement$;
  execute $vr_statement$-- 가방 확장 10칸 (보석)
create or replace function public.gear_expand() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m player_gear_meta; p gear_slot_price; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _gear_meta(uid);
  select * into p from gear_slot_price where slots_from = m.slots + 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'max'); end if;
  g := _gem_spend(uid, p.gem, 'gear_expand', jsonb_build_object('to', p.slots_to));
  update player_gear_meta set slots = p.slots_to, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'slots', p.slots_to, 'gem', p.gem, 'wallet', g);
exception when others then
  if sqlerrm = 'not enough gem' then return jsonb_build_object('ok', false, 'reason', 'gem', 'need', p.gem); end if;
  raise;
end $$;$vr_statement$;
  execute $vr_statement$-- 잠금
create or replace function public.gear_lock(p_gear bigint, p_locked boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  update player_gear set locked = coalesce(p_locked, false) where id = p_gear and user_id = uid;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 장착 (같은 인재 같은 슬롯에 있던 장비는 자동 해제). 인재는 story_progress.owned 에 있어야 함
create or replace function public.gear_equip(p_gear bigint, p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; sl text;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into g from player_gear where id = p_gear and user_id = uid for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if not exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
                 where sp.user_id = uid and o->>'id' = p_card) then
    return jsonb_build_object('ok', false, 'reason', 'card not owned'); end if;
  sl := split_part(g.def_id, '_', 1);
  update player_gear set equipped_card = null where user_id = uid and equipped_card = p_card and split_part(def_id, '_', 1) = sl and id <> p_gear;
  update player_gear set equipped_card = p_card where id = p_gear;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.gear_unequip(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  update player_gear set equipped_card = null where id = p_gear and user_id = uid;
  return jsonb_build_object('ok', found);
end $$;$vr_statement$;
  execute $vr_statement$-- 우편 목록
create or replace function public.mail_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'payload', payload, 'reason', reason, 'expires_at', expires_at) order by id)
    from player_mail where user_id = uid and claimed_at is null and expires_at > now()), '[]'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$-- 우편 받기 (지금은 장비만. 가방이 차 있으면 거부)
create or replace function public.mail_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; d gear_defs; m player_gear_meta; n int; gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if ml.kind <> 'gear' then return jsonb_build_object('ok', false, 'reason', 'unsupported'); end if;
  m := _gear_meta(uid);
  select count(*) into n from player_gear where user_id = uid;
  if n >= m.slots then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  select * into d from gear_defs where id = ml.payload->>'def_id';
  -- 우편은 지급 시점에 이미 검사됨. 그래도 영웅 초과는 이벤트 우편만 허용
  if d.tier > 5 and coalesce(ml.payload->>'source', '') <> 'event' then return jsonb_build_object('ok', false, 'reason', 'event only'); end if;
  insert into player_gear (user_id, def_id, opts, source, locked) values (uid, d.id, _gear_roll_opts(d.id), 'mail:' || ml.reason, d.tier >= 6) returning id into gid;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'gear_id', gid);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gear_status(), public.gear_expand(), public.gear_lock(bigint, boolean), public.gear_equip(bigint, text),
  public.gear_unequip(bigint), public.mail_list(), public.mail_claim(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gear_status(), public.gear_expand(), public.gear_lock(bigint, boolean), public.gear_equip(bigint, text),
  public.gear_unequip(bigint), public.mail_list(), public.mail_claim(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 시드 데이터 -------------------------------------------------------------
insert into gear_defs (id, slot, tier, name, icon, main_stat, main_pct, opt_count, event_only, raid_only)
select v.id, v.slot, v.tier, v.name, 'img/gear/' || v.id || '.webp', v.ms, v.pct, v.oc, v.tier >= 6, false
from (values
  ('weapon_1_1','weapon',1,'녹슨 쇠파이프','atk',2,0),('weapon_1_2','weapon',1,'나무 배트','atk',2,0),('weapon_1_3','weapon',1,'각목','atk',2,0),
  ('weapon_2_1','weapon',2,'쇠파이프','atk',4,0),('weapon_2_2','weapon',2,'알루미늄 야구배트','atk',4,0),('weapon_2_3','weapon',2,'커터칼','atk',4,0),
  ('weapon_3_1','weapon',3,'강철 야구배트','atk',6,1),('weapon_3_2','weapon',3,'삼단봉','atk',6,1),('weapon_3_3','weapon',3,'너클봉','atk',6,1),
  ('weapon_4_1','weapon',4,'낫','atk',8,1),('weapon_4_2','weapon',4,'사시미','atk',8,1),('weapon_4_3','weapon',4,'체인','atk',8,1),
  ('weapon_5_1','weapon',5,'스턴건','atk',10,2),('weapon_5_2','weapon',5,'전기봉','atk',10,2),('weapon_5_3','weapon',5,'제작 강철 너클봉','atk',10,2),
  ('weapon_6_1','weapon',6,'전기톱','atk',12,2),('weapon_6_2','weapon',6,'권총','atk',12,2),('weapon_6_3','weapon',6,'환도','atk',12,2),
  ('weapon_7_1','weapon',7,'심연의 낫','atk',14,3),('weapon_7_2','weapon',7,'검은 권총','atk',14,3),('weapon_7_3','weapon',7,'혼이 담긴 사시미','atk',14,3),
  ('armor_1_1','armor',1,'닳은 교복','hp',2,0),('armor_1_2','armor',1,'늘어난 트레이닝복','def',2,0),
  ('armor_2_1','armor',2,'교복','hp',4,0),('armor_2_2','armor',2,'트레이닝복','def',4,0),('armor_2_3','armor',2,'후드티','hp',4,0),
  ('armor_3_1','armor',3,'가죽자켓','def',6,1),('armor_3_2','armor',3,'야상 점퍼','hp',6,1),('armor_3_3','armor',3,'작업복','def',6,1),
  ('armor_4_1','armor',4,'라이더 자켓','def',8,1),('armor_4_2','armor',4,'검은 정장','hp',8,1),('armor_4_3','armor',4,'롱코트','hp',8,1),
  ('armor_5_1','armor',5,'방검조끼','def',10,2),('armor_5_2','armor',5,'가죽 코트','hp',10,2),('armor_5_3','armor',5,'전술 점퍼','def',10,2),
  ('armor_6_1','armor',6,'방탄조끼','def',12,2),('armor_6_2','armor',6,'주문 정장','hp',12,2),('armor_6_3','armor',6,'두리 방상 점퍼','def',12,2),
  ('armor_7_1','armor',7,'심연 정장','hp',14,3),('armor_7_2','armor',7,'심연 가죽자켓','def',14,3),
  ('acc_1_1','acc',1,'플라스틱 선글라스','crit',1,0),('acc_1_2','acc',1,'고무줄 팔찌','evade',1,0),
  ('acc_2_1','acc',2,'선글라스','crit',2,0),('acc_2_2','acc',2,'은반지','evade',2,0),('acc_2_3','acc',2,'손목시계','mp',2,0),
  ('acc_3_1','acc',3,'너클','crit',3,1),('acc_3_2','acc',3,'무전기','mp',3,1),('acc_3_3','acc',3,'은목걸이','evade',3,1),
  ('acc_4_1','acc',4,'금목걸이','crit',4,1),('acc_4_2','acc',4,'금반지','evade',4,1),('acc_4_3','acc',4,'호출기','mp',4,1),
  ('acc_5_1','acc',5,'금시계','crit',5,2),('acc_5_2','acc',5,'대포폰','mp',5,2),('acc_5_3','acc',5,'장미 문신 패치','evade',5,2),
  ('acc_6_1','acc',6,'두꺼운 금목걸이','crit',6,2),('acc_6_2','acc',6,'암호 무전기','mp',6,2),('acc_6_3','acc',6,'조직 배지','evade',6,2),
  ('acc_7_1','acc',7,'심연의 금목걸이','crit',7,3),('acc_7_2','acc',7,'검은 너클','crit',7,3),('acc_7_3','acc',7,'심연 선글라스','evade',7,3)
) v(id, slot, tier, name, ms, pct, oc)
on conflict (id) do update set slot = excluded.slot, tier = excluded.tier, name = excluded.name, icon = excluded.icon,
  main_stat = excluded.main_stat, main_pct = excluded.main_pct, opt_count = excluded.opt_count, event_only = excluded.event_only;$vr_statement$;
  execute $vr_statement$insert into gear_opt_pool (slot, opt, min_v, max_v, min_tier) values
  ('weapon','crit_dmg',3,10,3),('weapon','elem_dmg',2,8,3),('weapon','crit',1,3,3),
  ('armor','dmg_reduce',1,5,3),('armor','debuff_resist',3,10,3),('armor','evade',1,3,3),
  ('acc','mp_regen',1,5,3),('acc','kill_mp',2,6,3),('acc','cooldown',1,1,6)
on conflict (slot, opt) do update set min_v = excluded.min_v, max_v = excluded.max_v, min_tier = excluded.min_tier;$vr_statement$;
  execute $vr_statement$insert into gear_tier_gate (band, ch_from, ch_to, floor_from, floor_to, main_tier, bonus_tier, bonus_pct) values
  (1, 0, 5, 1, 29, 1, 2, 20), (2, 6, 10, 30, 59, 2, 3, 10), (3, 11, 15, 60, 89, 2, 4, 2),
  (4, 16, 20, 90, 119, 3, 4, 5), (5, 21, 25, 120, 149, 3, 5, 1), (6, 26, 30, 150, 100000, 4, 5, 3)
on conflict (band) do update set ch_from = excluded.ch_from, ch_to = excluded.ch_to, floor_from = excluded.floor_from, floor_to = excluded.floor_to,
  main_tier = excluded.main_tier, bonus_tier = excluded.bonus_tier, bonus_pct = excluded.bonus_pct;$vr_statement$;
  execute $vr_statement$insert into gear_drop_mode (mode, bonus_mult, up_pct, sigil_frag_pct) values
  ('normal', 1, 0, 15), ('hard', 1.5, 0.5, 20), ('hell', 2, 1, 25), ('abyss', 2.5, 2, 30)
on conflict (mode) do update set bonus_mult = excluded.bonus_mult, up_pct = excluded.up_pct, sigil_frag_pct = excluded.sigil_frag_pct;$vr_statement$;
  execute $vr_statement$insert into gear_mode_config (mode, gear_pct, sigil_max_plus) values
  ('story', 100, 5), ('tower', 100, 5), ('raid', 100, 5), ('pvp', 50, 3), ('war', 50, 3), ('arcade', 0, 0)
on conflict (mode) do nothing;$vr_statement$;
  execute $vr_statement$-- 사용자 조절값: 다시 실행해도 덮어쓰지 않음

insert into gear_slot_price (slots_from, slots_to, gem) values
  (101, 110, 100), (111, 120, 100), (121, 130, 150), (131, 140, 150), (141, 150, 200),
  (151, 160, 200), (161, 170, 400), (171, 180, 400), (181, 190, 1000), (191, 200, 1000)
on conflict (slots_from) do update set slots_to = excluded.slots_to, gem = excluded.gem;$vr_statement$;
  execute $vr_statement$insert into gear_raid_rewards (kind, stage_from, stage_to, rank_from, rank_to, tier, up_tier, up_pct, qty, sigil_frags) values
  ('drop', 1, 3, 0, 0, 3, 4, 10, 1, 0), ('drop', 4, 6, 0, 0, 4, null, 0, 1, 0), ('drop', 7, 99, 0, 0, 4, 5, 5, 1, 0),
  ('clear_box', 1, 6, 0, 0, 4, null, 0, 1, 0), ('clear_box', 7, 99, 0, 0, 4, 5, 15, 1, 0),
  ('rank_box', 0, 0, 1, 1, 5, null, 0, 1, 6), ('rank_box', 0, 0, 2, 3, 4, 5, 20, 2, 4),
  ('rank_box', 0, 0, 4, 10, 4, null, 0, 1, 3), ('rank_box', 0, 0, 11, 100000, 3, null, 0, 1, 2)
on conflict (kind, stage_from, rank_from) do nothing;$vr_statement$;
  execute $vr_statement$insert into sigil_cost (plus, frags) values (0, 50), (1, 30), (2, 50), (3, 80), (4, 120), (5, 200)
on conflict (plus) do update set frags = excluded.frags;$vr_statement$;
  execute $vr_statement$insert into sigil_defs (card_id, name, effects, icon, steps) values
('10118', '무답무용', 1, 'img/gear/sigil_10118.webp', '[
 {"plus":0,"skill":"무답무용","hit_pct":35,"hits":6,"bleed_pct":40},
 {"plus":1,"skill":"무답무용","hit_pct":40,"hits":6,"bleed_pct":45},
 {"plus":2,"skill":"무답무용","hit_pct":40,"hits":7,"bleed_pct":50,"cooldown":3},
 {"plus":3,"skill":"무답무용","hit_pct":45,"hits":7,"bleed_pct":60,"cooldown":3},
 {"plus":4,"skill":"무답무용","hit_pct":50,"hits":7,"bleed_pct":70,"cooldown":3},
 {"plus":5,"skill":"무답무용","hit_pct":50,"hits":7,"bleed_pct":70,"cooldown":3,"vs_bleed_dmg_pct":30,"on_kill_extra_hits":3}]'::jsonb),
('10415', '제발 그냥 가줘', 1, 'img/gear/sigil_10415.webp', '[
 {"plus":0,"skill":"제발 그냥 가줘","cooldown":6,"mp":75,"fallback_hp_pct":40},
 {"plus":1,"skill":"제발 그냥 가줘","cooldown":6,"mp":70,"fallback_hp_pct":50},
 {"plus":2,"skill":"제발 그냥 가줘","cooldown":5,"mp":65,"fallback_hp_pct":50,"also":{"skill":"나 좀 내버려둬","cooldown":4}},
 {"plus":3,"skill":"제발 그냥 가줘","cooldown":4,"mp":60,"fallback_hp_pct":60,"also":{"skill":"나 좀 내버려둬","cooldown":4}},
 {"plus":4,"skill":"제발 그냥 가줘","cooldown":4,"mp":55,"fallback_hp_pct":60,"also":{"skill":"나 좀 내버려둬","cooldown":4,"duration":2}},
 {"plus":5,"skill":"제발 그냥 가줘","cooldown":3,"mp":50,"fallback_hp_pct":60,"targets":2,"also":{"skill":"나 좀 내버려둬","cooldown":4,"duration":2}}]'::jsonb),
('10325', '피어난 키스', 2, 'img/gear/sigil_10325.webp', '[
 {"plus":0,"a":{"skill":"천천히 찢는 사랑","hit_pct":55,"hits":2,"bleed_pct":70},"b":{"hp_pct":[10,15],"cap":[160,240],"cc_pct":40}},
 {"plus":1,"a":{"skill":"천천히 찢는 사랑","hit_pct":60,"hits":2,"bleed_pct":75},"b":{"hp_pct":[10,15],"cap":[180,270],"cc_pct":45}},
 {"plus":2,"a":{"skill":"천천히 찢는 사랑","hit_pct":50,"hits":3,"bleed_pct":80},"b":{"hp_pct":[12,18],"cap":[200,300],"cc_pct":50}},
 {"plus":3,"a":{"skill":"천천히 찢는 사랑","hit_pct":55,"hits":3,"bleed_pct":80,"bleed_dmg_pct":8},"b":{"hp_pct":[12,18],"cap":[200,300],"cc_pct":50,"mp":35}},
 {"plus":4,"a":{"skill":"천천히 찢는 사랑","hit_pct":60,"hits":3,"bleed_pct":90,"bleed_dmg_pct":8},"b":{"hp_pct":[14,20],"cap":[230,340],"cc_pct":55,"mp":35}},
 {"plus":5,"a":{"skill":"천천히 찢는 사랑","hit_pct":65,"hits":3,"bleed_pct":100,"bleed_dmg_pct":8,"vs_bleed_dmg_pct":30},"b":{"hp_pct":[15,22],"cap":[230,340],"cc_pct":60,"mp":35,"cc_then_bleed":true}}]'::jsonb)
on conflict (card_id) do update set name = excluded.name, effects = excluded.effects, icon = excluded.icon, steps = excluded.steps;$vr_statement$;
  execute $vr_statement$insert into sigil_sources (card_id, source, ref) values
  ('10118','story_boss',null),('10118','raid_select',null),('10118','pvp_shop',null),('10118','exchange',null),
  ('10415','story_boss',null),('10415','raid_select',null),('10415','pvp_shop',null),('10415','exchange',null),
  ('10325','story_boss',null),('10325','raid_select',null),('10325','guild_shop',null),('10325','exchange',null)
on conflict do nothing;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_snap.sql =====
-- ===== 장비 PR3: 전투 스냅샷에 장비·증표 붙이기 =====
-- 선행: pvp.sql(_pvp_snap · pvp_card_meta) · gear_v1.sql. 여러 번 실행해도 안전 (create or replace)
-- PvP·토벌·세력전 덱은 모두 _pvp_snap 으로 서버가 만든 스냅샷을 씀 → 여기서 장비를 붙이면 클라이언트가 장비를 꾸밀 수 없음
-- 카드마다 gear: [{ def, stat, pct, plus, opts }] (장착한 것만), sigil: 증표 단계(없으면 null). 모드 배율(PvP·세력전 50%, 증표 +3)은
-- 전투 코어(js/gear-core.js GEAR_MODE)가 적용. 참고 값: gear_mode_config

create or replace function public._gear_snap(p_user uuid, p_card text) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'gear', coalesce((select jsonb_agg(jsonb_build_object('def', g.def_id, 'stat', d.main_stat, 'pct', d.main_pct, 'plus', g.plus, 'opts', g.opts) order by d.slot)
                      from player_gear g join gear_defs d on d.id = g.def_id where g.user_id = p_user and g.equipped_card = p_card), '[]'::jsonb),
    'sigil', (select to_jsonb(s.plus) from player_sigils s where s.user_id = p_user and s.card_id = p_card and s.plus is not null))
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_snap(uuid, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- pvp.sql 의 _pvp_snap 과 같고, 카드마다 _gear_snap 결과(gear·sigil)만 덧붙임
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
    out := out || (jsonb_build_object('uid', u, 'id', o->>'id', 'level', coalesce((o->>'level')::int, 1), 'ex', coalesce((o->>'ex')::int, 0),
      'exb', coalesce((o->>'exb')::numeric, 0), 'boost', coalesce(o->'boost', '{}'::jsonb), 'skillLv', coalesce(o->'skillLv', '{}'::jsonb))
      || _gear_snap(p_user, o->>'id'));
  end loop;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', out, 'cost', cost);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_snap(uuid, jsonb, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_drops.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _gear_raid_claim_trg, mail_claim, story_sweep 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 장비 PR4: 드롭 (소탕·탑·조직 토벌) + 토벌 상자 + 우편함 =====
-- 선행: gear_v1.sql · guild2.sql · guild3.sql · tower_v2.sql · phaseE_5.sql. 여러 번 실행해도 안전
-- · 등급: gear_tier_gate (챕터·층 대역, 희귀는 챕터 11부터 2%, 일반 콘텐츠 최대 5 영웅). 전설·심연은 _gear_grant 가 이벤트 외 거부
-- · 확률: gear_drop_rate (조절값, 다시 실행해도 덮어쓰지 않음)
-- · 가방이 꽉 차면: 스토리 소탕·탑 시작을 막음('bag full'). 토벌 드롭·상자는 우편함으로
-- · 부옵션은 드롭 순간에 굴림 (우편으로 가도 그 값 그대로)
-- · 획득 기록 gear_drop_log → 결과 화면이 gear_drops_take() 로 가져가 보여줌

-- 1) 표 -----------------------------------------------------------------------
create table if not exists public.gear_drop_rate (
  source text primary key check (source in ('story_sweep', 'tower', 'raid')),
  pct numeric not null check (pct between 0 and 100)
);$vr_statement$;
  execute $vr_statement$insert into public.gear_drop_rate (source, pct) values ('story_sweep', 30), ('tower', 35), ('raid', 100) on conflict (source) do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_drop_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null, def_id text not null, gear_id bigint, mail_id bigint, kind text not null default 'gear',
  created_at timestamptz not null default now(), seen boolean not null default false
);$vr_statement$;
  execute $vr_statement$create index if not exists gear_drop_log_unseen on public.gear_drop_log (user_id) where not seen;$vr_statement$;
  execute $vr_statement$alter table public.gear_drop_rate enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gear_drop_rate from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.gear_drop_rate to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists gear_drop_rate_read on public.gear_drop_rate;$vr_statement$;
  execute $vr_statement$create policy gear_drop_rate_read on public.gear_drop_rate for select to authenticated using (true);$vr_statement$;
  execute $vr_statement$alter table public.gear_drop_log enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.gear_drop_log from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.gear_drop_log to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists gear_drop_log_own on public.gear_drop_log;$vr_statement$;
  execute $vr_statement$create policy gear_drop_log_own on public.gear_drop_log for select to authenticated using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$-- 우편 종류에 'box'(토벌 상자) 추가
alter table public.player_mail drop constraint if exists player_mail_kind_check;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add constraint player_mail_kind_check check (kind in ('gear', 'box', 'sigil_frag', 'gold', 'gem'));$vr_statement$;
  execute $vr_statement$-- 2) 지급 (부옵션은 지금 굴림. 꽉 차면 p_to_mail 이면 우편, 아니면 'bag full') -------------
create or replace function public._gear_grant(p_uid uuid, p_def text, p_source text, p_to_mail boolean default false, p_event text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d gear_defs; m player_gear_meta; n int; gid bigint; mid bigint; o jsonb;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into d from gear_defs where id = p_def;
  if not found then raise exception 'unknown gear'; end if;
  if d.tier > 5 or d.event_only then
    if p_source <> 'event' or p_event is null or not exists (
      select 1 from gear_event_grants e where e.event_key = p_event and e.def_id = p_def and now() between e.starts_at and e.ends_at)
    then raise exception 'tier above hero is event only'; end if;
  end if;
  o := _gear_roll_opts(p_def);
  m := _gear_meta(p_uid);
  select count(*) into n from player_gear where user_id = p_uid;
  if n >= m.slots then
    if not p_to_mail then raise exception 'bag full'; end if;
    insert into player_mail (user_id, kind, payload, reason) values (p_uid, 'gear', jsonb_build_object('def_id', p_def, 'source', p_source, 'event', p_event, 'opts', o), p_source)
      returning id into mid;
    return jsonb_build_object('ok', true, 'mail', true, 'mail_id', mid, 'def_id', p_def);
  end if;
  insert into player_gear (user_id, def_id, opts, source, locked) values (p_uid, p_def, o, p_source, d.tier >= 6) returning id into gid;
  return jsonb_build_object('ok', true, 'gear_id', gid, 'def_id', p_def);
end $$;$vr_statement$;
  execute $vr_statement$-- 등급 하나 → 장비 하나 (슬롯 지정 가능) + 기록. 영웅(5) 초과는 거부
create or replace function public._gear_give_tier(p_uid uuid, p_tier int, p_slot text, p_source text, p_to_mail boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare did text; r jsonb;
begin
  if p_tier is null or p_tier < 1 or p_tier > 5 then raise exception 'drop tier out of range'; end if;
  select id into did from gear_defs where tier = p_tier and not event_only and (p_slot is null or slot = p_slot) order by random() limit 1;
  if did is null then return null; end if;
  r := _gear_grant(p_uid, did, p_source, p_to_mail, null);
  insert into gear_drop_log (user_id, source, def_id, gear_id, mail_id) values (p_uid, p_source, did, (r->>'gear_id')::bigint, (r->>'mail_id')::bigint);
  return r;
end $$;$vr_statement$;
  execute $vr_statement$-- 소탕·탑: 확률 굴림 후 챕터/층 대역 등급으로 1개 (가방이 중간에 차면 우편)
create or replace function public._gear_try_drop(p_uid uuid, p_chapter int, p_floor int, p_source text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pct numeric;
begin
  select r.pct into pct from gear_drop_rate r where r.source = p_source;
  if random() * 100 >= coalesce(pct, 0) then return null; end if;
  return _gear_give_tier(p_uid, _gear_roll_tier(p_chapter, p_floor, 'normal'), null, p_source, true);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._gear_bag_full(p_uid uuid) returns boolean language sql security definer set search_path = public as $$
  select (select count(*) from player_gear where user_id = p_uid) >= (_gear_meta(p_uid)).slots $$;$vr_statement$;
  execute $vr_statement$-- 토벌 상자 → 우편 (열 때 슬롯 선택)
create or replace function public._gear_box_mail(p_uid uuid, rw gear_raid_rewards, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare mid bigint;
begin
  for i in 1 .. greatest(rw.qty, 1) loop
    insert into player_mail (user_id, kind, payload, reason, expires_at)
      values (p_uid, 'box', jsonb_build_object('tier', rw.tier, 'up_tier', rw.up_tier, 'up_pct', rw.up_pct), p_reason, now() + interval '14 days') returning id into mid;
    insert into gear_drop_log (user_id, source, def_id, mail_id, kind) values (p_uid, p_reason, 'box_' || rw.tier, mid, 'box');
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_grant(uuid, text, text, boolean, text), public._gear_give_tier(uuid, int, text, text, boolean),
  public._gear_try_drop(uuid, int, int, text), public._gear_bag_full(uuid), public._gear_box_mail(uuid, gear_raid_rewards, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 탑: 시작 막기 + 층 클리어마다 드롭 (tower_progress 트리거, 기존 함수는 그대로) ----------
create or replace function public._gear_tower_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare n int; fl int;
begin
  if new.battle is not null and old.battle is null and _gear_bag_full(new.user_id) then raise exception 'bag full'; end if;
  n := new.clears - old.clears;
  if n > 0 and n <= 50 then
    fl := greatest(new.best_floor, coalesce((old.battle->>'floor')::int, 0), 1);
    for i in 1 .. n loop perform _gear_try_drop(new.user_id, null, fl, 'tower'); end loop;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_tower_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists gear_tower_drop on public.tower_progress;$vr_statement$;
  execute $vr_statement$create trigger gear_tower_drop before update on public.tower_progress for each row execute function public._gear_tower_trg();$vr_statement$;
  execute $vr_statement$-- 4) 조직 토벌: 도전(직접·소탕) 끝날 때 드롭, 처치·순위 보상 받을 때 상자 -------------------
create or replace function public._gear_raid_attempt_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; t int;
begin
  if old.finished_at is null and new.finished_at is not null and coalesce(new.damage, 0) > 0 and not coalesce(new.voided, false) then
    if random() * 100 >= coalesce((select pct from gear_drop_rate where source = 'raid'), 0) then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'drop' and new.stage between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is null then return new; end if;
    t := rw.tier; if rw.up_tier is not null and random() * 100 < rw.up_pct then t := rw.up_tier; end if;
    perform _gear_give_tier(new.user_id, least(t, 5), null, 'raid', true);
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_raid_attempt_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists gear_raid_drop on public.guild_raid_attempts;$vr_statement$;
  execute $vr_statement$create trigger gear_raid_drop after update on public.guild_raid_attempts for each row execute function public._gear_raid_attempt_trg();$vr_statement$;
  execute $vr_statement$create or replace function public._gear_raid_claim_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; st int; rk int;
begin
  if new.ref like 'raidst:%' then
    st := split_part(new.ref, ':', 3)::int;
    select * into rw from gear_raid_rewards where kind = 'clear_box' and st between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_clear'); end if;
  elsif new.ref like 'raidrk:%' then
    rk := nullif(new.reward->>'rank', '')::int;
    if rk is null then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'rank_box' and rk between rank_from and rank_to order by rank_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_rank'); end if;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_raid_claim_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists gear_raid_box on public.guild_claims;$vr_statement$;
  execute $vr_statement$create trigger gear_raid_box after insert on public.guild_claims for each row execute function public._gear_raid_claim_trg();$vr_statement$;
  execute $vr_statement$-- 5) 스토리 소탕: guild2.sql 의 story_sweep 그대로 + 가방 검사(행동력 쓰기 전) + 회차마다 드롭 ---------
create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb; gear jsonb := '[]'::jsonb; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_runs is null or p_runs not in (1, 5, 10) then raise exception 'invalid runs'; end if;
  if not _player_unlocked(uid, 'sweep') then raise exception 'sweep locked (player Lv%)', _player_unlock_level('sweep'); end if;
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if not found then raise exception 'unknown phase'; end if;
  select data into d from story_progress where user_id = uid for update;
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  if _gear_bag_full(uid) then raise exception 'bag full'; end if;   -- 장비 PR4: 가방이 꽉 차면 소탕 불가
  cost := _stamina_cost(p_chapter, p_phase);
  perform _player_stamina_add(uid, -cost * p_runs);   -- 부족하면 'not enough stamina' (전체 롤백)
  for i in 1..p_runs loop
    dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), false, cost, random()::numeric, random()::numeric);
    runs := runs || dr;
    g := _gear_try_drop(uid, p_chapter, null, 'story_sweep'); if g is not null then gear := gear || jsonb_build_array(g); end if;
    foreach k in array array['gold','blood','shard','soul'] loop
      tot := jsonb_set(tot, array[k], to_jsonb((tot->>k)::int + coalesce((dr->>k)::int, 0)));
    end loop;
  end loop;
  w := _wallet_add(uid, tot, 'story_sweep');
  xp := cost * p_runs * _player_xp_per_stamina();
  up := _player_add_xp(uid, xp, true);
  -- 조직 의뢰 진행 (guild2.sql): 소탕 1회 = 페이즈 1 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', p_runs); perform _guild_event(uid, 'stamina', cost * p_runs);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', p_runs); end if;
  end if;
  return jsonb_build_object('ok', true, 'chapter', p_chapter, 'phase', p_phase, 'runs', p_runs, 'stamina', cost * p_runs,
    'drops', tot, 'per_run', runs, 'wallet', w, 'gear', gear,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_sweep(int, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_sweep(int, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 공개 RPC ------------------------------------------------------------------
-- 결과 화면용: 아직 안 본 획득 기록 가져오기 (가져가면 본 것으로)
create or replace function public.gear_drops_take() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  with x as (update gear_drop_log set seen = true where user_id = uid and not seen and created_at > now() - interval '1 day' returning *)
  select coalesce(jsonb_agg(jsonb_build_object('source', x.source, 'def_id', x.def_id, 'gear_id', x.gear_id, 'mail', x.mail_id is not null, 'kind', x.kind,
           'opts', g.opts, 'tier', coalesce(d.tier, nullif(split_part(x.def_id, '_', 2), '')::int)) order by x.id), '[]'::jsonb) into r
    from x left join player_gear g on g.id = x.gear_id left join gear_defs d on d.id = x.def_id;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$-- 우편 받기: 장비는 드롭 때 굴린 부옵션 그대로. 상자는 gear_box_open 으로
create or replace function public.mail_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; d gear_defs; gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if ml.kind <> 'gear' then return jsonb_build_object('ok', false, 'reason', 'unsupported'); end if;
  if _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  select * into d from gear_defs where id = ml.payload->>'def_id';
  if d.tier > 5 and coalesce(ml.payload->>'source', '') <> 'event' then return jsonb_build_object('ok', false, 'reason', 'event only'); end if;
  insert into player_gear (user_id, def_id, opts, source, locked)
    values (uid, d.id, coalesce(ml.payload->'opts', _gear_roll_opts(d.id)), 'mail:' || ml.reason, d.tier >= 6) returning id into gid;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'gear_id', gid, 'def_id', d.id);
end $$;$vr_statement$;
  execute $vr_statement$-- 토벌 상자 열기: 슬롯 선택 → 등급(가끔 한 단계 위, 최대 영웅) 장비 1개
create or replace function public.gear_box_open(p_id bigint, p_slot text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; t int; r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot not in ('weapon', 'armor', 'acc') then raise exception 'invalid slot'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found or ml.kind <> 'box' then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  t := (ml.payload->>'tier')::int;
  if (ml.payload->>'up_tier') is not null and random() * 100 < coalesce((ml.payload->>'up_pct')::numeric, 0) then t := (ml.payload->>'up_tier')::int; end if;
  r := _gear_give_tier(uid, least(t, 5), p_slot, 'box:' || ml.reason, false);
  update gear_drop_log set seen = true where user_id = uid and gear_id = (r->>'gear_id')::bigint;
  update player_mail set claimed_at = now() where id = p_id;
  return r || jsonb_build_object('tier', least(t, 5));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gear_drops_take(), public.mail_claim(bigint), public.gear_box_open(bigint, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gear_drops_take(), public.mail_claim(bigint), public.gear_box_open(bigint, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 확인: select source, count(*) from public.gear_drop_log group by 1;


-- ===== SOURCE: gear_craft.sql =====
-- ===== 장비 PR5: 강화 · 부옵션 재설정 · 분해 · 매각 =====
-- 선행: phaseE_1.sql(_wallet_add) · gear_v1.sql. 여러 번 실행해도 안전. 쓰기는 RPC 로만
-- · 강화 +1~+5 확정 성공, 비용 골드 1k·2k·4k·8k·15k + 가루 5·10·20·30·50 (v4 Page)
-- · 분해 → 장비 가루, 매각 → 골드 (v4 Page 표). 잠금·장착 장비는 불가 (하나라도 있으면 전체 거부)
-- · 재설정(부옵션 다시 굴리기): Page 에 값 없음 → 임시값 (gear_reroll_cost, 조절 가능)
-- · 표 값은 조절값: 다시 실행해도 덮어쓰지 않음 (on conflict do nothing)

create table if not exists public.gear_enhance_cost (plus int primary key check (plus between 1 and 5), gold int not null check (gold >= 0), dust int not null check (dust >= 0));$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_salvage (tier int primary key check (tier between 1 and 7), dust int not null check (dust >= 0), gold int not null check (gold >= 0));$vr_statement$;
  execute $vr_statement$create table if not exists public.gear_reroll_cost (tier int primary key check (tier between 1 and 7), gold int not null check (gold >= 0), dust int not null check (dust >= 0));$vr_statement$;
  execute $vr_statement$insert into public.gear_enhance_cost (plus, gold, dust) values (1, 1000, 5), (2, 2000, 10), (3, 4000, 20), (4, 8000, 30), (5, 15000, 50) on conflict (plus) do nothing;$vr_statement$;
  execute $vr_statement$insert into public.gear_salvage (tier, dust, gold) values (1, 1, 100), (2, 2, 200), (3, 4, 500), (4, 8, 1000), (5, 15, 2000), (6, 30, 5000), (7, 60, 10000) on conflict (tier) do nothing;$vr_statement$;
  execute $vr_statement$insert into public.gear_reroll_cost (tier, gold, dust) values (3, 1000, 4), (4, 2000, 8), (5, 4000, 15), (6, 8000, 30), (7, 15000, 60) on conflict (tier) do nothing;$vr_statement$;
  execute $vr_statement$-- 임시값

do $$ declare t text; begin
  foreach t in array array['gear_enhance_cost', 'gear_salvage', 'gear_reroll_cost'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 내 장비 한 개 (잠금 행)
create or replace function public._gear_mine(p_uid uuid, p_gear bigint) returns public.player_gear
language plpgsql security definer set search_path = public as $$
declare g player_gear;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into g from player_gear where id = p_gear and user_id = p_uid for update;
  if not found then raise exception 'gear not found'; end if;
  return g;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_mine(uuid, bigint) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 가루 쓰기 (부족하면 예외)
create or replace function public._gear_dust_add(p_uid uuid, p_n bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare d bigint;
begin
  perform _gear_meta(p_uid);
  update player_gear_meta set dust = dust + p_n, updated_at = now() where user_id = p_uid and dust + p_n >= 0 returning dust into d;
  if d is null then raise exception 'not enough dust'; end if;
  return d;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_dust_add(uuid, bigint) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 강화: +1 (확정). 장착·잠금 상관없음
create or replace function public.gear_enhance(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; c gear_enhance_cost; w jsonb; d bigint;
begin
  g := _gear_mine(uid, p_gear);
  if g.plus >= 5 then return jsonb_build_object('ok', false, 'reason', 'max plus'); end if;
  select * into c from gear_enhance_cost where plus = g.plus + 1;
  w := _wallet_add(uid, jsonb_build_object('gold', -c.gold), 'gear_enhance');   -- 부족하면 'not enough gold' (전체 롤백)
  d := _gear_dust_add(uid, -c.dust);
  update player_gear set plus = plus + 1 where id = g.id;
  return jsonb_build_object('ok', true, 'gear_id', g.id, 'plus', g.plus + 1, 'gold', c.gold, 'dust_used', c.dust, 'dust', d, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$-- 부옵션 재설정: 같은 개수로 다시 굴림 (부옵션 없는 1~2등급은 불가)
create or replace function public.gear_reroll(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; df gear_defs; c gear_reroll_cost; w jsonb; d bigint; o jsonb;
begin
  g := _gear_mine(uid, p_gear);
  select * into df from gear_defs where id = g.def_id;
  select * into c from gear_reroll_cost where tier = df.tier;
  if df.opt_count = 0 or c.tier is null then return jsonb_build_object('ok', false, 'reason', 'no options'); end if;
  w := _wallet_add(uid, jsonb_build_object('gold', -c.gold), 'gear_reroll');
  d := _gear_dust_add(uid, -c.dust);
  o := _gear_roll_opts(g.def_id);
  update player_gear set opts = o where id = g.id;
  return jsonb_build_object('ok', true, 'gear_id', g.id, 'opts', o, 'before', g.opts, 'gold', c.gold, 'dust_used', c.dust, 'dust', d, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$-- 분해·매각 공통 (여러 개). 잠금·장착·남의 장비가 하나라도 있으면 전체 거부
create or replace function public._gear_salvage(p_ids bigint[], p_sell boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; bad int; gold bigint; dust bigint; w jsonb := null; d bigint := null;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('ok', false, 'reason', 'empty'); end if;
  if cardinality(p_ids) > 200 then raise exception 'too many'; end if;
  perform 1 from player_gear where user_id = uid and id = any(p_ids) for update;
  select count(*), count(*) filter (where locked or equipped_card is not null) into n, bad from player_gear where user_id = uid and id = any(p_ids);
  if n <> (select count(distinct x) from unnest(p_ids) x) then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if bad > 0 then return jsonb_build_object('ok', false, 'reason', 'locked or equipped', 'count', bad); end if;
  select coalesce(sum(s.gold), 0), coalesce(sum(s.dust), 0) into gold, dust
    from player_gear g join gear_defs df on df.id = g.def_id join gear_salvage s on s.tier = df.tier where g.user_id = uid and g.id = any(p_ids);
  delete from player_gear where user_id = uid and id = any(p_ids);
  if p_sell then w := _wallet_add(uid, jsonb_build_object('gold', gold), 'gear_sell');
  else d := _gear_dust_add(uid, dust); end if;
  return jsonb_build_object('ok', true, 'count', n, 'gold', case when p_sell then gold else 0 end, 'dust_got', case when p_sell then 0 else dust end, 'dust', d, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._gear_salvage(bigint[], boolean) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.gear_dismantle(p_ids bigint[]) returns jsonb language sql security definer set search_path = public as $$ select _gear_salvage(p_ids, false) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.gear_sell(p_ids bigint[]) returns jsonb language sql security definer set search_path = public as $$ select _gear_salvage(p_ids, true) $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.gear_enhance(bigint), public.gear_reroll(bigint), public.gear_dismantle(bigint[]), public.gear_sell(bigint[]) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.gear_enhance(bigint), public.gear_reroll(bigint), public.gear_dismantle(bigint[]), public.gear_sell(bigint[]) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_sigil.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _sigil_story_roll 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 장비 PR6: 증표 제작·강화 + 조각 획득처 =====
-- 선행: gear_v1.sql · gear_drops.sql (story_sweep · 토벌 트리거). 여러 번 실행해도 안전
-- · 제작 50 → +1 30 → +2 50 → +3 80 → +4 120 → +5 200 = 530 (sigil_cost, v4 Page)
-- · 획득처 (v4 Page "콘텐츠별 획득처"):
--   - 스토리 보스전 소탕: 그 인재 챕터 보스 페이즈 소탕 1회당 15%로 1개, 인재별 하루 최대 3개 (sigil_story_boss · sigil_drop_config)
--   - 조직 토벌 주간 순위 상자: 2~6개 선택 조각 (gear_raid_rewards.sigil_frags) → 우편, 받을 때 인재 선택 (raid_select 가능한 인재만)
--   - 범용 교환: 아무 조각 3개 → 원하는 인재 1개 (exchange 가능한 인재만)
--   - 조직 상점·PvP 상점·이벤트 조각은 상점 PR 에서
-- · 조절값 표는 다시 실행해도 덮어쓰지 않음

-- 1) 표 -----------------------------------------------------------------------
create table if not exists public.sigil_story_boss (     -- 인재 → 그 인재 챕터 (보스 페이즈 소탕에서 조각). 임시값
  card_id text primary key references public.sigil_defs(card_id), chapter int not null
);$vr_statement$;
  execute $vr_statement$insert into public.sigil_story_boss (card_id, chapter) values ('10325', 4), ('10118', 7), ('10415', 5) on conflict (card_id) do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.sigil_drop_config (key text primary key, v numeric not null);$vr_statement$;
  execute $vr_statement$insert into public.sigil_drop_config (key, v) values ('story_boss_pct', 15), ('story_boss_daily', 3), ('exchange_rate', 3) on conflict (key) do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.sigil_daily (
  user_id uuid not null references auth.users(id) on delete cascade, card_id text not null, day date not null, n int not null default 0,
  primary key (user_id, card_id, day)
);$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['sigil_story_boss', 'sigil_drop_config'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$alter table public.sigil_daily enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.sigil_daily from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.sigil_daily to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists sigil_daily_own on public.sigil_daily;$vr_statement$;
  execute $vr_statement$create policy sigil_daily_own on public.sigil_daily for select to authenticated using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$-- 2) 내부 ---------------------------------------------------------------------
create or replace function public._sigil_add(p_uid uuid, p_card text, p_n int, p_source text) returns int
language plpgsql security definer set search_path = public as $$
declare f int;
begin
  if p_n is null or p_n <= 0 then return null; end if;
  insert into player_sigils (user_id, card_id, plus, frags) values (p_uid, p_card, null, p_n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + p_n returning frags into f;
  insert into gear_drop_log (user_id, source, def_id, kind) select p_uid, p_source, p_card, 'sigil' from generate_series(1, least(p_n, 20));
  return f;
end $$;$vr_statement$;
  execute $vr_statement$-- 스토리 보스 소탕 1회: 그 챕터 인재마다 확률 굴림, 하루 상한
create or replace function public._sigil_story_roll(p_uid uuid, p_chapter int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b record; pct numeric := (select v from sigil_drop_config where key = 'story_boss_pct'); cap int := (select v from sigil_drop_config where key = 'story_boss_daily');
  dday date := (now() at time zone 'Asia/Seoul')::date; n int; got jsonb := '[]'::jsonb;
begin
  for b in select s.card_id from sigil_story_boss s join sigil_sources src on src.card_id = s.card_id and src.source = 'story_boss' where s.chapter = p_chapter loop
    select coalesce((select d.n from sigil_daily d where d.user_id = p_uid and d.card_id = b.card_id and d.day = dday), 0) into n;
    if n >= cap or random() * 100 >= pct then continue; end if;
    insert into sigil_daily (user_id, card_id, day, n) values (p_uid, b.card_id, dday, 1) on conflict (user_id, card_id, day) do update set n = sigil_daily.n + 1;
    perform _sigil_add(p_uid, b.card_id, 1, 'story_boss');
    got := got || to_jsonb(b.card_id);
  end loop;
  return got;
end $$;$vr_statement$;
  execute $vr_statement$-- 토벌 처치·순위 트리거 (gear_drops.sql 것 + 순위 상자의 증표 조각)
create or replace function public._gear_raid_claim_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; st int; rk int; mid bigint;
begin
  if new.ref like 'raidst:%' then
    st := split_part(new.ref, ':', 3)::int;
    select * into rw from gear_raid_rewards where kind = 'clear_box' and st between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_clear'); end if;
  elsif new.ref like 'raidrk:%' then
    rk := nullif(new.reward->>'rank', '')::int;
    if rk is null then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'rank_box' and rk between rank_from and rank_to order by rank_from desc limit 1;
    if rw.id is not null then
      perform _gear_box_mail(new.user_id, rw, 'raid_rank');
      if rw.sigil_frags > 0 then
        insert into player_mail (user_id, kind, payload, reason, expires_at)
          values (new.user_id, 'sigil_frag', jsonb_build_object('n', rw.sigil_frags, 'pick', 'raid_select'), 'raid_rank', now() + interval '14 days') returning id into mid;
        insert into gear_drop_log (user_id, source, def_id, mail_id, kind) values (new.user_id, 'raid_rank', 'sigilpick', mid, 'sigil');
      end if;
    end if;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._sigil_add(uuid, text, int, text), public._sigil_story_roll(uuid, int), public._gear_raid_claim_trg() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 스토리 소탕: gear_drops.sql 의 story_sweep 그대로 + 보스 페이즈면 증표 조각 ------------------
create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb; gear jsonb := '[]'::jsonb; g jsonb; sig jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_runs is null or p_runs not in (1, 5, 10) then raise exception 'invalid runs'; end if;
  if not _player_unlocked(uid, 'sweep') then raise exception 'sweep locked (player Lv%)', _player_unlock_level('sweep'); end if;
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if not found then raise exception 'unknown phase'; end if;
  select data into d from story_progress where user_id = uid for update;
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  if _gear_bag_full(uid) then raise exception 'bag full'; end if;   -- 장비 PR4: 가방이 꽉 차면 소탕 불가
  cost := _stamina_cost(p_chapter, p_phase);
  perform _player_stamina_add(uid, -cost * p_runs);   -- 부족하면 'not enough stamina' (전체 롤백)
  for i in 1..p_runs loop
    dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), false, cost, random()::numeric, random()::numeric);
    runs := runs || dr;
    g := _gear_try_drop(uid, p_chapter, null, 'story_sweep'); if g is not null then gear := gear || jsonb_build_array(g); end if;
    if cfg.type = 'boss' then sig := sig || _sigil_story_roll(uid, p_chapter); end if;   -- 장비 PR6: 증표 조각
    foreach k in array array['gold','blood','shard','soul'] loop
      tot := jsonb_set(tot, array[k], to_jsonb((tot->>k)::int + coalesce((dr->>k)::int, 0)));
    end loop;
  end loop;
  w := _wallet_add(uid, tot, 'story_sweep');
  xp := cost * p_runs * _player_xp_per_stamina();
  up := _player_add_xp(uid, xp, true);
  -- 조직 의뢰 진행 (guild2.sql): 소탕 1회 = 페이즈 1 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', p_runs); perform _guild_event(uid, 'stamina', cost * p_runs);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', p_runs); end if;
  end if;
  return jsonb_build_object('ok', true, 'chapter', p_chapter, 'phase', p_phase, 'runs', p_runs, 'stamina', cost * p_runs,
    'drops', tot, 'per_run', runs, 'wallet', w, 'gear', gear, 'sigil', sig,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_sweep(int, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_sweep(int, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 공개 RPC -----------------------------------------------------------------
-- 제작 (+0): 그 인재를 가지고 있어야 함
create or replace function public.sigil_craft(p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s player_sigils; need int := (select frags from sigil_cost where plus = 0);
begin
  if uid is null then raise exception 'login required'; end if;
  if not exists (select 1 from sigil_defs where card_id = p_card) then return jsonb_build_object('ok', false, 'reason', 'no sigil'); end if;
  if not exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
                 where sp.user_id = uid and o->>'id' = p_card) then return jsonb_build_object('ok', false, 'reason', 'card not owned'); end if;
  select * into s from player_sigils where user_id = uid and card_id = p_card for update;
  if s.plus is not null then return jsonb_build_object('ok', false, 'reason', 'already crafted'); end if;
  if coalesce(s.frags, 0) < need then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', need, 'have', coalesce(s.frags, 0)); end if;
  update player_sigils set plus = 0, frags = frags - need where user_id = uid and card_id = p_card;
  return jsonb_build_object('ok', true, 'card', p_card, 'plus', 0, 'frags', s.frags - need);
end $$;$vr_statement$;
  execute $vr_statement$-- 강화 (+1 씩)
create or replace function public.sigil_enhance(p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s player_sigils; need int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into s from player_sigils where user_id = uid and card_id = p_card for update;
  if s.plus is null then return jsonb_build_object('ok', false, 'reason', 'not crafted'); end if;
  if s.plus >= 5 then return jsonb_build_object('ok', false, 'reason', 'max plus'); end if;
  need := (select frags from sigil_cost where plus = s.plus + 1);
  if s.frags < need then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', need, 'have', s.frags); end if;
  update player_sigils set plus = plus + 1, frags = frags - need where user_id = uid and card_id = p_card;
  return jsonb_build_object('ok', true, 'card', p_card, 'plus', s.plus + 1, 'frags', s.frags - need);
end $$;$vr_statement$;
  execute $vr_statement$-- 범용 교환: p_from 조각 (rate × p_n) → p_to 조각 p_n
create or replace function public.sigil_exchange(p_from text, p_to text, p_n int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rate int := (select v from sigil_drop_config where key = 'exchange_rate'); f int;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_n is null or p_n < 1 or p_n > 200 or p_from = p_to then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if not exists (select 1 from sigil_sources where card_id = p_to and source = 'exchange') then return jsonb_build_object('ok', false, 'reason', 'no exchange'); end if;
  update player_sigils set frags = frags - rate * p_n where user_id = uid and card_id = p_from and frags >= rate * p_n returning frags into f;
  if f is null then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', rate * p_n); end if;
  insert into player_sigils (user_id, card_id, plus, frags) values (uid, p_to, null, p_n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + p_n;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'n', p_n, 'spent', rate * p_n);
end $$;$vr_statement$;
  execute $vr_statement$-- 선택 조각 우편 받기 (토벌 순위): 고를 수 있는 인재만
create or replace function public.sigil_mail_claim(p_id bigint, p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() and kind = 'sigil_frag' for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if not exists (select 1 from sigil_sources where card_id = p_card and source = coalesce(ml.payload->>'pick', 'raid_select')) then return jsonb_build_object('ok', false, 'reason', 'not selectable'); end if;
  n := (ml.payload->>'n')::int;
  insert into player_sigils (user_id, card_id, plus, frags) values (uid, p_card, null, n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + n;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'card', p_card, 'n', n);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.sigil_craft(text), public.sigil_enhance(text), public.sigil_exchange(text, text, int), public.sigil_mail_claim(bigint, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.sigil_craft(text), public.sigil_enhance(text), public.sigil_exchange(text, text, int), public.sigil_mail_claim(bigint, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_sigil_story_off.sql =====
-- ===== 장비 PR6 후속: 스토리 보스 소탕 증표 조각 끄기 =====
-- 선행: gear_sigil.sql. 여러 번 실행해도 안전
-- 인재별 "주인공 챕터"는 나중에 정함 → 그때까지 스토리에서는 증표 조각이 나오지 않음 (레벨업·장비로 진행)
-- 다시 켜려면: sigil_story_boss 에 (card_id, chapter) 를 정해 넣고
--   update public.sigil_drop_config set v = 1 where key = 'story_boss_on';
insert into public.sigil_drop_config (key, v) values ('story_boss_on', 0) on conflict (key) do nothing;$vr_statement$;
  execute $vr_statement$delete from public.sigil_story_boss;$vr_statement$;
  execute $vr_statement$-- 임시 매핑(임유리 4 · 민홍기 7 · 최윤희 5) 제거

create or replace function public._sigil_story_roll(p_uid uuid, p_chapter int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b record; pct numeric := (select v from sigil_drop_config where key = 'story_boss_pct'); cap int := (select v from sigil_drop_config where key = 'story_boss_daily');
  dday date := (now() at time zone 'Asia/Seoul')::date; n int; got jsonb := '[]'::jsonb;
begin
  if coalesce((select v from sigil_drop_config where key = 'story_boss_on'), 0) = 0 then return got; end if;   -- 꺼짐
  for b in select s.card_id from sigil_story_boss s join sigil_sources src on src.card_id = s.card_id and src.source = 'story_boss' where s.chapter = p_chapter loop
    select coalesce((select d.n from sigil_daily d where d.user_id = p_uid and d.card_id = b.card_id and d.day = dday), 0) into n;
    if n >= cap or random() * 100 >= pct then continue; end if;
    insert into sigil_daily (user_id, card_id, day, n) values (p_uid, b.card_id, dday, 1) on conflict (user_id, card_id, day) do update set n = sigil_daily.n + 1;
    perform _sigil_add(p_uid, b.card_id, 1, 'story_boss');
    got := got || to_jsonb(b.card_id);
  end loop;
  return got;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._sigil_story_roll(uuid, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gear_shop.sql =====
-- ===== 장비 PR7: 조직 상점(충성) · PvP 상점(혼) — 증표 조각 · 장비 상자 · 장비 가루 =====
-- 선행: guild.sql(guild_shop · 충성) · phaseE_1.sql(지갑: 혼 = soul) · gear_v1/gear_drops/gear_sigil.sql. 여러 번 실행해도 안전
-- · 재화: 조직 상점 = 기존 충성(loyalty_wallet), PvP 상점 = 기존 혼(player_wallet.soul). 새 재화 없음
-- · v4 Page: 조직 상점 임유리 조각 주 3개 / PvP 상점 민홍기·최윤희 조각 주 3개 + 월 1회 선택 5개
-- · 장비 상자는 영웅까지 (전설·심연 없음). 상자는 우편함으로 → 열 때 슬롯 선택, 가방이 꽉 차면 못 엶 (PR4 와 같음)
-- · 가격·상자·가루 상품은 임시값. 표 값은 다시 실행해도 덮어쓰지 않음

-- 1) 조직 상점 상품 추가 (기존 guild_shop 표) ------------------------------------
insert into public.guild_shop (item, ord, price, gives, limit_kind, limit_n, min_level) values
  ('sigil_yuri', 10, 150,  '{"sigil":{"card":"10325","n":1}}', 'week', 3, 1),
  ('gbox_adv',   11, 400,  '{"gear_box":{"tier":3,"up_tier":4,"up_pct":10}}', 'week', 2, 1),
  ('gbox_rare',  12, 1200, '{"gear_box":{"tier":4,"up_tier":5,"up_pct":5}}', 'week', 1, 3),
  ('gdust10',    13, 100,  '{"dust":10}', 'day', 1, 1)
on conflict (item) do nothing;$vr_statement$;
  execute $vr_statement$-- 공통 지급: 상자(우편) · 증표 조각 · 가루. 나머지 키는 그대로 남겨 돌려줌
create or replace function public._shop_give_gear(p_uid uuid, p_gives jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; b jsonb; mid bigint; t int;
begin
  if p_gives ? 'gear_box' then
    b := p_gives->'gear_box'; t := (b->>'tier')::int;
    if t < 1 or t > 5 or coalesce((b->>'up_tier')::int, 0) > 5 then raise exception 'box tier out of range'; end if;   -- 영웅까지
    insert into player_mail (user_id, kind, payload, reason, expires_at)
      values (p_uid, 'box', jsonb_build_object('tier', t, 'up_tier', (b->>'up_tier')::int, 'up_pct', coalesce((b->>'up_pct')::numeric, 0)), p_reason, now() + interval '14 days') returning id into mid;
    insert into gear_drop_log (user_id, source, def_id, mail_id, kind, seen) values (p_uid, p_reason, 'box_' || t, mid, 'box', true);
    res := res || jsonb_build_object('box_mail', mid);
  end if;
  if p_gives ? 'sigil' then
    if p_gives->'sigil' ? 'pick' then
      insert into player_mail (user_id, kind, payload, reason, expires_at)
        values (p_uid, 'sigil_frag', jsonb_build_object('n', (p_gives->'sigil'->>'n')::int, 'pick', p_gives->'sigil'->>'pick'), p_reason, now() + interval '14 days') returning id into mid;
      res := res || jsonb_build_object('sigil_mail', mid);
    else
      insert into player_sigils (user_id, card_id, plus, frags) values (p_uid, p_gives->'sigil'->>'card', null, (p_gives->'sigil'->>'n')::int)
        on conflict (user_id, card_id) do update set frags = player_sigils.frags + excluded.frags;
      res := res || jsonb_build_object('sigil', p_gives->'sigil');
    end if;
  end if;
  if p_gives ? 'dust' then res := res || jsonb_build_object('dust', _gear_dust_add(p_uid, (p_gives->>'dust')::int)); end if;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._shop_give_gear(uuid, jsonb, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- guild.sql 의 guild_shop_buy 그대로 + 장비 상품
create or replace function public.guild_shop_buy(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s guild_shop; lv int; t int; res jsonb := '{}'::jsonb; w jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  select * into s from guild_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  select level into lv from guilds where id = m.guild_id;
  if lv < s.min_level then raise exception 'guild level required %', s.min_level; end if;
  if _guild_shop_left(uid, s) = 0 or (s.limit_kind = 'once' and exists (select 1 from guild_titles where user_id = uid and title = s.gives->>'title')) then raise exception 'limit reached'; end if;
  perform _loyalty_add(uid, -s.price, 'shop:' || s.item, null, jsonb_build_object('gives', s.gives));
  if s.gives ? 'tickets' then
    insert into story_gacha (user_id, last_draw) values (uid, _guild_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (s.gives->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  w := s.gives - 'tickets' - 'stamina' - 'title' - 'gear_box' - 'sigil' - 'dust';
  if w <> '{}'::jsonb then res := res || jsonb_build_object('wallet', _wallet_add(uid, w, 'guild_shop')); end if;
  if s.gives ? 'stamina' then res := res || jsonb_build_object('stamina', _player_stamina_add(uid, (s.gives->>'stamina')::int)); end if;
  if s.gives ? 'title' then insert into guild_titles (user_id, title) values (uid, s.gives->>'title') on conflict do nothing; end if;
  res := res || _shop_give_gear(uid, s.gives, 'guild_shop');   -- 장비 PR7
  return res || jsonb_build_object('ok', true, 'item', s.item, 'loyalty', (select balance from loyalty_wallet where user_id = uid));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_shop_buy(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_shop_buy(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) PvP 상점 (혼) ------------------------------------------------------------
create table if not exists public.pvp_shop (
  item text primary key, ord int not null default 0, price int not null check (price > 0), gives jsonb not null,
  limit_grp text,                                                    -- 같은 묶음끼리 한도 공유 (예: 증표 조각 주 3개)
  limit_kind text check (limit_kind in ('day', 'week', 'month')), limit_n int, active boolean not null default true
);$vr_statement$;
  execute $vr_statement$insert into public.pvp_shop (item, ord, price, gives, limit_grp, limit_kind, limit_n) values
  ('sigil_min',   1, 10, '{"sigil":{"card":"10118","n":1}}', 'sigil_week', 'week', 3),
  ('sigil_yun',   2, 10, '{"sigil":{"card":"10415","n":1}}', 'sigil_week', 'week', 3),
  ('sigil_pick5', 3, 40, '{"sigil":{"pick":"pvp_shop","n":5}}', 'sigil_month', 'month', 1),
  ('gbox_rare',   4, 30, '{"gear_box":{"tier":4,"up_tier":5,"up_pct":5}}', 'gbox_rare', 'week', 1),
  ('gdust10',     5, 5,  '{"dust":10}', 'gdust10', 'day', 1)
on conflict (item) do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.pvp_shop_log (
  id bigint generated always as identity primary key, user_id uuid not null references auth.users(id) on delete cascade,
  item text not null, grp text not null, price int not null, created_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists pvp_shop_log_user on public.pvp_shop_log (user_id, grp, created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.pvp_shop enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.pvp_shop from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.pvp_shop to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_shop_read on public.pvp_shop;$vr_statement$;
  execute $vr_statement$create policy pvp_shop_read on public.pvp_shop for select to authenticated using (true);$vr_statement$;
  execute $vr_statement$alter table public.pvp_shop_log enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.pvp_shop_log from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.pvp_shop_log to authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists pvp_shop_log_own on public.pvp_shop_log;$vr_statement$;
  execute $vr_statement$create policy pvp_shop_log_own on public.pvp_shop_log for select to authenticated using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$-- 남은 횟수 (KST 기준 하루·주(월요일)·달)
create or replace function public._pvp_shop_left(p_uid uuid, s pvp_shop) returns int language sql stable security definer set search_path = public as $$
  select case when s.limit_kind is null then null else greatest(0, s.limit_n - (select count(*)::int from pvp_shop_log l
    where l.user_id = p_uid and l.grp = coalesce(s.limit_grp, s.item)
      and l.created_at >= (date_trunc(s.limit_kind, now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'))) end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_shop_left(uuid, pvp_shop) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_shop_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'soul', coalesce((select soul from player_wallet where user_id = uid), 0),
    'items', coalesce((select jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price, 'gives', s.gives, 'grp', coalesce(s.limit_grp, s.item), 'limit_kind', s.limit_kind, 'limit_n', s.limit_n,
      'left', _pvp_shop_left(uid, s)) order by s.ord) from pvp_shop s where s.active), '[]'::jsonb));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_shop_buy(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s pvp_shop; w jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('pvpshop:' || uid::text));
  select * into s from pvp_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  if _pvp_shop_left(uid, s) = 0 then raise exception 'limit reached'; end if;
  w := _wallet_add(uid, jsonb_build_object('soul', -s.price), 'pvp_shop:' || s.item);   -- 부족하면 'not enough soul'
  insert into pvp_shop_log (user_id, item, grp, price) values (uid, s.item, coalesce(s.limit_grp, s.item), s.price);
  res := _shop_give_gear(uid, s.gives, 'pvp_shop');
  return res || jsonb_build_object('ok', true, 'item', s.item, 'wallet', w, 'left', _pvp_shop_left(uid, s));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_shop_status(), public.pvp_shop_buy(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_shop_status(), public.pvp_shop_buy(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_origin.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _story_new_card 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 거래 PR1: 인재 출처(src)·귀속(bound) 기록 =====
-- 선행: story_merge.sql(_story_new_card) · gacha.sql(story_gacha_log). 여러 번 실행해도 안전. 화면 거래 기능은 아직 없음
-- 새 인재는 모두 _story_new_card 한 곳에서 만들어짐 → 여기서 호출한 함수(PG_CONTEXT)를 보고 출처를 붙임
--   story_ticket_draw · story_daily_draw → recruit (영입, 거래 가능)
--   story_choose_starter → starter (귀속) · story_complete_phase(챕터 보상) → story (귀속)
--   _story_migrate → legacy (귀속) · 그 밖의 새 경로 → other (귀속: 모르면 막는 쪽이 안전)
-- owned[] 항목에 'src', 'bound', 'got_at' 추가. 기존 함수의 _story_norm 은 다른 키를 그대로 둠

create or replace function public._story_card_src() returns text language plpgsql stable as $$
declare ctx text;
begin
  get diagnostics ctx = pg_context;
  return case when ctx ~ 'story_ticket_draw|story_daily_draw' then 'recruit'
              when ctx ~ 'story_choose_starter' then 'starter'
              when ctx ~ 'story_complete_phase' then 'story'
              when ctx ~ '_story_migrate' then 'legacy'
              else 'other' end;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._story_new_card(cid text) returns jsonb language plpgsql volatile as $$
declare s text := _story_card_src();
begin
  return jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0,
    'src', s, 'bound', s <> 'recruit', 'got_at', extract(epoch from now())::bigint);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_card_src(), public._story_new_card(text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 기존 보유분 소급 (출처 없는 항목만. 다시 실행해도 이미 정한 것은 그대로)
-- 인재별로: 영입 기록 수(story_gacha_log) − 이미 recruit 로 표시된 수 = 거래 가능으로 돌릴 수 있는 최대치
--          스토리로 받은 것이 확실한 수(클리어한 페이즈 보상 · 시작 인재 · 챕터 0 임유리)는 먼저 귀속으로 뺌
--          남는 것: 영입 기록이 있으면 recruit_backfill(거래 가능), 없으면 unknown(귀속)
create or replace function public._trade_origin_backfill(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; o jsonb; res jsonb := '[]'::jsonb; cid text; known jsonb := '{}'::jsonb; avail jsonb := '{}'::jsonb; left_known int; left_rec int;
  n_rec int := 0; n_story int := 0; n_unknown int := 0; total jsonb := '{}'::jsonb; seen jsonb := '{}'::jsonb; i int; arr jsonb;
begin
  select data into d from story_progress where user_id = p_uid for update;
  if d is null or jsonb_typeof(d->'owned') <> 'array' then return null; end if;
  if not exists (select 1 from jsonb_array_elements(d->'owned') x where not (x ? 'src')) then return jsonb_build_object('skipped', true); end if;
  -- 스토리로 받은 것이 확실한 인재 (카드 id → 개수)
  for cid in
    select c.reward_card from story_phase_config c
      where c.reward_card is not null and coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase)
    union all select d->>'starter' where coalesce(d->>'starter', '') <> ''
    union all select '10325'
  loop known := jsonb_set(known, array[cid], to_jsonb(coalesce((known->>cid)::int, 0) + 1)); end loop;
  -- 영입 가능분 = 영입 기록 − 이미 recruit 표시
  for cid in select distinct x->>'id' from jsonb_array_elements(d->'owned') x where not (x ? 'src') loop
    avail := jsonb_set(avail, array[cid], to_jsonb(greatest(0,
      (select count(*)::int from story_gacha_log l where l.user_id = p_uid and l.card_id = cid)
      - (select count(*)::int from jsonb_array_elements(d->'owned') y where y->>'id' = cid and y->>'src' in ('recruit', 'recruit_backfill')))));
  end loop;
  -- 출처 없는 항목: 같은 인재 안에서 앞쪽(먼저 받은 것)부터 스토리 몫으로 채우고, 나머지를 영입 몫으로
  for o in select x from jsonb_array_elements(d->'owned') x loop
    if o ? 'src' then res := res || jsonb_build_array(o); continue; end if;
    cid := o->>'id';
    left_known := coalesce((known->>cid)::int, 0);
    left_rec := coalesce((avail->>cid)::int, 0);
    if left_known > 0 then
      o := o || jsonb_build_object('src', 'story', 'bound', true); known := jsonb_set(known, array[cid], to_jsonb(left_known - 1)); n_story := n_story + 1;
    elsif left_rec > 0 then
      o := o || jsonb_build_object('src', 'recruit_backfill', 'bound', false); avail := jsonb_set(avail, array[cid], to_jsonb(left_rec - 1)); n_rec := n_rec + 1;
    else
      o := o || jsonb_build_object('src', 'unknown', 'bound', true); n_unknown := n_unknown + 1;
    end if;
    res := res || jsonb_build_array(o);
  end loop;
  update story_progress set data = jsonb_set(data, '{owned}', res) where user_id = p_uid;
  return jsonb_build_object('story', n_story, 'recruit', n_rec, 'unknown', n_unknown);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._trade_origin_backfill(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$do $$ declare u uuid; begin
  for u in select user_id from story_progress loop perform public._trade_origin_backfill(u); end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 확인: select o->>'src' src, o->>'bound' bound, count(*) from story_progress, jsonb_array_elements(data->'owned') o group by 1, 2 order by 1;


-- ===== SOURCE: trade_origin_v2.sql =====
-- ===== 거래 PR1 후속: 스토리 보상만 귀속, 나머지는 모두 거래 가능 =====
-- 선행: trade_origin.sql. 여러 번 실행해도 안전
-- 앞으로: story(챕터 보상·스토리 지급)만 bound=true. recruit·starter·legacy·other 는 거래 가능
create or replace function public._story_new_card(cid text) returns jsonb language plpgsql volatile as $$
declare s text := _story_card_src();
begin
  return jsonb_build_object('uid', public._story_new_uid(), 'id', cid, 'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0,
    'src', s, 'bound', s = 'story', 'got_at', extract(epoch from now())::bigint);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._story_new_card(text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 기존 보유분 재표시
--  1) 소급 때 시작 인재가 story 로 묶였던 것(got_at 없음 = 소급분) 1장 → starter (챕터 보상 목록에 같은 인재가 있으면 그대로 둠)
--  2) story 가 아닌 것은 모두 bound=false
update public.story_progress sp set data = jsonb_set(sp.data, '{owned}', (
  select coalesce(jsonb_agg(case
      when o->>'src' = 'story' and not (o ? 'got_at') and n = (
             select min(m) from jsonb_array_elements(sp.data->'owned') with ordinality y(v, m)
             where v->>'id' = sp.data->>'starter' and v->>'src' = 'story' and not (v ? 'got_at'))
           and not exists (select 1 from public.story_phase_config c where c.reward_card = sp.data->>'starter')
        then o || jsonb_build_object('src', 'starter', 'bound', false)
      when o->>'src' is distinct from 'story' then o || jsonb_build_object('bound', false)
      else o || jsonb_build_object('bound', true) end order by n), '[]'::jsonb)
  from jsonb_array_elements(sp.data->'owned') with ordinality x(o, n)))
where jsonb_typeof(sp.data->'owned') = 'array'
  and exists (select 1 from jsonb_array_elements(sp.data->'owned') z
              where ((z->>'src') is distinct from 'story' and (z->>'bound')::boolean is distinct from false)
                 or (z->>'src' = 'story' and not (z ? 'got_at') and z->>'id' = sp.data->>'starter'));$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (5, '2e51781f300b93c84298e678ab1ea699a95d4d5bc29d23bc3cc785cdcfebdd30', 'a76fd1f8e73c144cb17b7ab191f735e7a2a7e9e101d52f5719ba02c5097b4036', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '05_install.sql: 완료 또는 이미 완료 (5/14)' as result;
