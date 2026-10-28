-- 조직 4단계 보완: 구역 전쟁 「참가 신청(개인)」 · 아지트 칸에 리더 얼굴. 여러 번 실행해도 안전.
-- 선행: guild4.sql
-- · 조직원은 신청 기간(셋째 주 일~화)에 개인 참가 신청 (war_signup). 보스는 신청 안 한 조직원도 배치 가능 (war_set_slot 그대로)
-- · 시즌 잠금 때 빈 칸 자동 배치는 신청한 사람부터 (그다음 나머지 조직원)
-- · war_ui(): 내 조직 신청자 목록 + 내 조직·오늘 상대의 리더 인재 id (화면 표시용)

create table if not exists public.war_signups (
  season date not null, user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null,
  created_at timestamptz not null default now(), primary key (season, user_id));
create index if not exists war_signups_g on public.war_signups (season, guild_id);
alter table public.war_signups enable row level security;
revoke all on public.war_signups from public, anon, authenticated;

-- 리더 인재 id (스토리 저장에서)
create or replace function public._war_leader_card(p_uid uuid) returns text language sql stable security definer set search_path = public as $$
  select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = p_uid and o->>'uid' = sp.data->>'leader' limit 1 $$;

-- 개인 참가 신청 / 취소
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
end $$;

-- 화면 보조: 신청자 · 리더 얼굴
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
end $$;

-- 시즌 잠금: 빈 칸 자동 배치는 신청자 먼저
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
end $$;


revoke all on function public._war_leader_card(uuid), public._war_lock(date) from public, anon, authenticated;
revoke all on function public.war_signup(boolean), public.war_ui() from public, anon;
grant execute on function public.war_signup(boolean), public.war_ui() to authenticated;
