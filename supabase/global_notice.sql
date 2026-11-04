-- ===== 거래소 개편 4/4: 전체 알림 (UR·MR·LR 획득) + 소식 기록 =====
-- 선행: gacha.sql (story_gacha_log) · schema.sql (profiles). 여러 번 실행해도 안전. 지우는 것 없음 (표·트리거·함수 추가만)
-- 1) 어떤 뽑기든(일일·티켓·합성·이벤트 등) story_gacha_log 에 UR 이상이 들어오면 global_notices 에 한 줄 (트리거 → 뽑기 함수는 그대로)
-- 2) 화면은 global_notice_list 로 30초마다 새 알림만 받아 토스트 + 📢 소식 창. 이름 누르면 지정 거래 (이름 숨기기 없음)
-- 3) 3일 지난 알림은 목록에서 안 보임 (표는 남음, 정리는 원하면 따로)

create table if not exists public.global_notices (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  nick       text not null default '플레이어',
  card_id    text not null,
  grade      text not null,
  src        text not null default 'daily',
  created_at timestamptz not null default now()
);
create index if not exists global_notices_time on public.global_notices (created_at desc);
alter table public.global_notices enable row level security;
revoke all on public.global_notices from public, anon, authenticated;

create or replace function public._global_notice_gacha() returns trigger language plpgsql security definer set search_path = public as $$
declare g text := upper(coalesce(new.grade, ''));
begin
  if g in ('ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE', 'UR', 'MR', 'LR') then
    insert into global_notices (user_id, nick, card_id, grade, src)
    values (new.user_id, coalesce((select nickname from profiles where id = new.user_id), '플레이어'), new.card_id,
            case g when 'ULTRA RARE' then 'UR' when 'MYTHIC RARE' then 'MR' when 'LEGENDARY RARE' then 'LR' else g end,
            coalesce(to_jsonb(new)->>'kind', 'daily'));
  end if;
  return new;
exception when others then return new;   -- 알림 실패로 뽑기가 깨지면 안 됨
end $$;
drop trigger if exists global_notice_gacha on public.story_gacha_log;
create trigger global_notice_gacha after insert on public.story_gacha_log for each row execute function public._global_notice_gacha();

-- 목록: p_after 보다 새 것 (없으면 최근), 최대 50, 3일 이내. me = 내 알림 (이름 링크 끄기용)
create or replace function public.global_notice_list(p_after bigint default null, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'notices', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'uid', n.user_id, 'nick', n.nick, 'card_id', n.card_id, 'grade', n.grade, 'src', n.src,
      'created_at', n.created_at, 'me', n.user_id = uid) order by n.id desc), '[]'::jsonb)
    from (select * from global_notices where created_at > now() - interval '3 days' and (p_after is null or id > p_after)
          order by id desc limit greatest(1, least(coalesce(p_limit, 50), 100))) n));
end $$;

revoke all on function public._global_notice_gacha() from public, anon, authenticated;
revoke all on function public.global_notice_list(bigint, int) from public, anon;
grant execute on function public.global_notice_list(bigint, int) to authenticated;
notify pgrst, 'reload schema';
