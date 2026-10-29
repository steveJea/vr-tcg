-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 quest_complete, story_complete_phase, story_dismantle 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-3: 재화 드롭 · 시련의 탑 재화 보상 · 분해 수익(재화) · 남은 카드 EXP → 순수한 피 이전
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (이전은 유저마다 1회만)
-- 선행: story_*.sql, quest.sql, admin.sql, phaseE_1.sql, phaseE_2.sql
--
-- 스토리 페이즈 클리어 드롭 (행동력 6 기준, ch = 챕터)
--   골드       6 × 20 × (1 + 0.25 × (ch − 1))   (챕터1 120) · 첫 클리어 ×3 · 보스 ×2 (겹침)
--   순수한 피  6 × 2 = 12                        · 첫 클리어 ×3 · 보스 ×2 (겹침)
--   이상한 조각 보스 3 확정 / 일반 첫 클리어 1 확정 / 일반 반복 30% 확률 1 · 나올 때 챕터 2개마다 +1 (ch1·2 +0, ch3·4 +1 ...)
--   각성자의 혼 챕터 5 이상만: 보스 5 / 일반 첫 클리어 2 / 일반 반복 20% 확률 1
-- 시련의 탑 첫 클리어 (층 f): 골드 50 + 5f · 10층마다 순수한 피 50 × (f/10) · 25층마다 이상한 조각 5 · 100층 이후 50층마다 각성자의 혼 10 (소환권 보상은 그대로)
-- 분해: 대상 카드 없이 재화로 (EXP 지급 없음). 전투 EXP 로 카드 레벨업은 그대로
--   등급별  N / R / HR / SR / UR / MR
--   골드      20 / 50 / 120 / 300 / 800 / 2000
--   순수한 피 10 / 30 /  80 / 200 / 500 / 1200   + 그 카드 누적 EXP 50% 를 피로 (EXP 10 = 피 1)
--   각성자의 혼 0 / 1 / 3 / 10 / 30 / 80
--   공용 포인트 환급은 그대로. 리더·잠금 카드는 분해 불가
-- 이전: 모든 카드의 현재 레벨 안 남은 EXP 를 순수한 피로 (EXP 10 = 피 1, 버림), 레벨은 그대로, 남은 EXP 는 0
-- 확인용: select public.economy_rates();
-- =====================================================================

-- 1) 수치
create or replace function public._exp_per_blood() returns int language sql immutable as $$ select 10 $$;
create or replace function public._dismantle_yield(p_grade text) returns jsonb language sql immutable as $$
  select case p_grade
    when 'NORMAL'      then '{"gold":20,"blood":10,"soul":0}'
    when 'RARE'        then '{"gold":50,"blood":30,"soul":1}'
    when 'HIGH RARE'   then '{"gold":120,"blood":80,"soul":3}'
    when 'SUPER RARE'  then '{"gold":300,"blood":200,"soul":10}'
    when 'ULTRA RARE'  then '{"gold":800,"blood":500,"soul":30}'
    when 'MYTHIC RARE' then '{"gold":2000,"blood":1200,"soul":80}'
    else '{"gold":20,"blood":10,"soul":0}' end::jsonb
$$;
create or replace function public._quest_currency(p_floor int) returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'gold', 50 + 5 * p_floor,
    'blood', case when p_floor % 10 = 0 then 50 * (p_floor / 10) end,
    'shard', case when p_floor % 25 = 0 then 5 end,
    'soul', case when p_floor > 100 and p_floor % 50 = 0 then 10 end))
$$;
-- 드롭 계산 (p_roll1/2: 0~1 난수. 테스트에서 고정값을 넣을 수 있게 분리)
create or replace function public._story_drop_calc(p_chapter int, p_type text, p_first boolean, p_cost int, p_roll1 numeric, p_roll2 numeric) returns jsonb language plpgsql immutable as $$
declare m int := (case when p_first then 3 else 1 end) * (case when p_type = 'boss' then 2 else 1 end); g int; b int; s int := 0; o int := 0;
begin
  g := round(p_cost * 20 * (1 + 0.25 * (greatest(p_chapter, 1) - 1)))::int * m;
  b := p_cost * 2 * m;
  s := case when p_type = 'boss' then 3 when p_first then 1 when p_roll1 < 0.3 then 1 else 0 end;
  if s > 0 then s := s + (greatest(p_chapter, 1) - 1) / 2; end if;
  if p_chapter >= 5 then o := case when p_type = 'boss' then 5 when p_first then 2 when p_roll2 < 0.2 then 1 else 0 end; end if;
  return jsonb_build_object('gold', g, 'blood', b, 'shard', s, 'soul', o);
end $$;
revoke all on function public._story_drop_calc(int, text, boolean, int, numeric, numeric) from public, anon, authenticated;

-- 공개: 수치 확인 (탐침 겸용, 클라이언트 미리보기에도 사용)
create or replace function public.economy_rates() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 3, 'exp_per_blood', _exp_per_blood(),
    'dismantle', jsonb_build_object('NORMAL', _dismantle_yield('NORMAL'), 'RARE', _dismantle_yield('RARE'), 'HIGH RARE', _dismantle_yield('HIGH RARE'),
                                    'SUPER RARE', _dismantle_yield('SUPER RARE'), 'ULTRA RARE', _dismantle_yield('ULTRA RARE'), 'MYTHIC RARE', _dismantle_yield('MYTHIC RARE')),
    'story_ch1_repeat', _story_drop_calc(1, 'normal', false, 6, 0, 0), 'quest_floor_10', _quest_currency(10))
$$;
revoke all on function public.economy_rates() from public, anon;
grant execute on function public.economy_rates() to authenticated;

-- 2) 스토리 드롭 (phaseE_2 감싸는 함수가 호출)
create or replace function public._story_drops(p_uid uuid, p_chapter int, p_phase int, p_first boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg story_phase_config; dr jsonb;
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), p_first, _stamina_cost(p_chapter, p_phase), random()::numeric, random()::numeric);
  perform _wallet_add(p_uid, dr, case when p_first then 'story_first_clear' else 'story_clear' end);
  return dr;
end $$;
revoke all on function public._story_drops(uuid, int, int, boolean) from public, anon, authenticated;

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

-- 3) 시련의 탑: 첫 클리어 재화 보상 추가 (나머지는 quest.sql 과 같음)
create or replace function public.quest_complete(p_floor int, p_stats jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r quest_progress; b jsonb; first boolean; rw jsonb := '{}'::jsonb; cur jsonb := null; t int; tk int := null; turns int; k text;
begin
  r := _quest_row(uid);
  b := r.battle;
  if b is null or (b->>'floor')::int <> p_floor then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _quest_min_secs() then raise exception 'too fast'; end if;
  turns := coalesce((p_stats->>'turns')::int, 1);
  if turns < 1 or turns > 40 then raise exception 'invalid stats'; end if;
  first := p_floor = r.best_floor + 1;
  if first then
    rw := _quest_reward(p_floor);
    t := coalesce((rw->>'tickets')::int, 0);
    if t > 0 then
      insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
      update story_gacha set tickets = tickets + t, updated_at = now() where user_id = uid returning tickets into tk;
    end if;
    cur := _quest_currency(p_floor);
    perform _wallet_add(uid, cur, 'quest_first_clear');
  end if;
  update quest_progress set battle = null, clears = clears + 1,
    best_floor = case when first then p_floor else best_floor end,
    rewards = case when first then (
      select jsonb_object_agg(x.k, coalesce((rewards->>x.k)::int, 0) + coalesce((rw->>x.k)::int, 0) + coalesce((cur->>x.k)::int, 0))
      from unnest(array['tickets', 'gold', 'blood', 'shard', 'soul']) x(k)) else rewards end,
    updated_at = now()
  where user_id = uid;
  return jsonb_build_object('ok', true, 'first', first, 'floor', p_floor, 'best_floor', greatest(r.best_floor, case when first then p_floor else 0 end), 'reward', rw, 'tickets', tk, 'currency', cur);
end $$;
revoke all on function public.quest_complete(int, jsonb) from public, anon;
grant execute on function public.quest_complete(int, jsonb) to authenticated;

-- 4) 분해: 재화로 (대상 카드 없음). p_uids = 카드 인스턴스 uid (최대 200, 전부 성공 또는 전부 취소)
create or replace function public.story_dismantle(p_uids text[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; u text; e jsonb; g text; y jsonb; lead text; gone text[] := '{}';
        gold int := 0; blood int := 0; soul int := 0; refund int := 0; n int := 0; w jsonb;
begin
  if p_uids is null or cardinality(p_uids) = 0 then raise exception 'nothing to discard'; end if;
  if cardinality(p_uids) > 200 then raise exception 'too many cards'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d); lead := d->>'leader';
  foreach u in array p_uids loop
    if u = any(gone) then raise exception 'duplicate card'; end if;
    select x.e into e from jsonb_array_elements(owned) x(e) where x.e->>'uid' = u;
    if e is null then raise exception 'card not owned'; end if;
    if u = lead then raise exception 'cannot discard leader'; end if;
    if coalesce((e->>'locked')::boolean, false) then raise exception 'card locked'; end if;
    e := _story_norm(e);
    select grade into g from story_card_pool where id = e->>'id';
    y := _dismantle_yield(coalesce(g, 'NORMAL'));
    gold := gold + (y->>'gold')::int;
    blood := blood + (y->>'blood')::int + floor((e->>'totalExp')::int * 0.5 / _exp_per_blood())::int + floor(coalesce((e->>'bloodSpent')::int, 0) * 0.5)::int;
    soul := soul + (y->>'soul')::int;
    refund := refund + greatest(0, coalesce((e->'boost'->>'ATK')::int,0) + coalesce((e->'boost'->>'HP')::int,0) + coalesce((e->'boost'->>'DEF')::int,0) - (e->>'spentCard')::int);
    gone := gone || u; n := n + 1;
  end loop;
  select coalesce(jsonb_agg(x.e order by k), '[]'::jsonb) into owned from jsonb_array_elements(owned) with ordinality x(e, k) where not (x.e->>'uid' = any(gone));
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  w := _wallet_add(uid, jsonb_build_object('gold', gold, 'blood', blood, 'soul', soul), 'dismantle');
  return jsonb_build_object('data', d, 'count', n, 'gold', gold, 'blood', blood, 'soul', soul, 'refund', refund, 'wallet', w);
end $$;
revoke all on function public.story_dismantle(text[]) from public, anon;
grant execute on function public.story_dismantle(text[]) to authenticated;

-- 예전 분해 RPC(EXP 지급)는 막고 새 분해로 돌림 (대상 카드는 무시)
create or replace function public.story_discard_many(p_ids text[], p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
begin return public.story_dismantle(p_ids) || jsonb_build_object('exp', 0); end $$;
create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
begin return (public.story_dismantle(array[p_id]) - 'count') || jsonb_build_object('exp', 0); end $$;
revoke all on function public.story_discard_many(text[], text), public.story_discard(text, text) from public, anon;
grant execute on function public.story_discard_many(text[], text), public.story_discard(text, text) to authenticated;

-- 5) 이전: 남은 카드 EXP → 순수한 피 (유저마다 1회, data.econV >= 3 이면 건너뜀)
do $$
declare r record; owned jsonb; e jsonb; k int; left_exp int; tot int; blood int;
begin
  for r in select user_id, data from public.story_progress where coalesce((data->>'econV')::int, 0) < 3 and user_id in (select id from auth.users) loop
    owned := case when jsonb_typeof(r.data->'owned') = 'array' then r.data->'owned' else '[]'::jsonb end;
    tot := 0;
    for k in 0 .. jsonb_array_length(owned) - 1 loop
      e := owned->k;
      left_exp := greatest(0, coalesce((e->>'exp')::int, 0));
      if left_exp > 0 then
        tot := tot + left_exp;
        owned := jsonb_set(owned, array[k::text], e || jsonb_build_object('exp', 0, 'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0) - left_exp)));
      end if;
    end loop;
    blood := tot / public._exp_per_blood();
    update public.story_progress set data = jsonb_set(jsonb_set(data, '{owned}', owned), '{econV}', '3'), updated_at = now() where user_id = r.user_id;
    if blood > 0 then perform public._wallet_add(r.user_id, jsonb_build_object('blood', blood), 'migrate_exp'); end if;
  end loop;
end $$;
