-- ===== 장비 PR3: 전투 스냅샷에 장비·증표 붙이기 =====
-- 선행: pvp.sql(_pvp_snap · pvp_card_meta) · gear_v1.sql. 여러 번 실행해도 안전 (create or replace)
-- PvP·토벌·세력전 덱은 모두 _pvp_snap 으로 서버가 만든 스냅샷을 씀 → 여기서 장비를 붙이면 클라이언트가 장비를 꾸밀 수 없음
-- 카드마다 gear: [{ def, stat, pct, plus, opts }] (장착한 것만), sigil: 증표 단계(없으면 null). 모드 배율(PvP·세력전 50%, 증표 +3)은
-- 전투 코어(js/gear-core.js GEAR_MODE)가 적용. 참고 값: gear_mode_config

create or replace function public._gear_snap(p_user uuid, p_card text) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'gear', coalesce((select jsonb_agg(jsonb_build_object('def', g.def_id, 'stat', d.main_stat, 'pct', d.main_pct, 'plus', g.plus, 'opts', g.opts) order by d.slot)
                      from player_gear g join gear_defs d on d.id = g.def_id where g.user_id = p_user and g.equipped_card = p_card), '[]'::jsonb),
    'sigil', (select to_jsonb(s.plus) from player_sigils s where s.user_id = p_user and s.card_id = p_card and s.plus is not null))
$$;
revoke all on function public._gear_snap(uuid, text) from public, anon, authenticated;

-- pvp.sql 의 _pvp_snap 과 같고, 카드마다 _gear_snap 결과(gear·sigil)만 덧붙임
create or replace function public._pvp_snap(p_user uuid, p_uids jsonb, p_league text) returns jsonb language plpgsql stable set search_path = public as $$
declare owned jsonb; out jsonb := '[]'::jsonb; u text; o jsonb; m pvp_card_meta; cost int := 0; ids text[] := '{}';
begin
  if jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) not between 1 and 5 then raise exception 'deck size'; end if;
  select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' else '[]'::jsonb end into owned from story_progress where user_id = p_user;
  for u in select jsonb_array_elements_text(p_uids) loop
    if u like 'guest:%' then raise exception 'card not owned'; end if;
    select x into o from jsonb_array_elements(coalesce(owned, '[]'::jsonb)) x where x->>'uid' = u limit 1;
    if o is null then raise exception 'card not owned'; end if;
    select * into m from pvp_card_meta where id = o->>'id';
    if m.id is null then raise exception 'unknown card'; end if;
    if m.id = any(ids) then raise exception 'duplicate card'; end if;
    if p_league = 'hr' and m.grade not in ('NORMAL','RARE','HIGH RARE') then raise exception 'grade not allowed'; end if;
    ids := ids || m.id; cost := cost + m.cost;
    out := out || (jsonb_build_object('uid', u, 'id', o->>'id', 'level', coalesce((o->>'level')::int, 1), 'ex', coalesce((o->>'ex')::int, 0),
      'exb', coalesce((o->>'exb')::numeric, 0), 'boost', coalesce(o->'boost', '{}'::jsonb), 'skillLv', coalesce(o->'skillLv', '{}'::jsonb))
      || _gear_snap(p_user, o->>'id'));
  end loop;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', out, 'cost', cost);
end $$;
revoke all on function public._pvp_snap(uuid, jsonb, text) from public, anon, authenticated;
