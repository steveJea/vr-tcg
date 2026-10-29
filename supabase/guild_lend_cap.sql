-- 조직 인재 대여: 원주인 보상 하루 3번 · 빌리는 사람 조직 가입 24시간 + 계정 Lv10 — 선행: guild_lend.sql (+ guild_lend_notice.sql)
-- 여러 번 실행해도 안전 (열 추가·함수 다시 정의만, 데이터 삭제 없음). guild_lend_borrow 를 이 파일 것으로 바꿈
alter table public.guild_loans add column if not exists reward int;   -- 이 대여로 원주인이 받은 충성 (예전 기록은 null = 기본 보상으로 봄)
create or replace function public._lend_reward_daily() returns int language sql immutable as $$ select 3 $$;
create or replace function public._lend_join_hours() returns int language sql immutable as $$ select 24 $$;
create or replace function public._lend_min_level() returns int language sql immutable as $$ select 10 $$;
revoke all on function public._lend_reward_daily(), public._lend_join_hours(), public._lend_min_level() from public, anon, authenticated;

create or replace function public.guild_lend_borrow(p_owner uuid, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; jt timestamptz; plv int; rw int; nrw int; s guild_lend_slots; o jsonb; snap jsonb; lid bigint; ex timestamptz;
begin
  if me is null then raise exception 'login required'; end if;
  if p_owner = me then raise exception 'own card'; end if;
  select guild_id, joined_at into gid, jt from guild_members where user_id = me;
  if gid is null then raise exception 'not in guild'; end if;
  if jt > now() - make_interval(hours => _lend_join_hours()) then raise exception 'joined too recently'; end if;   -- 조직 가입 24시간 뒤부터
  select level into plv from player_state where user_id = me;
  if coalesce(plv, 1) < _lend_min_level() then raise exception 'level too low'; end if;   -- 계정 Lv10 부터
  if not exists (select 1 from guild_members where user_id = p_owner and guild_id = gid) then raise exception 'not guildmate'; end if;
  perform pg_advisory_xact_lock(hashtext('guild_lend:' || me::text));
  if exists (select 1 from guild_loans where borrower = me and day = _guild_day()) then raise exception 'already borrowed today'; end if;
  select * into s from guild_lend_slots where user_id = p_owner and uid = p_uid;
  if s.user_id is null then raise exception 'not lendable'; end if;
  o := _lend_owned(p_owner, p_uid);
  if o is null then raise exception 'not lendable'; end if;
  if exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
             where sp.user_id = me and x->>'id' = s.card_id) then raise exception 'already own card'; end if;
  snap := jsonb_strip_nulls(jsonb_build_object('id', o->'id', 'level', o->'level', 'boost', o->'boost', 'ex', o->'ex', 'exb', o->'exb', 'skillLv', o->'skillLv'));
  ex := now() + make_interval(hours => _lend_hours());
  perform pg_advisory_xact_lock(hashtext('guild_lend_reward:' || p_owner::text));
  select count(*) into nrw from guild_loans where lender = p_owner and day = _guild_day() and coalesce(reward, 0) > 0;
  rw := case when nrw < _lend_reward_daily() then _lend_reward() else 0 end;   -- 원주인 보상: 하루(KST) 3번까지 (그 뒤로도 빌려줄 수는 있음, 보상만 없음)
  insert into guild_loans (borrower, lender, guild_id, card_id, src_uid, snap, day, expires_at, reward) values (me, p_owner, gid, s.card_id, p_uid, snap, _guild_day(), ex, rw) returning id into lid;
  if rw > 0 then perform _loyalty_add(p_owner, rw, 'lend', 'lend:' || lid, jsonb_build_object('borrower', me, 'card', s.card_id)); end if;
  perform _guild_log(gid, me, 'lend', p_owner, jsonb_build_object('card', s.card_id));
  return jsonb_build_object('ok', true, 'id', lid, 'card_id', s.card_id, 'snap', snap, 'expires_at', ex, 'lender_reward', rw);
end $$;

revoke all on function public.guild_lend_borrow(uuid, text) from public, anon;
grant execute on function public.guild_lend_borrow(uuid, text) to authenticated;

-- 알림: 실제로 받은 보상(0 이면 0)을 보여 줌
create or replace function public.guild_lend_notices() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  with x as (
    select l.id from guild_loans l where l.lender = me and not l.lender_seen and l.borrowed_at > now() - interval '7 days' order by l.borrowed_at desc limit 30),
  u as (update guild_loans l set lender_seen = true from x where l.id = x.id returning l.*)
  select coalesce(jsonb_agg(jsonb_build_object('borrower_name', coalesce(p.nickname, '조직원'), 'card_id', u.card_id, 'reward', coalesce(u.reward, _lend_reward()), 'at', u.borrowed_at) order by u.borrowed_at desc), '[]'::jsonb) into r
    from u left join profiles p on p.id = u.borrower;
  update guild_loans set lender_seen = true where lender = me and not lender_seen;   -- 7일 지난 것도 정리
  return r;
end $$;
revoke all on function public.guild_lend_notices() from public, anon;
grant execute on function public.guild_lend_notices() to authenticated;
select 'guild_lend_cap ok' as result;
