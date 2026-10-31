-- =====================================================================
-- ⚔️ 친구 대전 (2단계) — 여러 번 실행해도 안전, 삭제 없음
-- 선행: friends.sql(friendships, _is_friend) · pvp.sql(pvp_decks, _pvp_snap, _pvp_day) · manual_battle.sql(_battle_acts_ok)
-- 방식: 기존 PvP 와 같은 비동기. 상대 = 친구의 PvP 방어 덱(무제한 리그) 스냅샷, 서버 seed 발급
-- 레이팅·랭킹·보상 없음. 하루 20회(KST). 결과 + seed + 양쪽 스냅샷 + 수동 행동 기록 저장 → 3단계 리플레이 공유가 이 행(id)을 참조
-- 공개 RPC: friend_battle_start(p_friend uuid, p_mode text) · friend_battle_report(p_id bigint, p_wins int, p_losses int, p_actions jsonb)
--           friend_battle_history(p_friend uuid default null)
-- =====================================================================

create table if not exists public.friend_battles (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,   -- 도전한 사람
  opp_user    uuid not null references auth.users(id) on delete cascade,   -- 친구 (방어 덱)
  mode        text not null check (mode in ('1v1','3v3')),
  day         date not null,
  seed        bigint not null,
  my_snap     jsonb not null,
  opp_snap    jsonb not null,
  manual      boolean not null default false,
  actions     jsonb,                                                       -- 수동 전투 행동 기록 (리플레이용)
  created_at  timestamptz not null default now(),
  reported_at timestamptz, wins smallint, losses smallint, win boolean
);
create index if not exists friend_battles_user_idx on public.friend_battles (user_id, created_at desc);
create index if not exists friend_battles_opp_idx on public.friend_battles (opp_user, created_at desc);
alter table public.friend_battles enable row level security;
revoke all on public.friend_battles from public, anon, authenticated;

create or replace function public._fb_daily_max() returns int language sql immutable as $$ select 20 $$;

create or replace function public.friend_battle_start(p_friend uuid, p_mode text default '1v1') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; used int; mine jsonb := '[]'::jsonb; osnap jsonb; d record; seed bigint; aid bigint; oname text;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_mode not in ('1v1','3v3') then raise exception 'bad mode'; end if;
  n := _pvp_ok('open', p_mode);
  if p_friend is null or not _is_friend(uid, p_friend) then raise exception 'not friends'; end if;
  perform pg_advisory_xact_lock(hashtext('fb:' || uid::text));
  select count(*) into used from friend_battles where user_id = uid and day = _pvp_day();
  if used >= _fb_daily_max() then raise exception 'no attempts left'; end if;
  if (select count(*) from pvp_decks where user_id = uid and league = 'open' and mode = p_mode) < n then raise exception 'deck required'; end if;
  if (select count(*) from pvp_decks where user_id = p_friend and league = 'open' and mode = p_mode and slot < n) < n then raise exception 'friend deck missing'; end if;
  for d in select * from pvp_decks where user_id = uid and league = 'open' and mode = p_mode and slot < n order by slot loop
    mine := mine || jsonb_build_array(_pvp_snap(uid, d.uids, 'open')->'cards');
  end loop;
  select coalesce(jsonb_agg(snap order by slot), '[]'::jsonb) into osnap from pvp_decks where user_id = p_friend and league = 'open' and mode = p_mode and slot < n;
  oname := coalesce((select nickname from profiles where id = p_friend), '플레이어');
  seed := floor(random() * 2147483647)::bigint;
  insert into friend_battles (user_id, opp_user, mode, day, seed, my_snap, opp_snap)
  values (uid, p_friend, p_mode, _pvp_day(), seed, mine, osnap) returning id into aid;
  return jsonb_build_object('id', aid, 'seed', seed, 'mode', p_mode, 'me', mine, 'opp', osnap, 'opp_name', oname, 'opp_user', p_friend,
    'left', _fb_daily_max() - used - 1);
end $$;

create or replace function public.friend_battle_report(p_id bigint, p_wins int, p_losses int, p_actions jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a friend_battles; need int; v_win boolean; x jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from friend_battles where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  need := case when a.mode = '3v3' then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  if p_actions is not null and jsonb_typeof(p_actions) <> 'null' then
    if jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) > 3 or octet_length(p_actions::text) > 131072 then raise exception 'bad actions'; end if;
    for x in select value from jsonb_array_elements(p_actions) loop
      if not _battle_acts_ok(x, 20 * 6 + 5) then raise exception 'bad actions'; end if;
    end loop;
  else p_actions := null; end if;
  v_win := p_wins = need;
  update friend_battles set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win, actions = p_actions, manual = p_actions is not null where id = a.id;
  return jsonb_build_object('ok', true, 'id', a.id, 'win', v_win, 'record', (
    select jsonb_build_object('w', count(*) filter (where (user_id = uid and win) or (opp_user = uid and not win)),
                              'l', count(*) filter (where (user_id = uid and not win) or (opp_user = uid and win)))
    from friend_battles where reported_at is not null and ((user_id = uid and opp_user = a.opp_user) or (user_id = a.opp_user and opp_user = uid))));
end $$;

-- 전적: p_friend 를 주면 그 친구와의 기록 (공격·방어 모두), 없으면 친구별 승패 요약
create or replace function public.friend_battle_history(p_friend uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if p_friend is null then
    return jsonb_build_object('ok', true, 'left', greatest(0, _fb_daily_max() - (select count(*) from friend_battles where user_id = uid and day = _pvp_day())::int),
      'records', (select coalesce(jsonb_object_agg(o, jsonb_build_object('w', w, 'l', l)), '{}'::jsonb) from (
        select case when user_id = uid then opp_user else user_id end o,
               count(*) filter (where (user_id = uid and win) or (opp_user = uid and not win)) w,
               count(*) filter (where (user_id = uid and not win) or (opp_user = uid and win)) l
        from friend_battles where reported_at is not null and (user_id = uid or opp_user = uid) group by 1) t));
  end if;
  if not _is_friend(uid, p_friend) then raise exception 'not friends'; end if;
  return jsonb_build_object('ok', true, 'battles', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'attack', user_id = uid, 'mode', mode,
      'win', case when user_id = uid then win else not win end, 'wins', wins, 'losses', losses, 'manual', manual, 'at', created_at) order by id desc), '[]'::jsonb)
    from (select * from friend_battles where reported_at is not null and ((user_id = uid and opp_user = p_friend) or (user_id = p_friend and opp_user = uid))
          order by id desc limit 30) b));
end $$;

revoke all on function public.friend_battle_start(uuid, text), public.friend_battle_report(bigint, int, int, jsonb), public.friend_battle_history(uuid) from public, anon;
grant execute on function public.friend_battle_start(uuid, text), public.friend_battle_report(bigint, int, int, jsonb), public.friend_battle_history(uuid) to authenticated;
