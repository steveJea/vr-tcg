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
  primary key (guild_id, week));
create table if not exists public.guild_raid_stages (
  guild_id bigint not null, week date not null, stage int not null, boss_id text, hp bigint not null,
  cleared_at timestamptz, last_hit uuid references auth.users(id) on delete set null,
  primary key (guild_id, week, stage), foreign key (guild_id, week) references public.guild_raids(guild_id, week) on delete cascade);
create table if not exists public.guild_raid_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade, guild_id bigint not null, week date not null, day date not null,
  kind text not null check (kind in ('fight', 'sweep')), stage int not null, difficulty text not null,
  seed bigint, snap jsonb, reported bigint, damage bigint not null default 0, flagged boolean not null default false, voided boolean not null default false,
  started_at timestamptz not null default now(), finished_at timestamptz);
create index if not exists guild_raid_attempts_user on public.guild_raid_attempts (user_id, day);
create index if not exists guild_raid_attempts_guild on public.guild_raid_attempts (guild_id, week);
create table if not exists public.guild_raid_damage (
  guild_id bigint not null, week date not null, user_id uuid not null references auth.users(id) on delete cascade,
  damage bigint not null default 0, attempts int not null default 0, updated_at timestamptz not null default now(),
  primary key (guild_id, week, user_id));
do $$ declare t text; begin
  foreach t in array array['guild_raids', 'guild_raid_stages', 'guild_raid_attempts', 'guild_raid_damage'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- 2) 숫자 (여기만 고치면 됨)
create or replace function public._raid_numbers() returns jsonb language sql immutable as $$ select '{
  "attempts_per_day": 3, "sweep_pct": 90, "min_secs": 3, "open_minutes": 10,
  "hp_per_member": {"normal": 500000, "hard": 1250000, "abyss": 3000000}, "hp_min_members": 5, "hp_growth": 1.35,
  "diff_level": {"normal": 1, "hard": 3, "abyss": 5}, "diff_mult": {"normal": 1, "hard": 1.6, "abyss": 2.5},
  "hit_cap": 6000, "hit_cap_growth": 1.1, "attempt_hits": 200,
  "attempt": {"loyalty": 5, "gold_base": 200, "gold_per_damage": 200, "gold_max": 2000, "exp": 5},
  "stage": {"loyalty": 20, "gold": 2000, "gem": 30, "gem_every3": 150, "tickets_every5": 1, "exp_per_stage": 30},
  "last_hit": {"loyalty": 10},
  "rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 100}}, {"from": 2, "to": 3, "reward": {"gem": 500, "loyalty": 70}}, {"from": 4, "to": 10, "reward": {"gem": 200, "loyalty": 40}}],
  "member": {"gem": 100, "loyalty": 20},
  "join_hours": 24
}'::jsonb $$;
-- 단계 → 보스 (js/raid-core.js RAID_BOSSES 와 같음)
create or replace function public._raid_boss(p_stage int) returns jsonb language sql immutable as $$
  select (array['{"id":"2000100001","name":"임유리","weak":"CHARGE"}', '{"id":"2000000008","name":"[각성] 임유리","weak":"DEFENSE"}',
                '{"id":"2000900234","name":"김신현","weak":"CRUSH"}', '{"id":"1000200030","name":"김성진","weak":"SUPPORT"}',
                '{"id":"2001500316","name":"이지영","weak":"DISTURB"}'])[((greatest(p_stage, 1) - 1) % 5) + 1]::jsonb $$;
create or replace function public._raid_now() returns timestamptz language sql stable as $$ select now() $$;   -- 테스트에서 바꿔 끼움
create or replace function public._raid_end(p_week date) returns timestamptz language sql stable as $$ select ((p_week + 6)::timestamp + interval '22 hours') at time zone 'Asia/Seoul' $$;
create or replace function public._raid_hp(p_diff text, p_members int, p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers()->'hp_per_member'->>p_diff)::numeric * greatest(p_members, (_raid_numbers()->>'hp_min_members')::int)
               * power((_raid_numbers()->>'hp_growth')::numeric, greatest(p_stage, 1) - 1))::bigint $$;
create or replace function public._raid_attempt_cap(p_stage int) returns bigint language sql immutable as $$
  select round((_raid_numbers()->>'hit_cap')::numeric * power((_raid_numbers()->>'hit_cap_growth')::numeric, greatest(p_stage, 1) - 1)) * (_raid_numbers()->>'attempt_hits')::int $$;
-- 단계 처치 개인 보상 (난이도 배율: 충성·골드·심연석)
create or replace function public._raid_stage_reward(p_diff text, p_stage int) returns jsonb language sql immutable as $$
  with n as (select _raid_numbers() j), x as (select j->'stage' s, (j->'diff_mult'->>p_diff)::numeric m from n)
  select jsonb_strip_nulls(jsonb_build_object('loyalty', round((s->>'loyalty')::int * m)::int, 'gold', round((s->>'gold')::int * m)::int,
    'gem', round(((s->>'gem')::int + case when p_stage % 3 = 0 then (s->>'gem_every3')::int else 0 end) * m)::int,
    'tickets', case when p_stage % 5 = 0 then (s->>'tickets_every5')::int end)) from x $$;
create or replace function public._raid_rank_reward(p_rank int) returns jsonb language sql immutable as $$
  select coalesce((select r->'reward' from jsonb_array_elements(_raid_numbers()->'rank') r where p_rank between (r->>'from')::int and (r->>'to')::int), '{}'::jsonb) $$;

-- 3) 내부
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
end $$;
-- 공유 HP 깎기 (넘친 피해는 다음 단계로). 반환 처치한 단계 수
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
end $$;
-- 한 판 마감 (피해 기록 · 공유 HP · 1회 보상 · 의뢰 진행)
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
end $$;
revoke all on function public._raid_get(bigint, date), public._raid_hit(bigint, date, uuid, bigint), public._raid_close(guild_raid_attempts, bigint) from public, anon, authenticated;

-- 4) 공개 RPC
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
end $$;
-- 받을 수 있는 보상 수 (빨간 점)
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
end $$;
-- 난이도 (보스·간부, 이번 주 첫 피해 전까지)
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
end $$;
-- 전투 시작: 횟수 차감 · 덱 스냅샷 · seed
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
end $$;
-- 전투 끝: 피해 보고 (한 판 상한 · 최소 시간)
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
end $$;
-- 소탕: 오늘 직접 싸운 최고 기록의 90% (횟수 1 사용)
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
end $$;
-- 보상 모두 받기: 처치 단계(그때 조직원이었던 사람) · 주간 순위/참여(정산 24시간 전 가입, 지금도 같은 조직)
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
end $$;
revoke all on function public.raid_status(), public.raid_claimable(), public.raid_set_difficulty(text), public.raid_start(jsonb), public.raid_finish(bigint, bigint), public.raid_sweep(), public.raid_claim() from public, anon;
grant execute on function public.raid_status(), public.raid_claimable(), public.raid_set_difficulty(text), public.raid_start(jsonb), public.raid_finish(bigint, bigint), public.raid_sweep(), public.raid_claim() to authenticated;

-- 5) 관리자: 조직 토벌 현황 · 의심 기록 · 기록 무효(사유 필수, 개인 누적만 빼고 공유 HP 는 그대로)
create or replace function public.admin_guild_raid(p_gid bigint) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('raid', (select to_jsonb(r) from guild_raids r where guild_id = p_gid and week = _guild_week()),
    'flagged', (select coalesce(jsonb_agg(to_jsonb(a) - 'snap' order by a.id desc), '[]'::jsonb) from (select * from guild_raid_attempts where guild_id = p_gid and flagged order by id desc limit 50) a),
    'top', (select coalesce(jsonb_agg(to_jsonb(d) order by d.damage desc), '[]'::jsonb) from guild_raid_damage d where guild_id = p_gid and week = _guild_week()));
end $$;
create or replace function public.admin_raid_void(p_id bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
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
end $$;
revoke all on function public.admin_guild_raid(bigint), public.admin_raid_void(bigint, text) from public, anon;
grant execute on function public.admin_guild_raid(bigint), public.admin_raid_void(bigint, text) to authenticated;
