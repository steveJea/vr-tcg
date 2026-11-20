-- =====================================================================
-- 2026-11-17 신규 카드 우승찬(10533, RARE, 코스트 25): 카드 목록 · PVP 덱 검증 · 도감 카탈로그 FK
-- 시트 NPC 칸이 비어 있어 플레이어 카드. 프로필만 있고 스킬 없음. 뽑기 풀에는 넣지 않음 (gacha = false, 11-11 신규 카드와 같음).
-- staging_install.sql 에 포함 (security_phase1_rewards.sql 의 reward_card_catalog 보다 먼저). 여러 번 실행해도 안전. 삭제 없음.
-- tools/build_ch18_19_sql.py 가 생성.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10533','RARE','우승찬',false)
on conflict (id) do update set grade = excluded.grade, name = excluded.name;

insert into public.pvp_card_meta (id, grade, cost) values
  ('10533','RARE',25)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;
