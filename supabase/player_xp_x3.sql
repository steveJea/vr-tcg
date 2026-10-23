-- 플레이어(유저) 레벨 필요 경험치 3배 (2026-10-23)
-- 레벨업마다 행동력이 최대치만큼 채워져 행동력이 계속 넘쳐서, 레벨업 속도를 1/3로.
-- 기존: Lv n → n+1 필요 = 100 + 20(n-1).  변경: 3 × (100 + 20(n-1)).
-- 기존 유저: player_state 의 level 은 그대로, xp(현재 레벨 안에서 모은 양)도 그대로. 다음 레벨까지 필요량만 늘어남 → 레벨이 내려가는 사람 없음.
-- 여러 번 실행해도 안전 (함수 교체만).
create or replace function public._player_xp_need(p_level int) returns int language sql immutable as $$ select 3 * (100 + 20 * (greatest(p_level, 1) - 1)) $$;
