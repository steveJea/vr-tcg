-- ===== 훈련소 1단계 (인재를 넣어 두면 시간이 지나며 EXP 가 쌓임) =====
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: phaseE_1.sql(_wallet_add) · phaseE_2.sql(_player_sync) · gem.sql(_gem_spend) · story_levels.sql / story_merge.sql(_story_gain · _story_cap · 인재 uid)
-- 규칙
--  * 칸 5개: 1칸 플레이어 Lv10 무료 · 2칸 Lv20 골드 2만 · 3칸 Lv35 골드 5만 · 4칸 Lv50 심연석 300 · 5칸 Lv70 심연석 800
--  * EXP: 칸 하나에 시간당 20 + 플레이어 레벨 × 1.5 (받을 때 레벨 기준). 마지막으로 받은 뒤 최대 24시간까지만 쌓임
--  * 레벨 상한: min(등급 최대 레벨(EX 포함), 플레이어 레벨 − 5). 상한에 닿으면 더 안 쌓임
--  * 시간은 서버 now() 만 사용. 훈련 중인 인재도 덱·스토리·PvP 사용 가능
--  * 훈련 중인 인재는 거래 등록·분해·합성 재료로 못 씀 (story_progress 에서 빠지려 하면 거부하는 트리거)

-- 1) 테이블 (행이 있으면 그 칸은 열린 것)
create table if not exists public.camp_slots (
  user_id  uuid not null references auth.users(id) on delete cascade,
  slot     int  not null check (slot between 1 and 5),
  card_uid text,
  last_at  timestamptz,
  opened_at timestamptz not null default now(),
  primary key (user_id, slot));
create unique index if not exists camp_slots_card on public.camp_slots (user_id, card_uid) where card_uid is not null;
alter table public.camp_slots enable row level security;
revoke all on public.camp_slots from anon, authenticated;
drop policy if exists camp_slots_own on public.camp_slots;
create policy camp_slots_own on public.camp_slots for select using (user_id = auth.uid());
grant select on public.camp_slots to authenticated;

-- 2) 수치
create or replace function public._camp_need_level(s int) returns int language sql immutable as $$ select case s when 1 then 10 when 2 then 20 when 3 then 35 when 4 then 50 when 5 then 70 end $$;
create or replace function public._camp_cost(s int) returns jsonb language sql immutable as $$
  select case s when 1 then '{}'::jsonb when 2 then '{"gold":20000}'::jsonb when 3 then '{"gold":50000}'::jsonb when 4 then '{"gem":300}'::jsonb when 5 then '{"gem":800}'::jsonb end $$;
create or replace function public._camp_rate(plv int) returns numeric language sql immutable as $$ select 20 + 1.5 * greatest(plv, 1) $$;
create or replace function public._camp_max_hours() returns int language sql immutable as $$ select 24 $$;
create or replace function public._camp_cap(g text, ex int, plv int) returns int language sql immutable as $$ select least(_story_cap(g, ex), plv - 5) $$;

-- 3) 도우미
create or replace function public._camp_plv(p_uid uuid) returns int language plpgsql security definer set search_path = public as $$
declare lv int; begin select (_player_sync(p_uid)).level into lv; return coalesce(lv, 1); end $$;
create or replace function public._camp_owned(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' end from story_progress where user_id = p_uid), '[]'::jsonb) $$;
create or replace function public._camp_grade(p_id text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select grade from story_card_pool where id = p_id), 'NORMAL') $$;
-- 지금 받으면 들어올 EXP (상한 반영)
create or replace function public._camp_pending(e jsonb, p_last timestamptz, plv int) returns int language plpgsql stable security definer set search_path = public as $$
declare hrs numeric; amt int; lv int; ex int; cap int; need int := 0; l int;
begin
  if e is null or p_last is null then return 0; end if;
  hrs := least(_camp_max_hours(), greatest(0, extract(epoch from (now() - p_last)) / 3600.0));
  amt := floor(_camp_rate(plv) * hrs)::int;
  lv := greatest(1, coalesce((e->>'level')::int, 1)); ex := greatest(0, coalesce((e->>'exp')::int, 0));
  cap := _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv);
  if lv >= cap then return 0; end if;
  for l in lv..cap - 1 loop need := need + l * 100; end loop;
  return greatest(0, least(amt, need - ex));
end $$;

create or replace function public._camp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare plv int := _camp_plv(p_uid); owned jsonb := _camp_owned(p_uid);
begin
  -- 1칸은 Lv10 되면 자동으로 열림
  if plv >= _camp_need_level(1) then insert into camp_slots (user_id, slot) values (p_uid, 1) on conflict do nothing; end if;
  return jsonb_build_object('ok', true, 'now', now(), 'level', plv, 'rate', _camp_rate(plv), 'max_hours', _camp_max_hours(), 'cap_minus', 5,
    'slots', (select jsonb_agg(jsonb_build_object('slot', s, 'need_level', _camp_need_level(s), 'cost', _camp_cost(s), 'open', c.slot is not null,
                'uid', c.card_uid, 'last_at', c.last_at,
                'card', (select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1),
                'pending', coalesce(_camp_pending((select o from jsonb_array_elements(owned) o where o->>'uid' = c.card_uid limit 1), c.last_at, plv), 0)) order by s)
              from generate_series(1, 5) s left join camp_slots c on c.user_id = p_uid and c.slot = s));
end $$;

-- 한 칸 정산 (story_progress 를 이미 잠근 상태에서 호출). 반환 { uid, exp, from, level }
create or replace function public._camp_settle(p_uid uuid, p_slot int, plv int) returns jsonb language plpgsql security definer set search_path = public as $$
declare c camp_slots; d jsonb; owned jsonb; idx int; e jsonb; amt int; before int;
begin
  select * into c from camp_slots where user_id = p_uid and slot = p_slot for update;
  if c.card_uid is null then return null; end if;
  select data into d from story_progress where user_id = p_uid;
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1, t.e into idx, e from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'uid' = c.card_uid limit 1;
  if idx is null then update camp_slots set card_uid = null, last_at = null where user_id = p_uid and slot = p_slot; return null; end if;
  amt := _camp_pending(e, c.last_at, plv);
  update camp_slots set last_at = now() where user_id = p_uid and slot = p_slot;
  if amt <= 0 then return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', 0, 'from', coalesce((e->>'level')::int, 1), 'level', coalesce((e->>'level')::int, 1)); end if;
  before := coalesce((e->>'level')::int, 1);
  e := _story_gain(e, amt, _camp_grade(e->>'id'));
  update story_progress set data = jsonb_set(d, array['owned', idx::text], e), updated_at = now() where user_id = p_uid;
  return jsonb_build_object('uid', c.card_uid, 'id', e->>'id', 'exp', amt, 'from', before, 'level', (e->>'level')::int);
end $$;

-- 4) 공개 함수
create or replace function public.camp_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  return _camp_json(uid);
end $$;

create or replace function public.camp_unlock(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); plv int; cost jsonb; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot is null or p_slot not between 1 and 5 then raise exception 'bad slot'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  if exists (select 1 from camp_slots where user_id = uid and slot = p_slot) then raise exception 'already open'; end if;
  if p_slot > 1 and not exists (select 1 from camp_slots where user_id = uid and slot = p_slot - 1) then raise exception 'open previous'; end if;
  plv := _camp_plv(uid);
  if plv < _camp_need_level(p_slot) then raise exception 'need level %', _camp_need_level(p_slot); end if;
  cost := _camp_cost(p_slot);
  if (cost->>'gold') is not null then w := _wallet_add(uid, jsonb_build_object('gold', -(cost->>'gold')::int), 'camp_unlock'); end if;   -- 부족하면 'not enough gold'
  if (cost->>'gem') is not null then perform _gem_spend(uid, (cost->>'gem')::int, 'camp_unlock', jsonb_build_object('slot', p_slot)); end if;
  insert into camp_slots (user_id, slot) values (uid, p_slot);
  return _camp_json(uid) || jsonb_build_object('spent', cost, 'wallet', w);
end $$;

create or replace function public.camp_put(p_slot int, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c camp_slots; e jsonb; plv int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  select * into c from camp_slots where user_id = uid and slot = p_slot for update;
  if c.user_id is null then raise exception 'slot locked'; end if;
  if c.card_uid is not null then raise exception 'slot busy'; end if;
  if exists (select 1 from camp_slots where user_id = uid and card_uid = p_uid) then raise exception 'already training'; end if;
  select o into e from jsonb_array_elements(_camp_owned(uid)) o where o->>'uid' = p_uid limit 1;
  if e is null then raise exception 'not owned'; end if;
  plv := _camp_plv(uid);
  if coalesce((e->>'level')::int, 1) >= _camp_cap(_camp_grade(e->>'id'), coalesce((e->>'ex')::int, 0), plv) then raise exception 'at cap'; end if;
  update camp_slots set card_uid = p_uid, last_at = now() where user_id = uid and slot = p_slot;
  return _camp_json(uid);
end $$;

-- 빼기: 쌓인 EXP 는 먼저 정산하고 뺌
create or replace function public.camp_remove(p_slot int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform 1 from story_progress where user_id = uid for update;
  r := _camp_settle(uid, p_slot, _camp_plv(uid));
  update camp_slots set card_uid = null, last_at = null where user_id = uid and slot = p_slot;
  return _camp_json(uid) || jsonb_build_object('got', case when r is null then '[]'::jsonb else jsonb_build_array(r) end);
end $$;

-- 모두 받기
create or replace function public.camp_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); plv int; s int; r jsonb; got jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('camp:' || uid::text));
  perform 1 from story_progress where user_id = uid for update;
  plv := _camp_plv(uid);
  for s in select slot from camp_slots where user_id = uid and card_uid is not null order by slot loop
    r := _camp_settle(uid, s, plv);
    if r is not null and (r->>'exp')::int > 0 then got := got || jsonb_build_array(r); end if;
  end loop;
  return _camp_json(uid) || jsonb_build_object('got', got);
end $$;

-- 5) 보호: 훈련 중인 인재가 보유 목록에서 빠지는 변경(거래 등록·분해·합성 재료 등)은 거부
create or replace function public._camp_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from camp_slots c where c.user_id = new.user_id and c.card_uid is not null
             and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(new.data->'owned') = 'array' then new.data->'owned' else '[]'::jsonb end) o where o->>'uid' = c.card_uid)
             and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(old.data->'owned') = 'array' then old.data->'owned' else '[]'::jsonb end) o where o->>'uid' = c.card_uid)) then
    raise exception '훈련소에 있는 인재는 거래·분해·합성 재료로 쓸 수 없어요. 먼저 훈련소에서 빼 주세요 (card in camp)';
  end if;
  return new;
end $$;
drop trigger if exists camp_guard on public.story_progress;
create trigger camp_guard before update of data on public.story_progress for each row execute function public._camp_guard();

revoke all on function public._camp_need_level(int), public._camp_cost(int), public._camp_rate(int), public._camp_max_hours(), public._camp_cap(text, int, int),
  public._camp_plv(uuid), public._camp_owned(uuid), public._camp_grade(text), public._camp_pending(jsonb, timestamptz, int), public._camp_json(uuid),
  public._camp_settle(uuid, int, int), public._camp_guard() from public, anon, authenticated;
revoke all on function public.camp_status(), public.camp_unlock(int), public.camp_put(int, text), public.camp_remove(int), public.camp_claim() from public, anon;
grant execute on function public.camp_status(), public.camp_unlock(int), public.camp_put(int, text), public.camp_remove(int), public.camp_claim() to authenticated;
