-- ⚠ 테스트 전용. 운영 실행 금지. 테스트 SQL Editor 에서 파일 전체를 그대로 Run.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji (DB 고유번호 7703759698107299042). 다른 DB면 첫 블록에서 중단.
-- 목적: 개발자 테스트 계정을 최대 레벨·대량 재화·전체 카드·전체 스토리/탑 클리어 상태로 만듦.
-- 여러 번 실행해도 안전 (이미 높은 값은 그대로, 같은 카드 중복 지급 없음). 한 트랜잭션: 오류 시 전부 되돌아감.
-- 보안 1단계 보호(권한 회수·검증 이벤트·보상 영수증)는 건드리지 않음. 탑 드롭/조직 트리거만 이 트랜잭션 안에서 잠시 끄고 끝에서 다시 켬.
-- 도감 보상·업적 보상은 서버 검증 대상이라 이 스크립트로 자동 지급하지 않음 (카드만 도감에 등록).

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

do $vr_dev_boost$
declare
  target_email text := 'stevejean77@gmail.com';
  uid uuid;
  max_lv int;
  d jsonb;
  owned jsonb;
  gem_target bigint := 999999;
  cur_gem bigint;
  t text;
begin
  select id into uid from auth.users where lower(email) = lower(target_email);
  if uid is null then raise exception 'STOP: % 계정을 찾지 못했어요.', target_email; end if;
  perform set_config('vr_dev_boost.uid', uid::text, true);

  -- 탑 첫 클리어 드롭·조직 세력 트리거는 이 트랜잭션 안에서만 끔 (커밋 전에 다시 켬)
  alter table public.tower_progress disable trigger gear_tower_drop;
  alter table public.tower_progress disable trigger guild_ev_tower;
  alter table public.quest_progress disable trigger guild_ev_tower;

  -- 1) 플레이어 레벨·행동력
  max_lv := public._player_max_level();
  insert into public.player_state(user_id, level, xp, stamina, stamina_at) values (uid, max_lv, 0, public._stamina_max(max_lv), now())
  on conflict (user_id) do update set level = greatest(player_state.level, excluded.level), xp = 0,
    stamina = greatest(player_state.stamina, excluded.stamina), stamina_at = now(), updated_at = now();

  -- 2) 재화: 심연석은 정식 원장(_gem_add)으로, 나머지는 지갑에 직접 (목표치까지만 채움)
  insert into public.player_wallet(user_id) values (uid) on conflict (user_id) do nothing;
  update public.player_wallet set gold = greatest(gold, 99999999), blood = greatest(blood, 999999),
    shard = greatest(shard, 999999), soul = greatest(soul, 999999), updated_at = now() where user_id = uid;
  select gem_free into cur_gem from public.player_wallet where user_id = uid;
  if cur_gem < gem_target then
    perform public._gem_add(uid, (gem_target - cur_gem)::int, 0, 'admin', 'staging_dev_boost:' || clock_timestamp()::text,
      jsonb_build_object('note', 'staging dev boost'));
  end if;
  insert into public.story_gacha(user_id, last_draw, tickets) values (uid, public._gem_day() - 1, 9999)
  on conflict (user_id) do update set tickets = greatest(story_gacha.tickets, 9999), updated_at = now();
  foreach t in array array['drink'] loop
    insert into public.player_items(user_id, item, bound) values (uid, t, 999)
    on conflict (user_id, item) do update set bound = greatest(player_items.bound, 999), updated_at = now();
  end loop;

  -- 3) 스토리: 전 챕터·페이즈 클리어 + 모든 카드 최고 레벨 보유
  insert into public.story_progress(user_id, data) values (uid, '{}'::jsonb) on conflict (user_id) do nothing;
  select data into d from public.story_progress where user_id = uid for update;
  d := coalesce(d, '{}'::jsonb);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  -- 없는 카드 1장씩 추가
  select owned || coalesce(jsonb_agg(jsonb_build_object('uid', 'dev' || substr(md5(uid::text || p.id), 1, 12), 'id', p.id,
      'boost', '{}'::jsonb, 'level', 1, 'exp', 0, 'totalExp', 0, 'cpts', 0, 'spentCard', 0, 'ex', 0, 'exb', 0) order by p.id), '[]'::jsonb)
    into owned from public.story_card_pool p
    where not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id);
  -- 모든 보유 카드를 등급 최대 레벨(+EX 단계당 5)로
  select coalesce(jsonb_agg(o.v || jsonb_build_object('level', greatest(coalesce((o.v->>'level')::int, 1),
      (case upper(coalesce(p.grade, '')) when 'N' then 20 when 'NORMAL' then 20 when 'R' then 30 when 'RARE' then 30
        when 'HR' then 40 when 'HIGH RARE' then 40 when 'SR' then 50 when 'SUPER RARE' then 50 when 'UR' then 60 when 'ULTRA RARE' then 60
        when 'MR' then 70 when 'MYTHIC RARE' then 70 when 'LR' then 100 when 'LEGENDARY RARE' then 100 else 20 end)
        + 5 * greatest(0, coalesce((o.v->>'ex')::int, 0))), 'exp', 0) order by o.n), '[]'::jsonb)
    into owned from jsonb_array_elements(owned) with ordinality o(v, n) left join public.story_card_pool p on p.id = o.v->>'id';
  d := d || jsonb_build_object('owned', owned, 'openingSeen', true,
    'cleared', (select coalesce(jsonb_object_agg(chapter::text, phases), '{}'::jsonb) from (
      select chapter, jsonb_agg(phase order by phase) phases from public.story_phase_config group by chapter) c));
  if coalesce(d->>'starter', '') = '' then d := d || jsonb_build_object('starter', owned->0->>'id'); end if;
  if coalesce(d->>'leader', '') = '' then d := d || jsonb_build_object('leader', owned->0->>'uid'); end if;
  d := jsonb_set(d, '{points}', to_jsonb(greatest(0, public._story_earned(d) - public._story_used(d))));
  update public.story_progress set data = d, updated_at = now() where user_id = uid;

  -- 도감 등록 (보상 수령은 검증 이벤트가 필요해서 그대로 보류)
  insert into public.gallery(user_id, card_id, count, mvp_count) select uid, c.card_id, 1, 0 from public.reward_card_catalog c
  on conflict (user_id, card_id) do update set count = greatest(gallery.count, 1);

  -- 4) 시련의 탑 전체 층 클리어 (첫 클리어 보상 표시도 끝까지 받은 것으로)
  foreach t in array array['normal', 'wind', 'ice', 'fire', 'light', 'dark'] loop
    insert into public.tower_progress(user_id, tower, best_floor, paid_floor, clears)
    values (uid, t, public._tower_max_floor(t), public._tower_max_floor(t), public._tower_max_floor(t))
    on conflict (user_id, tower) do update set best_floor = greatest(tower_progress.best_floor, excluded.best_floor),
      paid_floor = greatest(tower_progress.paid_floor, excluded.paid_floor), clears = greatest(tower_progress.clears, excluded.clears), updated_at = now();
  end loop;
  insert into public.quest_progress(user_id, best_floor, clears) values (uid, public._tower_max_floor('normal'), public._tower_max_floor('normal'))
  on conflict (user_id) do update set best_floor = greatest(quest_progress.best_floor, excluded.best_floor), clears = greatest(quest_progress.clears, excluded.clears), updated_at = now();

  -- 5) 훈련소·장비 공간
  insert into public.camp_state(user_id, camp_lv, dojo_slots) values (uid, 10, 2)
  on conflict (user_id) do update set camp_lv = 10, dojo_slots = 2, updated_at = now();
  insert into public.player_gear_meta(user_id, slots, dust) values (uid, 200, 999999)
  on conflict (user_id) do update set slots = 200, dust = greatest(player_gear_meta.dust, 999999), updated_at = now();

  alter table public.tower_progress enable trigger gear_tower_drop;
  alter table public.tower_progress enable trigger guild_ev_tower;
  alter table public.quest_progress enable trigger guild_ev_tower;
end $vr_dev_boost$;

select u.email, s.level, w.gold, w.gem_free, w.blood, w.shard, w.soul, g.tickets,
  jsonb_array_length(p.data->'owned') owned_cards, (select count(*) from jsonb_object_keys(p.data->'cleared')) chapters_cleared,
  (p.data->>'points')::int stat_points, (select min(best_floor) from public.tower_progress t where t.user_id = u.id) tower_min_floor
from auth.users u
join public.player_state s on s.user_id = u.id join public.player_wallet w on w.user_id = u.id
join public.story_gacha g on g.user_id = u.id join public.story_progress p on p.user_id = u.id
where u.id = current_setting('vr_dev_boost.uid')::uuid;

commit;
