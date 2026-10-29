-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 story_set_decks 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- 마이 덱(최대 10개) · 덱 카드 자동 잠금 · 카드 즐겨찾기
-- 저장 위치: story_progress.data.decks = [{name, uids[]}], owned[i].fav, owned[i].locked(+dlk: 덱 자동 잠금 표시)
-- 모두 SECURITY DEFINER + auth.uid() 본인 행만. 여러 번 실행해도 안전(idempotent).

-- 1) 마이 덱 저장: 최대 10개, 덱당 최대 10장 (story_decks10.sql), 내가 가진 카드만. 덱에 든 카드는 locked+dlk, 빠지면 dlk 잠금만 해제(수동 잠금 유지)
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
      if jsonb_array_length(x->'uids') > 5 then raise exception 'deck too large'; end if;
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

-- 2) 즐겨찾기
create or replace function public.story_set_fav(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then e || jsonb_build_object('fav', true) else e - 'fav' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'fav', coalesce(p_on, false));
end $$;
revoke all on function public.story_set_fav(text, boolean) from public, anon;
grant execute on function public.story_set_fav(text, boolean) to authenticated;

-- 3) 잠금: 덱에 든 카드는 해제 불가. 수동 잠금 시 dlk 제거(덱에서 빠져도 잠금 유지)
create or replace function public.story_set_lock(p_uid text, p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  if not coalesce(p_on, false) and exists (
    select 1 from jsonb_array_elements(case when jsonb_typeof(d->'decks') = 'array' then d->'decks' else '[]'::jsonb end) k
    where jsonb_typeof(k->'uids') = 'array' and k->'uids' @> to_jsonb(p_uid)) then raise exception 'card in deck'; end if;
  e := owned->i;
  e := case when coalesce(p_on, false) then (e - 'dlk') || jsonb_build_object('locked', true) else e - 'locked' - 'dlk' end;
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'uid', p_uid, 'locked', coalesce(p_on, false));
end $$;
revoke all on function public.story_set_lock(text, boolean) from public, anon;
grant execute on function public.story_set_lock(text, boolean) to authenticated;
