-- =====================================================================
-- [조직] 1단계 (길드 코어) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(지갑) · phaseE_2.sql(레벨·행동력) · gem.sql(심연석) · admin.sql · pvp.sql · pvp_tier.sql
-- 역할: 보스(boss) · 간부(officer) · 조직원(member). 개인 재화: 충성 (loyalty_wallet + loyalty_ledger)
-- 창설: 계정 Lv.15+ · 골드 50,000 또는 심연석 300 (기존 _wallet_add / _gem_spend 로 차감)
-- 세력(조직 EXP): 스토리(행동력 6 = 1, 하루 100) · PvP 승리 +10 (하루 100). 기여한 만큼 본인 충성 +
-- 탈퇴 후 24시간 가입 불가 · 추방된 조직은 72시간 재가입 불가 · 추방 하루 5명
-- 쓰기는 전부 서버 함수로만. 테이블은 클라이언트 접근 불가 (RLS + revoke)
-- 나중 단계: 집결(출석) · 의뢰(퀘스트) · 토벌(레이드) · 전쟁 → _guild_exp / _loyalty_add 를 호출해 연결
-- 확인용: select public.guild_status();
-- =====================================================================

-- 1) 테이블
create table if not exists public.guild_level_table (
  level int primary key, exp_total bigint not null, max_members int not null, officers int not null, unlock text);
insert into public.guild_level_table (level, exp_total, max_members, officers, unlock) values
  (1, 0, 15, 1, '기본 상점'), (2, 1000, 18, 2, null), (3, 3000, 21, 2, '상점 확장'), (4, 7000, 24, 3, '토벌 (준비 중)'), (5, 15000, 27, 3, '엠블럼 프레임'),
  (6, 30000, 30, 4, '전쟁 (준비 중)'), (7, 60000, 33, 4, null), (8, 120000, 36, 5, null), (9, 240000, 38, 5, null), (10, 480000, 40, 5, null)
on conflict (level) do update set exp_total = excluded.exp_total, max_members = excluded.max_members, officers = excluded.officers, unlock = excluded.unlock;

create table if not exists public.guilds (
  id          bigint generated always as identity primary key,
  name        text not null,
  name_key    text not null unique,                 -- lower(name) — 대소문자 무시 중복 금지
  emblem      int not null default 1 check (emblem between 1 and 12),
  intro       text not null default '' check (char_length(intro) <= 60),
  notice      text not null default '' check (char_length(notice) <= 100),
  join_mode   text not null default 'open' check (join_mode in ('open', 'approval', 'closed')),
  level       int not null default 1,
  exp         bigint not null default 0 check (exp >= 0),
  boss        uuid not null references auth.users(id),
  renamed_at  timestamptz,
  created_at  timestamptz not null default now()
);
create table if not exists public.guild_members (
  user_id       uuid primary key references auth.users(id) on delete cascade,   -- 한 사람 한 조직
  guild_id      bigint not null references public.guilds(id) on delete cascade,
  role          text not null default 'member' check (role in ('boss', 'officer', 'member')),
  joined_at     timestamptz not null default now(),
  loyalty_total bigint not null default 0,           -- 이 조직에서 쌓은 충성 (누적, 순위용)
  seen_at       timestamptz not null default now()
);
create index if not exists guild_members_gid on public.guild_members (guild_id);
create table if not exists public.guild_requests (
  id         bigint generated always as identity primary key,
  guild_id   bigint not null references public.guilds(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('apply', 'invite')),
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  by_user    uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '3 days'
);
create unique index if not exists guild_requests_pending on public.guild_requests (guild_id, user_id, kind) where status = 'pending';
create table if not exists public.guild_cooldowns (
  user_id  uuid not null references auth.users(id) on delete cascade,
  guild_id bigint not null default 0,                -- 0 = 모든 조직 (탈퇴), 그 외 = 그 조직만 (추방)
  until    timestamptz not null,
  primary key (user_id, guild_id)
);
create table if not exists public.guild_log (
  id bigint generated always as identity primary key, guild_id bigint, actor uuid, action text not null, target uuid, meta jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create index if not exists guild_log_gid on public.guild_log (guild_id, created_at desc);
create table if not exists public.guild_exp_log (
  id bigint generated always as identity primary key, guild_id bigint not null, user_id uuid, amount int not null, src text not null,
  day date not null, ref text not null default gen_random_uuid()::text, created_at timestamptz not null default now(), unique (guild_id, ref));
create index if not exists guild_exp_log_day on public.guild_exp_log (user_id, day, src);
create table if not exists public.loyalty_wallet (
  user_id uuid primary key references auth.users(id) on delete cascade, balance bigint not null default 0 check (balance >= 0), updated_at timestamptz not null default now());
create table if not exists public.loyalty_ledger (
  id bigint generated always as identity primary key, user_id uuid not null references auth.users(id) on delete cascade, delta int not null, after bigint not null,
  reason text not null check (char_length(reason) <= 40), ref text not null default gen_random_uuid()::text, meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), unique (user_id, ref));
create index if not exists loyalty_ledger_user on public.loyalty_ledger (user_id, created_at desc);
create table if not exists public.guild_shop (
  item text primary key, ord int not null default 0, price int not null check (price > 0), gives jsonb not null,
  limit_kind text check (limit_kind in ('day', 'week', 'once')), limit_n int, min_level int not null default 1, active boolean not null default true);
insert into public.guild_shop (item, ord, price, gives, limit_kind, limit_n, min_level) values
  ('ticket',    1,  300, '{"tickets":1}',          'week', 2,    1),
  ('stamina30', 2,  100, '{"stamina":30}',         'day',  1,    1),
  ('gold5k',    3,   80, '{"gold":5000}',          null,   null, 1),
  ('shard5',    4,  150, '{"shard":5}',            null,   null, 3),
  ('soul3',     5,  150, '{"soul":3}',             null,   null, 3),
  ('frame',     6, 2000, '{"title":"guild_frame"}', 'once', 1,   5)
on conflict (item) do update set ord = excluded.ord, price = excluded.price, gives = excluded.gives, limit_kind = excluded.limit_kind, limit_n = excluded.limit_n, min_level = excluded.min_level;
create table if not exists public.guild_titles (user_id uuid not null references auth.users(id) on delete cascade, title text not null, created_at timestamptz not null default now(), primary key (user_id, title));

do $$ declare t text; begin
  foreach t in array array['guild_level_table', 'guilds', 'guild_members', 'guild_requests', 'guild_cooldowns', 'guild_log', 'guild_exp_log', 'loyalty_wallet', 'loyalty_ledger', 'guild_shop', 'guild_titles'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- 2) 수치
create or replace function public._guild_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._guild_min_level() returns int language sql immutable as $$ select 15 $$;
create or replace function public._guild_cost_gold() returns int language sql immutable as $$ select 50000 $$;
create or replace function public._guild_cost_gem() returns int language sql immutable as $$ select 300 $$;
create or replace function public._guild_rename_gem() returns int language sql immutable as $$ select 500 $$;
create or replace function public._guild_feed_cap(p_src text) returns int language sql immutable as $$ select case p_src when 'story' then 100 when 'pvp' then 100 else 1000 end $$;

-- 3) 내부 도우미
create or replace function public._guild_lock(p_gid bigint) returns void language sql as $$ select pg_advisory_xact_lock(hashtext('guild:' || p_gid)) $$;
create or replace function public._guild_me(p_uid uuid) returns guild_members language sql stable security definer set search_path = public as $$
  select * from guild_members where user_id = p_uid $$;
create or replace function public._guild_name_ok(p_name text) returns text language plpgsql immutable as $$
declare n text := btrim(coalesce(p_name, '')); w text;
begin
  if n !~ '^[가-힣A-Za-z0-9]{2,8}$' then raise exception 'bad name'; end if;
  foreach w in array array['운영', '관리자', 'admin', 'gm', '시발', '씨발', '병신', '좆', '섹스', '느금', '애미', '애비', '지랄', '꺼져', 'fuck', 'shit', 'sex'] loop
    if position(w in lower(n)) > 0 then raise exception 'bad name'; end if;
  end loop;
  return n;
end $$;
create or replace function public._guild_text_ok(p_text text, p_max int) returns text language plpgsql immutable as $$
declare t text := btrim(coalesce(p_text, '')); w text;
begin
  if char_length(t) > p_max then raise exception 'too long'; end if;
  foreach w in array array['시발', '씨발', '병신', '좆', '섹스', '느금', '애미'] loop
    if position(w in t) > 0 then raise exception 'bad word'; end if;
  end loop;
  return t;
end $$;
create or replace function public._guild_log(p_gid bigint, p_actor uuid, p_action text, p_target uuid, p_meta jsonb) returns void language sql security definer set search_path = public as $$
  insert into guild_log (guild_id, actor, action, target, meta) values (p_gid, p_actor, p_action, p_target, coalesce(p_meta, '{}'::jsonb)) $$;
-- 쿨타임 확인: 탈퇴(전체) 또는 이 조직에서 추방
create or replace function public._guild_cd_check(p_uid uuid, p_gid bigint) returns void language plpgsql stable security definer set search_path = public as $$
declare u timestamptz;
begin
  select max(until) into u from guild_cooldowns where user_id = p_uid and guild_id in (0, coalesce(p_gid, 0)) and until > now();
  if u is not null then raise exception 'cooldown until %', to_char(u at time zone 'Asia/Seoul', 'MM-DD HH24:MI'); end if;
end $$;
-- 멤버 추가 (조직 잠금 상태에서 호출). 인원·중복·쿨타임 확인, 이 사람의 다른 대기 신청은 취소
create or replace function public._guild_add_member(p_gid bigint, p_uid uuid, p_by uuid) returns void language plpgsql security definer set search_path = public as $$
declare g guilds; cnt int; mx int;
begin
  select * into g from guilds where id = p_gid;
  if g.id is null then raise exception 'no such guild'; end if;
  if exists (select 1 from guild_members where user_id = p_uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(p_uid, p_gid);
  select count(*) into cnt from guild_members where guild_id = p_gid;
  select max_members into mx from guild_level_table where level = g.level;
  if cnt >= coalesce(mx, 15) then raise exception 'guild full'; end if;
  insert into guild_members (user_id, guild_id, role) values (p_uid, p_gid, 'member');
  update guild_requests set status = 'cancelled' where user_id = p_uid and status = 'pending';
  perform _guild_log(p_gid, coalesce(p_by, p_uid), 'join', p_uid, '{}');
end $$;
-- 충성 증감 (+ 획득, − 사용). p_ref 중복이면 null. 부족하면 'not enough loyalty'
create or replace function public._loyalty_add(p_uid uuid, p_delta int, p_reason text, p_ref text, p_meta jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare b bigint;
begin
  if coalesce(p_delta, 0) = 0 then return null; end if;
  insert into loyalty_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select balance into b from loyalty_wallet where user_id = p_uid for update;
  if p_ref is not null and exists (select 1 from loyalty_ledger where user_id = p_uid and ref = p_ref) then return null; end if;
  b := b + p_delta;
  if b < 0 then raise exception 'not enough loyalty'; end if;
  update loyalty_wallet set balance = b, updated_at = now() where user_id = p_uid;
  insert into loyalty_ledger (user_id, delta, after, reason, ref, meta) values (p_uid, p_delta, b, left(p_reason, 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  if p_delta > 0 then update guild_members set loyalty_total = loyalty_total + p_delta where user_id = p_uid; end if;
  return b;
end $$;
-- 세력(조직 EXP) 추가 + 레벨업. p_ref 중복이면 0. 반환 실제 추가량
create or replace function public._guild_exp(p_gid bigint, p_uid uuid, p_n int, p_src text, p_ref text) returns int language plpgsql security definer set search_path = public as $$
declare g guilds; lv int;
begin
  if coalesce(p_n, 0) <= 0 then return 0; end if;
  select * into g from guilds where id = p_gid for update;
  if g.id is null then return 0; end if;
  if p_ref is not null and exists (select 1 from guild_exp_log where guild_id = p_gid and ref = p_ref) then return 0; end if;
  insert into guild_exp_log (guild_id, user_id, amount, src, day, ref) values (p_gid, p_uid, p_n, p_src, _guild_day(), coalesce(p_ref, gen_random_uuid()::text));
  select max(level) into lv from guild_level_table where exp_total <= g.exp + p_n;
  update guilds set exp = exp + p_n, level = greatest(level, coalesce(lv, 1)) where id = p_gid;
  if coalesce(lv, 1) > g.level then perform _guild_log(p_gid, null, 'level_up', null, jsonb_build_object('level', lv)); end if;
  return p_n;
end $$;
-- 활동 → 세력 + 본인 충성 (하루 상한). 조직이 없으면 아무것도 안 함. 스토리/PvP 함수에서 호출
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
-- 조직 요약 / 상세 JSON
create or replace function public._guild_card(p_gid bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', g.id, 'name', g.name, 'emblem', g.emblem, 'intro', g.intro, 'join_mode', g.join_mode, 'level', g.level,
    'members', (select count(*) from guild_members where guild_id = g.id), 'max_members', (select max_members from guild_level_table where level = g.level),
    'boss_name', (select coalesce(nickname, '보스') from profiles where id = g.boss))
  from guilds g where g.id = p_gid $$;
create or replace function public._guild_shop_left(p_uid uuid, s guild_shop) returns int language sql stable security definer set search_path = public as $$
  select case when s.limit_kind is null then null else greatest(0, s.limit_n - (select count(*)::int from loyalty_ledger l where l.user_id = p_uid and l.reason = 'shop:' || s.item
    and l.created_at >= case s.limit_kind when 'day' then (_guild_day()::timestamp at time zone 'Asia/Seoul')
                                          when 'week' then (date_trunc('week', _guild_day()::timestamp) at time zone 'Asia/Seoul') else '-infinity'::timestamptz end)) end $$;
revoke all on function public._guild_lock(bigint), public._guild_me(uuid), public._guild_log(bigint, uuid, text, uuid, jsonb), public._guild_cd_check(uuid, bigint),
  public._guild_add_member(bigint, uuid, uuid), public._loyalty_add(uuid, int, text, text, jsonb), public._guild_exp(bigint, uuid, int, text, text),
  public._guild_feed(uuid, text, int), public._guild_card(bigint), public._guild_shop_left(uuid, guild_shop) from public, anon, authenticated;

-- 4) 공개 RPC
-- 내 조직 상태. 조직 없음: { ok, guild:null, list, invites, applies, cooldown, can_create, cost } / 있음: { ok, guild, me, members, requests, shop, levels, log, loyalty }
create or replace function public.guild_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; lv int; cd timestamptz; res jsonb; lt guild_level_table; nx guild_level_table;
begin
  if uid is null then raise exception 'login required'; end if;
  update guild_requests set status = 'cancelled' where status = 'pending' and expires_at < now() and (user_id = uid or guild_id = (select guild_id from guild_members where user_id = uid));
  select coalesce((select level from player_state where user_id = uid), 1) into lv;
  res := jsonb_build_object('ok', true, 'loyalty', coalesce((select balance from loyalty_wallet where user_id = uid), 0), 'my_level', lv);
  m := _guild_me(uid);
  if m.user_id is null then
    select max(until) into cd from guild_cooldowns where user_id = uid and guild_id = 0 and until > now();
    return res || jsonb_build_object('guild', null, 'cooldown', cd, 'min_level', _guild_min_level(), 'cost', jsonb_build_object('gold', _guild_cost_gold(), 'gem', _guild_cost_gem()),
      'list', (select coalesce(jsonb_agg(_guild_card(x.id) order by x.lv desc, x.n desc), '[]'::jsonb) from (
                 select g2.id, g2.level lv, (select count(*) from guild_members where guild_id = g2.id) n from guilds g2 where g2.join_mode <> 'closed' order by g2.level desc, g2.exp desc limit 20) x),
      'invites', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'guild', _guild_card(r.guild_id)) order by r.id desc), '[]'::jsonb) from guild_requests r where r.user_id = uid and r.kind = 'invite' and r.status = 'pending'),
      'applies', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'guild', _guild_card(r.guild_id)) order by r.id desc), '[]'::jsonb) from guild_requests r where r.user_id = uid and r.kind = 'apply' and r.status = 'pending'));
  end if;
  update guild_members set seen_at = now() where user_id = uid;
  select * into g from guilds where id = m.guild_id;
  select * into lt from guild_level_table where level = g.level;
  select * into nx from guild_level_table where level = g.level + 1;
  return res || jsonb_build_object(
    'guild', _guild_card(g.id) || jsonb_build_object('notice', g.notice, 'exp', g.exp, 'exp_cur', lt.exp_total, 'exp_next', nx.exp_total, 'officers_max', lt.officers, 'boss', g.boss),
    'me', jsonb_build_object('role', m.role, 'joined_at', m.joined_at, 'loyalty_total', m.loyalty_total,
      'today', (select coalesce(jsonb_object_agg(src, s), '{}'::jsonb) from (select src, sum(amount) s from guild_exp_log where user_id = uid and day = _guild_day() group by src) t),
      'can_claim', m.role <> 'boss' and exists (select 1 from guild_members b where b.guild_id = g.id and b.role = 'boss' and b.seen_at < now() - interval '14 days')),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', gm.user_id, 'name', coalesce(p.nickname, '조직원'), 'role', gm.role, 'loyalty_total', gm.loyalty_total,
                  'joined_at', gm.joined_at, 'seen_at', gm.seen_at,
                  'card', (select o->>'id' from story_progress sp, jsonb_array_elements(coalesce(sp.data->'owned', '[]'::jsonb)) o where sp.user_id = gm.user_id and o->>'uid' = sp.data->>'leader' limit 1))
                order by case gm.role when 'boss' then 0 when 'officer' then 1 else 2 end, gm.loyalty_total desc), '[]'::jsonb)
                from guild_members gm left join profiles p on p.id = gm.user_id where gm.guild_id = g.id),
    'requests', case when m.role in ('boss', 'officer') then (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'user_id', r.user_id, 'name', coalesce(p.nickname, '플레이어'),
                  'level', coalesce((select level from player_state where user_id = r.user_id), 1)) order by r.id), '[]'::jsonb)
                from guild_requests r left join profiles p on p.id = r.user_id where r.guild_id = g.id and r.kind = 'apply' and r.status = 'pending') else '[]'::jsonb end,
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price, 'gives', s.gives, 'min_level', s.min_level, 'left', _guild_shop_left(uid, s),
                'owned', s.limit_kind = 'once' and exists (select 1 from guild_titles t where t.user_id = uid and t.title = s.gives->>'title')) order by s.ord), '[]'::jsonb) from guild_shop s where s.active),
    'levels', (select jsonb_agg(jsonb_build_object('level', level, 'exp', exp_total, 'members', max_members, 'officers', officers, 'unlock', unlock) order by level) from guild_level_table),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('action', l.action, 'actor', (select nickname from profiles where id = l.actor), 'target', (select nickname from profiles where id = l.target), 'meta', l.meta, 'at', l.created_at) order by l.id desc), '[]'::jsonb)
            from (select * from guild_log where guild_id = g.id order by id desc limit 20) l));
end $$;

-- 조직 찾기 (이름 검색, 비공개 제외)
create or replace function public.guild_search(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return (select coalesce(jsonb_agg(_guild_card(g.id) order by g.level desc, g.exp desc), '[]'::jsonb) from (
    select * from guilds where name_key like '%' || lower(replace(replace(btrim(coalesce(p_q, '')), '%', ''), '_', '')) || '%' order by level desc, exp desc limit 20) g);
end $$;

-- 창설: p_pay = 'gold' | 'gem'
create or replace function public.guild_create(p_name text, p_emblem int, p_intro text, p_join text, p_pay text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text; gid bigint; lv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  select coalesce((select level from player_state where user_id = uid), 1) into lv;
  if lv < _guild_min_level() then raise exception 'level required %', _guild_min_level(); end if;
  if exists (select 1 from guild_members where user_id = uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(uid, 0);
  n := _guild_name_ok(p_name);
  if p_emblem is null or p_emblem not between 1 and 12 then raise exception 'bad emblem'; end if;
  if coalesce(p_join, 'open') not in ('open', 'approval', 'closed') then raise exception 'bad join mode'; end if;
  perform pg_advisory_xact_lock(hashtext('guildname:' || lower(n)));
  if exists (select 1 from guilds where name_key = lower(n)) then raise exception 'name taken'; end if;
  if p_pay = 'gold' then perform _wallet_add(uid, jsonb_build_object('gold', -_guild_cost_gold()), 'guild_create');
  elsif p_pay = 'gem' then perform _gem_spend(uid, _guild_cost_gem(), 'guild_create', jsonb_build_object('name', n));
  else raise exception 'bad pay'; end if;
  insert into guilds (name, name_key, emblem, intro, join_mode, boss) values (n, lower(n), p_emblem, _guild_text_ok(p_intro, 60), coalesce(p_join, 'open'), uid) returning id into gid;
  insert into guild_members (user_id, guild_id, role) values (uid, gid, 'boss');
  update guild_requests set status = 'cancelled' where user_id = uid and status = 'pending';
  perform _guild_log(gid, uid, 'create', null, jsonb_build_object('pay', p_pay));
  return jsonb_build_object('ok', true, 'id', gid);
end $$;

-- 설정 변경: p_patch { intro, emblem, join_mode (보스) · notice (보스·간부) · name (보스, 심연석 500, 30일 1회) }
create or replace function public.guild_update(p_patch jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; g guilds; n text;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform _guild_lock(m.guild_id);
  select * into g from guilds where id = m.guild_id;
  if p_patch ? 'notice' then
    if m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
    update guilds set notice = _guild_text_ok(p_patch->>'notice', 100) where id = g.id;
  end if;
  if p_patch ?| array['intro', 'emblem', 'join_mode', 'name'] and m.role <> 'boss' then raise exception 'no permission'; end if;
  if p_patch ? 'intro' then update guilds set intro = _guild_text_ok(p_patch->>'intro', 60) where id = g.id; end if;
  if p_patch ? 'emblem' then
    if (p_patch->>'emblem')::int not between 1 and 12 then raise exception 'bad emblem'; end if;
    update guilds set emblem = (p_patch->>'emblem')::int where id = g.id;
  end if;
  if p_patch ? 'join_mode' then
    if p_patch->>'join_mode' not in ('open', 'approval', 'closed') then raise exception 'bad join mode'; end if;
    update guilds set join_mode = p_patch->>'join_mode' where id = g.id;
  end if;
  if p_patch ? 'name' then
    n := _guild_name_ok(p_patch->>'name');
    if g.renamed_at is not null and g.renamed_at > now() - interval '30 days' then raise exception 'rename cooldown'; end if;
    perform pg_advisory_xact_lock(hashtext('guildname:' || lower(n)));
    if exists (select 1 from guilds where name_key = lower(n) and id <> g.id) then raise exception 'name taken'; end if;
    perform _gem_spend(uid, _guild_rename_gem(), 'guild_rename', jsonb_build_object('guild', g.id, 'name', n));
    update guilds set name = n, name_key = lower(n), renamed_at = now() where id = g.id;
  end if;
  perform _guild_log(g.id, uid, 'update', null, p_patch - 'notice' - 'intro' || case when p_patch ? 'notice' then '{"notice":true}'::jsonb else '{}'::jsonb end);
  return jsonb_build_object('ok', true);
end $$;

-- 가입 신청: 공개 = 바로 가입 · 승인제 = 신청 (대기 최대 3개) · 비공개 = 불가
create or replace function public.guild_apply(p_gid bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g guilds;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  perform _guild_lock(p_gid);
  select * into g from guilds where id = p_gid;
  if g.id is null then raise exception 'no such guild'; end if;
  if exists (select 1 from guild_members where user_id = uid) then raise exception 'already in guild'; end if;
  perform _guild_cd_check(uid, p_gid);
  if g.join_mode = 'closed' then raise exception 'closed'; end if;
  if g.join_mode = 'open' then perform _guild_add_member(p_gid, uid, null); return jsonb_build_object('ok', true, 'joined', true); end if;
  if (select count(*) from guild_requests where user_id = uid and kind = 'apply' and status = 'pending' and expires_at > now()) >= 3 then raise exception 'too many requests'; end if;
  insert into guild_requests (guild_id, user_id, kind, by_user) values (p_gid, uid, 'apply', uid) on conflict do nothing;
  return jsonb_build_object('ok', true, 'joined', false, 'pending', true);
end $$;

-- 초대 (보스·간부, 닉네임으로)
create or replace function public.guild_invite(p_nick text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; t uuid;
begin
  m := _guild_me(uid);
  if m.user_id is null or m.role not in ('boss', 'officer') then raise exception 'no permission'; end if;
  select id into t from profiles where nickname = btrim(p_nick) limit 1;
  if t is null then raise exception 'no such player'; end if;
  if exists (select 1 from guild_members where user_id = t) then raise exception 'already in guild'; end if;
  if (select count(*) from guild_requests where guild_id = m.guild_id and kind = 'invite' and created_at > now() - interval '1 day') >= 20 then raise exception 'too many invites'; end if;
  insert into guild_requests (guild_id, user_id, kind, by_user) values (m.guild_id, t, 'invite', uid) on conflict do nothing;
  perform _guild_log(m.guild_id, uid, 'invite', t, '{}');
  return jsonb_build_object('ok', true);
end $$;

-- 신청/초대 응답: 가입 신청은 그 조직 보스·간부가, 초대는 초대받은 본인이. 본인 신청 취소도 여기서 (p_accept = false)
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
end $$;

-- 탈퇴: 24시간 가입 불가. 보스는 넘기기 전엔 못 나감 (혼자면 해산)
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
end $$;
create or replace function public.guild_disband() returns jsonb language plpgsql security definer set search_path = public as $$
declare m guild_members := _guild_me(auth.uid());
begin
  if m.user_id is null or m.role <> 'boss' then raise exception 'no permission'; end if;
  if (select count(*) from guild_members where guild_id = m.guild_id) > 1 then raise exception 'members remain'; end if;
  return guild_leave();
end $$;

-- 추방: 보스 = 누구든 (보스 제외) · 간부 = 조직원만. 하루 5명. 그 조직 72시간 재가입 불가
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
end $$;

-- 간부 임명/해제 (보스). 간부 수는 레벨표 상한
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
end $$;

-- 보스 넘기기 (보스 → 조직원 중 1명, 이전 보스는 간부)
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
end $$;

-- 보스 14일 미접속: 가장 오래된 간부 (간부 없으면 충성 누적 1위 조직원) 가 보스 승계
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
end $$;

-- 충성 상점 (개인 충성 사용, 조직 레벨로 해금, 하루/주/1회 제한)
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
end $$;

revoke all on function public.guild_status(), public.guild_search(text), public.guild_create(text, int, text, text, text), public.guild_update(jsonb), public.guild_apply(bigint),
  public.guild_invite(text), public.guild_respond(bigint, boolean), public.guild_leave(), public.guild_disband(), public.guild_kick(uuid), public.guild_set_role(uuid, text),
  public.guild_transfer(uuid), public.guild_claim_boss(), public.guild_shop_buy(text) from public, anon;
grant execute on function public.guild_status(), public.guild_search(text), public.guild_create(text, int, text, text, text), public.guild_update(jsonb), public.guild_apply(bigint),
  public.guild_invite(text), public.guild_respond(bigint, boolean), public.guild_leave(), public.guild_disband(), public.guild_kick(uuid), public.guild_set_role(uuid, text),
  public.guild_transfer(uuid), public.guild_claim_boss(), public.guild_shop_buy(text) to authenticated;

-- 5) 관리자: 목록 · 이름 변경 · 공지 지우기 · 해산 (admin_log 기록)
create or replace function public.admin_guild_list(p_q text default null) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return (select coalesce(jsonb_agg(_guild_card(g.id) || jsonb_build_object('exp', g.exp, 'notice', g.notice, 'created_at', g.created_at) order by g.id desc), '[]'::jsonb)
    from (select * from guilds where p_q is null or name_key like '%' || lower(p_q) || '%' order by id desc limit 200) g);
end $$;
create or replace function public.admin_guild_edit(p_gid bigint, p_action text, p_value text, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
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
end $$;
revoke all on function public.admin_guild_list(text), public.admin_guild_edit(bigint, text, text, text) from public, anon;
grant execute on function public.admin_guild_list(text), public.admin_guild_edit(bigint, text, text, text) to authenticated;


-- 6) 스토리·PvP 연동 (phaseE_2.sql / pvp_tier.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_guild_sql.mjs 가 일치 확인)
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
end $$;
revoke all on function public._player_add_xp(uuid, int, boolean) from public, anon, authenticated;
create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
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
end $$;
revoke all on function public.pvp_report(bigint, int, int) from public, anon;
grant execute on function public.pvp_report(bigint, int, int) to authenticated;
