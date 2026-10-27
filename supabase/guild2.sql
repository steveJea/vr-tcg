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
  primary key (user_id, day));
create index if not exists guild_attendance_gday on public.guild_attendance (guild_id, day);
create table if not exists public.guild_quest_pool (
  key text primary key, kind text not null check (kind in ('daily', 'weekly')), event text not null, goal int not null check (goal > 0),
  reward jsonb not null default '{}'::jsonb, weight int not null default 1, label text not null, icon text not null default '📜', active boolean not null default true);
insert into public.guild_quest_pool (key, kind, event, goal, reward, label, icon) values
  ('d_phase',   'daily', 'phase',   5,  '{"loyalty":15,"gold":800,"exp":10}',  '페이즈 정리',  '🗡️'),
  ('d_stamina', 'daily', 'stamina', 60, '{"loyalty":15,"gold":800,"exp":10}',  '행동력 소모',  '🔋'),
  ('d_pvp',     'daily', 'pvp_win', 2,  '{"loyalty":20,"gold":1000,"exp":15}', 'PvP 승리',     '⚔️'),
  ('d_tower',   'daily', 'tower',   1,  '{"loyalty":15,"gold":800,"exp":10}',  '탑 오르기',    '🗼'),
  ('d_draw',    'daily', 'draw',    1,  '{"loyalty":10,"gold":500,"exp":5}',   '소환',         '🎴'),
  ('d_boss',    'daily', 'boss',    1,  '{"loyalty":20,"gold":1000,"exp":15}', '보스 처치',    '💀'),
  ('d_levelup', 'daily', 'levelup', 1,  '{"loyalty":10,"gold":500,"exp":5}',   '카드 강화',    '⬆️'),
  ('d_checkin', 'daily', 'checkin', 1,  '{"loyalty":10,"exp":5}',              '집결',         '🕯️'),
  ('w_phase',   'weekly', 'phase',   30,  '{}', '균열 정리',   '🗡️'),
  ('w_pvp',     'weekly', 'pvp_win', 10,  '{}', '피의 결투',   '⚔️'),
  ('w_stamina', 'weekly', 'stamina', 300, '{}', '행동력 헌납', '🔋'),
  ('w_tower',   'weekly', 'tower',   5,   '{}', '탑 정복',     '🗼'),
  ('w_checkin', 'weekly', 'checkin', 5,   '{}', '집결의 맹세', '🕯️'),
  ('w_draw',    'weekly', 'draw',    5,   '{}', '소환 의식',   '🎴')
on conflict (key) do update set kind = excluded.kind, event = excluded.event, goal = excluded.goal, reward = excluded.reward, label = excluded.label, icon = excluded.icon;
create table if not exists public.guild_daily_quests (
  user_id uuid not null references auth.users(id) on delete cascade, day date not null, slot int not null check (slot between 1 and 3),
  qkey text not null, goal int not null, progress int not null default 0, rerolled boolean not null default false, claimed_at timestamptz,
  primary key (user_id, day, slot));
create table if not exists public.guild_weekly_quests (
  guild_id bigint not null references public.guilds(id) on delete cascade, week date not null, slot int not null check (slot between 1 and 3),
  qkey text not null, goal int not null, progress int not null default 0, primary key (guild_id, week, slot));
create table if not exists public.guild_weekly_contrib (
  guild_id bigint not null, week date not null, slot int not null, user_id uuid not null references auth.users(id) on delete cascade,
  amount int not null default 0, primary key (guild_id, week, slot, user_id));
create table if not exists public.guild_claims (
  user_id uuid not null references auth.users(id) on delete cascade, ref text not null, guild_id bigint, reward jsonb not null, at timestamptz not null default now(),
  primary key (user_id, ref));
do $$ declare t text; begin
  foreach t in array array['guild_attendance', 'guild_quest_pool', 'guild_daily_quests', 'guild_weekly_quests', 'guild_weekly_contrib', 'guild_claims'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- 2) 수치 (한 곳에서 조정)
create or replace function public._guild_week() returns date language sql stable as $$ select date_trunc('week', _guild_day()::timestamp)::date $$;
create or replace function public._guild_checkin_reward() returns jsonb language sql immutable as $$ select '{"loyalty":20,"gold":1000,"exp":10}'::jsonb $$;
-- 출석률 보너스: [필요 %, 개인 보상, 조직 세력]
create or replace function public._guild_rally_tiers() returns jsonb language sql immutable as $$
  select '[{"tier":30,"reward":{"loyalty":10},"exp":30},{"tier":60,"reward":{"loyalty":20,"gold":1000},"exp":60},{"tier":90,"reward":{"loyalty":30,"gem":5},"exp":100}]'::jsonb $$;
create or replace function public._guild_week_streak_reward() returns jsonb language sql immutable as $$ select '{"loyalty":100,"tickets":1}'::jsonb $$;
create or replace function public._guild_daily_all_reward() returns jsonb language sql immutable as $$ select '{"loyalty":20}'::jsonb $$;
-- 주간 공동 의뢰 단계: [%, 개인 보상, 조직 세력]
create or replace function public._guild_weekly_tiers() returns jsonb language sql immutable as $$
  select '[{"tier":50,"reward":{"loyalty":30},"exp":100},{"tier":100,"reward":{"loyalty":60,"gold":3000,"gem":10},"exp":200},{"tier":150,"reward":{"loyalty":100,"tickets":1},"exp":300}]'::jsonb $$;
create or replace function public._guild_weekly_min_pct() returns numeric language sql immutable as $$ select 0.01 $$;

-- 3) 내부 도우미
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
end $$;
-- 오늘 일일 의뢰 3개 (없으면 뽑기, 같은 종류 중복 없음)
create or replace function public._guild_roll_daily(p_uid uuid) returns void language plpgsql security definer set search_path = public as $$
declare d date := _guild_day(); q record; i int := 0;
begin
  if exists (select 1 from guild_daily_quests where user_id = p_uid and day = d) then return; end if;
  for q in select key, goal from guild_quest_pool where kind = 'daily' and active order by -ln(1 - random()) / greatest(weight, 1) limit 3 loop
    i := i + 1; insert into guild_daily_quests (user_id, day, slot, qkey, goal) values (p_uid, d, i, q.key, q.goal) on conflict do nothing;
  end loop;
end $$;
-- 이번 주 공동 의뢰 3개 (목표 = 1인 목표 × 그때 인원)
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
end $$;
-- 진행 이벤트 (서버 함수·트리거에서만). 조직이 없으면 무시. 오류가 나도 원래 동작은 막지 않음
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
end $$;
-- 오늘 출석 인원 (오늘 가입한 사람 제외) / 현재 인원
create or replace function public._guild_rally_count(p_gid bigint) returns int[] language sql stable security definer set search_path = public as $$
  select array[(select count(*)::int from guild_attendance a join guild_members gm on gm.user_id = a.user_id and gm.guild_id = p_gid
                 where a.guild_id = p_gid and a.day = _guild_day() and gm.joined_at < (_guild_day()::timestamp at time zone 'Asia/Seoul')),
               (select count(*)::int from guild_members where guild_id = p_gid)] $$;
revoke all on function public._guild_reward(uuid, bigint, jsonb, text, text), public._guild_roll_daily(uuid), public._guild_roll_weekly(bigint),
  public._guild_event(uuid, text, int), public._guild_rally_count(bigint) from public, anon, authenticated;

-- 4) 트리거: 카드 뽑기(story_gacha_log) · 카드 레벨업(wallet_log 'card_levelup') · 탑 클리어(quest_progress / tower_progress clears 증가)
create or replace function public._guild_trg_draw() returns trigger language plpgsql security definer set search_path = public as $$
begin perform _guild_event(new.user_id, 'draw', 1); return null; end $$;
create or replace function public._guild_trg_levelup() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.reason = 'card_levelup' then perform _guild_event(new.user_id, 'levelup', 1); end if; return null; end $$;
create or replace function public._guild_trg_tower() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.clears > old.clears then perform _guild_event(new.user_id, 'tower', new.clears - old.clears); end if; return null; end $$;
revoke all on function public._guild_trg_draw(), public._guild_trg_levelup(), public._guild_trg_tower() from public, anon, authenticated;
drop trigger if exists guild_ev_draw on public.story_gacha_log;
create trigger guild_ev_draw after insert on public.story_gacha_log for each row execute function public._guild_trg_draw();
drop trigger if exists guild_ev_levelup on public.wallet_log;
create trigger guild_ev_levelup after insert on public.wallet_log for each row execute function public._guild_trg_levelup();
do $$ begin
  if to_regclass('public.quest_progress') is not null then
    drop trigger if exists guild_ev_tower on public.quest_progress;
    create trigger guild_ev_tower after update of clears on public.quest_progress for each row execute function public._guild_trg_tower();
  end if;
  if to_regclass('public.tower_progress') is not null then
    drop trigger if exists guild_ev_tower on public.tower_progress;
    create trigger guild_ev_tower after update of clears on public.tower_progress for each row execute function public._guild_trg_tower();
  end if;
end $$;

-- 5) 공개 RPC
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
end $$;
-- 집결 (하루 1번, 조직을 옮겨도 하루 1번)
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
end $$;
-- 출석률 보너스 (p_tier = 30 | 60 | 90) 또는 주간 개근 (p_tier = 7)
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
end $$;
-- 의뢰 상태
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
end $$;
-- 일일 의뢰 보상 (p_slot 1~3) · 3개 완료 보너스 (p_slot = 0)
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
end $$;
-- 일일 의뢰 교체 (하루 1번 무료, 받지 않은 칸만, 진행도 0 부터)
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
end $$;
-- 주간 공동 의뢰 보상 (p_tier = 50 | 100 | 150). 기여 1% 이상만. 조직 세력은 조직당 한 번
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
end $$;
-- 조직 홈 빨간 점: { rally: 집결 안 했거나 받을 보너스, quest: 받을 의뢰 보상 }
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
end $$;
revoke all on function public.guild_rally(), public.guild_checkin(), public.guild_rally_claim(int), public.guild_quests(), public.guild_quest_claim(int),
  public.guild_quest_reroll(int), public.guild_weekly_claim(int, int), public.guild_dots() from public, anon;
grant execute on function public.guild_rally(), public.guild_checkin(), public.guild_rally_claim(int), public.guild_quests(), public.guild_quest_claim(int),
  public.guild_quest_reroll(int), public.guild_weekly_claim(int, int), public.guild_dots() to authenticated;

-- 조직원 상세 (같은 조직만, 공개 정보만)
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
end $$;
revoke all on function public.guild_member_info(uuid) from public, anon;
grant execute on function public.guild_member_info(uuid) to authenticated;

-- 6) 관리자: 조직 출석·의뢰 보기 · 주간 의뢰 다시 뽑기
create or replace function public.admin_guild_activity(p_gid bigint) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('rally', _guild_rally_count(p_gid),
    'attendance_7d', (select coalesce(jsonb_object_agg(day, n), '{}'::jsonb) from (select day, count(*) n from guild_attendance where guild_id = p_gid and day > _guild_day() - 7 group by day) x),
    'weekly', (select coalesce(jsonb_agg(to_jsonb(q) order by slot), '[]'::jsonb) from guild_weekly_quests q where guild_id = p_gid and week = _guild_week()));
end $$;
create or replace function public.admin_guild_reset_weekly(p_gid bigint, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  delete from guild_weekly_quests where guild_id = p_gid and week = _guild_week();
  delete from guild_weekly_contrib where guild_id = p_gid and week = _guild_week();
  perform _guild_roll_weekly(p_gid);
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason) values (auth.uid(), auth.jwt()->>'email', 'guild_reset_weekly', null, p_gid::int, left(btrim(p_reason), 200));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_guild_activity(bigint), public.admin_guild_reset_weekly(bigint, text) from public, anon;
grant execute on function public.admin_guild_activity(bigint), public.admin_guild_reset_weekly(bigint, text) to authenticated;


-- 7) 스토리·PvP 연동 (phaseE_3.sql / phaseE_5.sql / guild.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_guild2_sql.mjs 가 일치 확인)
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
end $$;
revoke all on function public.story_complete_phase(int, int, jsonb) from public, anon;
grant execute on function public.story_complete_phase(int, int, jsonb) to authenticated;
create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.story_sweep(int, int, int) from public, anon;
grant execute on function public.story_sweep(int, int, int) to authenticated;
create or replace function public._guild_feed(p_uid uuid, p_src text, p_n int) returns int language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public._guild_feed(uuid, text, int) from public, anon, authenticated;
