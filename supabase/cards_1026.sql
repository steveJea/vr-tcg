-- =====================================================================
-- VR: Abyss Gate - CH7 빌런 스킬 (2026-10-26)
-- 강태준(10019) 「에이스의 힘이다」 · 강태안(10018) 「너한테만 통하는 기술이야」 · 이민수(10299) 「나? 폭격기야~」 · 김철민(10074) 「약해보이냐? 진짜?」
-- 액티브 1번 스킬 해금 Lv1 → 스킬 레벨업(story_skill_levelup) 메타. 스탯·뽑기 풀 변경 없음
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전.
-- =====================================================================
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10019',1,1), ('10018',1,1), ('10299',1,1), ('10074',1,1)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

-- 확인용: 4행
select card_id, idx, unlock from public.story_skill_meta where card_id in ('10019','10018','10299','10074') order by card_id;
