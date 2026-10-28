-- =====================================================================
-- 일회성: mbbs.art@gmail.com 계정의 게임 데이터 전부 초기화 (로그인 auth.users 행은 유지)
-- Supabase SQL Editor 에서 직접 실행. 한 트랜잭션: 중간에 오류 나면 아무것도 안 바뀜.
-- 실행 결과 = 표(테이블별 지운/바꾼 행 수). 브라우저 localStorage 는 따로 지워야 함 (맨 아래 참고).
-- 남기는 것: auth.users 행 · profiles 행(가입 때 값으로 되돌림) · 관리자 기록(admin_log) · 조직 기록(guild_log)
--          · 다른 유저의 PvP 기록 중 이 계정이 상대였던 줄(pvp_attempts.opp_user)
-- =====================================================================
-- 실행 방식: 아래 전체를 SQL Editor 에 붙여 넣고 Run.
--   1) 잠긴 일회용 함수 생성  2) 마지막 SELECT 가 함수를 실행 → 결과 표(tbl · action · n)로 보여 줌
--   함수 호출 하나 = 한 트랜잭션: 중간 오류면 아무것도 안 바뀜. 다시 실행해도 안전(이미 지운 건 0).
--   끝나면 (선택) drop function public._oneoff_wipe_mbbs_art();
create or replace function public._oneoff_wipe_mbbs_art() returns table (tbl text, action text, n bigint)
language plpgsql security definer set search_path = public, auth as $fn$
#variable_conflict use_column
declare
  uid uuid; g record; heir uuid; c bigint; t text;
  -- 이 계정 user_id 행을 지우는 테이블 (scan: supabase/*.sql 의 user_id uuid 컬럼)
  tabs text[] := array[
    'story_progress','story_gacha','story_gacha_log','saves','matches','gallery',
    'player_state','player_wallet','wallet_log','gem_ledger','gem_login',
    'quest_progress','tower_progress',
    'pvp_decks','pvp_ratings','pvp_attempts','pvp_reward_claims','pvp_bonus_tries','pvp_tier_claims','pvp_titles',
    'loyalty_wallet','loyalty_ledger','guild_requests','guild_cooldowns','guild_titles','guild_exp_log',
    'guild_attendance','guild_daily_quests','guild_weekly_contrib','guild_claims',
    'guild_raid_attempts','guild_raid_damage',
    'war_signups','war_roster','war_decks','war_attacks','war_atk_state','war_ajits'];
begin
  select id into uid from auth.users where lower(email) = 'mbbs.art@gmail.com';
  if uid is null then raise exception 'mbbs.art@gmail.com 계정을 찾지 못함'; end if;
  tbl := 'auth.users'; action := 'found (kept) ' || uid::text; n := 1; return next;

  -- 1) 조직: 보스라면 → 다른 조직원이 있으면 보스 넘김(간부 중 가장 오래된 사람, 없으면 충성 높은 조직원), 혼자면 조직 해체
  select gm.guild_id, gm.role into g from guild_members gm where gm.user_id = uid;
  if g.guild_id is not null and g.role = 'boss' then
    select user_id into heir from guild_members where guild_id = g.guild_id and user_id <> uid
      order by (role = 'officer') desc, case when role = 'officer' then extract(epoch from joined_at) else -loyalty_total end, joined_at limit 1;
    if heir is null then
      delete from guilds where id = g.guild_id;   -- 조직원·가입 신청은 cascade 로 같이 삭제
      tbl := 'guilds'; action := 'disbanded (solo boss) id ' || g.guild_id; n := 1; return next;
    else
      update guild_members set role = 'boss' where user_id = heir;
      update guilds set boss = heir where id = g.guild_id;
      tbl := 'guilds'; action := 'boss transferred to ' || heir::text || ' (guild ' || g.guild_id || ')'; n := 1; return next;
    end if;
  end if;
  delete from guild_members where user_id = uid; get diagnostics c = row_count;
  tbl := 'guild_members'; action := 'delete'; n := c; return next;
  -- 혹시 남은 보스 표시 (다른 조직 boss 칸) 확인용
  if exists (select 1 from guilds where boss = uid) then raise exception '아직 이 계정이 보스인 조직이 있음 — 중단'; end if;

  -- 2) 이 계정 행 삭제 (테이블이 없으면 건너뜀)
  foreach t in array tabs loop
    if to_regclass('public.' || t) is null then tbl := t; action := 'skip (no table)'; n := 0; return next; continue; end if;
    execute format('delete from public.%I where user_id = $1', t) using uid; get diagnostics c = row_count;
    tbl := t; action := 'delete'; n := c; return next;
  end loop;
  if to_regclass('public.guild_requests') is not null then
    delete from guild_requests where by_user = uid; get diagnostics c = row_count; tbl := 'guild_requests (by_user)'; action := 'delete'; n := c; return next;
  end if;
  -- 다른 사람 기록에 남은 참조는 비움 (행은 유지)
  if to_regclass('public.guild_raid_stages') is not null then
    update guild_raid_stages set last_hit = null where last_hit = uid; get diagnostics c = row_count; tbl := 'guild_raid_stages.last_hit'; action := 'set null'; n := c; return next;
  end if;
  if to_regclass('public.war_ajits') is not null then
    update war_ajits set destroyed_by = null where destroyed_by = uid; get diagnostics c = row_count; tbl := 'war_ajits.destroyed_by'; action := 'set null'; n := c; return next;
    update war_ajits set locked_by = null where locked_by = uid; get diagnostics c = row_count; tbl := 'war_ajits.locked_by'; action := 'set null'; n := c; return next;
  end if;

  -- 3) 프로필: 앱이 로그인 때 읽고 upsert 하므로 행은 두고 가입 때 값으로 되돌림
  update profiles p set nickname = left(coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1), '플레이어'), 20),
         avatar_url = u.raw_user_meta_data->>'avatar_url', updated_at = now()
    from auth.users u where u.id = uid and p.id = uid;
  get diagnostics c = row_count; tbl := 'profiles'; action := 'reset to signup defaults'; n := c; return next;
end $fn$;
revoke all on function public._oneoff_wipe_mbbs_art() from public, anon, authenticated;

select * from public._oneoff_wipe_mbbs_art();

-- 브라우저: tcg.mbbs.kr 에서 그 계정으로 쓰던 브라우저의 사이트 데이터(localStorage)도 지울 것
--   (크롬: 주소창 자물쇠 → 사이트 설정 → 데이터 삭제, 또는 개발자도구 Console 에서 localStorage.clear(); 후 새로고침)
--   지우지 않으면 vrTcgStory.v1:<id> 등 로컬 사본이 다시 서버로 올라갈 수 있음.
