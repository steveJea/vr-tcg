-- ===== 훈련소 2·3단계: 훈련소 레벨업 + 연마소(장비) + 도장(스킬) =====
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: camp.sql · gear_v1.sql · gear_craft.sql(gear_enhance_cost · _gear_mine · _gear_dust_add) · phaseE_6.sql(_skill_cost · story_skill_meta) · gem.sql(_gem_spend)
-- ※ camp.sql 을 다시 실행했다면 이 파일도 다시 실행 (_camp_json · _camp_settle · _camp_guard 를 여기서 덮어씀)
-- 규칙
--  * 훈련소 Lv1~10. 다음 레벨 비용: Lv2 골드 1만 · Lv3 2만 · Lv4 4만 · Lv5 8만 · Lv6 심연석 200 · Lv7 300 · Lv8 500 · Lv9 700 · Lv10 1000 (무료 심연석부터 사용)
--    필요 플레이어 레벨 = 5 × 목표 레벨 + 10 (Lv5 → 35, Lv8 → 50, Lv10 → 60). 레벨마다 훈련 EXP +5% (Lv10 = +45%)
--  * 연마소 (훈련소 Lv5): 장비 1개. 다음 강화 비용(골드·가루)의 50% 를 먼저 내고, +1 2시간 · +2 4시간 · +3 8시간 · +4 12시간 · +5 24시간 뒤 받으면 +1
--    연마 중인 장비는 강화·재설정·분해·매각·거래 불가 (장착·해제·잠금은 가능). 바로 강화(gear_enhance)는 그대로
--  * 도장 (훈련소 Lv8 + 심연석 1500): 스킬 하나. 다음 스킬 레벨 비용(혼·골드)의 50% 를 먼저 내고, 지금 스킬 레벨 × 4시간 뒤 받으면 +1. 도장으로는 Lv7 까지
--    2번째 칸 심연석 1000. 도장 중인 스킬은 바로 레벨업 불가, 그 인재는 거래·분해·합성 재료 불가
--  * 재화가 모자라면 시작 안 함 ('not enough ...'). 시간은 서버 now() 만. 시작 후 취소 없음

-- 1) 테이블
create table if not exists public.camp_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  camp_lv int not null default 1 check (camp_lv between 1 and 10),
  dojo_slots int not null default 0 check (dojo_slots between 0 and 2),
  updated_at timestamptz not null default now());
create table if not exists public.camp_jobs (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('forge', 'dojo')),
  slot int not null default 1,
  gear_id bigint, card_uid text, skill int,
  from_lv int not null, cost jsonb not null,
  started_at timestamptz not null default now(), ends_at timestamptz not null, claimed_at timestamptz);
create unique index if not exists camp_jobs_open_slot on public.camp_jobs (user_id, kind, slot) where claimed_at is null;
create unique index if not exists camp_jobs_open_gear on public.camp_jobs (gear_id) where claimed_at is null and gear_id is not null;
create unique index if not exists camp_jobs_open_skill on public.camp_jobs (user_id, card_uid, skill) where claimed_at is null and card_uid is not null;
do $$ declare t text; begin
  foreach t in array array['camp_state', 'camp_jobs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', t || '_own', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop; end $$;

-- 2) 수치
create or replace function public._camp_lv_cost(p_to int) returns jsonb language sql immutable as $$
  select case p_to when 2 then '{"gold":10000}' when 3 then '{"gold":20000}' when 4 then '{"gold":40000}' when 5 then '{"gold":80000}'
    when 6 then '{"gem":200}' when 7 then '{"gem":300}' when 8 then '{"gem":500}' when 9 then '{"gem":700}' when 10 then '{"gem":1000}' end::jsonb $$;
create or replace function public._camp_lv_need(p_to int) returns int language sql immutable as $$ select 5 * p_to + 10 $$;
create or replace function public._camp_lv_mult(p_lv int) returns numeric language sql immutable as $$ select 1 + 0.05 * (greatest(p_lv, 1) - 1) $$;
create or replace function public._camp_forge_lv() returns int language sql immutable as $$ select 5 $$;
create or replace function public._camp_dojo_lv() returns int language sql immutable as $$ select 8 $$;
create or replace function public._camp_dojo_cost(p_slot int) returns int language sql immutable as $$ select case p_slot when 1 then 1500 when 2 then 1000 end $$;
create or replace function public._camp_dojo_max() returns int language sql immutable as $$ select 7 $$;
create or replace function public._camp_forge_hours(p_to int) returns int language sql immutable as $$ select case p_to when 1 then 2 when 2 then 4 when 3 then 8 when 4 then 12 when 5 then 24 end $$;
create or replace function public._camp_half(n numeric) returns int language sql immutable as $$ select ceil(coalesce(n, 0) * 0.5)::int $$;

-- 3) 도우미
create or replace function public._camp_st(p_uid uuid) returns camp_state language plpgsql security definer set search_path = public as $$
declare s camp_state; begin
  insert into camp_state (user_id) values (p_uid) on conflict do nothing;
  select * into s from camp_state where user_id = p_uid; return s; end $$;
-- 지금 받으면 들어올 EXP (상한 반영, 훈련소 레벨 배율 포함)
create or replace function public._camp_pending2(e jsonb, p_last timestamptz, plv int, mult numeric) returns int language plpgsql stable security definer set search_path = public as $$
declare hrs numeric; amt int; lv int; ex int; cap int; need int := 0; l int;
begin
  if e is null or p_last is null then return 0; end if;
  hrs := least(_camp_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0));
  amt := floor(_camp_rate(plv) * mult * hrs)::int;
  lv := greatest(1, coalesce((e->>'level')::int, 1)); ex := greatest(0, coalesce((e->>'exp')::int, 0));
  cap := _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv);
  if lv >= cap then return 0; end if;
  for l in lv..cap - 1 loop need := need + l * 100; end loop;
  return greatest(0, least(amt, need - ex));
end $$;

create or replace function public._camp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare plv int := _camp_plv(p_uid); owned jsonb := _camp_owned(p_uid); cs camp_state := _camp_st(p_uid); m numeric := _camp_lv_mult(cs.camp_lv);
begin
  if plv >= _camp_need_level(1) then insert into camp_slots (user_id, slot) values (p_uid, 1) on conflict do nothing; end if;
  return jsonb_build_object('ok', true, 'now', now(), 'level', plv, 'rate', round(_camp_rate(plv) * m, 1), 'max_hours', _camp_max_hours(), 'cap_minus', 5,
    'camp_lv', cs.camp_lv, 'camp_max', 10, 'mult', m,
    'next', case when cs.camp_lv < 10 then jsonb_build_object('lv', cs.camp_lv + 1, 'cost', _camp_lv_cost(cs.camp_lv + 1), 'need_level', _camp_lv_need(cs.camp_lv + 1)) end,
    'forge_lv', _camp_forge_lv(), 'dojo_lv', _camp_dojo_lv(), 'dojo_slots', cs.dojo_slots, 'dojo_max', _camp_dojo_max(),
    'dojo_next_cost', case when cs.dojo_slots < 2 then _camp_dojo_cost(cs.dojo_slots + 1) end,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'slot', j.slot, 'gear_id', j.gear_id, 'card_uid', j.card_uid, 'skill', j.skill,
              'from', j.from_lv, 'cost', j.cost, 'started_at', j.started_at, 'ends_at', j.ends_at, 'done', j.ends_at <= now(),
              'card', case when j.card_uid is not null then (select o->>'id' from jsonb_array_elements(owned) o where o->>'uid' = j.card_uid limit 1) end,
              'gear_def', case when j.gear_id is not null then (select g.def_id from player_gear g where g.id = j.gear_id) end) order by j.kind, j.slot)
              from camp_jobs j where j.user_id = p_uid and j.claimed_at is null), '[]'::jsonb),
    'slots', (select jsonb_agg(jsonb_build_object('slot', s, 'need_level', _camp_need_level(s), 'cost', _camp_cost(s), 'open', c.slot is not null,
                'uid', c.card_uid, 'last_at', c.last_at,
                'card', (select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1),
                'pending', coalesce(_camp_pending2((select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1), c.last_at, plv, m), 0)) order by s)
              from generate_series(1, 5) s left join camp_slots c on c.user_id = p_uid and c.slot = s));
end $$;

create or replace function public._camp_settle(p_uid uuid, p_slot int, plv int) returns jsonb language plpgsql security definer set search_path = public as $$
declare c camp_slots; d jsonb; owned jsonb; idx int; e jsonb; amt int; before int; m numeric := _camp_lv_mult((_camp_st(p_uid)).camp_lv);
begin
  select * into c from camp_slots where user_id = p_uid and slot = p_slot for update;
  if c.card_uid is null then return null; end if;
  select data into d from story_progress where user_id = p_uid;
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1, t.e into idx, e from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'uid' = c.card_uid limit 1;
  if idx is null then update camp_slots set card_uid = null, last_at = null where user_id = p_uid and slot = p_slot; return null; end if;
  amt := _camp_pending2(e, c.last_at, plv, m);
  update camp_slots set last_at = now() where user_id = p_uid and slot = p_slot;
  if amt <= 0 then return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', 0, 'from', coalesce((e->>'level')::int, 1), 'level', coalesce((e->>'level')::int, 1)); end if;
  before := coalesce((e->>'level')::int, 1);
  e := _story_gain(e, amt, _camp_grade(e->>'id'));
  update story_progress set data = jsonb_set(d, array['owned', idx::text], e), updated_at = now() where user_id = p_uid;
  return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', amt, 'from', before, 'level', (e->>'level')::int);
end $$;

-- 4) 훈련소 레벨업
create or replace function public.camp_levelup() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; nx int; cost jsonb; plv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  select * into cs from camp_state where user_id = uid for update;
  if cs.camp_lv >= 10 then raise exception 'max camp level'; end if;
  nx := cs.camp_lv + 1; plv := _camp_plv(uid);
  if plv < _camp_lv_need(nx) then raise exception 'need level %', _camp_lv_need(nx); end if;
  -- 레벨이 바뀌기 전 배율로 지금까지 쌓인 EXP 정산 (배율 소급 방지)
  perform 1 from story_progress where user_id = uid for update;
  perform _camp_settle(uid, s.slot, plv) from camp_slots s where s.user_id = uid and s.card_uid is not null;
  cost := _camp_lv_cost(nx);
  if (cost->>'gold') is not null then perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_levelup'); end if;
  if (cost->>'gem') is not null then perform _gem_spend(uid, (cost->>'gem')::int, 'camp_levelup', jsonb_build_object('lv', nx)); end if;
  update camp_state set camp_lv = nx, updated_at = now() where user_id = uid;
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;

-- 5) 연마소
create or replace function public.camp_forge_start(p_gear bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; c gear_enhance_cost; cost jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  if (_camp_st(uid)).camp_lv < _camp_forge_lv() then raise exception 'forge locked'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'forge' and claimed_at is null) then raise exception 'forge busy'; end if;
  g := _gear_mine(uid, p_gear);
  if g.plus >= 5 then raise exception 'max plus'; end if;
  select * into c from gear_enhance_cost where plus = g.plus + 1;
  if c.plus is null then raise exception 'no cost'; end if;
  cost := jsonb_build_object('gold', _camp_half(c.gold), 'dust', _camp_half(c.dust));
  perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_forge');   -- 'not enough gold'
  perform _gear_dust_add(uid, -(cost->>'dust')::int);                                           -- 'not enough dust'
  insert into camp_jobs (user_id, kind, slot, gear_id, from_lv, cost, ends_at)
    values (uid, 'forge', 1, g.id, g.plus, cost, now() + make_interval(hours => _camp_forge_hours(g.plus + 1)));
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;

-- 6) 도장
create or replace function public.camp_dojo_unlock() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  if cs.camp_lv < _camp_dojo_lv() then raise exception 'dojo locked'; end if;
  if cs.dojo_slots >= 2 then raise exception 'already open'; end if;
  n := cs.dojo_slots + 1;
  perform _gem_spend(uid, _camp_dojo_cost(n), 'camp_dojo', jsonb_build_object('slot', n));   -- 'not enough gem'
  update camp_state set dojo_slots = n, updated_at = now() where user_id = uid;
  return _camp_json(uid) || jsonb_build_object('spent', jsonb_build_object('gem', _camp_dojo_cost(n)));
end $$;

create or replace function public.camp_dojo_start(p_slot int, p_uid text, p_skill int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cs camp_state; e jsonb; g text; ul int; lv int; c jsonb; cost jsonb; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  cs := _camp_st(uid);
  if p_slot is null or p_slot < 1 or p_slot > cs.dojo_slots then raise exception 'dojo locked'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'dojo' and slot = p_slot and claimed_at is null) then raise exception 'slot busy'; end if;
  if exists (select 1 from camp_jobs where user_id = uid and kind = 'dojo' and card_uid = p_uid and skill = p_skill and claimed_at is null) then raise exception 'already training'; end if;
  select o into e from jsonb_array_elements(_camp_owned(uid)) o where o->>'uid' = p_uid limit 1;
  if e is null then raise exception 'not owned'; end if;
  select m.unlock into ul from story_skill_meta m where m.card_id = e->>'id' and m.idx = p_skill;
  if ul is null then raise exception 'invalid skill'; end if;
  if coalesce((e->>'level')::int, 1) < ul then raise exception 'skill locked'; end if;
  sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
  lv := greatest(1, coalesce((sl->>p_skill::text)::int, 1));
  if lv >= _camp_dojo_max() then raise exception 'dojo max'; end if;
  g := _camp_grade(e->>'id');
  c := _skill_cost(g, lv);
  cost := jsonb_build_object('gold', _camp_half((c->>'gold')::int), 'soul', _camp_half((c->>'soul')::int));
  perform _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int, 'soul', -(cost->>'soul')::int), 'camp_dojo');   -- 'not enough gold/soul'
  insert into camp_jobs (user_id, kind, slot, card_uid, skill, from_lv, cost, ends_at)
    values (uid, 'dojo', p_slot, p_uid, p_skill, lv, cost, now() + make_interval(hours => 4 * lv));
  return _camp_json(uid) || jsonb_build_object('spent', cost);
end $$;

-- 7) 받기 (연마·도장 중 끝난 것 모두, p_job 주면 그것만)
create or replace function public.camp_job_claim(p_job bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); j camp_jobs; got jsonb := '[]'::jsonb; d jsonb; owned jsonb; i int; e jsonb; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform set_config('camp.ok', '1', true);
  for j in select * from camp_jobs where user_id = uid and claimed_at is null and ends_at <= now() and (p_job is null or id = p_job) order by id for update loop
    if j.kind = 'forge' then
      update player_gear set plus = least(5, plus + 1) where id = j.gear_id and user_id = uid and plus = j.from_lv;
      got := got || jsonb_build_array(jsonb_build_object('kind', 'forge', 'gear_id', j.gear_id, 'ok', found, 'level', j.from_lv + 1));
    else
      d := _story_lock(uid); owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = j.card_uid;
      if i is not null then
        e := owned->i; sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
        e := e || jsonb_build_object('skillLv', sl || jsonb_build_object(j.skill::text, greatest(coalesce((sl->>j.skill::text)::int, 1), j.from_lv + 1)),
                                     'soulSpent', coalesce((e->>'soulSpent')::int, 0) + coalesce((j.cost->>'soul')::int, 0));
        perform _story_save(uid, jsonb_set(d, array['owned', i::text], e));
      end if;
      got := got || jsonb_build_array(jsonb_build_object('kind', 'dojo', 'card_uid', j.card_uid, 'skill', j.skill, 'ok', i is not null, 'level', j.from_lv + 1));
    end if;
    update camp_jobs set claimed_at = now() where id = j.id;
  end loop;
  perform set_config('camp.ok', '', true);
  if p_job is not null and jsonb_array_length(got) = 0 then raise exception 'not done'; end if;
  return _camp_json(uid) || jsonb_build_object('got', got);
end $$;

-- 8) 보호
-- 연마 중 장비: 강화 단계·부옵션 변경·삭제(분해·매각·거래) 거부. 장착·해제·잠금은 허용
create or replace function public._camp_gear_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('camp.ok', true), '') = '1' then return coalesce(new, old); end if;
  if exists (select 1 from camp_jobs j where j.gear_id = old.id and j.claimed_at is null) then
    if tg_op = 'DELETE' or new.plus is distinct from old.plus or new.opts is distinct from old.opts or new.user_id is distinct from old.user_id then
      raise exception '연마소에 있는 장비는 강화·재설정·분해·매각·거래할 수 없어요 (gear in forge)';
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists camp_gear_guard on public.player_gear;
create trigger camp_gear_guard before update or delete on public.player_gear for each row execute function public._camp_gear_guard();

-- 훈련·도장 중 인재: 보유 목록에서 빠지면 거부. 도장 중인 스킬 레벨이 바뀌면 거부 (도장 받기 제외)
create or replace function public._camp_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare nw jsonb := case when jsonb_typeof(new.data->'owned') = 'array' then new.data->'owned' else '[]'::jsonb end;
        od jsonb := case when jsonb_typeof(old.data->'owned') = 'array' then old.data->'owned' else '[]'::jsonb end;
begin
  if exists (select 1 from (select card_uid from camp_slots where user_id = new.user_id and card_uid is not null
                            union select card_uid from camp_jobs where user_id = new.user_id and kind = 'dojo' and claimed_at is null) c
             where not exists (select 1 from jsonb_array_elements(nw) o where o->>'uid' = c.card_uid)
               and exists (select 1 from jsonb_array_elements(od) o where o->>'uid' = c.card_uid)) then
    raise exception '훈련소·도장에 있는 인재는 거래·분해·합성 재료로 쓸 수 없어요. 먼저 훈련소에서 빼 주세요 (card in camp)';
  end if;
  if coalesce(current_setting('camp.ok', true), '') <> '1' and exists (select 1 from camp_jobs j where j.user_id = new.user_id and j.kind = 'dojo' and j.claimed_at is null
       and (select o->'skillLv'->>j.skill::text from jsonb_array_elements(nw) o where o->>'uid' = j.card_uid limit 1)
           is distinct from (select o->'skillLv'->>j.skill::text from jsonb_array_elements(od) o where o->>'uid' = j.card_uid limit 1)) then
    raise exception '도장에서 수련 중인 스킬은 지금 올릴 수 없어요 (skill in dojo)';
  end if;
  return new;
end $$;

revoke all on function public._camp_lv_cost(int), public._camp_lv_need(int), public._camp_lv_mult(int), public._camp_forge_lv(), public._camp_dojo_lv(), public._camp_dojo_cost(int),
  public._camp_dojo_max(), public._camp_forge_hours(int), public._camp_half(numeric), public._camp_st(uuid), public._camp_pending2(jsonb, timestamptz, int, numeric),
  public._camp_json(uuid), public._camp_settle(uuid, int, int), public._camp_gear_guard(), public._camp_guard() from public, anon, authenticated;
revoke all on function public.camp_levelup(), public.camp_forge_start(bigint), public.camp_dojo_unlock(), public.camp_dojo_start(int, text, int), public.camp_job_claim(bigint) from public, anon;
grant execute on function public.camp_levelup(), public.camp_forge_start(bigint), public.camp_dojo_unlock(), public.camp_dojo_start(int, text, int), public.camp_job_claim(bigint) to authenticated;
