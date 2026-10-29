-- =====================================================================
-- 조직 인재 대여 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (새 테이블·함수만, 기존 데이터 삭제 없음)
-- 선행: guild.sql (guild_members · _loyalty_add · _guild_day), story_server.sql (story_progress 서버 저장)
--   · 내 인재 최대 3명을 조직에 대여 등록 (내가 계속 써도 됨)
--   · 조직원은 하루(KST) 1명 대여 · 12시간 뒤 자동 반납 (expires_at 지나면 끝)
--   · 대여 인재 = 빌릴 때 원주인의 레벨·스탯 그대로(스냅샷) · 스토리·시련의 탑에서만
--   · 내 인재는 못 빌림 · 이미 같은 인재(같은 카드)를 가지고 있으면 못 빌림
--   · 빌려줄 때마다 원주인에게 충성 +20 (_lend_reward 로 조정)
-- =====================================================================
create table if not exists public.guild_lend_slots (
  user_id uuid not null references auth.users(id) on delete cascade,
  uid text not null check (char_length(uid) <= 80),
  card_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, uid));
create table if not exists public.guild_loans (
  id bigint generated always as identity primary key,
  borrower uuid not null references auth.users(id) on delete cascade,
  lender uuid not null references auth.users(id) on delete cascade,
  guild_id bigint not null,
  card_id text not null, src_uid text not null, snap jsonb not null,
  day date not null, borrowed_at timestamptz not null default now(), expires_at timestamptz not null,
  unique (borrower, day));
create index if not exists guild_loans_borrower on public.guild_loans (borrower, expires_at desc);
alter table public.guild_lend_slots enable row level security;
alter table public.guild_loans enable row level security;
revoke all on public.guild_lend_slots, public.guild_loans from anon, authenticated;   -- 읽기·쓰기 모두 아래 함수로만

create or replace function public._lend_reward() returns int language sql immutable as $$ select 20 $$;
create or replace function public._lend_hours() returns int language sql immutable as $$ select 12 $$;
create or replace function public._lend_max() returns int language sql immutable as $$ select 3 $$;

-- 내 보유 인재 (story_progress.data.owned) 에서 uid 로 한 장
create or replace function public._lend_owned(p_uid uuid, p_card_uid text) returns jsonb language sql stable security definer set search_path = public as $$
  select o from story_progress s, jsonb_array_elements(case when jsonb_typeof(s.data->'owned') = 'array' then s.data->'owned' else '[]'::jsonb end) o
  where s.user_id = p_uid and o->>'uid' = p_card_uid limit 1 $$;

-- 등록 바꾸기: p_uids = 내 인재 uid 최대 3개 (빈 배열 = 전부 해제)
create or replace function public.guild_lend_set(p_uids jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); u text; o jsonb; n int := 0;
begin
  if me is null then raise exception 'login required'; end if;
  if not exists (select 1 from guild_members where user_id = me) then raise exception 'not in guild'; end if;
  if jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) > _lend_max() then raise exception 'too many'; end if;
  delete from guild_lend_slots where user_id = me;
  for u in select distinct value from jsonb_array_elements_text(p_uids) loop
    o := _lend_owned(me, u);
    if o is null then raise exception 'not owned'; end if;
    if exists (select 1 from guild_lend_slots where user_id = me and card_id = o->>'id') then continue; end if;   -- 같은 카드 두 장 X
    insert into guild_lend_slots (user_id, uid, card_id) values (me, u, o->>'id'); n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;

-- 대여 화면: 내 등록 · 조직원 등록 인재(원주인 레벨) · 내 대여 중 · 오늘 빌렸는지
create or replace function public.guild_lend_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; mine jsonb; others jsonb; cur jsonb; today boolean;
begin
  if me is null then raise exception 'login required'; end if;
  select guild_id into gid from guild_members where user_id = me;
  if gid is null then return jsonb_build_object('in_guild', false); end if;
  select coalesce(jsonb_agg(jsonb_build_object('uid', s.uid, 'id', s.card_id, 'level', (_lend_owned(me, s.uid)->>'level')::int) order by s.created_at), '[]'::jsonb) into mine
    from guild_lend_slots s where s.user_id = me and _lend_owned(me, s.uid) is not null;
  select coalesce(jsonb_agg(jsonb_build_object('owner', s.user_id, 'owner_name', coalesce(p.nickname, '조직원'), 'uid', s.uid, 'id', s.card_id, 'level', (o.o->>'level')::int) order by p.nickname, s.created_at), '[]'::jsonb) into others
    from guild_lend_slots s join guild_members m on m.user_id = s.user_id and m.guild_id = gid left join profiles p on p.id = s.user_id
    cross join lateral (select _lend_owned(s.user_id, s.uid) o) o
    where s.user_id <> me and o.o is not null;
  select jsonb_build_object('id', l.id, 'card_id', l.card_id, 'snap', l.snap, 'lender', l.lender, 'lender_name', coalesce(p.nickname, '조직원'), 'expires_at', l.expires_at) into cur
    from guild_loans l left join profiles p on p.id = l.lender where l.borrower = me and l.expires_at > now() order by l.expires_at desc limit 1;
  today := exists (select 1 from guild_loans where borrower = me and day = _guild_day());
  return jsonb_build_object('in_guild', true, 'max', _lend_max(), 'hours', _lend_hours(), 'reward', _lend_reward(), 'mine', mine, 'others', others, 'loan', cur, 'borrowed_today', today, 'now', now());
end $$;

-- 빌리기: 하루 1명 · 12시간 · 같은 조직 · 내 것 X · 같은 카드 보유 X · 원주인 레벨 스냅샷 · 원주인 충성 +보상
create or replace function public.guild_lend_borrow(p_owner uuid, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; s guild_lend_slots; o jsonb; snap jsonb; lid bigint; ex timestamptz;
begin
  if me is null then raise exception 'login required'; end if;
  if p_owner = me then raise exception 'own card'; end if;
  select guild_id into gid from guild_members where user_id = me;
  if gid is null then raise exception 'not in guild'; end if;
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
  insert into guild_loans (borrower, lender, guild_id, card_id, src_uid, snap, day, expires_at) values (me, p_owner, gid, s.card_id, p_uid, snap, _guild_day(), ex) returning id into lid;
  perform _loyalty_add(p_owner, _lend_reward(), 'lend', 'lend:' || lid, jsonb_build_object('borrower', me, 'card', s.card_id));
  perform _guild_log(gid, me, 'lend', p_owner, jsonb_build_object('card', s.card_id));
  return jsonb_build_object('ok', true, 'id', lid, 'card_id', s.card_id, 'snap', snap, 'expires_at', ex);
end $$;

-- 일찍 반납 (선택)
create or replace function public.guild_lend_return() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n int;
begin
  if me is null then raise exception 'login required'; end if;
  update guild_loans set expires_at = now() where borrower = me and expires_at > now(); get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'n', n);
end $$;

revoke all on function public._lend_owned(uuid, text), public._lend_reward(), public._lend_hours(), public._lend_max() from public, anon, authenticated;
revoke all on function public.guild_lend_set(jsonb), public.guild_lend_status(), public.guild_lend_borrow(uuid, text), public.guild_lend_return() from public, anon;
grant execute on function public.guild_lend_set(jsonb), public.guild_lend_status(), public.guild_lend_borrow(uuid, text), public.guild_lend_return() to authenticated;
select 'guild_lend ok' as result;
