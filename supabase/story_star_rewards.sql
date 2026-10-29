-- 스토리 별 보상 (챕터별 ★9 · ★18 · 전부) — 선행: story_stars.sql. 여러 번 실행해도 안전 (함수만, 데이터 삭제 없음)
-- 마나 전투 페이즈만 셈: 챕터 1~ 전부 · 챕터 0 은 P4 만. 최대 = 3 × 그 페이즈 수
-- 별은 story_progress.data.stars 의 최고 별 중 실제로 클리어한(data.cleared) 페이즈만 합산
-- 받은 기록: data.starClaims = { "<챕터>": ["9", "18", "all"] } · 보상: 소환권(story_gacha.tickets) + 골드(_wallet_add)
create or replace function public._star_milestones() returns jsonb language sql immutable as $$
  select '[{"key":"9","need":9,"tickets":1,"gold":3000},{"key":"18","need":18,"tickets":1,"gold":5000},{"key":"all","need":null,"tickets":2,"gold":10000}]'::jsonb $$;

-- 챕터 별 현황: { total, max, milestones:[{key, need, tickets, gold, claimed, ready}] }
create or replace function public._star_chapter(d jsonb, p_chapter int) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare mx int; tot int; cl jsonb := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb); got jsonb := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb); ms jsonb := '[]'::jsonb; m jsonb; need int;
begin
  select 3 * count(*) into mx from story_phase_config where chapter = p_chapter and (p_chapter >= 1 or phase = 4);
  select coalesce(sum(least(3, greatest(0, (s.value)::int))), 0) into tot
    from jsonb_each_text(case when jsonb_typeof(d->'stars'->(p_chapter::text)) = 'object' then d->'stars'->(p_chapter::text) else '{}'::jsonb end) s
    where s.key ~ '^\d+$' and cl @> to_jsonb(s.key::int)
      and exists (select 1 from story_phase_config c where c.chapter = p_chapter and c.phase = s.key::int and (p_chapter >= 1 or c.phase = 4));
  tot := least(tot, mx);
  for m in select * from jsonb_array_elements(_star_milestones()) loop
    need := coalesce((m->>'need')::int, mx);
    if mx = 0 or need > mx or (m->>'key' <> 'all' and need >= mx) then continue; end if;   -- 최대보다 크거나 '전부'와 같으면 생략
    ms := ms || (m || jsonb_build_object('need', need, 'claimed', got @> to_jsonb(m->>'key'), 'ready', tot >= need));
  end loop;
  return jsonb_build_object('chapter', p_chapter, 'total', tot, 'max', mx, 'milestones', ms);
end $$;

-- 전체 챕터 현황 (지도 표시용)
create or replace function public.story_star_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; r jsonb := '[]'::jsonb; c int;
begin
  if me is null then raise exception 'login required'; end if;
  select data into d from story_progress where user_id = me; d := coalesce(d, '{}'::jsonb);
  for c in select distinct chapter from story_phase_config order by 1 loop r := r || _star_chapter(d, c); end loop;
  return r;
end $$;

-- 받기: 서버가 별을 다시 합산 · 한 번만
create or replace function public.story_star_claim(p_chapter int, p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; st jsonb; m jsonb; got jsonb; t int; w jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  d := _story_lock(me);
  st := _star_chapter(d, p_chapter);
  select x into m from jsonb_array_elements(st->'milestones') x where x->>'key' = p_key;
  if m is null then raise exception 'invalid milestone'; end if;
  if (m->>'claimed')::boolean then raise exception 'already claimed'; end if;
  if not (m->>'ready')::boolean then raise exception 'not enough stars'; end if;
  got := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb) || to_jsonb(p_key);
  if jsonb_typeof(d->'starClaims') is distinct from 'object' then d := jsonb_set(d, '{starClaims}', '{}'::jsonb); end if;
  d := _story_save(me, jsonb_set(d, array['starClaims', p_chapter::text], got));
  insert into story_gacha (user_id, last_draw) values (me, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + (m->>'tickets')::int, updated_at = now() where user_id = me returning tickets into t;
  w := _wallet_add(me, jsonb_build_object('gold', (m->>'gold')::int), 'star_reward');
  return jsonb_build_object('ok', true, 'tickets', t, 'wallet', w, 'gave', jsonb_build_object('tickets', (m->>'tickets')::int, 'gold', (m->>'gold')::int), 'status', _star_chapter(d, p_chapter));
end $$;
revoke all on function public._star_milestones(), public._star_chapter(jsonb, int) from public, anon, authenticated;
revoke all on function public.story_star_status(), public.story_star_claim(int, text) from public, anon;
grant execute on function public.story_star_status(), public.story_star_claim(int, text) to authenticated;
select 'story_star_rewards ok' as result;
