-- 조직 인재 대여 알림 — 선행: guild_lend.sql. 여러 번 실행해도 안전 (열 추가·함수만, 삭제 없음)
-- 내 인재를 누가 빌리면, 다음에 게임/조직 홈을 열 때 'OO님이 OO를 빌렸어요 · 충성 +20' 을 한 번 보여 주고 읽음 표시
alter table public.guild_loans add column if not exists lender_seen boolean not null default false;
create index if not exists guild_loans_lender_unseen on public.guild_loans (lender) where not lender_seen;

-- 안 본 알림 (최근 30개, 7일 안) 을 돌려주고 읽음으로 표시
create or replace function public.guild_lend_notices() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  with x as (
    select l.id from guild_loans l where l.lender = me and not l.lender_seen and l.borrowed_at > now() - interval '7 days' order by l.borrowed_at desc limit 30),
  u as (update guild_loans l set lender_seen = true from x where l.id = x.id returning l.*)
  select coalesce(jsonb_agg(jsonb_build_object('borrower_name', coalesce(p.nickname, '조직원'), 'card_id', u.card_id, 'reward', _lend_reward(), 'at', u.borrowed_at) order by u.borrowed_at desc), '[]'::jsonb) into r
    from u left join profiles p on p.id = u.borrower;
  update guild_loans set lender_seen = true where lender = me and not lender_seen;   -- 7일 지난 것도 정리
  return r;
end $$;
revoke all on function public.guild_lend_notices() from public, anon;
grant execute on function public.guild_lend_notices() to authenticated;
select 'guild_lend_notice ok' as result;
