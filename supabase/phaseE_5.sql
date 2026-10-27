-- phaseE_5.sql — 소탕 (스토리 반복 클리어 자동 정산)
-- 실행 순서: phaseE_2 → phaseE_3 → (phaseE_4) → phaseE_5. 여러 번 실행해도 안전.
-- 조건: 플레이어 Lv5 이상(_player_unlock_level('sweep')), 이미 클리어한 스토리 페이즈만, 1/5/10회.
-- 1회당 행동력 _stamina_cost (6). 보상 = 반복 클리어와 동일 (골드·순수한 피·이상한 조각/영혼 확률·플레이어 XP).
-- 첫 클리어 보상 없음, 카드 전투 EXP 없음, 퀘스트 소탕 없음.
-- 확인용: select public.sweep_info();

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

-- 탐침: 조건·비용·예상 보상
create or replace function public.sweep_info() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 5, 'unlock_level', _player_unlock_level('sweep'), 'runs', jsonb_build_array(1, 5, 10),
    'stamina_per_run', _stamina_cost(0, 0), 'xp_per_run', _stamina_cost(0, 0) * _player_xp_per_stamina(),
    'ch1_normal_run', _story_drop_calc(1, 'normal', false, 6, 0.99, 0.99), 'shard_chance', 0.3, 'soul_chance_ch5plus', 0.2)
$$;
revoke all on function public.sweep_info() from public, anon;
grant execute on function public.sweep_info() to authenticated;
