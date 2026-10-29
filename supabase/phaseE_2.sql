-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _player_add_xp, _player_xp_need, story_complete_phase 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-2: 플레이어 레벨 + 행동력 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql 전부, admin.sql, phaseE_1.sql (레벨업 골드 보상에 지갑 사용)
--
-- 규칙 (확정안)
--   플레이어 레벨 1~100. 경험치는 스토리에서만: 클리어 1회 = 소모 행동력 × 10 (= 60),
--     첫 클리어 보너스 일반 +50 / 보스 +150. 다음 레벨까지 필요량 = 100 + 20 × (L − 1)
--   레벨업 보상: 행동력 +새 최대치 (최대치를 넘어도 보관), 골드 +100 × 새 레벨
--   행동력 최대치 = 40 + 5 × floor(L / 5)  (Lv1 40 · Lv50 90 · Lv100 140)
--   회복: 6분에 1 (서버 시각 기준 계산). 최대치 이상이면 회복 없음
--   비용: 스토리 모든 페이즈 6 (보스 포함). 시련의 탑·아케이드는 0
--   패배·포기: 전부 반환 (story_abort_phase). 전투를 끝내지 않고 새 전투를 시작해도 이전 전투 분은 반환
--   행동력 골드 충전 없음
--   해금 레벨: 소탕 5 · 기술 레벨 10 · 장비 15 · 장비 합성 20 (_player_unlocked 로 이후 단계에서 확인)
--   기존 유저도 모두 Lv1 부터 시작 (클리어 기록 소급 없음)
--
-- 구조: 기존 story_start_phase / story_complete_phase(3인자) 를 _e0 이름으로 보관하고
--       같은 이름의 감싸는 함수(행동력·경험치 처리)를 새로 만듦.
--       ※ 나중에 story_merge.sql 등 스토리 SQL 을 다시 실행했다면 이 파일도 다시 실행해 주세요 (자동으로 다시 감쌈)
-- 확인용: select public.player_status();
-- =====================================================================

-- 1) 플레이어 상태
create table if not exists public.player_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  level      int not null default 1 check (level between 1 and 100),
  xp         int not null default 0 check (xp >= 0),          -- 현재 레벨 안에서 모은 경험치
  stamina    int not null default 40 check (stamina >= 0),
  stamina_at timestamptz not null default now(),             -- 회복 기준 시각
  updated_at timestamptz not null default now()
);
alter table public.player_state enable row level security;
revoke all on public.player_state from public, anon, authenticated;
grant select on public.player_state to authenticated;
drop policy if exists "player_read_own" on public.player_state;
create policy "player_read_own" on public.player_state for select using (auth.uid() = user_id);

-- 2) 수치 (한 곳에서 조정)
create or replace function public._player_max_level() returns int language sql immutable as $$ select 100 $$;
create or replace function public._player_xp_need(p_level int) returns int language sql immutable as $$ select 3 * (100 + 20 * (greatest(p_level, 1) - 1)) $$;   -- 2026-10: 3배 (player_xp_x3.sql)
create or replace function public._stamina_max(p_level int) returns int language sql immutable as $$ select 40 + 5 * (greatest(p_level, 1) / 5) $$;
create or replace function public._stamina_regen_secs() returns int language sql immutable as $$ select 360 $$;
create or replace function public._stamina_cost(p_chapter int, p_phase int) returns int language sql immutable as $$ select 6 $$;
create or replace function public._player_xp_per_stamina() returns int language sql immutable as $$ select 10 $$;
create or replace function public._player_first_bonus(p_type text) returns int language sql immutable as $$ select case when p_type = 'boss' then 150 else 50 end $$;
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20 else null end $$;

-- 3) 내부 도우미
-- 경험치를 더하고 레벨업 처리. p_reward = true 면 레벨업 보상(행동력·골드) 지급. 반환 { levelups, gold }
create or replace function public._player_add_xp(p_uid uuid, p_xp int, p_reward boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; n int := 0; gold int := 0; mx int;
begin
  select * into ps from player_state where user_id = p_uid for update;
  if ps.user_id is null or p_xp <= 0 then return jsonb_build_object('levelups', 0, 'gold', 0); end if;
  ps.xp := ps.xp + p_xp;
  while ps.level < _player_max_level() and ps.xp >= _player_xp_need(ps.level) loop
    ps.xp := ps.xp - _player_xp_need(ps.level);
    ps.level := ps.level + 1; n := n + 1;
    if p_reward then
      mx := _stamina_max(ps.level);
      if ps.stamina >= _stamina_max(ps.level - 1) then ps.stamina_at := now(); end if;
      ps.stamina := ps.stamina + mx;
      gold := gold + 100 * ps.level;
    end if;
  end loop;
  if ps.level >= _player_max_level() then ps.xp := 0; end if;
  update player_state set level = ps.level, xp = ps.xp, stamina = ps.stamina, stamina_at = ps.stamina_at, updated_at = now() where user_id = p_uid;
  if gold > 0 and to_regprocedure('public._wallet_add(uuid,jsonb,text)') is not null then
    perform public._wallet_add(p_uid, jsonb_build_object('gold', gold), 'player_levelup');
  end if;
  -- 조직 세력 (guild.sql): 스토리 경험치 60 = 행동력 6 → 세력 1 (하루 상한은 _guild_feed 가 처리)
  if to_regprocedure('public._guild_feed(uuid,text,integer)') is not null then perform public._guild_feed(p_uid, 'story', greatest(1, p_xp / 60)); end if;
  return jsonb_build_object('levelups', n, 'gold', gold);
end $$;

-- 행 잠금 + 회복 반영. 없으면 Lv1 · 행동력 최대치로 생성
create or replace function public._player_sync(p_uid uuid) returns player_state language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; n int; secs int := _stamina_regen_secs();
begin
  if p_uid is null then raise exception 'login required'; end if;
  insert into player_state (user_id, stamina) values (p_uid, _stamina_max(1)) on conflict (user_id) do nothing;   -- 모두 Lv1 부터 (소급 없음)
  select * into ps from player_state where user_id = p_uid for update;
  mx := _stamina_max(ps.level);
  if ps.stamina >= mx then
    ps.stamina_at := now();
  else
    n := floor(extract(epoch from (now() - ps.stamina_at)) / secs)::int;
    if n > 0 then
      ps.stamina := least(mx, ps.stamina + n);
      ps.stamina_at := case when ps.stamina >= mx then now() else ps.stamina_at + make_interval(secs => n * secs) end;
    end if;
  end if;
  update player_state set stamina = ps.stamina, stamina_at = ps.stamina_at where user_id = p_uid;
  return ps;
end $$;

-- 행동력 증감 (회복 기준 시각 보정 포함). 반환 새 값
create or replace function public._player_stamina_add(p_uid uuid, p_delta int) returns int language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; nv int;
begin
  ps := _player_sync(p_uid);
  mx := _stamina_max(ps.level); nv := ps.stamina + p_delta;
  if nv < 0 then raise exception 'not enough stamina'; end if;
  -- 최대치 이상 → 미만으로 내려가면 지금부터 회복 시작
  update player_state set stamina = nv, stamina_at = case when ps.stamina >= mx or nv >= mx then now() else stamina_at end, updated_at = now() where user_id = p_uid;
  return nv;
end $$;

create or replace function public._player_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; secs int := _stamina_regen_secs();
begin
  ps := _player_sync(p_uid); mx := _stamina_max(ps.level);
  return jsonb_build_object('ok', true, 'level', ps.level, 'max_level', _player_max_level(), 'xp', ps.xp,
    'xp_next', case when ps.level >= _player_max_level() then 0 else _player_xp_need(ps.level) end,
    'stamina', ps.stamina, 'stamina_max', mx, 'regen_secs', secs,
    'next_regen_secs', case when ps.stamina >= mx then 0 else greatest(0, secs - floor(extract(epoch from (now() - ps.stamina_at)))::int) end,
    'cost', jsonb_build_object('story', _stamina_cost(0, 0), 'quest', 0, 'arcade', 0),
    'unlocks', jsonb_build_object('sweep', _player_unlock_level('sweep'), 'skill', _player_unlock_level('skill'), 'equip', _player_unlock_level('equip'), 'equip_merge', _player_unlock_level('equip_merge')));
end $$;

-- 이후 단계용: 해금 확인 (서버 RPC 안에서 perform 으로 사용)
create or replace function public._player_unlocked(p_uid uuid, p_key text) returns boolean language plpgsql security definer set search_path = public as $$
declare lv int := (_player_sync(p_uid)).level; need int := _player_unlock_level(p_key);
begin return need is not null and lv >= need; end $$;

revoke all on function public._player_add_xp(uuid, int, boolean), public._player_sync(uuid), public._player_stamina_add(uuid, int), public._player_json(uuid), public._player_unlocked(uuid, text) from public, anon, authenticated;

-- 4) 기존 스토리 함수 보관 (_e0) — 이미 감싼 상태면 건너뜀, 스토리 SQL 재실행으로 원본이 새로 생겼으면 다시 보관
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_start_phase(int,int)');
  if src is not null and src not like '%phaseE_2 wrapper%' then
    drop function if exists public._story_start_phase_e0(int, int);
    alter function public.story_start_phase(int, int) rename to _story_start_phase_e0;
  end if;
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_complete_phase(int,int,jsonb)');
  if src is not null and src not like '%phaseE_2 wrapper%' then
    drop function if exists public._story_complete_phase_e0(int, int, jsonb);
    alter function public.story_complete_phase(int, int, jsonb) rename to _story_complete_phase_e0;
  end if;
end $$;
revoke all on function public._story_start_phase_e0(int, int), public._story_complete_phase_e0(int, int, jsonb) from public, anon, authenticated;

-- 5) 감싸는 함수
-- 전투 시작: 이전 미완료 전투 행동력 반환 → 6 차감 → 원래 시작 처리 → battle.stamina 기록
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper
declare uid uuid := auth.uid(); b jsonb; d jsonb; cost int := _stamina_cost(p_chapter, p_phase);
begin
  if uid is null then raise exception 'login required'; end if;
  perform _player_sync(uid);
  select data->'battle' into b from story_progress where user_id = uid for update;
  if b is not null and (b->>'stamina') is not null then perform _player_stamina_add(uid, (b->>'stamina')::int); end if;
  perform _player_stamina_add(uid, -cost);   -- 부족하면 'not enough stamina' (전체 롤백)
  d := _story_start_phase_e0(p_chapter, p_phase);
  d := jsonb_set(d, '{battle,stamina}', to_jsonb(cost));
  update story_progress set data = d where user_id = uid;
  return d;
end $$;

-- 전투 완료(승리): 원래 처리 → 플레이어 경험치 (행동력 × 10 + 첫 클리어 보너스). 결과에 player 추가
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper
declare uid uuid := auth.uid(); b jsonb; spent int; r jsonb; cfg story_phase_config; xp int; up jsonb; drops jsonb := null;
begin
  if uid is null then raise exception 'login required'; end if;
  select data->'battle' into b from story_progress where user_id = uid;
  spent := coalesce((b->>'stamina')::int, 0);
  r := _story_complete_phase_e0(p_chapter, p_phase, p_stats);
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  xp := spent * _player_xp_per_stamina() + case when coalesce((r->>'first')::boolean, false) then _player_first_bonus(cfg.type) else 0 end;
  perform _player_sync(uid);
  up := _player_add_xp(uid, xp, true);
  -- 재화 드롭 (phaseE_3.sql 의 _story_drops 가 있으면)
  if to_regprocedure('public._story_drops(uuid,integer,integer,boolean)') is not null then
    execute 'select public._story_drops($1, $2, $3, $4)' into drops using uid, p_chapter, p_phase, coalesce((r->>'first')::boolean, false);
  end if;
  return r || jsonb_build_object('player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'))
           || case when drops is null then '{}'::jsonb else jsonb_build_object('drops', drops) end;
end $$;

-- 패배·포기: 진행 중 전투 기록 지우고 행동력 전부 반환. 반환 player_status
create or replace function public.story_abort_phase() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; refund int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  d := _story_lock(uid);
  if d->'battle' is not null then
    refund := coalesce((d->'battle'->>'stamina')::int, 0);
    perform _story_save(uid, d - 'battle');
    if refund > 0 then perform _player_stamina_add(uid, refund); end if;
  end if;
  return _player_json(uid) || jsonb_build_object('refunded', refund);
end $$;

-- 6) 공개 RPC: 내 레벨·행동력 (탐침 겸용)
create or replace function public.player_status() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _player_json(auth.uid());
end $$;

revoke all on function public.story_start_phase(int, int), public.story_complete_phase(int, int, jsonb), public.story_abort_phase(), public.player_status() from public, anon;
grant execute on function public.story_start_phase(int, int), public.story_complete_phase(int, int, jsonb), public.story_abort_phase(), public.player_status() to authenticated;

-- 7) 관리자: 유저 레벨·행동력 조회
create or replace function public.admin_user_player(p_user uuid) returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  return _player_json(p_user);
end $$;
revoke all on function public.admin_user_player(uuid) from public, anon;
grant execute on function public.admin_user_player(uuid) to authenticated;
