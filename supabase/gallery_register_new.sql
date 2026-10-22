-- 아케이드 판 종료 'NEW!' 수정: 갤러리 행이 아예 없던 카드만 NEW.
-- 보유(스토리·뽑기) 자동 등록으로 count 0 행이 이미 있는 카드는 아케이드 첫 수집 시 count 1 이 되지만 NEW 아님.
-- 시그니처·권한·15초 도배 방지는 그대로. 여러 번 실행해도 안전 (create or replace).
-- 함께 수정: MVP 없이(p_mvp null) 부른 판은 mvp_count 가 null 이 되어 not-null 오류 → coalesce(…, 0).
create or replace function public.gallery_register(p_cards text[], p_mvp text default null)
returns table (card_id text, count int, mvp_count int, is_new boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare uid uuid := auth.uid(); ids text[];
begin
  if uid is null then raise exception 'not logged in'; end if;
  select array_agg(distinct x) into ids
    from unnest(coalesce(p_cards, '{}') || case when p_mvp is null then '{}'::text[] else array[p_mvp] end) x
    where x is not null and char_length(x) between 1 and 40;
  if ids is null then return; end if;
  if array_length(ids, 1) > 12 then raise exception 'too many cards'; end if;
  -- 도배 방지: 15초 안에 연속 등록 불가
  if exists (select 1 from public.gallery g where g.user_id = uid and g.last_at > now() - interval '15 seconds') then
    raise exception 'too fast';
  end if;
  return query
  insert into public.gallery as g (user_id, card_id, count, mvp_count, first_at, last_at)
  select uid, x, 1, coalesce((x = p_mvp)::int, 0), now(), now() from unnest(ids) x
  on conflict (user_id, card_id) do update
    set count = g.count + 1, mvp_count = g.mvp_count + excluded.mvp_count, last_at = now()
  returning g.card_id, g.count, g.mvp_count, (g.xmax = 0);   -- 새로 insert 된 행만 NEW (보유 자동 등록 count 0 행은 update → NEW 아님)
end $$;

revoke all on function public.gallery_register(text[], text) from public, anon;
grant execute on function public.gallery_register(text[], text) to authenticated;
