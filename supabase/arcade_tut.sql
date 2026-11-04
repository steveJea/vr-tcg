-- =====================================================================
-- 📖 유리의 특강 (아케이드 튜토리얼) 첫 클리어 보상 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_gacha.sql (소환권 = 영입권, story_gacha.tickets) · gem.sql (_gem_day)
-- 보상: 초급 영입권 10 · 중급 100 · 상급 300 (계정당 단계별 1회, 앞 단계를 받아야 다음 단계)
-- 공개 RPC: arcade_tut_status() · arcade_tut_claim(stage)
-- 확인용: select public.arcade_tut_status();
-- =====================================================================

create table if not exists public.arcade_tut_claims (
  user_id    uuid not null references auth.users(id) on delete cascade,
  stage      int  not null check (stage between 1 and 3),
  tickets    int  not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, stage)
);
alter table public.arcade_tut_claims enable row level security;
revoke all on public.arcade_tut_claims from public, anon, authenticated;

create or replace function public._arcade_tut_reward(p_stage int) returns int language sql immutable as $$
  select case p_stage when 1 then 10 when 2 then 100 when 3 then 300 end
$$;
revoke all on function public._arcade_tut_reward(int) from public, anon, authenticated;

create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_reward(1), '2', _arcade_tut_reward(2), '3', _arcade_tut_reward(3)));
end $$;

create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); amt int := _arcade_tut_reward(p_stage); n int; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  if amt is null then raise exception 'bad stage'; end if;
  if p_stage > 1 and not exists (select 1 from arcade_tut_claims where user_id = uid and stage = p_stage - 1) then raise exception 'previous stage first'; end if;
  insert into arcade_tut_claims (user_id, stage, tickets) values (uid, p_stage, amt) on conflict (user_id, stage) do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    select tickets into t from story_gacha where user_id = uid;
    return jsonb_build_object('ok', true, 'already', true, 'stage', p_stage, 'tickets', coalesce(t, 0));
  end if;
  insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + amt, updated_at = now() where user_id = uid returning tickets into t;
  return jsonb_build_object('ok', true, 'stage', p_stage, 'gave', amt, 'tickets', t);
end $$;

revoke all on function public.arcade_tut_status(), public.arcade_tut_claim(int) from public, anon;
grant execute on function public.arcade_tut_status(), public.arcade_tut_claim(int) to authenticated;
