-- =====================================================================
-- 관리자: 계정 초기화 (admin_reset_account) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: admin.sql (_admin_guard · admin_log) 및 게임 테이블 SQL 들. 없는 테이블은 건너뜀
-- 동작: 대상 유저의 게임 데이터를 새 계정 상태로 되돌림. 로그인(auth.users)·닉네임(profiles)은 유지
--   유료 재화는 기본 유지: player_wallet.gem_paid(유료 심연석) · player_items.tradable(유료 심연석으로 산 드링크)
--   거래소: 대상이 올린 열린 글은 취소(판매자·제안자 모두 원래대로 반환), 대상의 대기 제안은 환불 → 그 뒤 초기화
--   조직: 조직원이면 탈퇴 처리. 보스면 조직원이 남아 있으면 승계자(간부 우선 → 충성 순)에게 보스 이전, 혼자면 조직 해산
-- 한 트랜잭션(함수 1회 호출)으로 실행. 실패하면 전부 되돌아감. admin_log 에 기록 (meta 에 표별 삭제 수)
-- 호출: select public.admin_reset_account('<uuid>', '<닉네임 그대로>', '사유');
-- =====================================================================

alter table public.admin_log add column if not exists meta jsonb;

create or replace function public.admin_reset_account(p_user uuid, p_confirm text, p_reason text, p_keep_paid boolean default true)
returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare
  nick text; em text; n bigint; s jsonb := '{}'::jsonb; lid bigint; oid bigint; m guild_members; heir uuid; gp bigint := 0; dt int := 0;
  t text;
  wipe text[] := array[
    'story_progress', 'story_gacha', 'story_gacha_log', 'saves', 'matches', 'gallery',
    'player_state', 'player_gear', 'player_gear_meta', 'player_sigils', 'player_mail', 'sigil_daily', 'gear_drop_log',
    'quest_progress', 'tower_progress', 'gem_login',
    'pvp_decks', 'pvp_ratings', 'pvp_attempts', 'pvp_reward_claims', 'pvp_bonus_tries', 'pvp_tier_claims', 'pvp_titles', 'pvp_shop_log',
    'guild_requests', 'guild_cooldowns', 'guild_attendance', 'guild_claims', 'guild_daily_quests', 'guild_titles',
    'loyalty_wallet', 'loyalty_ledger', 'war_decks', 'war_signups', 'war_atk_state'];
begin
  perform public._admin_guard();
  select u.email::text, p.nickname into em, nick from auth.users u left join public.profiles p on p.id = u.id where u.id = p_user;
  if em is null then raise exception 'no such user'; end if;
  if p_user = auth.uid() then raise exception 'cannot reset self'; end if;
  if coalesce(btrim(p_confirm), '') = '' or btrim(p_confirm) <> coalesce(nick, em) then raise exception 'confirm mismatch'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  perform pg_advisory_xact_lock(hashtext('admin_reset:' || p_user));

  -- 1) 거래소 정리 (반환·환불이 먼저 일어나야 상대방 물건이 안전)
  if to_regclass('public.trade_listings') is not null then
    n := 0;
    for lid in select id from trade_listings where seller = p_user and status = 'open' order by id loop
      perform _trade_close_listing(lid, 'cancelled'); n := n + 1;
    end loop;
    s := s || jsonb_build_object('trade_listings_cancelled', n);
    n := 0;
    for oid in select id from trade_offers where offerer = p_user and status = 'pending' order by id loop
      if _trade_refund_offer(oid, 'cancelled') then n := n + 1; end if;
    end loop;
    s := s || jsonb_build_object('trade_offers_refunded', n);
  end if;

  -- 2) 조직
  if to_regclass('public.guild_members') is not null then
    select * into m from guild_members where user_id = p_user;
    if m.user_id is not null then
      perform _guild_lock(m.guild_id);
      if m.role = 'boss' then
        select user_id into heir from guild_members where guild_id = m.guild_id and user_id <> p_user
          order by (role = 'officer') desc, case when role = 'officer' then extract(epoch from joined_at) else -loyalty_total end, joined_at limit 1;
        if heir is null then
          perform _guild_log(m.guild_id, p_user, 'disband', null, jsonb_build_object('by', 'admin_reset'));
          delete from guilds where id = m.guild_id;
          s := s || jsonb_build_object('guild', 'disbanded', 'guild_id', m.guild_id);
        else
          update guild_members set role = 'boss' where user_id = heir;
          update guilds set boss = heir where id = m.guild_id;
          delete from guild_members where user_id = p_user;
          perform _guild_log(m.guild_id, p_user, 'transfer', heir, jsonb_build_object('by', 'admin_reset'));
          s := s || jsonb_build_object('guild', 'boss_transferred', 'guild_id', m.guild_id, 'heir', heir);
        end if;
      else
        delete from guild_members where user_id = p_user;
        perform _guild_log(m.guild_id, p_user, 'leave', p_user, jsonb_build_object('by', 'admin_reset'));
        s := s || jsonb_build_object('guild', 'left', 'guild_id', m.guild_id);
      end if;
    end if;
  end if;
  if to_regclass('public.war_roster') is not null then
    update war_roster set user_id = null, def_snap = null where user_id = p_user; get diagnostics n = row_count;
    s := s || jsonb_build_object('war_roster_cleared', n);
  end if;

  -- 3) 지갑: 유료 심연석만 남김
  if to_regclass('public.player_wallet') is not null then
    select coalesce(gem_paid, 0) into gp from player_wallet where user_id = p_user;
    gp := case when p_keep_paid then coalesce(gp, 0) else 0 end;
    delete from player_wallet where user_id = p_user;
    if gp > 0 then insert into player_wallet (user_id, gem_paid) values (p_user, gp); end if;
    s := s || jsonb_build_object('gem_paid_kept', gp);
  end if;
  if to_regclass('public.gem_ledger') is not null then
    -- 무료 보상 기록(ref 고유)을 지워야 챕터·로그인 보상을 다시 받을 수 있음. 결제 기록(d_paid<>0)은 유지
    delete from gem_ledger where user_id = p_user and (d_paid = 0 or not p_keep_paid); get diagnostics n = row_count;
    s := s || jsonb_build_object('gem_ledger', n);
    if gp > 0 then insert into gem_ledger (user_id, d_free, d_paid, free_after, paid_after, reason, ref, meta)
      values (p_user, 0, 0, 0, gp, 'admin_reset', 'admin_reset:' || gen_random_uuid(), jsonb_build_object('reason', p_reason)); end if;
  end if;
  -- 드링크: 유료분(tradable)만 남김 (거래 묶임 해제 — 위에서 거래는 이미 정리됨)
  if to_regclass('public.player_items') is not null then
    select coalesce(tradable, 0) into dt from player_items where user_id = p_user and item = 'drink';
    dt := case when p_keep_paid then coalesce(dt, 0) else 0 end;
    delete from player_items where user_id = p_user;
    delete from item_log where user_id = p_user and (d_tradable = 0 or not p_keep_paid);
    if dt > 0 then
      insert into player_items (user_id, item, tradable, bound, locked) values (p_user, 'drink', dt, 0, 0);
      insert into item_log (user_id, item, d_tradable, d_bound, tradable_after, bound_after, reason, meta)
        values (p_user, 'drink', 0, 0, dt, 0, 'admin_reset', jsonb_build_object('reason', p_reason));
    end if;
    s := s || jsonb_build_object('drink_paid_kept', dt);
  end if;

  -- 4) 나머지 게임 데이터 삭제
  foreach t in array wipe loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I where user_id = $1', t) using p_user; get diagnostics n = row_count;
      if n > 0 then s := s || jsonb_build_object(t, n); end if;
    end if;
  end loop;

  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, meta)
  values (auth.uid(), coalesce(auth.jwt()->>'email', ''), 'reset_account', p_user, null, left(p_reason, 200), s);
  return jsonb_build_object('ok', true, 'nickname', coalesce(nick, em), 'summary', s);
end $$;
revoke all on function public.admin_reset_account(uuid, text, text, boolean) from public, anon;
grant execute on function public.admin_reset_account(uuid, text, text, boolean) to authenticated;
