-- =====================================================================
-- 2026-10-27 LEGENDARY RARE(LR) 등급 추가: 등급 check 제약에 LR 허용. 여러 번 실행해도 안전.
--   LR 카드(장서아 10334)는 NPC 전용이라 카드 풀·뽑기·PVP 메타에는 넣지 않음 (제약만 열어 둠).
--   보상 등급(reward_grade)·아케이드 갤러리(card_pool) 제약은 그대로 (LR 보상·뽑기 없음).
-- =====================================================================
alter table public.story_card_pool drop constraint if exists story_card_pool_grade_check;
alter table public.story_card_pool add constraint story_card_pool_grade_check
  check (grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'));
