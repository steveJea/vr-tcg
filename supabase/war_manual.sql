-- 구역 전쟁 수동 전투: 내 행동 기록 저장 → tools/war_verify.mjs 가 같은 seed 로 다시 돌려 검증
-- guild4.sql · manual_battle.sql 뒤에 실행. 여러 번 실행해도 안전
alter table public.war_attacks add column if not exists actions jsonb;   -- null = 자동 전투

-- 수동은 시간이 더 걸려서 공격 제한 시간 10분 → 20분 (나머지 숫자는 guild4.sql 그대로)
create or replace function public._war_numbers() returns jsonb language sql immutable as $$ select '{
  "min_members": 10, "attacks_per_day": 5, "open_hour": 9, "close_hour": 23, "min_secs": 3, "open_minutes": 20, "lock_minutes": 3, "hp_cap": 60000,
  "layout": {"def": [1,2,3,4,5], "atk": [6,7,8,9,10], "mid": [11,12,13], "boss": [14], "etc": [15,16,17,18,19,20,21]},
  "roles": {"def": {"atk": 1, "def": 1.2}, "atk": {"atk": 1.2, "def": 1}, "mid": {"atk": 1.15, "def": 1.15}, "boss": {"atk": 1.25, "def": 1.25}, "etc": {"atk": 1, "def": 1}},
  "points": {"def": 200, "atk": 150, "etc": 150, "mid": 250, "boss": 400},
  "standings": {"win": 3, "draw": 2, "loss": 0, "boss_bonus": 1},
  "npc_level": 10, "npc_scale": 1, "signup_days_before": 3,
  "match_win": {"loyalty": 60, "gold": 5000}, "match_boss_kill": {"loyalty": 20, "gold": 2000}, "match_draw": {"loyalty": 20, "gold": 1500}, "match_loss": {"loyalty": 10}, "match_exp_win": 300,
  "season_rank": [{"from": 1, "to": 1, "reward": {"gem": 1000, "loyalty": 300}}, {"from": 2, "to": 2, "reward": {"gem": 700, "loyalty": 200}}, {"from": 3, "to": 3, "reward": {"gem": 500, "loyalty": 150}},
                  {"from": 4, "to": 10, "reward": {"gem": 300, "loyalty": 100}}, {"from": 11, "to": 30, "reward": {"gem": 150, "loyalty": 50}}],
  "season_member": {"gem": 100, "loyalty": 30}
}'::jsonb $$;

-- war_finish 전에 호출 (끝나기 전 · 본인 공격만 · 한 번만). 40턴 → 내 턴 20 × (5장 + 턴 종료)
create or replace function public.war_log(p_id bigint, p_actions jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a war_attacks;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from war_attacks where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'no battle'; end if;
  if a.finished_at is not null then raise exception 'already finished'; end if;
  if a.actions is not null then raise exception 'already logged'; end if;
  if not _battle_acts_ok(p_actions, 20 * 6 + 5) then raise exception 'bad actions'; end if;
  update war_attacks set actions = p_actions where id = a.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.war_log(bigint, jsonb) from public, anon;
grant execute on function public.war_log(bigint, jsonb) to authenticated;
