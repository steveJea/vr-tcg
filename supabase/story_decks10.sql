-- 마이 덱: 덱당 최대 5장 → 10장 (스토리 마나 전투 손패 10장). story_set_decks 만 다시 정의 · 여러 번 실행해도 안전 · 데이터 삭제 없음
-- 탑·PvP·전쟁·토벌은 클라이언트에서 앞 5장만 씀
create or replace function public.story_set_decks(p_decks jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; clean jsonb := '[]'::jsonb; x jsonb; ids jsonb; u text; nm text;
        alluids text[] := '{}'; mine text[]; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_decks is null or jsonb_typeof(p_decks) <> 'array' then raise exception 'bad decks'; end if;
  if jsonb_array_length(p_decks) > 10 then raise exception 'too many decks'; end if;
  select coalesce(array_agg(o->>'uid'), '{}') into mine from jsonb_array_elements(owned) o where coalesce(o->>'uid', '') <> '' and o->>'uid' not like 'guest:%';
  for x in select * from jsonb_array_elements(p_decks) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'bad deck'; end if;
    nm := left(btrim(coalesce(x->>'name', '')), 16);
    ids := '[]'::jsonb;
    if jsonb_typeof(x->'uids') = 'array' then
      if jsonb_array_length(x->'uids') > 10 then raise exception 'deck too large'; end if;
      for u in select jsonb_array_elements_text(x->'uids') loop
        if not (u = any(mine)) then raise exception 'card not owned'; end if;
        if not (ids @> to_jsonb(u)) then ids := ids || to_jsonb(u); alluids := alluids || u; end if;
      end loop;
    end if;
    clean := clean || jsonb_build_object('name', nm, 'uids', ids);
  end loop;
  for i in 0 .. coalesce(jsonb_array_length(owned), 0) - 1 loop
    e := owned->i;
    if (e->>'uid') = any(alluids) then
      if not coalesce((e->>'locked')::boolean, false) then e := e || jsonb_build_object('locked', true, 'dlk', true); end if;
    elsif coalesce((e->>'dlk')::boolean, false) then
      e := e - 'locked' - 'dlk';
    end if;
    owned := jsonb_set(owned, array[i::text], e);
  end loop;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{decks}', clean);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'decks', clean);
end $$;
revoke all on function public.story_set_decks(jsonb) from public, anon;
grant execute on function public.story_set_decks(jsonb) to authenticated;
select 'story_decks10 ok' as result;
