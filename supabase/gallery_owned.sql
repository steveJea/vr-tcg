-- 갤러리 자동 등록: 스토리·뽑기로 얻은 보유 카드(story_progress.data.owned)를 갤러리에 등록
-- 1) 트리거: story_progress 저장(insert/update) 때 새로 생긴 보유 카드 id 를 gallery 에 추가 (이미 있으면 그대로)
-- 2) 백필: 지금 보유 중인 카드 전부 1회 등록
-- 여러 번 실행해도 안전. 왕관 등급(mvp_count)은 건드리지 않음.
-- 등록 행: count 1, mvp_count 0, first_at = now(). last_at 은 1분 전으로 둬서 gallery_register 의 15초 도배 방지에 걸리지 않게 함.

create or replace function public._gallery_sync_owned(p_uid uuid, p_data jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_uid is null or p_data is null or jsonb_typeof(p_data->'owned') <> 'array' then return 0; end if;
  with ids as (
    select distinct o->>'id' as id from jsonb_array_elements(p_data->'owned') o
    where jsonb_typeof(o) = 'object' and char_length(coalesce(o->>'id', '')) between 1 and 40
  ), ins as (
    insert into public.gallery (user_id, card_id, count, mvp_count, first_at, last_at)
    select p_uid, id, 1, 0, now(), now() - interval '1 minute' from ids
    on conflict (user_id, card_id) do nothing
    returning 1
  ) select count(*) into n from ins;
  return n;
end $$;
revoke all on function public._gallery_sync_owned(uuid, jsonb) from public, anon, authenticated;

create or replace function public._gallery_owned_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.data->'owned' is not distinct from old.data->'owned' then return new; end if;
  perform public._gallery_sync_owned(new.user_id, new.data);
  return new;
end $$;
revoke all on function public._gallery_owned_trg() from public, anon, authenticated;

drop trigger if exists story_progress_gallery on public.story_progress;
create trigger story_progress_gallery after insert or update of data on public.story_progress
  for each row execute function public._gallery_owned_trg();

-- 백필 (기존 보유 카드)
select public._gallery_sync_owned(user_id, data) from public.story_progress;

-- 확인용: 내 갤러리 중 보유 카드로 등록된 수
-- select count(*) from public.gallery g where g.user_id = auth.uid();
