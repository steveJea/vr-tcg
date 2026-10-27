-- 수동 전투 (균열 토벌 · PvP): 내 행동 기록 저장 → tools/raid_verify.mjs · tools/pvp_verify.mjs 가 같은 seed 로 다시 돌려 검증
-- guild3.sql · guild.sql(pvp_report) 뒤에 실행. 여러 번 실행해도 안전
alter table public.guild_raid_attempts add column if not exists actions jsonb;   -- null = 자동 전투
alter table public.pvp_attempts add column if not exists actions jsonb;          -- null = 자동 · 판마다 배열 [[..],[..]]

-- 수동은 시간이 더 걸려서 토벌 제한 시간 10분 → 20분 (나머지 숫자는 guild3.sql 그대로)
create or replace function public._raid_numbers() returns jsonb language sql immutable as $$ select '{
  "attempts_per_day": 3, "sweep_pct": 90, "min_secs": 3, "open_minutes": 20,
  "hp_per_member": {"normal": 500000, "hard": 1250000, "abyss": 3000000}, "hp_min_members": 5, "hp_growth": 1.35,
  "diff_level": {"normal": 1, "hard": 3, "abyss": 5}, "diff_mult": {"normal": 1, "hard": 1.6, "abyss": 2.5},
  "hit_cap": 6000, "hit_cap_growth": 1.1, "attempt_hits": 200,
  "attempt": {"loyalty": 5, "gold_base": 200, "gold_per_damage": 200, "gold_max": 2000, "exp": 5},
  "stage": {"loyalty": 20, "gold": 2000, "gem": 30, "gem_every3": 150, "tickets_every5": 1, "exp_per_stage": 30},
  "last_hit": {"loyalty": 10},
  "rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 100}}, {"from": 2, "to": 3, "reward": {"gem": 500, "loyalty": 70}}, {"from": 4, "to": 10, "reward": {"gem": 200, "loyalty": 40}}],
  "member": {"gem": 100, "loyalty": 20},
  "join_hours": 24
}'::jsonb $$;

-- 행동 기록 검사: 배열 · 크기 제한 (한 판 최대 행동 수 = 턴 × 5장 + 턴 종료)
create or replace function public._battle_acts_ok(p jsonb, p_max int) returns boolean language sql immutable as $$
  select p is not null and jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= p_max and octet_length(p::text) <= 65536 $$;

-- 토벌: raid_finish 전에 호출 (끝나기 전 · 본인 판만 · 한 번만)
create or replace function public.raid_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a guild_raid_attempts;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from guild_raid_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.kind <> 'fight' or a.finished_at is not null then raise exception 'already finished'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if not _battle_acts_ok(p_actions, 15 * 6 + 5) then raise exception 'bad actions'; end if;
  update guild_raid_attempts set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;

-- PvP: pvp_report 전에 호출 (보고 전 · 본인 판만 · 한 번만). 판마다 배열
create or replace function public.pvp_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a pvp_attempts; x jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if p_actions is null or jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) > 3 or octet_length(p_actions::text) > 131072 then raise exception 'bad actions'; end if;
  for x in select value from jsonb_array_elements(p_actions) loop
    if not _battle_acts_ok(x, 20 * 6 + 5) then raise exception 'bad actions'; end if;
  end loop;
  update pvp_attempts set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public._battle_acts_ok(jsonb, int) from public, anon, authenticated;
revoke all on function public.raid_log(bigint, jsonb) from public, anon;
grant execute on function public.raid_log(bigint, jsonb) to authenticated;
revoke all on function public.pvp_log(bigint, jsonb) from public, anon;
grant execute on function public.pvp_log(bigint, jsonb) to authenticated;
