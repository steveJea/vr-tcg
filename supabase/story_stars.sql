-- 스토리 별점(★1~3, 마나 전투) — 페이즈별 최고 별 저장. 여러 번 실행해도 안전 (함수만, 데이터 삭제 없음)
-- 저장 위치: story_progress.data.stars = { "<챕터>": { "<페이즈>": 1~3 } } · 이미 클리어한 페이즈만, 더 높을 때만 갱신
-- 별 계산은 클라이언트(보상 없음): ★1 클리어 · +★ 내 턴 10턴 이내 · +★ 남은 마나 30% 이상
create or replace function public.story_set_stars(p_chapter int, p_phase int, p_stars int) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; cur int; s int := greatest(1, least(3, coalesce(p_stars, 1)));
begin
  if me is null then raise exception 'login required'; end if;
  if not exists (select 1 from story_phase_config where chapter = p_chapter and phase = p_phase) then raise exception 'invalid phase'; end if;
  d := _story_lock(me);
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  cur := coalesce((d->'stars'->(p_chapter::text)->>(p_phase::text))::int, 0);
  if s > cur then
    if jsonb_typeof(d->'stars') is distinct from 'object' then d := jsonb_set(d, '{stars}', '{}'::jsonb); end if;
    if jsonb_typeof(d->'stars'->(p_chapter::text)) is distinct from 'object' then d := jsonb_set(d, array['stars', p_chapter::text], '{}'::jsonb); end if;
    d := jsonb_set(d, array['stars', p_chapter::text, p_phase::text], to_jsonb(s));
    d := _story_save(me, d); cur := s;
  end if;
  return jsonb_build_object('ok', true, 'stars', cur, 'all', coalesce(d->'stars', '{}'::jsonb));
end $$;
revoke all on function public.story_set_stars(int, int, int) from public, anon;
grant execute on function public.story_set_stars(int, int, int) to authenticated;
select 'story_stars ok' as result;
