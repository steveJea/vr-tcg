-- =====================================================================
-- 챕터 0 (튜토리얼 · 공허한 여신) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql, phaseE_2.sql, story_ch1_reward.sql (reward_card 열 · 고정 보상 지급)
--   페이즈 1~3, 첫 클리어 보상: 1 오유나 · 2 황보예 · 3 송지아 (이미 있으면 한 장 더)
--   새 사용자: 캐릭터(스타터)를 고르기 전에도 챕터 0 을 할 수 있음
--   기존 사용자: 진행 그대로. 챕터 0 은 다른 챕터의 열림 조건에 들어가지 않음 (챕터 1 은 챕터 0 클리어 없이 열림)
--   행동력: 다른 페이즈와 같이 6 (0 이면 소탕으로 공짜 반복 가능) · 챕터 0 전체 클리어 시 소환권 +10 (기존 규칙)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (0,1,'normal',3,null,1), (0,2,'normal',3,null,5), (0,3,'normal',3,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;
update public.story_phase_config set reward_card = case phase when 1 then '10256' when 2 then '10462' when 3 then '10207' end where chapter = 0;

-- 원래 전투 시작(_e0, phaseE_2 가 감쌈)을 다시 정의: 챕터 0 은 스타터 불필요 · 챕터 0 은 다른 챕터 선행 조건에서 제외
create or replace function public._story_start_phase_e0(p_chapter int, p_phase int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  if p_chapter <> 0 and coalesce(d->>'starter', '') = '' then raise exception 'choose starter first'; end if;
  -- 열림 조건: 같은 챕터의 이전 페이즈 모두 클리어 + 이전 챕터 전체 클리어 (챕터 0 은 다른 챕터 조건에서 빠짐)
  if exists (
    select 1 from story_phase_config c
    where (c.chapter < p_chapter or (c.chapter = p_chapter and c.phase < p_phase))
      and (c.chapter <> 0 or p_chapter = 0)
      and not (coalesce(d->'cleared'->(c.chapter::text), '[]'::jsonb) @> to_jsonb(c.phase))
  ) then raise exception 'phase locked'; end if;
  d := jsonb_set(d, '{battle}', jsonb_build_object('chapter', p_chapter, 'phase', p_phase, 'at', (extract(epoch from clock_timestamp()))::bigint));
  return _story_save(uid, d);
end $$;
revoke all on function public._story_start_phase_e0(int, int) from public, anon, authenticated;

select chapter, phase, type, reward_card from public.story_phase_config where chapter = 0 order by phase;
