-- ===== 장비 PR6 후속: 스토리 보스 소탕 증표 조각 끄기 =====
-- 선행: gear_sigil.sql. 여러 번 실행해도 안전
-- 인재별 "주인공 챕터"는 나중에 정함 → 그때까지 스토리에서는 증표 조각이 나오지 않음 (레벨업·장비로 진행)
-- 다시 켜려면: sigil_story_boss 에 (card_id, chapter) 를 정해 넣고
--   update public.sigil_drop_config set v = 1 where key = 'story_boss_on';
insert into public.sigil_drop_config (key, v) values ('story_boss_on', 0) on conflict (key) do nothing;
delete from public.sigil_story_boss;   -- 임시 매핑(임유리 4 · 민홍기 7 · 최윤희 5) 제거

create or replace function public._sigil_story_roll(p_uid uuid, p_chapter int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b record; pct numeric := (select v from sigil_drop_config where key = 'story_boss_pct'); cap int := (select v from sigil_drop_config where key = 'story_boss_daily');
  dday date := (now() at time zone 'Asia/Seoul')::date; n int; got jsonb := '[]'::jsonb;
begin
  if coalesce((select v from sigil_drop_config where key = 'story_boss_on'), 0) = 0 then return got; end if;   -- 꺼짐
  for b in select s.card_id from sigil_story_boss s join sigil_sources src on src.card_id = s.card_id and src.source = 'story_boss' where s.chapter = p_chapter loop
    select coalesce((select d.n from sigil_daily d where d.user_id = p_uid and d.card_id = b.card_id and d.day = dday), 0) into n;
    if n >= cap or random() * 100 >= pct then continue; end if;
    insert into sigil_daily (user_id, card_id, day, n) values (p_uid, b.card_id, dday, 1) on conflict (user_id, card_id, day) do update set n = sigil_daily.n + 1;
    perform _sigil_add(p_uid, b.card_id, 1, 'story_boss');
    got := got || to_jsonb(b.card_id);
  end loop;
  return got;
end $$;
revoke all on function public._sigil_story_roll(uuid, int) from public, anon, authenticated;
