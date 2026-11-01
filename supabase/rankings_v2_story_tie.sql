-- 스토리 랭킹 동점 처리 보강 (rankings_v2.sql 다음에 실행). 여러 번 실행해도 안전.
-- 순위: 가장 먼 챕터-페이즈 → 깬 페이즈 수 → 그 기록에 먼저 도달한 사람.
-- story_progress 에는 '언제 깼는지'가 없어서, 기록(챕터·페이즈·깬 수)이 올라간 시각을 따로 적어 둡니다.

create table if not exists public.story_rank_reach (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  ch int not null, ph int not null, total int not null,
  reached_at timestamptz not null default now());
alter table public.story_rank_reach enable row level security;   -- 정책 없음 = 직접 조회 불가 (아래 함수로만)
revoke all on public.story_rank_reach from anon, authenticated;

create or replace function public._story_best(d jsonb, out ch int, out ph int, out total int)
language sql immutable set search_path = public as $$
  with c as (select (k.key)::int ch, max((v.value)::int) ph, count(*)::int n
               from jsonb_each(case when jsonb_typeof(d->'cleared') = 'object' then d->'cleared' else '{}'::jsonb end) k,
                    jsonb_array_elements_text(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) v
              where k.key ~ '^[0-9]{1,3}$' and v.value ~ '^[0-9]{1,3}$' group by k.key)
  select (select c.ch from c order by c.ch desc limit 1), (select c.ph from c order by c.ch desc limit 1), (select coalesce(sum(n), 0)::int from c)
$$;

create or replace function public._story_reach_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare b record;
begin
  select * into b from _story_best(new.data);
  if b.ch is null then return new; end if;
  insert into story_rank_reach (user_id, ch, ph, total, reached_at) values (new.user_id, b.ch, b.ph, b.total, now())
  on conflict (user_id) do update set ch = excluded.ch, ph = excluded.ph, total = excluded.total, reached_at = now()
    where (story_rank_reach.ch, story_rank_reach.ph, story_rank_reach.total) is distinct from (excluded.ch, excluded.ph, excluded.total);
  return new;
end $$;
drop trigger if exists story_reach on public.story_progress;
create trigger story_reach after insert or update of data on public.story_progress for each row execute function public._story_reach_trg();

-- 기존 기록 채우기: 정확한 시각을 모르니 마지막 저장 시각으로 (이미 있으면 그대로)
insert into public.story_rank_reach (user_id, ch, ph, total, reached_at)
select s.user_id, b.ch, b.ph, b.total, s.updated_at from public.story_progress s, lateral public._story_best(s.data) b where b.ch is not null
on conflict (user_id) do nothing;

create or replace function public.story_rankings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); top jsonb; mine jsonb;
begin
  with t as (select r.*, rank() over (order by ch desc, ph desc, total desc, reached_at) rk from story_rank_reach r)
  select coalesce((select jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'ch', ch, 'ph', ph, 'total', total, 'me', t.user_id = uid) order by rk)
                     from (select * from t order by rk limit 50) t left join profiles p on p.id = t.user_id), '[]'::jsonb),
         (select jsonb_build_object('rank', rk, 'ch', ch, 'ph', ph, 'total', total) from t where t.user_id = uid)
    into top, mine;
  return jsonb_build_object('top', top, 'me', mine);
end $$;
revoke all on function public.story_rankings() from public;
grant execute on function public.story_rankings() to anon, authenticated;
revoke all on function public._story_best(jsonb), public._story_reach_trg() from public, anon, authenticated;
