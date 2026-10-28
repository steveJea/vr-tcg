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
  def1 jsonb, def2 jsonb, atk1 jsonb, atk2 jsonb, updated_at timestamptz not null default now());
create table if not exists public.war_entries (
  season date not null, guild_id bigint not null references public.guilds(id) on delete cascade,
  status text not null default 'in' check (status in ('in', 'out')), locked boolean not null default false, scale numeric not null default 1,
  points int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0, boss_kills int not null default 0, score_total int not null default 0,
  entered_at timestamptz not null default now(), primary key (season, guild_id));
create table if not exists public.war_roster (
  season date not null, guild_id bigint not null, slot int not null check (slot between 1 and 21), user_id uuid references auth.users(id) on delete set null,
  def_snap jsonb, primary key (season, guild_id, slot), foreign key (season, guild_id) references public.war_entries(season, guild_id) on delete cascade);
create unique index if not exists war_roster_user on public.war_roster (season, user_id) where user_id is not null;
create table if not exists public.war_matches (
  id bigint generated always as identity primary key, season date not null, day int not null check (day between 1 and 5),
  guild_a bigint not null, guild_b bigint, score_a int not null default 0, score_b int not null default 0,
  winner bigint, draw boolean not null default false, boss_kill boolean not null default false, ended_at timestamptz, settled boolean not null default false,
  unique (season, day, guild_a));
create index if not exists war_matches_b on public.war_matches (season, day, guild_b);
create table if not exists public.war_ajits (
  match_id bigint not null references public.war_matches(id) on delete cascade, side int not null check (side in (0, 1)), slot int not null,
  role text not null, user_id uuid, npc boolean not null default false, snaps jsonb not null default '[]'::jsonb,
  deck int not null default 1, state jsonb, destroyed_at timestamptz, destroyed_by uuid, locked_by uuid, locked_until timestamptz,
  primary key (match_id, side, slot));
create table if not exists public.war_atk_state (
  match_id bigint not null references public.war_matches(id) on delete cascade, user_id uuid not null, deck int not null check (deck in (1, 2)),
  snap jsonb not null, state jsonb, primary key (match_id, user_id, deck));
create table if not exists public.war_attacks (
  id bigint generated always as identity primary key, match_id bigint not null references public.war_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, side int not null, target_slot int not null, atk_deck int not null, def_deck int not null,
  seed bigint not null, atk_snap jsonb not null, def_snap jsonb not null, atk_buff jsonb not null, def_buff jsonb not null,
  before jsonb not null, reported jsonb, win boolean, points int not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);
create index if not exists war_attacks_user on public.war_attacks (user_id, match_id);
do $$ declare t text; begin
  foreach t in array array['war_decks', 'war_entries', 'war_roster', 'war_matches', 'war_ajits', 'war_atk_state', 'war_attacks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- 2) 숫자 (여기만 고치면 됨)
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
}'::jsonb $$;
create or replace function public._war_role(p_slot int) returns text language sql immutable as $$
  select case when p_slot <= 5 then 'def' when p_slot <= 10 then 'atk' when p_slot <= 13 then 'mid' when p_slot = 14 then 'boss' else 'etc' end $$;

-- 3) 시간 (KST)
create or replace function public._war_now() returns timestamptz language sql stable as $$ select now() $$;   -- 테스트에서 바꿔 끼움
create or replace function public._war_kst() returns timestamp language sql stable as $$ select _war_now() at time zone 'Asia/Seoul' $$;
create or replace function public._war_third_wed(p_d date) returns date language sql immutable as $$
  select (date_trunc('month', p_d)::date + ((3 - extract(isodow from date_trunc('month', p_d))::int + 7) % 7) + 14) $$;
-- 지금 시즌 (진행 중 · 끝난 날 당일 · 아니면 다음 시즌)
create or replace function public._war_season() returns date language sql stable as $$
  select case when _war_kst()::date <= _war_third_wed(_war_kst()::date) + 4 then _war_third_wed(_war_kst()::date)
              else _war_third_wed((date_trunc('month', _war_kst()) + interval '1 month')::date) end $$;
create or replace function public._war_at(p_season date, p_day int, p_hour int) returns timestamptz language sql immutable as $$
  select ((p_season + p_day - 1)::timestamp + make_interval(hours => p_hour)) at time zone 'Asia/Seoul' $$;
-- 오늘 몇 일차 (1~5, 아니면 null)
create or replace function public._war_day(p_season date) returns int language sql stable as $$
  select case when _war_kst()::date between p_season and p_season + 4 then (_war_kst()::date - p_season) + 1 end $$;
create or replace function public._war_phase(p_season date) returns text language sql stable as $$
  select case when _war_now() < _war_at(p_season, 1 - (_war_numbers()->>'signup_days_before')::int, 0) then 'soon'
              when _war_now() < _war_at(p_season, 1, (_war_numbers()->>'open_hour')::int) then 'signup'
              when _war_now() >= _war_at(p_season, 5, (_war_numbers()->>'close_hour')::int) then 'ended'
              when extract(hour from _war_kst()) >= (_war_numbers()->>'open_hour')::int and extract(hour from _war_kst()) < (_war_numbers()->>'close_hour')::int then 'live'
              else 'rest' end $$;

-- 4) 동네 불량배 (NPC): HR 2 + R 3, 남녀 섞임, seed 로 고정
create or replace function public._war_npc_deck(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $$
declare hr text[] := array['1000000031','1000000032','2000000033','2000000034','2000000035','2000000036','2000000037','2000000038'];
        r text[] := array['1000000028','1000000029','1000000030','2000000029','2000000030','2000000031','2000000032'];
        male text[] := array['1000000028','1000000029','1000000030','1000000031','1000000032'];   -- 성별은 ID 첫 자리가 아니라 카드 데이터(gender)로 (ID 변경 후에도 맞게)
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
end $$;
-- 동네 불량배 = 고정 약체 (레벨 10 · 배율 1, 조직 덱과 무관)
create or replace function public._war_scale(p_season date, p_gid bigint) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((_war_numbers()->>'npc_scale')::numeric, 1) $$;

-- 5) 진행 (모든 공개 RPC 가 먼저 부름): 시즌 잠금 · 매일 대진 · 23시 정산
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
end $$;
-- 한 쪽 아지트 21곳 만들기
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
end $$;
create or replace function public._war_pair(p_season date, p_day int) returns void language plpgsql security definer set search_path = public as $$
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
end $$;
create or replace function public._war_settle(p_mid bigint) returns void language plpgsql security definer set search_path = public as $$
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
end $$;
create or replace function public._war_tick() returns date language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public._war_npc_deck(text, numeric), public._war_scale(date, bigint), public._war_lock(date), public._war_build_side(bigint, int, date, bigint, numeric),
  public._war_pair(date, int), public._war_settle(bigint), public._war_tick() from public, anon, authenticated;

-- 6) 공개 RPC
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
end $$;
-- 참가 (보스·간부, 신청 기간)
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
end $$;
create or replace function public.war_withdraw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s date := _war_tick();
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role <> 'boss' then raise exception 'not allowed'; end if;
  if _war_phase(s) <> 'signup' then raise exception 'signup closed'; end if;
  delete from war_entries where season = s and guild_id = m.guild_id;
  return war_status();
end $$;
-- 배치 (보스만, 신청 기간): p_user = null 이면 그 칸 비움. 같은 사람을 다른 칸에 두면 옮겨짐
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
end $$;
-- 아지트 목록 (한 쪽)
create or replace function public._war_side_json(p_mid bigint, p_side int) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', a.slot, 'role', a.role, 'npc', a.npc, 'user_id', a.user_id,
      'name', case when a.npc and a.user_id is null then '동네 불량배' else coalesce(p.nickname, '조직원') end, 'deck', a.deck, 'decks', jsonb_array_length(a.snaps) - (case when jsonb_array_length(coalesce(a.snaps->1, '[]'::jsonb)) = 0 then 1 else 0 end),
      'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', c->'level', 'scale', c->'scale', 'hp', a.state->(c->>'uid'))), '[]'::jsonb) from jsonb_array_elements(a.snaps->(a.deck - 1)) c),
      'destroyed', a.destroyed_at is not null, 'locked', a.locked_until > _war_now()) order by a.slot), '[]'::jsonb)
  from war_ajits a left join profiles p on p.id = a.user_id where a.match_id = p_mid and a.side = p_side $$;
-- 상태
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
end $$;
-- 공격 시작
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
end $$;
-- 공격 끝: p_atk_hp / p_def_hp = { 카드 uid: 남은 HP } (살아남은 카드만). 서버는 이전 HP 를 넘지 않게 자름
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
end $$;
create or replace function public._war_sum(a jsonb, b jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, coalesce((a->>k)::int, 0) + coalesce((b->>k)::int, 0)), '{}'::jsonb) from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) x $$;
-- 받을 보상 (경기 승리 · 시즌 순위) 수
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
end $$;
create or replace function public.war_claimable() returns int language sql stable security definer set search_path = public as $$ select jsonb_array_length(_war_pending(auth.uid())) $$;
create or replace function public.war_claim() returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public._war_side_json(bigint, int), public._war_pending(uuid) from public, anon, authenticated;
revoke all on function public.war_set_deck(text, jsonb), public.war_enter(), public.war_withdraw(), public.war_set_slot(int, uuid), public.war_status(), public.war_start(int, int),
  public.war_finish(bigint, boolean, jsonb, jsonb), public.war_claimable(), public.war_claim() from public, anon;
grant execute on function public.war_set_deck(text, jsonb), public.war_enter(), public.war_withdraw(), public.war_set_slot(int, uuid), public.war_status(), public.war_start(int, int),
  public.war_finish(bigint, boolean, jsonb, jsonb), public.war_claimable(), public.war_claim() to authenticated;

-- 7) 관리자: 시즌 현황 · 의심 기록 · 공격 무효(정산 전만: 그 공격 전 상태로 되돌리고 점수 회수)
create or replace function public.admin_war(p_season date) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('entries', (select coalesce(jsonb_agg(to_jsonb(e) order by e.points desc), '[]'::jsonb) from war_entries e where season = coalesce(p_season, _war_season())),
    'matches', (select coalesce(jsonb_agg(to_jsonb(m) order by m.day, m.id), '[]'::jsonb) from war_matches m where season = coalesce(p_season, _war_season())),
    'flagged', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'match_id', a.match_id, 'user_id', a.user_id, 'target', a.target_slot, 'win', a.win, 'points', a.points, 'at', a.finished_at) order by a.id desc), '[]'::jsonb)
                from war_attacks a join war_matches m on m.id = a.match_id where m.season = coalesce(p_season, _war_season()) and a.flagged and not a.voided));
end $$;
create or replace function public.admin_war_void(p_id bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
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
end $$;
revoke all on function public.admin_war(date), public.admin_war_void(bigint, text) from public, anon;
grant execute on function public.admin_war(date), public.admin_war_void(bigint, text) to authenticated;
