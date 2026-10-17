-- =====================================================================
-- VR: Abyss Gate - 스토리 진행 서버 확정 (추가분)
-- 사용법: story.sql, gacha.sql 실행 후 SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
-- 클라이언트는 story_progress 를 읽기만 하고, 모든 쓰기는 아래 SECURITY DEFINER 함수로만.
-- =====================================================================

-- 1) 직접 쓰기 차단 (읽기 정책 story_select_own 은 유지)
drop policy if exists "story_insert_own" on public.story_progress;
drop policy if exists "story_update_own" on public.story_progress;
revoke insert, update, delete on public.story_progress from anon, authenticated;
grant select on public.story_progress to authenticated;

-- 2) 페이즈 설정: 보상은 서버가 결정 (챕터 2부터는 reward_grade 없음 = 스탯 포인트만)
create table if not exists public.story_phase_config (
  chapter      int  not null,
  phase        int  not null,
  type         text not null check (type in ('normal','boss')),
  points       int  not null check (points between 0 and 100),
  reward_grade text check (reward_grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE')),
  primary key (chapter, phase)
);
alter table public.story_phase_config enable row level security;
drop policy if exists "phase_cfg_read" on public.story_phase_config;
create policy "phase_cfg_read" on public.story_phase_config for select using (true);
insert into public.story_phase_config (chapter, phase, type, points, reward_grade) values
  (1,1,'normal',3,'NORMAL'), (1,2,'normal',3,'NORMAL'), (1,3,'normal',3,'NORMAL'), (1,4,'normal',3,'NORMAL'), (1,5,'boss',5,'NORMAL')
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade;

-- 스탯 포인트 1당 상승량은 클라이언트(js/story-data.js statPerPoint)에서 적용: ATK+2 / HP+10 / DEF+2
-- 전투 최소 시간 (초): 전투 시작 기록 후 이 시간 이전의 클리어 요청은 거부
create or replace function public._story_min_battle_secs() returns int language sql immutable as $$ select 3 $$;

-- 3) 내부 도우미
-- 첫 클리어로 얻을 수 있는 포인트 총량
create or replace function public._story_earned(d jsonb) returns int language sql stable set search_path = public as $$
  select coalesce(sum(c.points), 0)::int
  from jsonb_each(coalesce(d->'cleared', '{}'::jsonb)) ch(k, v)
  cross join lateral jsonb_array_elements_text(case when jsonb_typeof(ch.v) = 'array' then ch.v else '[]'::jsonb end) p(no)
  join story_phase_config c on c.chapter::text = ch.k and c.phase::text = p.no
$$;
-- 분배한 포인트 합계
create or replace function public._story_used(d jsonb) returns int language sql immutable as $$
  select coalesce(sum(greatest(0, coalesce((o->'boost'->>'ATK')::int,0)) + greatest(0, coalesce((o->'boost'->>'HP')::int,0)) + greatest(0, coalesce((o->'boost'->>'DEF')::int,0))), 0)::int
  from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o
$$;
-- 행 잠금 후 data 반환 (없으면 생성)
create or replace function public._story_lock(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_progress (user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from story_progress where user_id = uid for update;
  return coalesce(d, '{}'::jsonb);
end $$;
create or replace function public._story_save(uid uuid, d jsonb) returns jsonb language plpgsql set search_path = public as $$
begin
  d := jsonb_set(d, '{updatedAt}', to_jsonb((extract(epoch from clock_timestamp()) * 1000)::bigint));
  update story_progress set data = d, updated_at = now() where user_id = uid;
  return d;
end $$;
revoke all on function public._story_earned(jsonb), public._story_used(jsonb), public._story_lock(uuid), public._story_save(uuid, jsonb) from public, anon, authenticated;

-- 4) 공개 RPC (모두 갱신된 data 를 반환)
-- 오프닝·시작 스토리 본 표시
create or replace function public.story_mark_seen(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if p_key not in ('openingSeen', 'startSeen') then raise exception 'invalid key'; end if;
  d := _story_lock(uid);
  return _story_save(uid, jsonb_set(d, array[p_key], 'true'::jsonb));
end $$;

-- 시작 캐릭터 선택 (1회). 기존 보유 카드(뽑기 등)는 유지하고 시작 카드를 맨 앞(리더)으로
create or replace function public.story_choose_starter(p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb;
begin
  if p_id not in ('2000600126', '2000200044', '2001500294') then raise exception 'invalid starter'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') <> '' then raise exception 'starter already chosen'; end if;
  select coalesce(jsonb_agg(o), '[]'::jsonb) into owned from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o where o->>'id' <> p_id;
  owned := jsonb_build_array(jsonb_build_object('id', p_id, 'boost', '{}'::jsonb, 'count', 1)) || owned;
  d := jsonb_set(jsonb_set(d, '{starter}', to_jsonb(p_id)), '{owned}', owned);
  if d->'points' is null then d := jsonb_set(d, '{points}', '0'::jsonb); end if;
  if d->'cleared' is null then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
  return _story_save(uid, d);
end $$;

-- 전투 시작 기록 (열린 페이즈만)
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  if coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  -- 열림 조건: 같은 챕터의 이전 페이즈 모두 클리어 + 이전 챕터 전체 클리어
  if exists (
    select 1 from story_phase_config c
    where (c.chapter < p_chapter or (c.chapter = p_chapter and c.phase < p_phase))
      and not (coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase))
  ) then raise exception 'phase locked'; end if;
  d := jsonb_set(d, '{battle}', jsonb_build_object('chapter', p_chapter, 'phase', p_phase, 'at', (extract(epoch from clock_timestamp()))::bigint));
  return _story_save(uid, d);
end $$;

-- 페이즈 클리어: 시작 기록·최소 전투 시간 확인. 첫 클리어만 보상(카드+포인트), 재클리어는 아무것도 없음
create or replace function public.story_complete_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; owned jsonb;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then d := jsonb_set(d, '{owned}', owned || jsonb_build_array(jsonb_build_object('id', rid, 'boost', '{}'::jsonb, 'count', 1))); end if;
    end if;
  end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid);
end $$;

-- 스탯 분배: p_alloc = {"카드id": {"ATK":n,"HP":n,"DEF":n}, ...} (추가할 포인트). 보유 카드만, 0 이상 정수, 보유 포인트 이내
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int := 0; idx int; pts int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = k limit 1;
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
  end loop;
  if total > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - total));
  return _story_save(uid, d);
end $$;

revoke all on function public.story_mark_seen(text), public.story_choose_starter(text), public.story_start_phase(int, int), public.story_complete_phase(int, int), public.story_allocate(jsonb) from public, anon;
grant execute on function public.story_mark_seen(text), public.story_choose_starter(text), public.story_start_phase(int, int), public.story_complete_phase(int, int), public.story_allocate(jsonb) to authenticated;

-- 5) 기존 데이터 정리: 잘못된 클리어 기록 제거, 포인트를 (첫 클리어 총량 − 분배량) 이내로
update public.story_progress sp set data = jsonb_set(sp.data, '{cleared}', coalesce((
    select jsonb_object_agg(ch.k, (select coalesce(jsonb_agg(distinct p.no::int), '[]'::jsonb) from jsonb_array_elements_text(ch.v) p(no)
                                   where exists (select 1 from public.story_phase_config c where c.chapter::text = ch.k and c.phase::text = p.no)))
    from jsonb_each(sp.data->'cleared') ch(k, v) where jsonb_typeof(ch.v) = 'array'), '{}'::jsonb))
  where jsonb_typeof(sp.data->'cleared') = 'object';
update public.story_progress sp set data = jsonb_set(sp.data, '{points}', to_jsonb(greatest(0, least(coalesce((sp.data->>'points')::int, 0), public._story_earned(sp.data) - public._story_used(sp.data)))))
  where sp.data ? 'points' or sp.data ? 'cleared';
