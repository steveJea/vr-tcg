-- 스토리 챕터 입장 레벨 제한 (계정 레벨 player_state.level) — 선행: phaseE_2.sql (+ 이후 파일들)
-- ⚠ 이 파일 실행 뒤에는 phaseE_2.sql 을 다시 돌리지 마세요 (_player_unlock_level · _player_json · story_start_phase 가 옛 버전으로 돌아가 제한이 사라짐)
-- 여러 번 실행해도 안전 (함수만, 데이터 변경 없음)
-- 설정은 _player_unlock_level('chapter_N') 한 곳. 클라이언트는 _player_json 의 unlocks.chapters 로 받음
-- 규칙: 그 챕터를 아직 한 페이즈도 클리어하지 않은 경우에만 막음 → 이미 시작한 챕터는 레벨과 상관없이 계속·다시 하기 가능
--       소탕은 클리어한 페이즈만 가능하므로 자연히 영향 없음 (변경 없음)

-- 1) 해금 레벨 (기존 키 그대로 + chapter_2 ~ chapter_11)
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24
    else null end $$;

-- 2) 플레이어 정보: unlocks.chapters = { "2": 7, "3": 9, ... } 추가 (나머지는 phaseE_2 와 동일)
create or replace function public._player_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare ps player_state; mx int; secs int := _stamina_regen_secs(); chs jsonb;
begin
  ps := _player_sync(p_uid); mx := _stamina_max(ps.level);
  select coalesce(jsonb_object_agg(c::text, _player_unlock_level('chapter_' || c)), '{}'::jsonb) into chs
    from generate_series(0, 30) c where _player_unlock_level('chapter_' || c) is not null;
  return jsonb_build_object('ok', true, 'level', ps.level, 'max_level', _player_max_level(), 'xp', ps.xp,
    'xp_next', case when ps.level >= _player_max_level() then 0 else _player_xp_need(ps.level) end,
    'stamina', ps.stamina, 'stamina_max', mx, 'regen_secs', secs,
    'next_regen_secs', case when ps.stamina >= mx then 0 else greatest(0, secs - floor(extract(epoch from (now() - ps.stamina_at)))::int) end,
    'cost', jsonb_build_object('story', _stamina_cost(0, 0), 'quest', 0, 'arcade', 0),
    'unlocks', jsonb_build_object('sweep', _player_unlock_level('sweep'), 'skill', _player_unlock_level('skill'), 'equip', _player_unlock_level('equip'), 'equip_merge', _player_unlock_level('equip_merge'), 'chapters', chs));
end $$;

-- 3) 전투 시작: 레벨 제한 검사 추가 (나머지는 phaseE_2 wrapper 와 동일 — 'phaseE_2 wrapper' 표시 유지해서 phaseE_2 의 보관 로직이 원본으로 착각하지 않게)
create or replace function public.story_start_phase(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_2 wrapper (+ story_level_gate)
declare uid uuid := auth.uid(); b jsonb; d jsonb; cost int := _stamina_cost(p_chapter, p_phase); need int := _player_unlock_level('chapter_' || p_chapter); lv int; started boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _player_sync(uid);
  select data->'battle' into b from story_progress where user_id = uid for update;
  if need is not null then
    select coalesce(jsonb_array_length(data->'cleared'->(p_chapter::text)), 0) > 0 into started from story_progress where user_id = uid;
    if not coalesce(started, false) then
      select level into lv from player_state where user_id = uid;
      if coalesce(lv, 1) < need then raise exception 'level required: chapter % needs level %', p_chapter, need; end if;
    end if;
  end if;
  if b is not null and (b->>'stamina') is not null then perform _player_stamina_add(uid, (b->>'stamina')::int); end if;
  perform _player_stamina_add(uid, -cost);   -- 부족하면 'not enough stamina' (전체 롤백)
  d := _story_start_phase_e0(p_chapter, p_phase);
  d := jsonb_set(d, '{battle,stamina}', to_jsonb(cost));
  update story_progress set data = d where user_id = uid;
  return d;
end $$;

revoke all on function public._player_json(uuid) from public, anon, authenticated;
revoke all on function public.story_start_phase(int, int) from public, anon;
grant execute on function public.story_start_phase(int, int) to authenticated;
