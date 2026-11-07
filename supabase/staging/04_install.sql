-- ⚠ 테스트 전용 4/10. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> 'd58808b88d2b2323a18856d9663da6bec0c35ea9b3485319d62a3c189dd7aa8e' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 4) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 4 and part_hash = '5815c51c3b4078dd7ba66c2a6bdb4725a00f5a07ebae8fd729b093fbbf02ab3e') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '04_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 4) <> 3 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (04_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- 신청/초대 응답: 가입 신청은 그 조직 보스·간부가, 초대는 초대받은 본인이. 본인 신청 취소도 여기서 (p_accept = false)
create or replace function public.guild_respond(p_req bigint, p_accept boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r guild_requests; m guild_members;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into r from guild_requests where id = p_req;
  if r.id is null or r.status <> 'pending' then raise exception 'no such request'; end if;
  perform _guild_lock(r.guild_id);
  select * into r from guild_requests where id = p_req for update;
  if r.status <> 'pending' then raise exception 'no such request'; end if;
  if r.expires_at < now() then update guild_requests set status = 'cancelled' where id = r.id; raise exception 'expired'; end if;
  if r.kind = 'apply' and r.user_id = uid and not p_accept then
    update guild_requests set status = 'cancelled' where id = r.id; return jsonb_build_object('ok', true);
  end if;
  if r.kind = 'apply' then
    m := _guild_me(uid);
    if m.user_id is null or m.guild_id <> r.guild_id or m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
  elsif r.user_id <> uid then raise exception 'no permission'; end if;
  if p_accept then
    perform pg_advisory_xact_lock(hashtext('guilduser:' || r.user_id::text));
    perform _guild_add_member(r.guild_id, r.user_id, uid);
    update guild_requests set status = 'accepted' where id = r.id;
  else
    update guild_requests set status = 'rejected' where id = r.id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept);
end $$;$vr_statement$;
  execute $vr_statement$-- 탈퇴: 24시간 가입 불가. 보스는 넘기기 전엔 못 나감 (혼자면 해산)
create or replace function public.guild_leave() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_lock(m.guild_id);
  if m.role = 'boss' then
    if (select count(*) from guild_members where guild_id = m.guild_id) > 1 then raise exception 'boss must transfer'; end if;
    perform _guild_log(m.guild_id, uid, 'disband', null, '{}');
    delete from guilds where id = m.guild_id;
  else
    delete from guild_members where user_id = uid;
    perform _guild_log(m.guild_id, uid, 'leave', uid, '{}');
  end if;
  insert into guild_cooldowns (user_id, guild_id, until) values (uid, 0, now() + interval '24 hours') on conflict (user_id, guild_id) do update set until = excluded.until;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.guild_disband() returns jsonb language plpgsql security definer set search_path = public as $$
declare m guild_members := _guild_me(auth.uid());
begin
  if m.user_id is null or m.role <> 'boss' then raise exception 'no permission'; end if;
  if (select count(*) from guild_members where guild_id = m.guild_id) > 1 then raise exception 'members remain'; end if;
  return guild_leave();
end $$;$vr_statement$;
  execute $vr_statement$-- 추방: 보스 = 누구든 (보스 제외) · 간부 = 조직원만. 하루 5명. 그 조직 72시간 재가입 불가
create or replace function public.guild_kick(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; t guild_members;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
  perform _guild_lock(m.guild_id);
  t := _guild_me(p_user);
  if t.user_id is null or t.guild_id <> m.guild_id or t.role = 'boss' or (m.role = 'officer' and t.role <> 'member') then raise exception 'no permission'; end if;
  if (select count(*) from guild_log where guild_id = m.guild_id and action = 'kick' and created_at >= (_guild_day()::timestamp at time zone 'Asia/Seoul')) >= 5 then raise exception 'kick limit'; end if;
  delete from guild_members where user_id = p_user;
  insert into guild_cooldowns (user_id, guild_id, until) values (p_user, m.guild_id, now() + interval '72 hours') on conflict (user_id, guild_id) do update set until = excluded.until;
  perform _guild_log(m.guild_id, uid, 'kick', p_user, '{}');
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 간부 임명/해제 (보스). 간부 수는 레벨표 상한
create or replace function public.guild_set_role(p_user uuid, p_role text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; t guild_members; mx int;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'no permission'; end if;
  if p_role not in ('officer', 'member') then raise exception 'bad role'; end if;
  perform _guild_lock(m.guild_id);
  t := _guild_me(p_user);
  if t.user_id is null or t.guild_id <> m.guild_id or t.role = 'boss' then raise exception 'no permission'; end if;
  if p_role = 'officer' and t.role <> 'officer' then
    select officers into mx from guild_level_table where level = (select level from guilds where id = m.guild_id);
    if (select count(*) from guild_members where guild_id = m.guild_id and role = 'officer') >= coalesce(mx, 1) then raise exception 'officer slots full'; end if;
  end if;
  update guild_members set role = p_role where user_id = p_user;
  perform _guild_log(m.guild_id, uid, 'role', p_user, jsonb_build_object('role', p_role));
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 보스 넘기기 (보스 → 조직원 중 1명, 이전 보스는 간부)
create or replace function public.guild_transfer(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; t guild_members;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'no permission'; end if;
  perform _guild_lock(m.guild_id);
  t := _guild_me(p_user);
  if t.user_id is null or t.guild_id <> m.guild_id or p_user = uid then raise exception 'no permission'; end if;
  update guild_members set role = 'officer' where user_id = uid;
  update guild_members set role = 'boss' where user_id = p_user;
  update guilds set boss = p_user where id = m.guild_id;
  perform _guild_log(m.guild_id, uid, 'transfer', p_user, '{}');
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 보스 14일 미접속: 가장 오래된 간부 (간부 없으면 충성 누적 1위 조직원) 가 보스 승계
create or replace function public.guild_claim_boss() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; b guild_members; heir uuid;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_lock(m.guild_id);
  select * into b from guild_members where guild_id = m.guild_id and role = 'boss';
  if b.seen_at > now() - interval '14 days' then raise exception 'boss active'; end if;
  select user_id into heir from guild_members where guild_id = m.guild_id and role <> 'boss'
    order by (role = 'officer') desc, case when role = 'officer' then extract(epoch from joined_at) else -loyalty_total end, joined_at limit 1;
  if heir is distinct from uid then raise exception 'not heir'; end if;
  update guild_members set role = 'member' where user_id = b.user_id;
  update guild_members set role = 'boss' where user_id = uid;
  update guilds set boss = uid where id = m.guild_id;
  perform _guild_log(m.guild_id, uid, 'claim_boss', b.user_id, '{}');
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 충성 상점 (개인 충성 사용, 조직 레벨로 해금, 하루/주/1회 제한)
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
  w := s.gives - 'tickets' - 'stamina' - 'title';
  if w <> '{}'::jsonb then res := res || jsonb_build_object('wallet', _wallet_add(uid, w, 'guild_shop')); end if;
  if s.gives ? 'stamina' then res := res || jsonb_build_object('stamina', _player_stamina_add(uid, (s.gives->>'stamina')::int)); end if;
  if s.gives ? 'title' then insert into guild_titles (user_id, title) values (uid, s.gives->>'title') on conflict do nothing; end if;
  return res || jsonb_build_object('ok', true, 'item', s.item, 'loyalty', (select balance from loyalty_wallet where user_id = uid));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_status(), public.guild_search(text), public.guild_create(text, int, text, text, text), public.guild_update(jsonb), public.guild_apply(bigint),
  public.guild_invite(text), public.guild_respond(bigint, boolean), public.guild_leave(), public.guild_disband(), public.guild_kick(uuid), public.guild_set_role(uuid, text),
  public.guild_transfer(uuid), public.guild_claim_boss(), public.guild_shop_buy(text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_status(), public.guild_search(text), public.guild_create(text, int, text, text, text), public.guild_update(jsonb), public.guild_apply(bigint),
  public.guild_invite(text), public.guild_respond(bigint, boolean), public.guild_leave(), public.guild_disband(), public.guild_kick(uuid), public.guild_set_role(uuid, text),
  public.guild_transfer(uuid), public.guild_claim_boss(), public.guild_shop_buy(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 관리자: 목록 · 이름 변경 · 공지 지우기 · 해산 (admin_log 기록)
create or replace function public.admin_guild_list(p_q text default null) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return (select coalesce(jsonb_agg(_guild_card(g.id) || jsonb_build_object('exp', g.exp, 'notice', g.notice, 'created_at', g.created_at) order by g.id desc), '[]'::jsonb)
    from (select * from guilds where p_q is null or name_key like '%' || lower(p_q) || '%' order by id desc limit 200) g);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_guild_edit(p_gid bigint, p_action text, p_value text, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare g guilds; n text;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  select * into g from guilds where id = p_gid;
  if g.id is null then raise exception 'no such guild'; end if;
  if p_action = 'rename' then n := _guild_name_ok(p_value);
    if exists (select 1 from guilds where name_key = lower(n) and id <> g.id) then raise exception 'name taken'; end if;
    update guilds set name = n, name_key = lower(n) where id = g.id;
  elsif p_action = 'clear_text' then update guilds set notice = '', intro = '' where id = g.id;
  elsif p_action = 'disband' then delete from guilds where id = g.id;
  else raise exception 'bad action'; end if;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'guild_' || p_action, g.boss, g.id::int, left(btrim(p_reason) || ' · ' || g.name || coalesce(' → ' || n, ''), 200), null, null);
  perform _guild_log(case when p_action = 'disband' then null else g.id end, auth.uid(), 'admin_' || p_action, null, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_guild_list(text), public.admin_guild_edit(bigint, text, text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_guild_list(text), public.admin_guild_edit(bigint, text, text, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 스토리·PvP 연동 (phaseE_2.sql / pvp_tier.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_guild_sql.mjs 가 일치 확인)
--    스토리 경험치(= 행동력 × 10) 60 당 세력 1 · PvP 승리 +10
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._player_add_xp(uuid, int, boolean) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
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
  execute $vr_statement$revoke all on function public.pvp_report(bigint, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_report(bigint, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild2.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 story_sweep 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- [조직] 2단계: 집결(출석) · 의뢰(일일 개인 / 주간 공동) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: guild.sql (1단계) · gem.sql · phaseE_3.sql · phaseE_5.sql · quest.sql / tower_v2.sql
-- 하루 = KST 00:00 기준, 한 주 = 월요일 00:00 (KST) 시작
-- 집결: 하루 1번 충성 20 · 골드 1,000 · 세력 10 / 출석률 30·60·90% 보너스 / 주 7일 개근 충성 100 + 소환권 1
-- 의뢰: 일일 3개(풀 8종, 하루 1번 무료 교체, 3개 완료 보너스 충성 20) · 주간 공동 3개(풀 6종, 목표 = 1인 목표 × 인원, 50·100·150% 보상)
-- 진행도는 서버 이벤트로만 (_guild_event): 스토리 클리어·소탕, PvP 승리, 탑 클리어, 카드 뽑기, 카드 레벨업, 집결
-- 보상은 guild_claims (유저별 고유 ref) 로 한 번만. 쓰기는 전부 서버 함수 (테이블 RLS + revoke)
-- 확인용: select public.guild_rally(); select public.guild_quests();
-- =====================================================================

-- 1) 테이블
create table if not exists public.guild_attendance (
  user_id  uuid not null references auth.users(id) on delete cascade,
  day      date not null,
  guild_id bigint not null,
  at       timestamptz not null default now(),
  primary key (user_id, day));$vr_statement$;
  execute $vr_statement$create index if not exists guild_attendance_gday on public.guild_attendance (guild_id, day);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_quest_pool (
  key text primary key, kind text not null check (kind in ('daily', 'weekly')), event text not null, goal int not null check (goal > 0),
  reward jsonb not null default '{}'::jsonb, weight int not null default 1, label text not null, icon text not null default '📜', active boolean not null default true);$vr_statement$;
  execute $vr_statement$insert into public.guild_quest_pool (key, kind, event, goal, reward, label, icon) values
  ('d_phase',   'daily', 'draw',    1,  '{"loyalty":15,"gold":800,"exp":10}',  '인재 소환 1회', '🎴'),   -- guild_quest_draw.sql (예전 '페이즈 정리 5')
  ('d_stamina', 'daily', 'stamina', 60, '{"loyalty":15,"gold":800,"exp":10}',  '행동력 소모',  '🔋'),
  ('d_pvp',     'daily', 'pvp_win', 2,  '{"loyalty":20,"gold":1000,"exp":15}', 'PvP 승리',     '⚔️'),
  ('d_tower',   'daily', 'tower',   1,  '{"loyalty":15,"gold":800,"exp":10}',  '탑 오르기',    '🗼'),
  ('d_draw',    'daily', 'draw',    1,  '{"loyalty":10,"gold":500,"exp":5}',   '소환',         '🎴'),
  ('d_boss',    'daily', 'raid',    1,  '{"loyalty":20,"gold":1000,"exp":15}', '균열 토벌',    '🐉'),   -- guild_quest_raid.sql
  ('d_levelup', 'daily', 'levelup', 1,  '{"loyalty":10,"gold":500,"exp":5}',   '카드 강화',    '⬆️'),
  ('d_checkin', 'daily', 'checkin', 1,  '{"loyalty":10,"exp":5}',              '집결',         '🕯️'),
  ('w_phase',   'weekly', 'phase',   30,  '{}', '균열 정리',   '🗡️'),
  ('w_pvp',     'weekly', 'pvp_win', 10,  '{}', '피의 결투',   '⚔️'),
  ('w_stamina', 'weekly', 'stamina', 300, '{}', '행동력 헌납', '🔋'),
  ('w_tower',   'weekly', 'tower',   5,   '{}', '탑 정복',     '🗼'),
  ('w_checkin', 'weekly', 'checkin', 5,   '{}', '집결의 맹세', '🕯️'),
  ('w_draw',    'weekly', 'draw',    5,   '{}', '소환 의식',   '🎴')
on conflict (key) do update set kind = excluded.kind, event = excluded.event, goal = excluded.goal, reward = excluded.reward, label = excluded.label, icon = excluded.icon;$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_daily_quests (
  user_id uuid not null references auth.users(id) on delete cascade, day date not null, slot int not null check (slot between 1 and 3),
  qkey text not null, goal int not null, progress int not null default 0, rerolled boolean not null default false, claimed_at timestamptz,
  primary key (user_id, day, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_weekly_quests (
  guild_id bigint not null references public.guilds(id) on delete cascade, week date not null, slot int not null check (slot between 1 and 3),
  qkey text not null, goal int not null, progress int not null default 0, primary key (guild_id, week, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_weekly_contrib (
  guild_id bigint not null, week date not null, slot int not null, user_id uuid not null references auth.users(id) on delete cascade,
  amount int not null default 0, primary key (guild_id, week, slot, user_id));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_claims (
  user_id uuid not null references auth.users(id) on delete cascade, ref text not null, guild_id bigint, reward jsonb not null, at timestamptz not null default now(),
  primary key (user_id, ref));$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['guild_attendance', 'guild_quest_pool', 'guild_daily_quests', 'guild_weekly_quests', 'guild_weekly_contrib', 'guild_claims'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 수치 (한 곳에서 조정)
create or replace function public._guild_week() returns date language sql stable as $$ select date_trunc('week', _guild_day()::timestamp)::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_checkin_reward() returns jsonb language sql immutable as $$ select '{"loyalty":20,"gold":1000,"exp":10}'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 출석률 보너스: [필요 %, 개인 보상, 조직 세력]
create or replace function public._guild_rally_tiers() returns jsonb language sql immutable as $$
  select '[{"tier":30,"reward":{"loyalty":10},"exp":30},{"tier":60,"reward":{"loyalty":20,"gold":1000},"exp":60},{"tier":90,"reward":{"loyalty":30,"gem":5},"exp":100}]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_week_streak_reward() returns jsonb language sql immutable as $$ select '{"loyalty":100,"tickets":1}'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_daily_all_reward() returns jsonb language sql immutable as $$ select '{"loyalty":20}'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 주간 공동 의뢰 단계: [%, 개인 보상, 조직 세력]
create or replace function public._guild_weekly_tiers() returns jsonb language sql immutable as $$
  select '[{"tier":50,"reward":{"loyalty":30},"exp":100},{"tier":100,"reward":{"loyalty":60,"gold":3000,"gem":10},"exp":200},{"tier":150,"reward":{"loyalty":100,"tickets":1},"exp":300}]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_weekly_min_pct() returns numeric language sql immutable as $$ select 0.01 $$;$vr_statement$;
  execute $vr_statement$-- 3) 내부 도우미
-- 보상 지급 (한 번만). 키: loyalty · gold · gem · tickets · exp(조직 세력). 이미 받았으면 'already claimed'
create or replace function public._guild_reward(p_uid uuid, p_gid bigint, p_rw jsonb, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path = public as $$
declare ok boolean; w jsonb;
begin
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
  execute $vr_statement$-- 오늘 일일 의뢰 3개 (없으면 뽑기, 같은 종류 중복 없음)
create or replace function public._guild_roll_daily(p_uid uuid) returns void language plpgsql security definer set search_path = public as $$
declare d date := _guild_day(); q record; i int := 0;
begin
  if exists (select 1 from guild_daily_quests where user_id = p_uid and day = d) then return; end if;
  for q in select key, goal from guild_quest_pool where kind = 'daily' and active order by -ln(1 - random()) / greatest(weight, 1) limit 3 loop
    i := i + 1; insert into guild_daily_quests (user_id, day, slot, qkey, goal) values (p_uid, d, i, q.key, q.goal) on conflict do nothing;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 이번 주 공동 의뢰 3개 (목표 = 1인 목표 × 그때 인원)
create or replace function public._guild_roll_weekly(p_gid bigint) returns void language plpgsql security definer set search_path = public as $$
declare w date := _guild_week(); q record; i int := 0; n int;
begin
  if exists (select 1 from guild_weekly_quests where guild_id = p_gid and week = w) then return; end if;
  perform _guild_lock(p_gid);
  if exists (select 1 from guild_weekly_quests where guild_id = p_gid and week = w) then return; end if;
  select greatest(count(*), 1) into n from guild_members where guild_id = p_gid;
  for q in select key, goal from guild_quest_pool where kind = 'weekly' and active order by -ln(1 - random()) / greatest(weight, 1) limit 3 loop
    i := i + 1; insert into guild_weekly_quests (guild_id, week, slot, qkey, goal) values (p_gid, w, i, q.key, q.goal * n) on conflict do nothing;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 진행 이벤트 (서버 함수·트리거에서만). 조직이 없으면 무시. 오류가 나도 원래 동작은 막지 않음
create or replace function public._guild_event(p_uid uuid, p_kind text, p_n int) returns void language plpgsql security definer set search_path = public as $$
declare m guild_members; w date := _guild_week();
begin
  if p_uid is null or coalesce(p_n, 0) <= 0 then return; end if;
  select * into m from guild_members where user_id = p_uid;
  if m.user_id is null then return; end if;
  begin
    perform _guild_roll_daily(p_uid);
    update guild_daily_quests d set progress = least(d.goal, d.progress + p_n)
      from guild_quest_pool p where d.user_id = p_uid and d.day = _guild_day() and p.key = d.qkey and p.event = p_kind and d.claimed_at is null;
    perform _guild_roll_weekly(m.guild_id);
    if exists (select 1 from guild_weekly_quests q join guild_quest_pool p on p.key = q.qkey where q.guild_id = m.guild_id and q.week = w and p.event = p_kind) then
      perform _guild_lock(m.guild_id);
      insert into guild_weekly_contrib (guild_id, week, slot, user_id, amount)
        select q.guild_id, q.week, q.slot, p_uid, p_n from guild_weekly_quests q join guild_quest_pool p on p.key = q.qkey where q.guild_id = m.guild_id and q.week = w and p.event = p_kind
        on conflict (guild_id, week, slot, user_id) do update set amount = guild_weekly_contrib.amount + excluded.amount;
      update guild_weekly_quests q set progress = q.progress + p_n from guild_quest_pool p where q.guild_id = m.guild_id and q.week = w and p.key = q.qkey and p.event = p_kind;
    end if;
  exception when others then
    raise warning '[guild_event] %', sqlerrm;
  end;
end $$;$vr_statement$;
  execute $vr_statement$-- 오늘 출석 인원 (오늘 가입한 사람 제외) / 현재 인원
create or replace function public._guild_rally_count(p_gid bigint) returns int[] language sql stable security definer set search_path = public as $$
  select array[(select count(*)::int from guild_attendance a join guild_members gm on gm.user_id = a.user_id and gm.guild_id = p_gid
                 where a.guild_id = p_gid and a.day = _guild_day() and gm.joined_at < (_guild_day()::timestamp at time zone 'Asia/Seoul')),
               (select count(*)::int from guild_members where guild_id = p_gid)] $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._guild_reward(uuid, bigint, jsonb, text, text), public._guild_roll_daily(uuid), public._guild_roll_weekly(bigint),
  public._guild_event(uuid, text, int), public._guild_rally_count(bigint) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 트리거: 카드 뽑기(story_gacha_log) · 카드 레벨업(wallet_log 'card_levelup') · 탑 클리어(quest_progress / tower_progress clears 증가)
create or replace function public._guild_trg_draw() returns trigger language plpgsql security definer set search_path = public as $$
begin perform _guild_event(new.user_id, 'draw', 1); return null; end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_trg_levelup() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.reason = 'card_levelup' then perform _guild_event(new.user_id, 'levelup', 1); end if; return null; end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_trg_tower() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.clears > old.clears then perform _guild_event(new.user_id, 'tower', new.clears - old.clears); end if; return null; end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._guild_trg_draw(), public._guild_trg_levelup(), public._guild_trg_tower() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists guild_ev_draw on public.story_gacha_log;$vr_statement$;
  execute $vr_statement$create trigger guild_ev_draw after insert on public.story_gacha_log for each row execute function public._guild_trg_draw();$vr_statement$;
  execute $vr_statement$drop trigger if exists guild_ev_levelup on public.wallet_log;$vr_statement$;
  execute $vr_statement$create trigger guild_ev_levelup after insert on public.wallet_log for each row execute function public._guild_trg_levelup();$vr_statement$;
  execute $vr_statement$do $$ begin
  if to_regclass('public.quest_progress') is not null then
    drop trigger if exists guild_ev_tower on public.quest_progress;
    create trigger guild_ev_tower after update of clears on public.quest_progress for each row execute function public._guild_trg_tower();
  end if;
  if to_regclass('public.tower_progress') is not null then
    drop trigger if exists guild_ev_tower on public.tower_progress;
    create trigger guild_ev_tower after update of clears on public.tower_progress for each row execute function public._guild_trg_tower();
  end if;
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 공개 RPC
-- 집결 상태: { ok, checked, count, total, pct, tiers:[{tier, reward, exp, reached, claimed}], week:[7일 bool], week_claimable, week_claimed, checked_users:[uid] }
create or replace function public.guild_rally() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; c int[]; pct numeric; d date := _guild_day(); w date := _guild_week(); days int;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  c := _guild_rally_count(m.guild_id); pct := case when c[2] > 0 then c[1] * 100.0 / c[2] else 0 end;
  select count(*) into days from guild_attendance where user_id = uid and day between w and w + 6;
  return jsonb_build_object('ok', true, 'day', d, 'checked', exists (select 1 from guild_attendance where user_id = uid and day = d),
    'checked_other', exists (select 1 from guild_attendance where user_id = uid and day = d and guild_id <> m.guild_id),
    'count', c[1], 'total', c[2], 'pct', round(pct, 1), 'reward', _guild_checkin_reward(),
    'tiers', (select jsonb_agg(t || jsonb_build_object('reached', pct >= (t->>'tier')::int, 'claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'rally:' || d || ':' || (t->>'tier'))))
              from jsonb_array_elements(_guild_rally_tiers()) t),
    'week', (select jsonb_agg(exists (select 1 from guild_attendance where user_id = uid and day = w + i) order by i) from generate_series(0, 6) i),
    'week_reward', _guild_week_streak_reward(), 'week_claimable', days >= 7, 'week_claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'rallyweek:' || w),
    'checked_users', (select coalesce(jsonb_agg(a.user_id), '[]'::jsonb) from guild_attendance a where a.guild_id = m.guild_id and a.day = d));
end $$;$vr_statement$;
  execute $vr_statement$-- 집결 (하루 1번, 조직을 옮겨도 하루 1번)
create or replace function public.guild_checkin() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; ok boolean; r jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  insert into guild_attendance (user_id, day, guild_id) values (uid, _guild_day(), m.guild_id) on conflict do nothing returning true into ok;
  if not coalesce(ok, false) then raise exception 'already checked in'; end if;
  r := _guild_reward(uid, m.guild_id, _guild_checkin_reward(), 'guild_checkin', 'checkin:' || _guild_day());
  perform _guild_event(uid, 'checkin', 1);
  return guild_rally() || jsonb_build_object('got', _guild_checkin_reward(), 'wallet', r->'wallet');
end $$;$vr_statement$;
  execute $vr_statement$-- 출석률 보너스 (p_tier = 30 | 60 | 90) 또는 주간 개근 (p_tier = 7)
create or replace function public.guild_rally_claim(p_tier int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; c int[]; t jsonb; d date := _guild_day(); w date := _guild_week(); r jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if p_tier = 7 then
    if (select count(*) from guild_attendance where user_id = uid and day between w and w + 6) < 7 then raise exception 'not reached'; end if;
    r := _guild_reward(uid, m.guild_id, _guild_week_streak_reward(), 'guild_rally_week', 'rallyweek:' || w);
    return guild_rally() || jsonb_build_object('got', _guild_week_streak_reward(), 'wallet', r->'wallet');
  end if;
  select x into t from jsonb_array_elements(_guild_rally_tiers()) x where (x->>'tier')::int = p_tier;
  if t is null then raise exception 'bad tier'; end if;
  if not exists (select 1 from guild_attendance where user_id = uid and day = d and guild_id = m.guild_id) then raise exception 'check in first'; end if;
  c := _guild_rally_count(m.guild_id);
  if c[2] = 0 or c[1] * 100.0 / c[2] < p_tier then raise exception 'not reached'; end if;
  r := _guild_reward(uid, m.guild_id, t->'reward', 'guild_rally_bonus', 'rally:' || d || ':' || p_tier);
  perform _guild_exp(m.guild_id, null, (t->>'exp')::int, 'rally_bonus', 'rally:' || d || ':' || p_tier);   -- 조직 세력은 조직당 한 번
  return guild_rally() || jsonb_build_object('got', t->'reward', 'wallet', r->'wallet');
end $$;$vr_statement$;
  execute $vr_statement$-- 의뢰 상태
create or replace function public.guild_quests() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; d date := _guild_day(); w date := _guild_week();
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_roll_daily(uid); perform _guild_roll_weekly(m.guild_id);
  return jsonb_build_object('ok', true, 'day', d, 'week', w, 'week_end', ((w + 7)::timestamp at time zone 'Asia/Seoul'),
    'daily', (select jsonb_agg(jsonb_build_object('slot', q.slot, 'key', q.qkey, 'label', p.label, 'icon', p.icon, 'event', p.event, 'goal', q.goal, 'progress', q.progress,
                'reward', p.reward, 'claimed', q.claimed_at is not null) order by q.slot) from guild_daily_quests q join guild_quest_pool p on p.key = q.qkey where q.user_id = uid and q.day = d),
    'reroll_left', case when exists (select 1 from guild_daily_quests where user_id = uid and day = d and rerolled) then 0 else 1 end,
    'all_reward', _guild_daily_all_reward(), 'all_claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'dqall:' || d),
    'weekly', (select jsonb_agg(jsonb_build_object('slot', q.slot, 'key', q.qkey, 'label', p.label, 'icon', p.icon, 'event', p.event, 'goal', q.goal, 'progress', q.progress,
                'mine', coalesce((select amount from guild_weekly_contrib c where c.guild_id = q.guild_id and c.week = w and c.slot = q.slot and c.user_id = uid), 0),
                'min', ceil(q.goal * _guild_weekly_min_pct())::int,
                'tiers', (select jsonb_agg(t || jsonb_build_object('reached', q.progress * 100 >= q.goal * (t->>'tier')::int,
                            'claimed', exists (select 1 from guild_claims where user_id = uid and ref = 'wq:' || w || ':' || q.slot || ':' || (t->>'tier')))) from jsonb_array_elements(_guild_weekly_tiers()) t),
                'top', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(pr.nickname, '조직원'), 'amount', c.amount) order by c.amount desc), '[]'::jsonb)
                        from (select * from guild_weekly_contrib c2 where c2.guild_id = q.guild_id and c2.week = w and c2.slot = q.slot order by amount desc limit 5) c left join profiles pr on pr.id = c.user_id))
              order by q.slot) from guild_weekly_quests q join guild_quest_pool p on p.key = q.qkey where q.guild_id = m.guild_id and q.week = w));
end $$;$vr_statement$;
  execute $vr_statement$-- 일일 의뢰 보상 (p_slot 1~3) · 3개 완료 보너스 (p_slot = 0)
create or replace function public.guild_quest_claim(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; d date := _guild_day(); q guild_daily_quests; rw jsonb; r jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if p_slot = 0 then
    if (select count(*) from guild_daily_quests where user_id = uid and day = d and claimed_at is not null) < 3 then raise exception 'not reached'; end if;
    r := _guild_reward(uid, m.guild_id, _guild_daily_all_reward(), 'guild_daily_all', 'dqall:' || d);
    return guild_quests() || jsonb_build_object('got', _guild_daily_all_reward(), 'wallet', r->'wallet');
  end if;
  select * into q from guild_daily_quests where user_id = uid and day = d and slot = p_slot for update;
  if q.user_id is null then raise exception 'no quest'; end if;
  if q.progress < q.goal then raise exception 'not reached'; end if;
  select reward into rw from guild_quest_pool where key = q.qkey;
  r := _guild_reward(uid, m.guild_id, rw, 'guild_daily', 'dq:' || d || ':' || p_slot);
  update guild_daily_quests set claimed_at = now() where user_id = uid and day = d and slot = p_slot;
  return guild_quests() || jsonb_build_object('got', rw, 'wallet', r->'wallet');
end $$;$vr_statement$;
  execute $vr_statement$-- 일일 의뢰 교체 (하루 1번 무료, 받지 않은 칸만, 진행도 0 부터)
create or replace function public.guild_quest_reroll(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; d date := _guild_day(); q guild_daily_quests; nk record;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_roll_daily(uid);
  if exists (select 1 from guild_daily_quests where user_id = uid and day = d and rerolled) then raise exception 'reroll used'; end if;
  select * into q from guild_daily_quests where user_id = uid and day = d and slot = p_slot for update;
  if q.user_id is null or q.claimed_at is not null then raise exception 'no quest'; end if;
  select key, goal into nk from guild_quest_pool where kind = 'daily' and active and key not in (select qkey from guild_daily_quests where user_id = uid and day = d) order by random() limit 1;
  if nk.key is null then raise exception 'no quest'; end if;
  update guild_daily_quests set qkey = nk.key, goal = nk.goal, progress = 0, rerolled = true where user_id = uid and day = d and slot = p_slot;
  return guild_quests();
end $$;$vr_statement$;
  execute $vr_statement$-- 주간 공동 의뢰 보상 (p_tier = 50 | 100 | 150). 기여 1% 이상만. 조직 세력은 조직당 한 번
create or replace function public.guild_weekly_claim(p_slot int, p_tier int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; w date := _guild_week(); q guild_weekly_quests; t jsonb; mine int; r jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  select * into q from guild_weekly_quests where guild_id = m.guild_id and week = w and slot = p_slot;
  if q.guild_id is null then raise exception 'no quest'; end if;
  select x into t from jsonb_array_elements(_guild_weekly_tiers()) x where (x->>'tier')::int = p_tier;
  if t is null then raise exception 'bad tier'; end if;
  if q.progress * 100 < q.goal * p_tier then raise exception 'not reached'; end if;
  select amount into mine from guild_weekly_contrib where guild_id = q.guild_id and week = w and slot = p_slot and user_id = uid;
  if coalesce(mine, 0) < ceil(q.goal * _guild_weekly_min_pct()) then raise exception 'contribution too low'; end if;
  r := _guild_reward(uid, m.guild_id, t->'reward', 'guild_weekly', 'wq:' || w || ':' || p_slot || ':' || p_tier);
  perform _guild_exp(m.guild_id, null, (t->>'exp')::int, 'weekly_quest', 'wq:' || w || ':' || p_slot || ':' || p_tier);
  return guild_quests() || jsonb_build_object('got', t->'reward', 'wallet', r->'wallet');
end $$;$vr_statement$;
  execute $vr_statement$-- 조직 홈 빨간 점: { rally: 집결 안 했거나 받을 보너스, quest: 받을 의뢰 보상 }
create or replace function public.guild_dots() returns jsonb language plpgsql security definer set search_path = public as $$
declare rl jsonb; qs jsonb;
begin
  if (_guild_me(auth.uid())).user_id is null then return jsonb_build_object('ok', true, 'rally', false, 'quest', false); end if;
  rl := guild_rally(); qs := guild_quests();
  return jsonb_build_object('ok', true,
    'rally', not (rl->>'checked')::boolean or exists (select 1 from jsonb_array_elements(rl->'tiers') t where (t->>'reached')::boolean and not (t->>'claimed')::boolean)
             or ((rl->>'week_claimable')::boolean and not (rl->>'week_claimed')::boolean),
    'quest', exists (select 1 from jsonb_array_elements(qs->'daily') x where (x->>'progress')::int >= (x->>'goal')::int and not (x->>'claimed')::boolean)
             or exists (select 1 from jsonb_array_elements(qs->'weekly') x, jsonb_array_elements(x->'tiers') t where (t->>'reached')::boolean and not (t->>'claimed')::boolean and (x->>'mine')::int >= (x->>'min')::int));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_rally(), public.guild_checkin(), public.guild_rally_claim(int), public.guild_quests(), public.guild_quest_claim(int),
  public.guild_quest_reroll(int), public.guild_weekly_claim(int, int), public.guild_dots() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_rally(), public.guild_checkin(), public.guild_rally_claim(int), public.guild_quests(), public.guild_quest_claim(int),
  public.guild_quest_reroll(int), public.guild_weekly_claim(int, int), public.guild_dots() to authenticated;$vr_statement$;
  execute $vr_statement$-- 조직원 상세 (같은 조직만, 공개 정보만)
create or replace function public.guild_member_info(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me guild_members; x guild_members; pr record;
begin
  me := _guild_me(auth.uid());
  if me.user_id is null then raise exception 'not in guild'; end if;
  select * into x from guild_members where user_id = p_user and guild_id = me.guild_id;
  if x.user_id is null then raise exception 'not member'; end if;
  select rating, wins, losses into pr from pvp_ratings where user_id = p_user and season = _pvp_season() order by rating desc limit 1;
  return jsonb_build_object('ok', true, 'user_id', x.user_id, 'name', coalesce((select nickname from profiles where id = p_user), '조직원'),
    'level', coalesce((select level from player_state where user_id = p_user), 1), 'role', x.role, 'joined_at', x.joined_at, 'seen_at', x.seen_at,
    'loyalty_total', x.loyalty_total,
    'loyalty_week', coalesce((select sum(delta) from loyalty_ledger where user_id = p_user and delta > 0 and created_at >= (_guild_week()::timestamp at time zone 'Asia/Seoul')), 0),
    'pvp', case when pr.rating is null then null else jsonb_build_object('rating', pr.rating, 'tier', _pvp_tier(pr.rating), 'wins', pr.wins, 'losses', pr.losses) end,
    'card', (select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = p_user and o->>'uid' = sp.data->>'leader' limit 1),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'level', t.lv) order by t.lv desc), '[]'::jsonb) from (
              select o->>'id' id, max(coalesce((o->>'level')::int, 1)) lv from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o
              where sp.user_id = p_user and o ? 'id' group by o->>'id' order by 2 desc limit 3) t));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_member_info(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_member_info(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 관리자: 조직 출석·의뢰 보기 · 주간 의뢰 다시 뽑기
create or replace function public.admin_guild_activity(p_gid bigint) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('rally', _guild_rally_count(p_gid),
    'attendance_7d', (select coalesce(jsonb_object_agg(day, n), '{}'::jsonb) from (select day, count(*) n from guild_attendance where guild_id = p_gid and day > _guild_day() - 7 group by day) x),
    'weekly', (select coalesce(jsonb_agg(to_jsonb(q) order by slot), '[]'::jsonb) from guild_weekly_quests q where guild_id = p_gid and week = _guild_week()));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_guild_reset_weekly(p_gid bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  delete from guild_weekly_quests where guild_id = p_gid and week = _guild_week();
  delete from guild_weekly_contrib where guild_id = p_gid and week = _guild_week();
  perform _guild_roll_weekly(p_gid);
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason) values (auth.uid(), auth.jwt()->>'email', 'guild_reset_weekly', null, p_gid::int, left(btrim(p_reason), 200));
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_guild_activity(bigint), public.admin_guild_reset_weekly(bigint, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_guild_activity(bigint), public.admin_guild_reset_weekly(bigint, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 7) 스토리·PvP 연동 (phaseE_3.sql / phaseE_5.sql / guild.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_guild2_sql.mjs 가 일치 확인)
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
  -- 조직 의뢰 진행 (guild2.sql): 페이즈 클리어 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', 1); perform _guild_event(uid, 'stamina', spent);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', 1); end if;
  end if;
  -- 재화 드롭 (phaseE_3.sql 의 _story_drops 가 있으면)
  if to_regprocedure('public._story_drops(uuid,integer,integer,boolean)') is not null then
    execute 'select public._story_drops($1, $2, $3, $4)' into drops using uid, p_chapter, p_phase, coalesce((r->>'first')::boolean, false);
  end if;
  return r || jsonb_build_object('player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'))
           || case when drops is null then '{}'::jsonb else jsonb_build_object('drops', drops) end;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_complete_phase(int, int, jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_complete_phase(int, int, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_runs is null or p_runs not in (1, 5, 10) then raise exception 'invalid runs'; end if;
  if not _player_unlocked(uid, 'sweep') then raise exception 'sweep locked (player Lv%)', _player_unlock_level('sweep'); end if;
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if not found then raise exception 'unknown phase'; end if;
  select data into d from story_progress where user_id = uid for update;
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  cost := _stamina_cost(p_chapter, p_phase);
  perform _player_stamina_add(uid, -cost * p_runs);   -- 부족하면 'not enough stamina' (전체 롤백)
  for i in 1..p_runs loop
    dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), false, cost, random()::numeric, random()::numeric);
    runs := runs || dr;
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
    'drops', tot, 'per_run', runs, 'wallet', w,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_sweep(int, int, int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_sweep(int, int, int) to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_feed(p_uid uuid, p_src text, p_n int) returns int language plpgsql security definer set search_path = public as $$
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
  execute $vr_statement$revoke all on function public._guild_feed(uuid, text, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild3.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _raid_numbers 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- 조직 3단계: 「균열 토벌」 (조직 레이드). 여러 번 실행해도 안전.
-- 선행: guild.sql · guild2.sql · pvp.sql(_pvp_snap · pvp_card_meta) · gem.sql
-- 주기: 매주 월 00:00 ~ 일 22:00 (KST) 토벌, 일 22:00 부터 순위 보상 수령. 하루 3회(행동력 없음) · 소탕 = 오늘 최고 기록 90% (그날 1회 이상 직접 싸운 뒤)
-- 전투: 브라우저 js/raid-core.js (서버 seed + 서버가 만든 덱 스냅샷, 자동 전투). 서버는 한 판 상한·최소 시간 검사 + seed·스냅샷 보관 → tools/raid_verify.mjs 로 재검증
-- 보스: 단계별 1 임유리 · 2 [각성] 임유리 · 3 김신현 · 4 김성진 · 5 이지영 → 6단계부터 다시 1번, HP 는 단계마다 ×1.35
-- 보상 숫자는 전부 _raid_numbers() 하나에 있음

-- 1) 테이블
create table if not exists public.guild_raids (
  guild_id bigint not null references public.guilds(id) on delete cascade, week date not null,
  difficulty text not null default 'normal' check (difficulty in ('normal', 'hard', 'abyss')),
  members int not null, stage int not null default 1, hp_max bigint not null, hp_left bigint not null,
  total_damage bigint not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (guild_id, week));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_stages (
  guild_id bigint not null, week date not null, stage int not null, boss_id text, hp bigint not null,
  cleared_at timestamptz, last_hit uuid references auth.users(id) on delete set null,
  primary key (guild_id, week, stage), foreign key (guild_id, week) references public.guild_raids(guild_id, week) on delete cascade);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null, week date not null, day date not null,
  kind text not null check (kind in ('fight', 'sweep')), stage int not null, difficulty text not null,
  seed bigint, snap jsonb, reported bigint, damage bigint not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);$vr_statement$;
  execute $vr_statement$create index if not exists guild_raid_attempts_user on public.guild_raid_attempts (user_id, day);$vr_statement$;
  execute $vr_statement$create index if not exists guild_raid_attempts_guild on public.guild_raid_attempts (guild_id, week);$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_raid_damage (
  guild_id bigint not null, week date not null, user_id uuid not null references auth.users(id) on delete cascade,
  damage bigint not null default 0, attempts int not null default 0, updated_at timestamptz not null default now(),
  primary key (guild_id, week, user_id));$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['guild_raids', 'guild_raid_stages', 'guild_raid_attempts', 'guild_raid_damage'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 숫자 (여기만 고치면 됨)
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
  execute $vr_statement$-- 단계 → 보스 (js/raid-core.js RAID_BOSSES 와 같음)
create or replace function public._raid_boss(p_stage int) returns jsonb language sql immutable as $$
  select (array['{"id":"10325","name":"임유리","weak":"CHARGE"}', '{"id":"10326","name":"[각성] 임유리","weak":"DEFENSE"}',
                '{"id":"10062","name":"김신현","weak":"CRUSH"}', '{"id":"10060","name":"김성진","weak":"SUPPORT"}',
                '{"id":"10311","name":"이지영","weak":"DISTURB"}'])[((greatest(p_stage, 1) - 1) % 5) + 1]::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_now() returns timestamptz language sql stable as $$ select now() $$;$vr_statement$;
  execute $vr_statement$-- 테스트에서 바꿔 끼움
create or replace function public._raid_end(p_week date) returns timestamptz language sql stable as $$ select ((p_week + 6)::timestamp + interval '22 hours') at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_hp(p_diff text, p_members int, p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers()->'hp_per_member'->>p_diff)::numeric * greatest(p_members, (_raid_numbers()->>'hp_min_members')::int)
               * power((_raid_numbers()->>'hp_growth')::numeric, greatest(p_stage, 1) - 1))::bigint $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_attempt_cap(p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers()->>'hit_cap')::numeric * power((_raid_numbers()->>'hit_cap_growth')::numeric, greatest(p_stage, 1) - 1)) * (_raid_numbers()->>'attempt_hits')::int $$;$vr_statement$;
  execute $vr_statement$-- 단계 처치 개인 보상 (난이도 배율: 충성·골드·심연석)
create or replace function public._raid_stage_reward(p_diff text, p_stage int) returns jsonb language sql immutable as $$
  with n as (select _raid_numbers() j), x as (select j->'stage' s, (j->'diff_mult'->>p_diff)::numeric m from n)
  select jsonb_strip_nulls(jsonb_build_object('loyalty', round((s->>'loyalty')::int * m)::int, 'gold', round((s->>'gold')::int * m)::int,
    'gem', round(((s->>'gem')::int + case when p_stage % 3 = 0 then (s->>'gem_every3')::int else 0 end) * m)::int,
    'tickets', case when p_stage % 5 = 0 then (s->>'tickets_every5')::int end)) from x $$;$vr_statement$;
  execute $vr_statement$create or replace function public._raid_rank_reward(p_rank int) returns jsonb language sql immutable as $$
  select coalesce((select r->'reward' from jsonb_array_elements(_raid_numbers()->'rank') r where p_rank between (r->>'from')::int and (r->>'to')::int), '{}'::jsonb) $$;$vr_statement$;
  execute $vr_statement$-- 3) 내부
-- 이번 주 레이드 (없으면 만듦: 그때 인원으로 HP 고정)
create or replace function public._raid_get(p_gid bigint, p_week date) returns guild_raids language plpgsql security definer set search_path = public as $$
declare r guild_raids; n int;
begin
  select * into r from guild_raids where guild_id = p_gid and week = p_week;
  if r.guild_id is not null then return r; end if;
  select count(*) into n from guild_members where guild_id = p_gid;
  insert into guild_raids (guild_id, week, members, hp_max, hp_left) values (p_gid, p_week, n, _raid_hp('normal', n, 1), _raid_hp('normal', n, 1)) on conflict do nothing;
  insert into guild_raid_stages (guild_id, week, stage, boss_id, hp) values (p_gid, p_week, 1, _raid_boss(1)->>'id', _raid_hp('normal', n, 1)) on conflict do nothing;
  select * into r from guild_raids where guild_id = p_gid and week = p_week;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$-- 공유 HP 깎기 (넘친 피해는 다음 단계로). 반환 처치한 단계 수
create or replace function public._raid_hit(p_gid bigint, p_week date, p_uid uuid, p_dmg bigint) returns int language plpgsql security definer set search_path = public as $$
declare r guild_raids; d bigint := greatest(p_dmg, 0); k int := 0; nhp bigint;
begin
  select * into r from guild_raids where guild_id = p_gid and week = p_week for update;
  update guild_raids set total_damage = total_damage + d, updated_at = now() where guild_id = p_gid and week = p_week;
  while d > 0 and k < 100 loop
    if d < r.hp_left then r.hp_left := r.hp_left - d; d := 0;
    else
      d := d - r.hp_left; k := k + 1;
      update guild_raid_stages set cleared_at = now(), last_hit = p_uid where guild_id = p_gid and week = p_week and stage = r.stage;
      perform _guild_exp(p_gid, null, r.stage * (_raid_numbers()->'stage'->>'exp_per_stage')::int, 'raid_stage', 'raid:' || p_week || ':' || r.stage);
      perform _guild_reward(p_uid, p_gid, _raid_numbers()->'last_hit', 'raid_last_hit', 'raidlh:' || p_gid || ':' || p_week || ':' || r.stage);
      r.stage := r.stage + 1; nhp := _raid_hp(r.difficulty, r.members, r.stage); r.hp_max := nhp; r.hp_left := nhp;
      insert into guild_raid_stages (guild_id, week, stage, boss_id, hp) values (p_gid, p_week, r.stage, _raid_boss(r.stage)->>'id', nhp) on conflict do nothing;
    end if;
  end loop;
  update guild_raids set stage = r.stage, hp_max = r.hp_max, hp_left = r.hp_left where guild_id = p_gid and week = p_week;
  return k;
end $$;$vr_statement$;
  execute $vr_statement$-- 한 판 마감 (피해 기록 · 공유 HP · 1회 보상 · 의뢰 진행)
create or replace function public._raid_close(a guild_raid_attempts, p_dmg bigint) returns jsonb language plpgsql security definer set search_path = public as $$
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
  return jsonb_build_object('damage', p_dmg, 'cleared', k, 'got', rw - 'exp');
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._raid_get(bigint, date), public._raid_hit(bigint, date, uuid, bigint), public._raid_close(guild_raid_attempts, bigint) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 4) 공개 RPC
-- 상태
create or replace function public.raid_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; w date := _guild_week(); r guild_raids; N jsonb := _raid_numbers(); used int; best bigint; fought boolean; open_id bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  select * into g from guilds where id = m.guild_id;
  r := _raid_get(m.guild_id, w);
  select count(*), coalesce(max(damage) filter (where kind = 'fight' and finished_at is not null and not voided), 0), bool_or(kind = 'fight' and finished_at is not null)
    into used, best, fought from guild_raid_attempts where user_id = uid and day = _guild_day();
  return jsonb_build_object('ok', true, 'week', w, 'ends_at', _raid_end(w), 'ended', _raid_now() >= _raid_end(w),
    'difficulty', r.difficulty, 'guild_level', g.level, 'diff_level', N->'diff_level', 'diff_mult', N->'diff_mult',
    'can_set_diff', m.role in ('boss', 'officer') and r.total_damage = 0,
    'stage', r.stage, 'hp_max', r.hp_max, 'hp_left', r.hp_left, 'total_damage', r.total_damage, 'boss', _raid_boss(r.stage), 'next_boss', _raid_boss(r.stage + 1),
    'attempts_left', greatest(0, (N->>'attempts_per_day')::int - used), 'best_today', best, 'can_sweep', coalesce(fought, false) and best > 0,
    'sweep_damage', best * (N->>'sweep_pct')::int / 100,
    'ranking', (select coalesce(jsonb_agg(jsonb_build_object('user_id', d.user_id, 'name', coalesce(p.nickname, '조직원'), 'damage', d.damage, 'attempts', d.attempts, 'me', d.user_id = uid) order by d.damage desc, d.user_id), '[]'::jsonb)
                from guild_raid_damage d left join profiles p on p.id = d.user_id where d.guild_id = m.guild_id and d.week = w and d.damage > 0),
    'stages', (select coalesce(jsonb_agg(jsonb_build_object('stage', s.stage, 'boss', _raid_boss(s.stage), 'cleared', s.cleared_at is not null,
                 'reward', _raid_stage_reward(r.difficulty, s.stage), 'claimed', exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidst:' || w || ':' || s.stage)) order by s.stage), '[]'::jsonb)
               from guild_raid_stages s where s.guild_id = m.guild_id and s.week = w),
    'rank_rewards', N->'rank', 'member_reward', N->'member', 'claimable', raid_claimable());
end $$;$vr_statement$;
  execute $vr_statement$-- 받을 수 있는 보상 수 (빨간 점)
create or replace function public.raid_claimable() returns int language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; w date; n int := 0;
begin
  m := _guild_me(uid);
  if m.user_id is null then return 0; end if;
  foreach w in array array[_guild_week(), _guild_week() - 7] loop
    n := n + (select count(*) from guild_raid_stages s join guild_raids r using (guild_id, week) where s.guild_id = m.guild_id and s.week = w and s.cleared_at is not null and m.joined_at <= s.cleared_at
              and not exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidst:' || w || ':' || s.stage));
    if _raid_now() >= _raid_end(w) and m.joined_at <= _raid_end(w) - make_interval(hours => (_raid_numbers()->>'join_hours')::int)
       and exists (select 1 from guild_raids where guild_id = m.guild_id and week = w)
       and not exists (select 1 from guild_claims c where c.user_id = uid and c.ref = 'raidrk:' || w) then n := n + 1; end if;
  end loop;
  return n;
end $$;$vr_statement$;
  execute $vr_statement$-- 난이도 (보스·간부, 이번 주 첫 피해 전까지)
create or replace function public.raid_set_difficulty(p_diff text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; r guild_raids; lv int; w date := _guild_week(); nhp bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if m.role not in ('boss', 'officer') then raise exception 'not allowed'; end if;
  if p_diff not in ('normal', 'hard', 'abyss') then raise exception 'bad difficulty'; end if;
  select level into lv from guilds where id = m.guild_id;
  if lv < (_raid_numbers()->'diff_level'->>p_diff)::int then raise exception 'guild level'; end if;
  r := _raid_get(m.guild_id, w);
  select * into r from guild_raids where guild_id = m.guild_id and week = w for update;
  if r.total_damage > 0 then raise exception 'raid started'; end if;
  nhp := _raid_hp(p_diff, r.members, 1);
  update guild_raids set difficulty = p_diff, stage = 1, hp_max = nhp, hp_left = nhp, updated_at = now() where guild_id = m.guild_id and week = w;
  update guild_raid_stages set hp = nhp where guild_id = m.guild_id and week = w and stage = 1;
  return raid_status();
end $$;$vr_statement$;
  execute $vr_statement$-- 전투 시작: 횟수 차감 · 덱 스냅샷 · seed
create or replace function public.raid_start(p_uids jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; w date := _guild_week(); r guild_raids; N jsonb := _raid_numbers(); snap jsonb; seed bigint; aid bigint;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if _raid_now() >= _raid_end(w) then raise exception 'raid ended'; end if;
  perform pg_advisory_xact_lock(hashtext('raid:' || uid));
  -- 끝내지 않은 판은 0 피해로 마감 (횟수는 이미 씀)
  update guild_raid_attempts set finished_at = now(), damage = 0 where user_id = uid and finished_at is null;
  if (select count(*) from guild_raid_attempts where user_id = uid and day = _guild_day()) >= (N->>'attempts_per_day')::int then raise exception 'no attempts'; end if;
  r := _raid_get(m.guild_id, w);
  snap := _pvp_snap(uid, p_uids, 'open')->'cards';
  seed := floor(random() * 2147483647)::bigint;
  insert into guild_raid_attempts (user_id, guild_id, week, day, kind, stage, difficulty, seed, snap)
    values (uid, m.guild_id, w, _guild_day(), 'fight', r.stage, r.difficulty, seed, snap) returning id into aid;
  return jsonb_build_object('ok', true, 'id', aid, 'seed', seed, 'deck', snap, 'stage', r.stage, 'difficulty', r.difficulty, 'boss', _raid_boss(r.stage));
end $$;$vr_statement$;
  execute $vr_statement$-- 전투 끝: 피해 보고 (한 판 상한 · 최소 시간)
create or replace function public.raid_finish(p_id bigint, p_damage bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a guild_raid_attempts; N jsonb := _raid_numbers(); cap bigint; d bigint; res jsonb;
begin
  select * into a from guild_raid_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.finished_at is not null then raise exception 'already finished'; end if;
  if now() - a.started_at < make_interval(secs => (N->>'min_secs')::int) then raise exception 'too fast'; end if;
  if now() - a.started_at > make_interval(mins => (N->>'open_minutes')::int) then
    update guild_raid_attempts set finished_at = now(), damage = 0 where id = a.id; raise exception 'battle expired'; end if;
  if _raid_now() >= _raid_end(a.week) + interval '5 minutes' then raise exception 'raid ended'; end if;
  if not exists (select 1 from guild_members where user_id = uid and guild_id = a.guild_id) then raise exception 'not in guild'; end if;
  cap := _raid_attempt_cap(a.stage); d := least(greatest(coalesce(p_damage, 0), 0), cap);
  update guild_raid_attempts set reported = p_damage, flagged = p_damage > cap where id = a.id;
  res := _raid_close(a, d);
  return raid_status() || jsonb_build_object('result', res);
end $$;$vr_statement$;
  execute $vr_statement$-- 소탕: 오늘 직접 싸운 최고 기록의 90% (횟수 1 사용)
create or replace function public.raid_sweep() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; w date := _guild_week(); r guild_raids; N jsonb := _raid_numbers(); best bigint; a guild_raid_attempts; res jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if _raid_now() >= _raid_end(w) then raise exception 'raid ended'; end if;
  perform pg_advisory_xact_lock(hashtext('raid:' || uid));
  if (select count(*) from guild_raid_attempts where user_id = uid and day = _guild_day()) >= (N->>'attempts_per_day')::int then raise exception 'no attempts'; end if;
  select max(damage) into best from guild_raid_attempts where user_id = uid and day = _guild_day() and kind = 'fight' and finished_at is not null and not voided;
  if coalesce(best, 0) <= 0 then raise exception 'fight first'; end if;
  r := _raid_get(m.guild_id, w);
  insert into guild_raid_attempts (user_id, guild_id, week, day, kind, stage, difficulty) values (uid, m.guild_id, w, _guild_day(), 'sweep', r.stage, r.difficulty) returning * into a;
  res := _raid_close(a, best * (N->>'sweep_pct')::int / 100);
  return raid_status() || jsonb_build_object('result', res);
end $$;$vr_statement$;
  execute $vr_statement$-- 보상 모두 받기: 처치 단계(그때 조직원이었던 사람) · 주간 순위/참여(정산 24시간 전 가입, 지금도 같은 조직)
create or replace function public.raid_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; w date; s record; rr guild_raids; got jsonb := '{}'::jsonb; rw jsonb; k text; rk int;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  foreach w in array array[_guild_week() - 7, _guild_week()] loop
    select * into rr from guild_raids where guild_id = m.guild_id and week = w;
    if rr.guild_id is null then continue; end if;
    for s in select * from guild_raid_stages where guild_id = m.guild_id and week = w and cleared_at is not null and m.joined_at <= cleared_at order by stage loop
      if exists (select 1 from guild_claims where user_id = uid and ref = 'raidst:' || w || ':' || s.stage) then continue; end if;
      rw := _raid_stage_reward(rr.difficulty, s.stage);
      perform _guild_reward(uid, m.guild_id, rw, 'raid_stage', 'raidst:' || w || ':' || s.stage);
      for k in select jsonb_object_keys(rw) loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (rw->>k)::int)); end loop;
    end loop;
    if _raid_now() >= _raid_end(w) and m.joined_at <= _raid_end(w) - make_interval(hours => (_raid_numbers()->>'join_hours')::int)
       and not exists (select 1 from guild_claims where user_id = uid and ref = 'raidrk:' || w) then
      select x.rk into rk from (select user_id, row_number() over (order by damage desc, user_id) rk from guild_raid_damage where guild_id = m.guild_id and week = w and damage > 0) x where x.user_id = uid;
      rw := _raid_numbers()->'member';
      if rk is not null then
        for k in select jsonb_object_keys(_raid_rank_reward(rk)) loop rw := jsonb_set(rw, array[k], to_jsonb(coalesce((rw->>k)::int, 0) + (_raid_rank_reward(rk)->>k)::int)); end loop;
      end if;
      perform _guild_reward(uid, m.guild_id, rw || jsonb_build_object('rank', rk), 'raid_rank', 'raidrk:' || w);
      for k in select jsonb_object_keys(rw) loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (rw->>k)::int)); end loop;
      got := got || jsonb_build_object('rank', rk);
    end if;
  end loop;
  if got = '{}'::jsonb then raise exception 'nothing to claim'; end if;
  return raid_status() || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.raid_status(), public.raid_claimable(), public.raid_set_difficulty(text), public.raid_start(jsonb), public.raid_finish(bigint, bigint), public.raid_sweep(), public.raid_claim() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.raid_status(), public.raid_claimable(), public.raid_set_difficulty(text), public.raid_start(jsonb), public.raid_finish(bigint, bigint), public.raid_sweep(), public.raid_claim() to authenticated;$vr_statement$;
  execute $vr_statement$-- 5) 관리자: 조직 토벌 현황 · 의심 기록 · 기록 무효(사유 필수, 개인 누적만 빼고 공유 HP 는 그대로)
create or replace function public.admin_guild_raid(p_gid bigint) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('raid', (select to_jsonb(r) from guild_raids r where guild_id = p_gid and week = _guild_week()),
    'flagged', (select coalesce(jsonb_agg(to_jsonb(a) - 'snap' order by a.id desc), '[]'::jsonb) from (select * from guild_raid_attempts where guild_id = p_gid and flagged order by id desc limit 50) a),
    'top', (select coalesce(jsonb_agg(to_jsonb(d) order by d.damage desc), '[]'::jsonb) from guild_raid_damage d where guild_id = p_gid and week = _guild_week()));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_raid_void(p_id bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare a guild_raid_attempts;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  select * into a from guild_raid_attempts where id = p_id for update;
  if a.id is null or a.voided then raise exception 'no attempt'; end if;
  update guild_raid_attempts set voided = true where id = p_id;
  update guild_raid_damage set damage = greatest(0, damage - a.damage) where guild_id = a.guild_id and week = a.week and user_id = a.user_id;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason) values (auth.uid(), auth.jwt()->>'email', 'raid_void', a.user_id, least(a.damage, 2147483647)::int, left(btrim(p_reason), 200));
  return jsonb_build_object('ok', true, 'voided', p_id, 'damage', a.damage);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_guild_raid(bigint), public.admin_raid_void(bigint, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_guild_raid(bigint), public.admin_raid_void(bigint, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild4.sql =====
-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _war_lock, _war_npc_deck, _war_numbers 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- 조직 4단계: 「구역 전쟁」 (조직 대 조직). 여러 번 실행해도 안전.
-- 선행: guild.sql · guild2.sql(_guild_reward · guild_claims) · pvp.sql(_pvp_snap · pvp_card_meta) · gem.sql · admin.sql
-- 시즌: 매달 셋째 수요일 ~ 일요일 (KST, 5일). 매일 09:00~23:00 전투, 하루 1경기 = 상대 5개 조직.
--   1일차: 세력(exp) 비슷한 조직끼리 · 2일차부터: 승점 가까운 조직끼리 (이미 붙은 상대는 피함). 홀수면 「동네 불량배파」(NPC) 와 붙음.
-- 명단 21칸: 1~5 방어조 · 6~10 돌격조 · 11~13 중간보스 · 14 보스 · 15~21 조직원. 보스(조직장)가 배치, 시즌 시작(셋째 수 09:00)에 잠김.
--   빈 칸 = 동네 불량배(NPC, HR 2 + R 3 · 남녀 섞임 · 조직 평균 등급에 맞춰 강해짐). 실제 조직원 10명 미만이면 참가 불가.
-- 덱: 방어 2 · 공격 2. 방어 덱은 시즌 시작 때 스냅샷으로 잠김 (2번 덱 = 목숨 하나 더). 공격 덱은 그날 처음 쓸 때 스냅샷.
-- 전투: 브라우저 js/war-core.js (서버 seed + 서버 스냅샷 + 현재 HP, 양쪽 자동). 쓰러진 카드는 그 경기 동안 빠지고, 살아남은 카드는 깎인 HP 그대로.
-- 순서: 상대 방어조 5곳을 모두 부숴야 나머지 공격 가능. 보스 아지트 파괴 = 즉시 승리(그 경기 공격 끝, 승점 반영은 23:00 정산). 아니면 23:00 에 점수 높은 쪽 승리.
-- 숫자는 전부 _war_numbers() 하나에 있음

-- 1) 테이블
create table if not exists public.war_decks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  def1 jsonb, def2 jsonb, atk1 jsonb, atk2 jsonb, updated_at timestamptz not null default now());$vr_statement$;
  execute $vr_statement$create table if not exists public.war_entries (
  season date not null, guild_id bigint not null references public.guilds(id) on delete cascade,
  status text not null default 'in' check (status in ('in', 'out')), locked boolean not null default false, scale numeric not null default 1,
  points int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0, boss_kills int not null default 0, score_total int not null default 0,
  entered_at timestamptz not null default now(), primary key (season, guild_id));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_roster (
  season date not null, guild_id bigint not null, slot int not null check (slot between 1 and 21), user_id uuid references auth.users(id) on delete set null,
  def_snap jsonb, primary key (season, guild_id, slot), foreign key (season, guild_id) references public.war_entries(season, guild_id) on delete cascade);$vr_statement$;
  execute $vr_statement$create unique index if not exists war_roster_user on public.war_roster (season, user_id) where user_id is not null;$vr_statement$;
  execute $vr_statement$create table if not exists public.war_matches (
  id bigint generated always as identity primary key, season date not null, day int not null check (day between 1 and 5),
  guild_a bigint not null, guild_b bigint, score_a int not null default 0, score_b int not null default 0,
  winner bigint, draw boolean not null default false, boss_kill boolean not null default false, ended_at timestamptz, settled boolean not null default false,
  unique (season, day, guild_a));$vr_statement$;
  execute $vr_statement$create index if not exists war_matches_b on public.war_matches (season, day, guild_b);$vr_statement$;
  execute $vr_statement$create table if not exists public.war_ajits (
  match_id bigint not null references public.war_matches(id) on delete cascade, side int not null check (side in (0, 1)), slot int not null,
  role text not null, user_id uuid, npc boolean not null default false, snaps jsonb not null default '[]'::jsonb,
  deck int not null default 1, state jsonb, destroyed_at timestamptz, destroyed_by uuid, locked_by uuid, locked_until timestamptz,
  primary key (match_id, side, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_atk_state (
  match_id bigint not null references public.war_matches(id) on delete cascade, user_id uuid not null, deck int not null check (deck in (1, 2)),
  snap jsonb not null, state jsonb, primary key (match_id, user_id, deck));$vr_statement$;
  execute $vr_statement$create table if not exists public.war_attacks (
  id bigint generated always as identity primary key, match_id bigint not null references public.war_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, side int not null, target_slot int not null, atk_deck int not null, def_deck int not null,
  seed bigint not null, atk_snap jsonb not null, def_snap jsonb not null, atk_buff jsonb not null, def_buff jsonb not null,
  before jsonb not null, reported jsonb, win boolean, points int not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);$vr_statement$;
  execute $vr_statement$create index if not exists war_attacks_user on public.war_attacks (user_id, match_id);$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['war_decks', 'war_entries', 'war_roster', 'war_matches', 'war_ajits', 'war_atk_state', 'war_attacks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 숫자 (여기만 고치면 됨)
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
  execute $vr_statement$create or replace function public._war_role(p_slot int) returns text language sql immutable as $$
  select case when p_slot <= 5 then 'def' when p_slot <= 10 then 'atk' when p_slot <= 13 then 'mid' when p_slot = 14 then 'boss' else 'etc' end $$;$vr_statement$;
  execute $vr_statement$-- 3) 시간 (KST)
create or replace function public._war_now() returns timestamptz language sql stable as $$ select now() $$;$vr_statement$;
  execute $vr_statement$-- 테스트에서 바꿔 끼움
create or replace function public._war_kst() returns timestamp language sql stable as $$ select _war_now() at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_third_wed(p_d date) returns date language sql immutable as $$
  select (date_trunc('month', p_d)::date + ((3 - extract(isodow from date_trunc('month', p_d))::int + 7) % 7) + 14) $$;$vr_statement$;
  execute $vr_statement$-- 지금 시즌 (진행 중 · 끝난 날 당일 · 아니면 다음 시즌)
create or replace function public._war_season() returns date language sql stable as $$
  select case when _war_kst()::date <= _war_third_wed(_war_kst()::date) + 4 then _war_third_wed(_war_kst()::date)
              else _war_third_wed((date_trunc('month', _war_kst()) + interval '1 month')::date) end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_at(p_season date, p_day int, p_hour int) returns timestamptz language sql immutable as $$
  select ((p_season + p_day - 1)::timestamp + make_interval(hours => p_hour)) at time zone 'Asia/Seoul' $$;$vr_statement$;
  execute $vr_statement$-- 오늘 몇 일차 (1~5, 아니면 null)
create or replace function public._war_day(p_season date) returns int language sql stable as $$
  select case when _war_kst()::date between p_season and p_season + 4 then (_war_kst()::date - p_season) + 1 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_phase(p_season date) returns text language sql stable as $$
  select case when _war_now() < _war_at(p_season, 1 - (_war_numbers()->>'signup_days_before')::int, 0) then 'soon'
              when _war_now() < _war_at(p_season, 1, (_war_numbers()->>'open_hour')::int) then 'signup'
              when _war_now() >= _war_at(p_season, 5, (_war_numbers()->>'close_hour')::int) then 'ended'
              when extract(hour from _war_kst()) >= (_war_numbers()->>'open_hour')::int and extract(hour from _war_kst()) < (_war_numbers()->>'close_hour')::int then 'live'
              else 'rest' end $$;$vr_statement$;
  execute $vr_statement$-- 4) 동네 불량배 (NPC): HR 2 + R 3, 남녀 섞임, seed 로 고정
create or replace function public._war_npc_deck(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $$
declare hr text[] := array['10151','10152','10163','10164','10165','10166','10167','10168'];
        r text[] := array['10148','10149','10150','10159','10160','10161','10162'];
        male text[] := array['10148','10149','10150','10151','10152'];   -- 성별은 ID 첫 자리가 아니라 카드 데이터(gender)로 (ID 변경 후에도 맞게)
        a text[]; b text[]; ids text[]; alt text; out jsonb := '[]'::jsonb; i int;
begin
  select array_agg(x order by md5(p_seed || ':h:' || x)) into a from unnest(hr) x;
  select array_agg(x order by md5(p_seed || ':r:' || x)) into b from unnest(r) x;
  ids := a[1:2] || b[1:3];
  if (select count(distinct (x = any(male))) from unnest(ids) x) < 2 then
    select x into alt from unnest(b[4:7]) x where (x = any(male)) <> (ids[1] = any(male)) limit 1;
    ids[5] := alt;
  end if;
  for i in 1..5 loop out := out || jsonb_build_object('uid', 'n' || i, 'id', ids[i], 'level', (_war_numbers()->>'npc_level')::int, 'scale', p_scale); end loop;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$-- 동네 불량배 = 고정 약체 (레벨 10 · 배율 1, 조직 덱과 무관)
create or replace function public._war_scale(p_season date, p_gid bigint) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((_war_numbers()->>'npc_scale')::numeric, 1) $$;$vr_statement$;
  execute $vr_statement$-- 5) 진행 (모든 공개 RPC 가 먼저 부름): 시즌 잠금 · 매일 대진 · 23시 정산
create or replace function public._war_lock(p_season date) returns void language plpgsql security definer set search_path = public as $$
declare e record; u record; s int; n int; sc numeric;
begin
  for e in select * from war_entries where season = p_season and not locked loop
    -- 배치 안 된 조직원 → 빈 칸
    for u in select gm.user_id from guild_members gm where gm.guild_id = e.guild_id
               and not exists (select 1 from war_roster r where r.season = p_season and r.user_id = gm.user_id) order by gm.joined_at loop
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
  execute $vr_statement$-- 한 쪽 아지트 21곳 만들기
create or replace function public._war_build_side(p_mid bigint, p_side int, p_season date, p_gid bigint, p_scale numeric) returns void language plpgsql security definer set search_path = public as $$
declare i int; r war_roster; sn jsonb;
begin
  for i in 1..21 loop
    r := null;
    if p_gid is not null then select * into r from war_roster where season = p_season and guild_id = p_gid and slot = i; end if;
    sn := case when r.def_snap is not null and jsonb_array_length(coalesce(r.def_snap->0, '[]'::jsonb)) > 0 then r.def_snap
               else jsonb_build_array(_war_npc_deck(p_mid || ':' || p_side || ':' || i || ':1', p_scale), _war_npc_deck(p_mid || ':' || p_side || ':' || i || ':2', p_scale)) end;
    insert into war_ajits (match_id, side, slot, role, user_id, npc, snaps) values (p_mid, p_side, i, _war_role(i), r.user_id, r.def_snap is null or jsonb_array_length(coalesce(r.def_snap->0, '[]'::jsonb)) = 0, sn)
      on conflict do nothing;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_pair(p_season date, p_day int) returns void language plpgsql security definer set search_path = public as $$
declare ids bigint[]; used bigint[] := '{}'; a bigint; b bigint; mid bigint; i int; j int; sa numeric; sb numeric;
begin
  if exists (select 1 from war_matches where season = p_season and day = p_day) then return; end if;
  if p_day = 1 then
    select array_agg(e.guild_id order by g.exp desc, g.level desc, e.guild_id) into ids from war_entries e join guilds g on g.id = e.guild_id where e.season = p_season and e.status = 'in';
  else
    select array_agg(e.guild_id order by e.points desc, e.score_total desc, e.guild_id) into ids from war_entries e where e.season = p_season and e.status = 'in';
  end if;
  if ids is null then return; end if;
  for i in 1..array_length(ids, 1) loop
    a := ids[i]; if a = any(used) then continue; end if;
    b := null;
    for j in i + 1..array_length(ids, 1) loop   -- 가장 가까운, 아직 안 붙은 상대
      continue when ids[j] = any(used);
      if not exists (select 1 from war_matches m where m.season = p_season and ((m.guild_a = a and m.guild_b = ids[j]) or (m.guild_a = ids[j] and m.guild_b = a))) then b := ids[j]; exit; end if;
    end loop;
    if b is null then select x into b from unnest(ids[i + 1:]) x where not x = any(used) limit 1; end if;   -- 다 붙었으면 가장 가까운 조직
    used := used || a || coalesce(b, a);
    insert into war_matches (season, day, guild_a, guild_b) values (p_season, p_day, a, b) returning id into mid;
    select scale into sa from war_entries where season = p_season and guild_id = a;
    select scale into sb from war_entries where season = p_season and guild_id = b;
    perform _war_build_side(mid, 0, p_season, a, sa);
    perform _war_build_side(mid, 1, p_season, b, coalesce(sb, sa));   -- NPC 조직 = 상대 배율
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_settle(p_mid bigint) returns void language plpgsql security definer set search_path = public as $$
declare m war_matches; N jsonb := _war_numbers(); win bigint; dr boolean := false; side int;
begin
  select * into m from war_matches where id = p_mid for update;
  if m.settled then return; end if;
  if m.winner is null then
    if m.score_a > m.score_b then win := m.guild_a; elsif m.score_b > m.score_a then win := coalesce(m.guild_b, -1); else dr := true; end if;
  else win := m.winner; end if;
  update war_matches set winner = win, draw = dr, settled = true, ended_at = coalesce(ended_at, _war_now()) where id = p_mid;
  for side in 0..1 loop
    continue when (case side when 0 then m.guild_a else m.guild_b end) is null;
    update war_entries e set
      points = points + case when dr then (N->'standings'->>'draw')::int when win = e.guild_id then (N->'standings'->>'win')::int + case when m.boss_kill then (N->'standings'->>'boss_bonus')::int else 0 end else (N->'standings'->>'loss')::int end,
      wins = wins + (not dr and win = e.guild_id)::int, draws = draws + dr::int, losses = losses + (not dr and win is distinct from e.guild_id)::int,
      boss_kills = boss_kills + (m.boss_kill and win = e.guild_id)::int, score_total = score_total + case side when 0 then m.score_a else m.score_b end
      where season = m.season and guild_id = case side when 0 then m.guild_a else m.guild_b end;
  end loop;
  if win > 0 then perform _guild_exp(win, null, (N->>'match_exp_win')::int, 'war_win', 'war:' || p_mid); end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_tick() returns date language plpgsql security definer set search_path = public as $$
declare s date := _war_season(); d int; m record;
begin
  if _war_now() < _war_at(s, 1, (_war_numbers()->>'open_hour')::int) then return s; end if;
  perform pg_advisory_xact_lock(hashtext('war:' || s));
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
  execute $vr_statement$revoke all on function public._war_npc_deck(text, numeric), public._war_scale(date, bigint), public._war_lock(date), public._war_build_side(bigint, int, date, bigint, numeric),
  public._war_pair(date, int), public._war_settle(bigint), public._war_tick() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 6) 공개 RPC
-- 덱 설정: p_kind = def1 | def2 | atk1 | atk2, p_uids = 카드 uid 1~5장 ([] = 비움). 방어 덱은 시즌 잠금 뒤 못 바꿈(다음 시즌부터 적용)
create or replace function public.war_set_deck(p_kind text, p_uids jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); sn jsonb := null; other jsonb; s date;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_kind not in ('def1', 'def2', 'atk1', 'atk2') then raise exception 'bad deck'; end if;
  s := _war_tick();
  if p_kind like 'def%' and _war_phase(s) not in ('soon', 'signup', 'ended') and exists (select 1 from war_roster where season = s and user_id = uid) then raise exception 'defense locked'; end if;
  if jsonb_array_length(coalesce(p_uids, '[]'::jsonb)) > 0 then sn := _pvp_snap(uid, p_uids, 'open')->'cards'; end if;
  insert into war_decks (user_id) values (uid) on conflict do nothing;
  select case p_kind when 'def1' then def2 when 'def2' then def1 when 'atk1' then atk2 else atk1 end into other from war_decks where user_id = uid;
  if sn is not null and other is not null and exists (select 1 from jsonb_array_elements(sn) a, jsonb_array_elements(other) b where a->>'id' = b->>'id') then raise exception 'same card in both decks'; end if;
  execute format('update war_decks set %I = $1, updated_at = now() where user_id = $2', p_kind) using sn, uid;
  return jsonb_build_object('ok', true, 'decks', (select to_jsonb(d) - 'user_id' from war_decks d where user_id = uid));
end $$;$vr_statement$;
  execute $vr_statement$-- 참가 (보스·간부, 신청 기간)
create or replace function public.war_enter() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick();
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  if m.role not in ('boss', 'officer') then raise exception 'not allowed'; end if;
  if _war_phase(s) <> 'signup' then raise exception 'signup closed'; end if;
  if (select count(*) from guild_members where guild_id = m.guild_id) < (_war_numbers()->>'min_members')::int then raise exception 'need members'; end if;
  insert into war_entries (season, guild_id) values (s, m.guild_id) on conflict do nothing;
  return war_status();
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.war_withdraw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick();
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if _war_phase(s) <> 'signup' then raise exception 'signup closed'; end if;
  delete from war_entries where season = s and guild_id = m.guild_id;
  return war_status();
end $$;$vr_statement$;
  execute $vr_statement$-- 배치 (보스만, 신청 기간): p_user = null 이면 그 칸 비움. 같은 사람을 다른 칸에 두면 옮겨짐
create or replace function public.war_set_slot(p_slot int, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick();
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if _war_phase(s) <> 'signup' then raise exception 'signup closed'; end if;
  if not exists (select 1 from war_entries where season = s and guild_id = m.guild_id) then raise exception 'not entered'; end if;
  if p_slot not between 1 and 21 then raise exception 'bad slot'; end if;
  if p_user is not null and not exists (select 1 from guild_members where user_id = p_user and guild_id = m.guild_id) then raise exception 'not member'; end if;
  if p_user is not null then delete from war_roster where season = s and guild_id = m.guild_id and user_id = p_user; end if;
  insert into war_roster (season, guild_id, slot, user_id) values (s, m.guild_id, p_slot, p_user) on conflict (season, guild_id, slot) do update set user_id = excluded.user_id;
  return war_status();
end $$;$vr_statement$;
  execute $vr_statement$-- 아지트 목록 (한 쪽)
create or replace function public._war_side_json(p_mid bigint, p_side int) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', a.slot, 'role', a.role, 'npc', a.npc, 'user_id', a.user_id,
      'name', case when a.npc and a.user_id is null then '동네 불량배' else coalesce(p.nickname, '조직원') end, 'deck', a.deck, 'decks', jsonb_array_length(a.snaps) - (case when jsonb_array_length(coalesce(a.snaps->1, '[]'::jsonb)) = 0 then 1 else 0 end),
      'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', c->'level', 'scale', c->'scale', 'hp', a.state->(c->>'uid'))), '[]'::jsonb) from jsonb_array_elements(a.snaps->(a.deck - 1)) c),
      'destroyed', a.destroyed_at is not null, 'locked', a.locked_until > _war_now()) order by a.slot), '[]'::jsonb)
  from war_ajits a left join profiles p on p.id = a.user_id where a.match_id = p_mid and a.side = p_side $$;$vr_statement$;
  execute $vr_statement$-- 상태
create or replace function public.war_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date; e war_entries; mt war_matches; my int; d int; res jsonb; me_slot int; used int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_tick(); d := _war_day(s); m := _guild_me(uid);
  res := jsonb_build_object('ok', true, 'season', s, 'season_end', s + 4, 'phase', _war_phase(s), 'day', d,
    'opens_at', _war_at(s, coalesce(d, 1) + case when d is not null and _war_now() >= _war_at(s, d, (_war_numbers()->>'close_hour')::int) then 1 else 0 end, (_war_numbers()->>'open_hour')::int),
    'closes_at', case when d is not null then _war_at(s, d, (_war_numbers()->>'close_hour')::int) end,
    'numbers', _war_numbers() - 'npc_scale' - 'layout',
    'decks', (select to_jsonb(x) - 'user_id' from war_decks x where user_id = uid),
    'standings', (select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'guild_id', guild_id, 'name', name, 'emblem', emblem, 'points', points, 'wins', wins, 'draws', draws, 'losses', losses, 'boss_kills', boss_kills, 'score', score_total, 'me', guild_id = m.guild_id) order by rk), '[]'::jsonb)
                  from (select e2.*, g.name, g.emblem, row_number() over (order by e2.points desc, e2.boss_kills desc, e2.score_total desc, e2.guild_id) rk from war_entries e2 join guilds g on g.id = e2.guild_id where e2.season = s and e2.status = 'in') t where rk <= 30 or guild_id = m.guild_id),
    'claimable', war_claimable());
  if m.user_id is null then return res || jsonb_build_object('guild', null); end if;
  select * into e from war_entries where season = s and guild_id = m.guild_id;
  res := res || jsonb_build_object('guild', jsonb_build_object('id', m.guild_id, 'role', m.role, 'members', (select count(*) from guild_members where guild_id = m.guild_id)),
    'entry', to_jsonb(e) - 'season',
    'roster', (select coalesce(jsonb_agg(jsonb_build_object('slot', x, 'role', _war_role(x), 'user_id', r.user_id, 'name', p.nickname,
                 'ready', (select dd.def1 is not null from war_decks dd where dd.user_id = r.user_id)) order by x), '[]'::jsonb)
               from generate_series(1, 21) x left join war_roster r on r.season = s and r.guild_id = m.guild_id and r.slot = x left join profiles p on p.id = r.user_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', gm.user_id, 'name', coalesce(p.nickname, '조직원'), 'role', gm.role,
                  'ready', (select dd.def1 is not null from war_decks dd where dd.user_id = gm.user_id))), '[]'::jsonb) from guild_members gm left join profiles p on p.id = gm.user_id where gm.guild_id = m.guild_id));
  if d is null then return res; end if;
  select * into mt from war_matches where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id);
  if mt.id is null then return res; end if;
  my := case when mt.guild_a = m.guild_id then 0 else 1 end;
  select slot into me_slot from war_ajits where match_id = mt.id and side = my and user_id = uid;
  select count(*) into used from war_attacks where match_id = mt.id and user_id = uid;
  return res || jsonb_build_object('match', jsonb_build_object('id', mt.id, 'day', mt.day, 'side', my,
    'opponent', case when (case my when 0 then mt.guild_b else mt.guild_a end) is null then jsonb_build_object('name', '동네 불량배파', 'npc', true, 'emblem', 0)
                else (select jsonb_build_object('id', g.id, 'name', g.name, 'emblem', g.emblem, 'level', g.level, 'npc', false) from guilds g where g.id = case my when 0 then mt.guild_b else mt.guild_a end) end,
    'score_me', case my when 0 then mt.score_a else mt.score_b end, 'score_opp', case my when 0 then mt.score_b else mt.score_a end,
    'ended', mt.ended_at is not null or mt.settled, 'winner_me', mt.winner = m.guild_id, 'draw', mt.draw, 'boss_kill', mt.boss_kill,
    'gate_open', not exists (select 1 from war_ajits where match_id = mt.id and side = 1 - my and role = 'def' and destroyed_at is null),
    'me', jsonb_build_object('slot', me_slot, 'alive', me_slot is not null and exists (select 1 from war_ajits where match_id = mt.id and side = my and slot = me_slot and destroyed_at is null),
      'attacks_left', greatest(0, (_war_numbers()->>'attacks_per_day')::int - used),
      'atk', (select coalesce(jsonb_object_agg(deck, jsonb_build_object('alive', (select count(*) from jsonb_array_elements(snap) c where coalesce((state->>(c->>'uid'))::int, 1) > 0))), '{}'::jsonb) from war_atk_state where match_id = mt.id and user_id = uid)),
    'mine', _war_side_json(mt.id, my), 'enemy', _war_side_json(mt.id, 1 - my)));
end $$;$vr_statement$;
  execute $vr_statement$-- 공격 시작
create or replace function public.war_start(p_slot int, p_deck int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date; d int; N jsonb := _war_numbers(); m guild_members; mt war_matches; my int; me war_ajits; t war_ajits; st war_atk_state; snap jsonb;
        atk jsonb; def jsonb; seed bigint; aid bigint; ab jsonb; db jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  s := _war_tick(); d := _war_day(s);
  if _war_phase(s) <> 'live' then raise exception 'not battle time'; end if;
  m := _guild_me(uid);
  select * into mt from war_matches where season = s and day = d and (guild_a = m.guild_id or guild_b = m.guild_id) for update;
  if mt.id is null then raise exception 'no match'; end if;
  if mt.ended_at is not null then raise exception 'match ended'; end if;
  my := case when mt.guild_a = m.guild_id then 0 else 1 end;
  select * into me from war_ajits where match_id = mt.id and side = my and user_id = uid;
  if me.slot is null then raise exception 'not in roster'; end if;
  if me.destroyed_at is not null then raise exception 'ajit destroyed'; end if;
  perform pg_advisory_xact_lock(hashtext('waratk:' || uid));
  update war_attacks set finished_at = now(), win = false where user_id = uid and finished_at is null;   -- 끝내지 않은 판 = 패배(변화 없음)
  update war_ajits set locked_by = null, locked_until = null where locked_by = uid;
  if (select count(*) from war_attacks where match_id = mt.id and user_id = uid) >= (N->>'attacks_per_day')::int then raise exception 'no attacks'; end if;
  select * into t from war_ajits where match_id = mt.id and side = 1 - my and slot = p_slot for update;
  if t.slot is null then raise exception 'bad target'; end if;
  if t.destroyed_at is not null then raise exception 'already destroyed'; end if;
  if t.locked_until > _war_now() then raise exception 'target busy'; end if;
  if t.role <> 'def' and exists (select 1 from war_ajits where match_id = mt.id and side = 1 - my and role = 'def' and destroyed_at is null) then raise exception 'defense first'; end if;
  if p_deck not in (1, 2) then raise exception 'bad deck'; end if;
  select * into st from war_atk_state where match_id = mt.id and user_id = uid and deck = p_deck;
  if st.match_id is null then
    select case p_deck when 1 then atk1 else atk2 end into snap from war_decks where user_id = uid;
    if snap is null or jsonb_array_length(snap) = 0 then raise exception 'no attack deck'; end if;
    insert into war_atk_state (match_id, user_id, deck, snap) values (mt.id, uid, p_deck, snap) returning * into st;
  end if;
  select coalesce(jsonb_agg(c || jsonb_build_object('hp', st.state->(c->>'uid'))), '[]'::jsonb) into atk from jsonb_array_elements(st.snap) c where coalesce((st.state->>(c->>'uid'))::int, 1) > 0;
  if jsonb_array_length(atk) = 0 then raise exception 'deck dead'; end if;
  select coalesce(jsonb_agg(c || jsonb_build_object('hp', t.state->(c->>'uid'))), '[]'::jsonb) into def from jsonb_array_elements(t.snaps->(t.deck - 1)) c where coalesce((t.state->>(c->>'uid'))::int, 1) > 0;
  ab := jsonb_build_object('atk', (N->'roles'->me.role->>'atk')::numeric, 'def', case when me.role in ('mid', 'boss') then (N->'roles'->me.role->>'def')::numeric else 1 end);   -- 공격 측
  db := jsonb_build_object('atk', case when t.role in ('mid', 'boss') then (N->'roles'->t.role->>'atk')::numeric else 1 end, 'def', (N->'roles'->t.role->>'def')::numeric);   -- 방어 측
  seed := floor(random() * 2147483647)::bigint;
  update war_ajits set locked_by = uid, locked_until = _war_now() + make_interval(mins => (N->>'lock_minutes')::int) where match_id = mt.id and side = t.side and slot = t.slot;
  insert into war_attacks (match_id, user_id, side, target_slot, atk_deck, def_deck, seed, atk_snap, def_snap, atk_buff, def_buff, before)
    values (mt.id, uid, my, p_slot, p_deck, t.deck, seed, atk, def, ab, db, jsonb_build_object('atk_state', st.state, 'def_state', t.state, 'def_deck', t.deck))
    returning id into aid;
  return jsonb_build_object('ok', true, 'id', aid, 'seed', seed, 'atk', atk, 'def', def, 'atk_buff', ab, 'def_buff', db, 'target', jsonb_build_object('slot', t.slot, 'role', t.role, 'deck', t.deck, 'npc', t.npc));
end $$;$vr_statement$;
  execute $vr_statement$-- 공격 끝: p_atk_hp / p_def_hp = { 카드 uid: 남은 HP } (살아남은 카드만). 서버는 이전 HP 를 넘지 않게 자름
create or replace function public.war_finish(p_id bigint, p_win boolean, p_atk_hp jsonb, p_def_hp jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a war_attacks; N jsonb := _war_numbers(); mt war_matches; t war_ajits; cap int := (_war_numbers()->>'hp_cap')::int;
        ast jsonb := '{}'::jsonb; dst jsonb := '{}'::jsonb; c jsonb; hp int; iswin boolean; pts int := 0; flag boolean := false; next_ok boolean;
begin
  select * into a from war_attacks where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.finished_at is not null then raise exception 'already finished'; end if;
  if now() - a.started_at < make_interval(secs => (N->>'min_secs')::int) then raise exception 'too fast'; end if;
  select * into mt from war_matches where id = a.match_id for update;
  select * into t from war_ajits where match_id = a.match_id and side = 1 - a.side and slot = a.target_slot for update;
  if now() - a.started_at > make_interval(mins => (N->>'open_minutes')::int) or t.destroyed_at is not null or t.deck <> a.def_deck or mt.settled then
    update war_attacks set finished_at = now(), win = false where id = a.id;
    update war_ajits set locked_by = null, locked_until = null where match_id = t.match_id and side = t.side and slot = t.slot and locked_by = uid;
    return war_status() || jsonb_build_object('result', jsonb_build_object('win', false, 'expired', true));
  end if;
  -- 남은 HP (이전보다 클 수 없음, 없으면 쓰러짐)
  for c in select * from jsonb_array_elements(a.atk_snap) loop
    hp := greatest(0, least(coalesce((p_atk_hp->>(c->>'uid'))::int, 0), coalesce((c->>'hp')::int, cap)));
    if coalesce((p_atk_hp->>(c->>'uid'))::int, 0) > coalesce((c->>'hp')::int, cap) then flag := true; end if;
    ast := ast || jsonb_build_object(c->>'uid', hp);
  end loop;
  for c in select * from jsonb_array_elements(a.def_snap) loop
    hp := case when p_win then 0 else greatest(0, least(coalesce((p_def_hp->>(c->>'uid'))::int, 0), coalesce((c->>'hp')::int, cap))) end;
    dst := dst || jsonb_build_object(c->>'uid', hp);
  end loop;
  iswin := p_win or not exists (select 1 from jsonb_each_text(dst) x where x.value::int > 0);
  if not exists (select 1 from jsonb_each_text(ast) x where x.value::int > 0) and iswin then flag := true; end if;   -- 둘 다 전멸 = 의심
  update war_atk_state set state = coalesce(state, '{}'::jsonb) || ast where match_id = a.match_id and user_id = uid and deck = a.atk_deck;
  if iswin then
    next_ok := t.deck = 1 and jsonb_array_length(coalesce(t.snaps->1, '[]'::jsonb)) > 0;
    if next_ok then
      update war_ajits set deck = 2, state = null where match_id = t.match_id and side = t.side and slot = t.slot;   -- 2번 덱 등장
    else
      pts := (N->'points'->>t.role)::int;
      update war_ajits set destroyed_at = now(), destroyed_by = uid, state = dst where match_id = t.match_id and side = t.side and slot = t.slot;
      update war_matches set score_a = score_a + case a.side when 0 then pts else 0 end, score_b = score_b + case a.side when 1 then pts else 0 end where id = mt.id;
      if t.role = 'boss' then
        update war_matches set boss_kill = true, winner = coalesce(case a.side when 0 then mt.guild_a else mt.guild_b end, -1), ended_at = now() where id = mt.id;
      end if;
    end if;
  else
    update war_ajits set state = coalesce(state, '{}'::jsonb) || dst where match_id = t.match_id and side = t.side and slot = t.slot;
  end if;
  update war_ajits set locked_by = null, locked_until = null where match_id = t.match_id and side = t.side and slot = t.slot;
  update war_attacks set finished_at = now(), win = iswin, points = pts, flagged = flag, reported = jsonb_build_object('win', p_win, 'atk', p_atk_hp, 'def', p_def_hp) where id = a.id;
  return war_status() || jsonb_build_object('result', jsonb_build_object('win', iswin, 'points', pts, 'next_deck', iswin and next_ok, 'destroyed', iswin and not next_ok, 'boss_kill', t.role = 'boss' and iswin and not next_ok));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._war_sum(a jsonb, b jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, coalesce((a->>k)::int, 0) + coalesce((b->>k)::int, 0)), '{}'::jsonb) from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) x $$;$vr_statement$;
  execute $vr_statement$-- 받을 보상 (경기 승리 · 시즌 순위) 수
create or replace function public._war_pending(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r record; N jsonb := _war_numbers(); rk int;
begin
  for r in select mt.*, wr.guild_id gid from war_roster wr join war_matches mt on mt.season = wr.season and (mt.guild_a = wr.guild_id or mt.guild_b = wr.guild_id)
            where wr.user_id = p_uid and mt.settled and wr.season >= _war_season() - 62 loop
    continue when exists (select 1 from guild_claims where user_id = p_uid and ref = 'warm:' || r.id);
    out := out || jsonb_build_object('ref', 'warm:' || r.id, 'gid', r.gid, 'reward', case when r.draw then N->'match_draw' when r.winner is distinct from r.gid then N->'match_loss' else (N->'match_win') ||
      case when r.boss_kill then _war_sum(N->'match_win', N->'match_boss_kill') else '{}'::jsonb end end);
  end loop;
  for r in select wr.season, wr.guild_id from war_roster wr join war_entries e on e.season = wr.season and e.guild_id = wr.guild_id and e.status = 'in'
            where wr.user_id = p_uid and wr.season >= _war_season() - 62 and _war_now() >= _war_at(wr.season, 5, (N->>'close_hour')::int) loop
    continue when exists (select 1 from guild_claims where user_id = p_uid and ref = 'wars:' || r.season);
    select x.rk into rk from (select guild_id, row_number() over (order by points desc, boss_kills desc, score_total desc, guild_id) rk from war_entries where season = r.season and status = 'in') x where x.guild_id = r.guild_id;
    out := out || jsonb_build_object('ref', 'wars:' || r.season, 'gid', r.guild_id, 'rank', rk, 'reward', _war_sum(N->'season_member',
      coalesce((select q->'reward' from jsonb_array_elements(N->'season_rank') q where rk between (q->>'from')::int and (q->>'to')::int), '{}'::jsonb)));
  end loop;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.war_claimable() returns int language sql stable security definer set search_path = public as $$ select jsonb_array_length(_war_pending(auth.uid())) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.war_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p jsonb; x jsonb; got jsonb := '{}'::jsonb; k text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _war_tick();
  p := _war_pending(uid);
  if jsonb_array_length(p) = 0 then raise exception 'nothing to claim'; end if;
  for x in select * from jsonb_array_elements(p) loop
    perform _guild_reward(uid, (x->>'gid')::bigint, x->'reward', 'war_reward', x->>'ref');
    for k in select jsonb_object_keys(x->'reward') loop got := jsonb_set(got, array[k], to_jsonb(coalesce((got->>k)::int, 0) + (x->'reward'->>k)::int)); end loop;
    if x ? 'rank' then got := got || jsonb_build_object('rank', x->'rank'); end if;
  end loop;
  return war_status() || jsonb_build_object('got', got);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._war_side_json(bigint, int), public._war_pending(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_set_deck(text, jsonb), public.war_enter(), public.war_withdraw(), public.war_set_slot(int, uuid), public.war_status(), public.war_start(int, int),
  public.war_finish(bigint, boolean, jsonb, jsonb), public.war_claimable(), public.war_claim() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_set_deck(text, jsonb), public.war_enter(), public.war_withdraw(), public.war_set_slot(int, uuid), public.war_status(), public.war_start(int, int),
  public.war_finish(bigint, boolean, jsonb, jsonb), public.war_claimable(), public.war_claim() to authenticated;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (4, 'd58808b88d2b2323a18856d9663da6bec0c35ea9b3485319d62a3c189dd7aa8e', '5815c51c3b4078dd7ba66c2a6bdb4725a00f5a07ebae8fd729b093fbbf02ab3e', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '04_install.sql: 완료 또는 이미 완료 (4/10)' as result;
