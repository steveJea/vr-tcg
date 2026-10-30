-- =====================================================================
-- PvP 보스리그 (mode = 'boss'). pvp.sql · pvp_tier.sql · gem.sql 다음에 실행. 여러 번 실행해도 안전.
--   기존 PvP 구조 그대로 (pvp_set_deck / pvp_status / pvp_start / pvp_report / pvp_rankings / pvp_claim_reward / 티어·연승)
--   p_mode = 'boss' 로 부르면 레이팅·랭킹·하루 10회·시즌 보상이 1v1·3v3 과 따로.
--   덱 1~5장, 첫 장 = 수비대장 (HR 이하, 서버 트리거로 검사). 승패 = 상대 진영 HP 0 (클라이언트 pvp-core.js boss 모드)
--   기존 pvp 데이터(덱·레이팅·기록·보상)는 건드리지 않음. 바뀌는 것: pvp_decks 의 mode 체크 · _pvp_ok · 트리거 · 보상표 행 추가
-- =====================================================================

-- 1) pvp_decks.mode 에 'boss' 허용 (mode 체크 제약만 다시 만듦)
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.pvp_decks'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%mode%' loop
    execute format('alter table public.pvp_decks drop constraint %I', c);
  end loop;
end $$;
alter table public.pvp_decks add constraint pvp_decks_mode_check check (mode in ('1v1','3v3','boss'));

-- 2) 모드 확인: boss = 덱 1개 (1판)
create or replace function public._pvp_ok(p_league text, p_mode text) returns int language plpgsql immutable as $$
begin
  if p_league not in ('open','hr') then raise exception 'bad league'; end if;
  if p_mode = '1v1' then return 1; elsif p_mode = '3v3' then return 3; elsif p_mode = 'boss' then return 1; end if;
  raise exception 'bad mode';
end $$;

-- 3) 보스리그 덱: 첫 장(수비대장)은 HR 이하
create or replace function public._pvp_boss_deck_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare g text;
begin
  if new.mode <> 'boss' then return new; end if;
  select grade into g from pvp_card_meta where id = new.snap->0->>'id';
  if g is null or g not in ('NORMAL','RARE','HIGH RARE') then raise exception 'guard grade'; end if;
  return new;
end $$;
revoke all on function public._pvp_boss_deck_chk() from public, anon, authenticated;
drop trigger if exists pvp_boss_deck_chk on public.pvp_decks;
create trigger pvp_boss_deck_chk before insert or update on public.pvp_decks for each row execute function public._pvp_boss_deck_chk();

-- 4) 시즌 순위 보상 (1v1 과 같은 값)
insert into public.pvp_reward_table (league, mode, rank_from, rank_to, reward)
select l, 'boss', f, t, r::jsonb from (values ('open'), ('hr')) a(l),
  (values (1, 1, '{"gold":3000,"soul":50,"tickets":50}'), (2, 3, '{"gold":2000,"soul":30,"tickets":30}'), (4, 10, '{"gold":1200,"soul":15,"tickets":20}'),
          (11, 50, '{"gold":600,"shard":20,"tickets":10}'), (51, 100, '{"gold":300,"shard":10,"tickets":10}'), (101, 1000000, '{"gold":100,"tickets":5}')) c(f, t, r)
on conflict (league, mode, rank_from) do update set rank_to = excluded.rank_to, reward = excluded.reward;

-- 확인: select public.pvp_rankings('open','boss');   → {"season":..., "top":[], "me":null}
