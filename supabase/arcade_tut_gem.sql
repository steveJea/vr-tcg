-- =====================================================================
-- 📖 유리의 특강 첫 클리어 보상 변경 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: arcade_tut.sql · gem.sql (_gem_add, player_wallet.gem_free) · story_gacha.sql (영입권 = story_gacha.tickets)
-- 보상: 초급 영입권 10 · 중급 심연석 100 · 상급 심연석 300 (무료 심연석) — 계정당 단계별 1회, 앞 단계를 받아야 다음 단계
-- 이미 받은 단계는 다시 지급하지 않음 (예전 보상으로 받은 기록도 그대로 '받음')
-- =====================================================================

alter table public.arcade_tut_claims add column if not exists kind text not null default 'tickets';   -- tickets | gem

create or replace function public._arcade_tut_rw(p_stage int) returns jsonb language sql immutable as $$
  select case p_stage when 1 then '{"kind":"tickets","n":10}'::jsonb
                      when 2 then '{"kind":"gem","n":100}'::jsonb
                      when 3 then '{"kind":"gem","n":300}'::jsonb end
$$;
revoke all on function public._arcade_tut_rw(int) from public, anon, authenticated;

create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_rw(1), '2', _arcade_tut_rw(2), '3', _arcade_tut_rw(3)));
end $$;

create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rw jsonb := _arcade_tut_rw(p_stage); amt int; k text; n int; t int; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if rw is null then raise exception 'bad stage'; end if;
  if p_stage > 1 and not exists (select 1 from arcade_tut_claims where user_id = uid and stage = p_stage - 1) then raise exception 'previous stage first'; end if;
  amt := (rw->>'n')::int; k := rw->>'kind';
  insert into arcade_tut_claims (user_id, stage, tickets, kind) values (uid, p_stage, amt, k) on conflict (user_id, stage) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', true, 'already', true, 'stage', p_stage, 'kind', k); end if;
  if k = 'gem' then
    g := _gem_add(uid, amt, 0, 'arcade_tut', 'arcade_tut:' || p_stage, jsonb_build_object('stage', p_stage));
    return jsonb_build_object('ok', true, 'stage', p_stage, 'kind', 'gem', 'gave', amt, 'gem', g->'gem');
  end if;
  insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + amt, updated_at = now() where user_id = uid returning tickets into t;
  return jsonb_build_object('ok', true, 'stage', p_stage, 'kind', 'tickets', 'gave', amt, 'tickets', t);
end $$;

revoke all on function public.arcade_tut_status(), public.arcade_tut_claim(int) from public, anon;
grant execute on function public.arcade_tut_status(), public.arcade_tut_claim(int) to authenticated;
